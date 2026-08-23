// Матрица экспериментов POT-биндинга на видео, где был urlRejected.
// Для каждого видео: 2 клиента x 2 биндинга токена -> статус/форматы/Range.
//
//   node tool/pot_binding_experiment.js <videoId> [...]

process.on('unhandledRejection', function () {});
const https = require('https');
const fs = require('fs');
const vm = require('vm');
const path = require('path');
const { httpsGet, httpsPost } = require('./fetch_challenge.js');

const DESKTOP =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36';
const POT_HTTP = 'http://127.0.0.1:4416/get_pot';

let sandbox = null;
function bootstrapPlayer() {
  if (sandbox) return;
  const shim = fs.readFileSync(path.join(__dirname, 'browser_shim.js'), 'utf8');
  let p = fs.readFileSync(path.join(__dirname, '..', 'player_js_dump.js'), 'utf8');
  p = p.replace(/\bwindow=this\b/g, 'window=globalThis.window');
  const names = new Set();
  for (const m of p.matchAll(/(?:^|[,;\n}])([A-Za-z_$][\w$]*)\s*=\s*(?:async\s+)?(?:function\b|class\b)/g)) names.add(m[1]);
  for (const m of p.matchAll(/(?:^|[;\n}])function\s+([A-Za-z_$][\w$]*)\s*\(/g)) names.add(m[1]);
  const col = ';(function(){var o={};var names=[' + [...names].map((x) => JSON.stringify(x)).join(',')
    + '];for(var i=0;i<names.length;i++){try{var v=eval(names[i]);if(typeof v==="function")o[names[i]]=v}catch(e){}}globalThis.__closureFns=o;})();';
  p = p.replace(/\}\)\(_yt_player\);\s*$/, col + '\n})(_yt_player);');
  sandbox = {};
  sandbox.globalThis = sandbox;
  sandbox.URL = URL;
  sandbox.URLSearchParams = URLSearchParams;
  sandbox.console = console;
  vm.createContext(sandbox);
  vm.runInContext(shim, sandbox, { filename: 'shim.js', timeout: 5000 });
  vm.runInContext(p, sandbox, { filename: 'player.js', timeout: 15000 });
}

function resolveUrl(innerUrl, sp, s) {
  bootstrapPlayer();
  return String(vm.runInContext(`(function(){
    var JI = globalThis.__closureFns.ji;
    return String(JI(${JSON.stringify(innerUrl)}, ${JSON.stringify(sp || '')}, ${JSON.stringify(s || '')}).KW());
  })()`, sandbox, { filename: 'r.js', timeout: 15000 }));
}

function httpJson(url, opts = {}) {
  return new Promise((resolve, reject) => {
    const u = new URL(url);
    const mod = u.protocol === 'https:' ? require('https') : require('http');
    const req = mod.request({
      hostname: u.hostname, port: u.port || (u.protocol === 'https:' ? 443 : 80),
      path: u.pathname + u.search,
      method: opts.method || 'GET', headers: opts.headers || {},
    }, (res) => {
      let chunks = '';
      res.on('data', (c) => chunks += c);
      res.on('end', () => resolve({ status: res.statusCode, body: chunks }));
    });
    req.on('error', reject);
    if (opts.body) req.write(opts.body);
    req.end();
  });
}

async function genPot(binding) {
  const r = await httpJson(POT_HTTP, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ content_binding: binding }),
  });
  return JSON.parse(r.body).poToken;
}

function range(url) {
  return new Promise((resolve, reject) => {
    const u = new URL(url);
    https.get({ hostname: u.hostname, path: u.pathname + u.search, headers: { 'Range': 'bytes=0-1023' } }, (res) => {
      const c = [];
      res.on('data', (x) => c.push(x));
      res.on('end', () => resolve(res.statusCode));
    }).on('error', reject);
  });
}

