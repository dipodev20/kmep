// Точные реплики клиентских контекстов из yt-dlp 2026.08.19
// (INNERTUBE_CLIENTS), все запросы keyless — как у них.
process.on('unhandledRejection', function () {});
const { httpsPost } = require('./fetch_challenge.js');

const videoId = process.argv[2] || 'dQw4w9WgXcQ';

const CLIENTS = {
  ios: {
    context: {
      clientName: 'IOS', clientVersion: '21.26.4',
      deviceMake: 'Apple', deviceModel: 'iPhone16,2',
      userAgent: 'com.google.ios.youtube/21.26.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)',
      osName: 'iPhone', osVersion: '18.3.2.22D82', hl: 'en',
    },
    header: '5', ua: null,
  },
  android_vr_new: {
    context: {
      clientName: 'ANDROID_VR', clientVersion: '1.65.10',
      deviceMake: 'Oculus', deviceModel: 'Quest 3',
      androidSdkVersion: 32,
      userAgent: 'com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip',
      osName: 'Android', osVersion: '12L', hl: 'en',
    },
    header: '28',
  },
  tv: {
    context: {
      clientName: 'TVHTML5', clientVersion: '7.20260707.07.00',
      userAgent: 'Mozilla/5.0 (ChromiumStylePlatform) Cobalt/25.lts.30.1034943-gold (unlike Gecko), Unknown_TV_Unknown_0/Unknown (Unknown, Unknown)',
      hl: 'en',
    },
    header: '7',
    ua: 'Mozilla/5.0 (ChromiumStylePlatform) Cobalt/25.lts.30.1034943-gold (unlike Gecko), Unknown_TV_Unknown_0/Unknown (Unknown, Unknown)',
  },
  web_safari_as_web: {
    context: {
      clientName: 'WEB', clientVersion: '2.20260708.00.00', hl: 'en',
    },
    header: '1',
    ua: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.5 Safari/605.1.15,gzip(gfe)',
  },
};

function extractN(fmt) {
  if (fmt.url) { try { return new URL(fmt.url).searchParams.get('n'); } catch (e) { return null; } }
  const cipher = fmt.signatureCipher || fmt.cipher;
  if (cipher) {
    const inner = new URLSearchParams(cipher).get('url');
    if (inner) { try { return new URL(inner).searchParams.get('n'); } catch (e) {} }
  }
  return null;
}

async function tryClient(label, spec) {
  const body = {
    videoId,
    context: { client: spec.context },
    contentCheckOk: true,
    racyCheckOk: true,
  };
  const headers = { 'User-Agent': spec.ua || spec.context.userAgent };
  if (spec.header) {
    headers['X-YouTube-Client-Name'] = spec.header;
    headers['X-YouTube-Client-Version'] = spec.context.clientVersion;
  }
  let resp;
  try {
    resp = await httpsPost('https://www.youtube.com/youtubei/v1/player', body, headers);
  } catch (e) { console.log(`[${label}] СЕТЬ: ${e.message}`); return; }
  let json;
  try { json = JSON.parse(resp); } catch (e) { console.log(`[${label}] не-JSON`); return; }
  if (json.error) { console.log(`[${label}] ERR ${json.error.code}: ${(json.error.message||'').slice(0,60)}`); return; }
  const st = json.playabilityStatus?.status;
  const formats = [...(json.streamingData?.formats||[]), ...(json.streamingData?.adaptiveFormats||[])];
  const direct = formats.filter(f=>f.url).length;
  const cipher = formats.length - direct;
  const noUrl = formats.filter(f=>!f.url && !f.signatureCipher && !f.cipher).length;
  const maxH = formats.reduce((m,f)=>Math.max(m,f.height||0),0);
  console.log(`[${label}] status=${st} форматов=${formats.length} (url=${direct}, cipher=${cipher}, без-url=${noUrl}) maxH=${maxH}`
    + (st !== 'OK' && json.playabilityStatus?.reason ? ' :: ' + json.playabilityStatus.reason.slice(0,50) : ''));
}

(async () => {
  for (const [name, spec] of Object.entries(CLIENTS)) {
    await tryClient(name, spec);
  }
})();
