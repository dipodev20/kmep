// Общий модуль: получает свежий WEB playerResponse и извлекает первый
// формат с signatureCipher. Используется диагностическими скриптами.
//
//   const { fetchChallenge } = require('./fetch_challenge.js');
//   const ch = await fetchChallenge(videoId);
//   // ch = { itag, sp, s, n, innerUrl }

const https = require('https');

function httpsGet(url, headers) {
  return new Promise((resolve, reject) => {
    https.get(url, { headers }, (res) => {
      let chunks = '';
      res.on('data', (c) => chunks += c);
      res.on('end', () => resolve(chunks));
    }).on('error', reject);
  });
}

function httpsPost(url, body, headers) {
  return new Promise((resolve, reject) => {
    const data = JSON.stringify(body);
    const req = https.request(url, {
      method: 'POST',
      headers: Object.assign({
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(data),
      }, headers),
    }, (res) => {
      let chunks = '';
      res.on('data', (c) => chunks += c);
      res.on('end', () => resolve(chunks));
    });
    req.on('error', reject);
    req.write(data);
    req.end();
  });
}

async function fetchChallenge(videoId) {
  const desktopUA =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36';
  const watchUrl = `https://www.youtube.com/watch?v=${videoId}&hl=en&gl=US`;

  const watchHtml = await httpsGet(watchUrl, { 'User-Agent': desktopUA });
  const apiKey = watchHtml.match(/"INNERTUBE_API_KEY":"([^"]+)"/)?.[1];
  const stsMatch = watchHtml.match(/"STS":(\d+)/);
  const signatureTimestamp = stsMatch ? parseInt(stsMatch[1], 10) : null;
  if (!apiKey || !signatureTimestamp) {
    throw new Error('Не нашёл INNERTUBE_API_KEY/STS на watch-странице (consent/капча?)');
  }

  const resp = await httpsPost(
    `https://www.youtube.com/youtubei/v1/player?key=${apiKey}`,
    {
      videoId,
      context: {
        client: { clientName: 'WEB', clientVersion: '2.20240808.00.00', clientScreen: 'WATCH', hl: 'en', gl: 'US' },
        thirdParty: { embedUrl: 'https://www.youtube.com/' },
      },
      playbackContext: { contentPlaybackContext: { signatureTimestamp } },
      racyCheckOk: true,
      contentCheckOk: true,
    },
    { 'User-Agent': desktopUA, 'Origin': 'https://www.youtube.com' },
  );
  const json = JSON.parse(resp);
  const status = json.playabilityStatus?.status;
  const formats = [
    ...(json.streamingData?.formats || []),
    ...(json.streamingData?.adaptiveFormats || []),
  ];
  if (!formats.length) throw new Error(`playabilityStatus=${status}, форматов 0`);

  const fmt = formats.find((f) => f.signatureCipher || f.cipher);
  if (!fmt) throw new Error('Нет формата с signatureCipher');

  const params = new URLSearchParams(fmt.signatureCipher || fmt.cipher);
  const innerUrl = params.get('url');
  if (!innerUrl) throw new Error('signatureCipher без url');
  return {
    itag: fmt.itag,
    sp: params.get('sp') || 'sig',
    s: params.get('s') || '',
    n: new URL(innerUrl).searchParams.get('n'),
    innerUrl,
  };
}

module.exports = { fetchChallenge, httpsGet, httpsPost };