async function playerReq(videoId, clientName, clientVersion, ua, extraCtx, headerName, vd, pot, sts) {
  const ctxClient = { clientName, clientVersion, hl: 'en', gl: 'US', ...(extraCtx || {}) };
  if (vd) ctxClient.visitorData = vd;
  const body = {
    videoId,
    context: { client: ctxClient },
    contentCheckOk: true, racyCheckOk: true,
    ...(sts ? { playbackContext: { contentPlaybackContext: { signatureTimestamp: sts } } } : {}),
    ...(pot ? { serviceIntegrityDimensions: { poToken: pot } } : {}),
  };
  const headers = { 'User-Agent': ua };
  if (headerName) {
    headers['X-YouTube-Client-Name'] = headerName;
    headers['X-YouTube-Client-Version'] = clientVersion;
  }
  if (vd) headers['X-Goog-Visitor-Id'] = vd;
  const resp = await httpsPost('https://www.youtube.com/youtubei/v1/player', body, headers);
  const j = JSON.parse(resp);
  const formats = [...(j.streamingData?.formats || []), ...(j.streamingData?.adaptiveFormats || [])];
  return {
    status: j.playabilityStatus?.status,
    reason: (j.playabilityStatus?.reason || '').slice(0, 40),
    formats,
    responseContextVd: j.responseContext?.visitorData,
  };
}

async function bestPlayableUrl(formats) {
  // прямой URL? если в нём сырой n — трансформируем через ji (как резолвер).
  const d = formats.find((f) => f.url && f.height >= 360) || formats.find((f) => f.url);
  if (d) {
    const u = new URL(d.url);
    if (!u.searchParams.has('n')) return d.url;
    bootstrapPlayer();
    return String(vm.runInContext(`(function(){
      var JI = globalThis.__closureFns.ji;
      return String(JI(${JSON.stringify(d.url)}, '', '').KW());
    })()`, sandbox, { filename: 'r.js', timeout: 15000 }));
  }
  // иначе resolve первого cipher
  const c = formats.find((f) => f.signatureCipher || f.cipher);
  if (c) {
    const params = new URLSearchParams(c.signatureCipher || c.cipher);
    return resolveUrl(params.get('url'), params.get('sp') || 'sig', params.get('s'));
  }
  return null;
}

async function run(videoId) {
  console.log('\n======== ' + videoId + ' ========');
  const html = await httpsGet(`https://www.youtube.com/watch?v=${videoId}&hl=en&gl=US`, { 'User-Agent': DESKTOP });
  const vdM = html.match(/"VISITOR_DATA":"((?:[^"\\]|\\.)*)"/);
  const vd = vdM ? JSON.parse('"' + vdM[1] + '"') : null;
  const sts = parseInt((html.match(/"STS":(\d+)/) || [])[1] || '0');

  const potVid = await genPot(videoId);
  console.log('токены готовы: videoId-binding + visitorData-binding');
  const potVd = vd ? await genPot(vd) : null;

  const combos = [
    ['ANDROID_VR+POT(vid)', async () => {
      const r = await playerReq(videoId, 'ANDROID_VR', '1.65.10',
        'com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip',
        { deviceMake: 'Oculus', deviceModel: 'Quest 3', androidSdkVersion: 32, osName: 'Android', osVersion: '12L' },
        '28', null, potVid, null);
      return [r, potVid];
    }],
    ['WEB+POT(vid)', async () => {
      const r = await playerReq(videoId, 'WEB', '2.20240808.00.00', DESKTOP, {}, '1', null, potVid, sts);
      return [r, potVid];
    }],
    ['WEB+POT(vd)', async () => {
      const r = await playerReq(videoId, 'WEB', '2.20240808.00.00', DESKTOP, {}, '1', vd, potVd, sts);
      return [r, potVd];
    }],
  ];

  for (const [label, fn] of combos) {
    try {
      const [r, pot] = await fn();
      const direct = r.formats.filter((f) => f.url).length;
      const cipher = r.formats.filter((f) => f.signatureCipher || f.cipher).length;
      const sabr = r.formats.length - direct - cipher;
      let line = `[${label}] ${r.status} f=${r.formats.length} (прямых=${direct}, cipher=${cipher}, sabr=${sabr})`;
      if (r.reason) line += ' :: ' + r.reason;
      console.log(line);
      if (r.status !== 'OK') continue;
      const url = await bestPlayableUrl(r.formats);
      if (!url) { console.log('   URL нет'); continue; }
      console.log('   Range без pot:', await range(url));
      console.log('   Range с pot=:', await range(url + '&pot=' + pot));
    } catch (e) {
      console.log(`[${label}] ОШИБКА ${e.message}`);
    }
  }
}

(async () => {
  for (const id of process.argv.slice(2)) {
    await run(id).catch((e) => console.error(id, 'Ошибка:', e.message));
  }
})();
