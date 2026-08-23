// ЭКСПЕРИМЕНТ: чинит ли PO-token CDN-403 на датацентровом IP?
// Полный WEB-флоу: watch (vd/sts) -> POT(visitorData-binding) через
// bgutil generate_once -> player запрос с vd+POT -> sig/nsig resolve через
// player.js -> pot= в URL -> Range-чек.
//
//   node tool/pot_e2e_experiment.js <videoId> [ещё id...]

process.on('unhandledRejection', function () {});
const https = require('https');
const fs = require('fs');
const vm = require('vm');
const path = require('path');
const { execSync } = require('child_process');
const { httpsGet, httpsPost } = require('./fetch_challenge.js');

const DESKTOP =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36';
const BGUTIL_DIR = '/tmp/opencode/bgutil/server';

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
  const src = `(function(){
    var JI = globalThis.__closureFns && __closureFns.ji ? __closureFns.ji : null;
    if (!JI) throw new Error('resolve fn not found');
    return String(JI(${JSON.stringify(innerUrl)}, ${JSON.stringify(sp || '')}, ${JSON.stringify(s || '')}).KW());
  })()`;
  return String(vm.runInContext(src, sandbox, { filename: 'r.js', timeout: 15000 }));
}

function rangeCheck(url) {
  return new Promise((resolve, reject) => {
    const u = new URL(url);
    https.get({ hostname: u.hostname, path: u.pathname + u.search, headers: { 'Range': 'bytes=0-1023' } }, (res) => {
      const c = [];
      res.on('data', (x) => c.push(x));
      res.on('end', () => resolve(res.statusCode + ' ' + Buffer.concat(c).length + 'B'));
    }).on('error', reject);
  });
}

async function genPot(contentBinding) {
  const out = execSync(`node build/generate_once.js -c "${contentBinding}"`, {
    cwd: BGUTIL_DIR, timeout: 120000,
  }).toString();
  return JSON.parse(out.trim().split('\n').pop()).poToken;
}

async function run(videoId) {
  console.log('\n======== ' + videoId + ' ========');
  const html = await httpsGet(`https://www.youtube.com/watch?v=${videoId}&hl=en&gl=US`, { 'User-Agent': DESKTOP });
  const vdMatch = html.match(/"VISITOR_DATA":"((?:[^"\\]|\\.)*)"/);
  const vd = vdMatch ? JSON.parse('"' + vdMatch[1] + '"') : null;
  const sts = parseInt((html.match(/"STS":(\d+)/) || [])[1] || '0');
  if (!vd) { console.log('нет VISITOR_DATA'); return; }

  const potVd = await genPot(vd);
  console.log('POT(visitorData-binding):', potVd.slice(0, 24) + '...');

  const resp = await httpsPost('https://www.youtube.com/youtubei/v1/player', {
    videoId,
    context: { client: { clientName: 'WEB', clientVersion: '2.20240808.00.00', hl: 'en', gl: 'US', visitorData: vd } },
    contentCheckOk: true, racyCheckOk: true,
    playbackContext: { contentPlaybackContext: { signatureTimestamp: sts } },
    serviceIntegrityDimensions: { poToken: potVd },
  }, { 'User-Agent': DESKTOP, 'Origin': 'https://www.youtube.com', 'X-Goog-Visitor-Id': vd });
  const j = JSON.parse(resp);
  const formats = [...(j.streamingData?.formats || []), ...(j.streamingData?.adaptiveFormats || [])];
  const direct = formats.filter((f) => f.url).length;
  const cipher = formats.filter((f) => f.signatureCipher || f.cipher).length;
  console.log(`player+POT: status=${j.playabilityStatus?.status} форматов=${formats.length} (прямых=${direct}, cipher=${cipher}, sabr=${formats.length - direct - cipher})`);

  // Готовим лучший URL: прямой или resolved из cipher.
  let baseUrl = null;
  const fmtDirect = formats.find((f) => f.url && f.height >= 360);
  const fmtCipher = formats.find((f) => f.signatureCipher || f.cipher);
  if (fmtDirect) {
    baseUrl = fmtDirect.url;
  } else if (fmtCipher) {
    const params = new URLSearchParams(fmtCipher.signatureCipher || fmtCipher.cipher);
    baseUrl = resolveUrl(params.get('url'), params.get('sp') || 'sig', params.get('s'));
  }
  if (!baseUrl) { console.log('URL получить не удалось'); return; }

  // Контрольный прогон без pot и с pot.
  const withoutPot = await rangeCheck(baseUrl);
  const withPot = await rangeCheck(baseUrl + '&pot=' + potVd);
  console.log(`Range без pot=: ${withoutPot}`);
  console.log(`Range с  pot=: ${withPot}`);
}

(async () => {
  const ids = process.argv.slice(2);
  for (const id of (ids.length ? ids : ['jNQXAC9IVRw'])) {
    await run(id).catch((e) => console.error('Ошибка:', e.message));
  }
})();
