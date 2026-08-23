// Матричный прогон InnerTube-клиентов на живом YouTube.
// Цель: откалибровать конфиги из lib/src/clients/client_configs.dart —
// какие комбинации (clientName/version/key/context) реально отдают форматы.
//
//   node tool/client_matrix.js <videoId>

process.on('unhandledRejection', function () {});
const https = require('https');
const { httpsGet, httpsPost } = require('./fetch_challenge.js');

const videoId = process.argv[2] || 'dQw4w9WgXcQ';
const DESKTOP_UA =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36';

// Публичные InnerTube-ключи (не секреты).
const KEYS = {
  WEB: 'AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8',
  IOS: 'AIzaSyB-63vPrdThhKuerbB2N_l7Kwwcxj6yUAc',
  ANDROID: 'AIzaSyA8eiZmM1FaDVjRy-df2KTyQ_vz_yYM39w',
  TV: 'AIzaSyDCU8hByM-4DrUqRUYnGn-3llEO78bcxq8',
};

function extractN(fmt) {
  if (fmt.url) {
    try { return new URL(fmt.url).searchParams.get('n'); } catch (e) { return null; }
  }
  const cipher = fmt.signatureCipher || fmt.cipher;
  if (cipher) {
    const inner = new URLSearchParams(cipher).get('url');
    if (inner) { try { return new URL(inner).searchParams.get('n'); } catch (e) {} }
  }
  return null;
}

async function tryClient(label, opts) {
  const body = {
    videoId,
    context: { client: Object.assign({ hl: 'en', gl: 'US' }, opts.context) },
    contentCheckOk: true,
    racyCheckOk: true,
    ...(opts.sts ? { playbackContext: { contentPlaybackContext: { signatureTimestamp: opts.sts } } } : {}),
    ...(opts.extraBody || {}),
  };
  const headers = Object.assign(
    { 'User-Agent': opts.ua },
    opts.headers || {},
  );
  const url = opts.noKey
    ? 'https://www.youtube.com/youtubei/v1/player'
    : `https://www.youtube.com/youtubei/v1/player?key=${opts.key}`;
  let resp;
  try {
    resp = await httpsPost(url, body, headers);
  } catch (e) {
    console.log(`[${label}] СЕТЬ: ${e.message}`);
    return;
  }
  let json;
  try { json = JSON.parse(resp); } catch (e) {
    console.log(`[${label}] не-JSON ответ (${resp.length} байт): ${resp.slice(0, 120)}`);
    return;
  }
  const err = json.error;
  const status = json.playabilityStatus?.status;
  const formats = [
    ...(json.streamingData?.formats || []),
    ...(json.streamingData?.adaptiveFormats || []),
  ];
  const direct = formats.filter((f) => f.url).length;
  const ciphered = formats.length - direct;
  const withN = formats.filter((f) => extractN(f)).length;
  const maxHeight = formats.reduce((m, f) => Math.max(m, f.height || 0), 0);
  let summary;
  if (err) summary = `API ERROR ${err.code}: ${(err.message || '').slice(0, 60)}`;
  else if (!formats.length) summary = `status=${status}, форматов 0${json.playabilityStatus?.reason ? ' (' + json.playabilityStatus.reason.slice(0, 50) + ')' : ''}`;
  else summary = `status=${status}, форматов=${formats.length} (url=${direct}, cipher=${ciphered}, с n=${withN}), maxH=${maxHeight}`;
  console.log(`[${label}] ${summary}`);
}

async function main() {
  const watchHtml = await httpsGet(`https://www.youtube.com/watch?v=${videoId}&hl=en&gl=US`, { 'User-Agent': DESKTOP_UA });
  const sts = parseInt((watchHtml.match(/"STS":(\d+)/) || [])[1] || '0', 10);
  console.log(`videoId=${videoId}, STS=${sts}\n`);

  // --- ANDROID_VR ---
  await tryClient('ANDROID_VR v1.60.19 без key', {
    noKey: true,
    ua: 'com.google.android.apps.youtube.vr.oculus/1.60.19 (Linux; U; Android 12; eureka; en_US) gzip',
    context: { clientName: 'ANDROID_VR', clientVersion: '1.60.19', androidSdkVersion: 32, osName: 'Android', osVersion: '12' },
    headers: { 'X-YouTube-Client-Name': '28', 'X-YouTube-Client-Version': '1.60.19' },
  });

  // --- IOS ---
  await tryClient('IOS v19.29.1', {
    key: KEYS.IOS,
    ua: 'com.google.ios.youtube/19.29.1 (iPhone16,2; U; CPU iOS 17_5_1 like Mac OS X)',
    context: { clientName: 'IOS', clientVersion: '19.29.1', deviceMake: 'Apple', deviceModel: 'iPhone16,2', osName: 'iPhone', osVersion: '17.5.1.21F90' },
    headers: { 'X-YouTube-Client-Name': '5', 'X-YouTube-Client-Version': '19.29.1' },
  });
  await tryClient('IOS v19.29.1 без key', {
    noKey: true,
    ua: 'com.google.ios.youtube/19.29.1 (iPhone16,2; U; CPU iOS 17_5_1 like Mac OS X)',
    context: { clientName: 'IOS', clientVersion: '19.29.1', deviceMake: 'Apple', deviceModel: 'iPhone16,2', osName: 'iPhone', osVersion: '17.5.1.21F90' },
    headers: { 'X-YouTube-Client-Name': '5', 'X-YouTube-Client-Version': '19.29.1' },
  });

  // --- WEB_SAFARI ---
  await tryClient('WEB_SAFARI 2.44.20240101 +STS', {
    key: KEYS.WEB,
    ua: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4.1 Safari/605.1.15',
    context: { clientName: 'WEB_SAFARI', clientVersion: '2.20240808.00.00' },
    sts,
  });
  await tryClient('WEB_SAFARI 2.44.20240101 +STS, реальная версия', {
    key: KEYS.WEB,
    ua: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4.1 Safari/605.1.15',
    context: { clientName: 'WEB_SAFARI', clientVersion: '2.20240808.00.00' },
    sts,
    headers: { 'X-JavaScript-User-Agent': '2.20240808.00.00' },
  });

  // --- TV ---
  await tryClient('TVHTML5 7.20240808 +STS', {
    key: KEYS.TV,
    ua: 'Mozilla/5.0 (ChromiumStylePlatform) Cobalt/Version',
    context: { clientName: 'TVHTML5', clientVersion: '7.20240808.00.00' },
    sts,
  });
  await tryClient('TVHTML5_SIMPLY_EMBEDDED_PLAYER 7.20240808 +STS', {
    key: KEYS.TV,
    ua: 'Mozilla/5.0 (PlayStation; PlayStation 4/12.00) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/13.0 Safari/605.1.15',
    context: { clientName: 'TVHTML5_SIMPLY_EMBEDDED_PLAYER', clientVersion: '2.0' },
    sts,
    extraBody: { thirdParty: { embedUrl: 'https://www.youtube.com/' } },
  });

  // Базлайн WEB для сравнения.
  await tryClient('WEB (бейзлайн) +STS', {
    key: KEYS.WEB,
    ua: DESKTOP_UA,
    context: { clientName: 'WEB', clientVersion: '2.20240808.00.00' },
    sts,
  });
}

main();
