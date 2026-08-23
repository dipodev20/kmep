// Проверка пайплайна sig/nsig через публичные функции player.js.
// Гипотеза (по подходу yt-dlp ejs-солвера): функция с маркером X.Y("alr","yes")
// в теле (ji) принимает (urlString, keyName, sigValue), возвращает g.iO,
// а трансформация n происходит лениво при KW()/get().
//
//   node tool/probe_nsig_pipeline.js <videoId>
//
// Шаги: качает playerResponse (WEB), берёт signatureCipher первого формата,
// бутстрапит шим+player.js (с расширенным экспортом замыкания: и =class),
// зовёт _yt_player.ji(innerUrl, 's', sig), печатает KW()/get('n') результата,
// затем делает реальный Range-запрос на итоговый URL для проверки 200.

process.on('unhandledRejection', function () {});

const https = require('https');
const fs = require('fs');
const vm = require('vm');

const videoId = process.argv[2];
if (!videoId) {
  console.error('Usage: node tool/probe_nsig_pipeline.js <videoId>');
  process.exit(1);
}

function httpsGet(url, headers) {
  return new Promise((resolve, reject) => {
    https.get(url, { headers }, (res) => {
      let chunks = '';
      res.on('data', (c) => chunks += c);
      res.on('end', () => resolve(chunks));
    }).on('error', reject);
  });
}

function httpsGetBinaryFollow(url, headers, maxRedirects = 5) {
  return new Promise((resolve, reject) => {
    const u = new URL(url);
    https.get({
      hostname: u.hostname,
      path: u.pathname + u.search,
      headers,
    }, (res) => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location && maxRedirects > 0) {
        res.resume();
        const next = new URL(res.headers.location, u).toString();
        return resolve(httpsGetBinaryFollow(next, headers, maxRedirects - 1));
      }
      const chunks = [];
      res.on('data', (c) => chunks.push(c));
      res.on('end', () => resolve({ status: res.statusCode, headers: res.headers, body: Buffer.concat(chunks) }));
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

async function main() {
  const watchUrl = `https://www.youtube.com/watch?v=${videoId}&hl=en&gl=US`;
  const desktopUA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36';

  console.log('== 1. watch-страница: ключ + signatureTimestamp ==');
  const watchHtml = await httpsGet(watchUrl, { 'User-Agent': desktopUA });
  const apiKey = watchHtml.match(/"INNERTUBE_API_KEY":"([^"]+)"/)?.[1];
  const stsMatch = watchHtml.match(/"STS":(\d+)/);
  const signatureTimestamp = stsMatch ? parseInt(stsMatch[1], 10) : null;
  if (!apiKey || !signatureTimestamp) {
    console.error('Не нашёл ключ или STS на странице.');
    process.exit(1);
  }
  console.log(`ключ ${apiKey.slice(0, 10)}..., STS=${signatureTimestamp}`);

  console.log('\n== 2. playerResponse через WEB ==');
  const resp = await httpsPost(
    `https://www.youtube.com/youtubei/v1/player?key=${apiKey}`,
    {
      videoId,
      context: {
        client: { clientName: 'WEB', clientVersion: '2.20240808.00.00', clientScreen: 'WATCH', hl: 'en', gl: 'US' },
        thirdParty: { embedUrl: 'https://www.youtube.com/' },
      },
      playbackContext: { contentPlaybackContext: { signatureTimestamp } },
      racyCheckOk: true, contentCheckOk: true,
    },
    { 'User-Agent': desktopUA, 'Origin': 'https://www.youtube.com' },
  );
  const json = JSON.parse(resp);
  const status = json.playabilityStatus?.status;
  const formats = [
    ...(json.streamingData?.formats || []),
    ...(json.streamingData?.adaptiveFormats || []),
  ];
  console.log(`status=${status}, форматов=${formats.length}`);

  const cipherFmt = formats.find((f) => f.signatureCipher || f.cipher);
  if (!cipherFmt) {
    console.error('Нет формата с signatureCipher — нечего проверять.');
    process.exit(1);
  }
  const cipherParams = new URLSearchParams(cipherFmt.signatureCipher || cipherFmt.cipher);
  const sigS = cipherParams.get('s');
  const sigParam = cipherParams.get('sp') || 'sig';
  const innerUrl = cipherParams.get('url');
  const realN = new URL(innerUrl).searchParams.get('n');
  fs.writeFileSync('/tmp/opencode/challenge.json', JSON.stringify({ n: realN, innerUrl, s: sigS, sp: sigParam }));
  console.log(`itag=${cipherFmt.itag}: s(${sigS.length}), sp="${sigParam}", n="${realN}"`);
  console.log(`innerUrl: ${innerUrl.slice(0, 140)}...`);

  console.log('\n== 3. Бутстрап player.js ==');
  const dumpPath = __dirname + '/../player_js_dump.js';
  const shim = fs.readFileSync(__dirname + '/browser_shim.js', 'utf8');
  let playerJs = fs.readFileSync(dumpPath, 'utf8');
  const beforePatch = playerJs.length;
  playerJs = playerJs.replace(/\bwindow=this\b/g, 'window=globalThis.window');
  console.log(playerJs.length === beforePatch ? '(патч не нашёл совпадений)' : 'Патч window=this применён.');

  // Расширенный экспорт замыкания: NAME=function И NAME=class И function NAME(
  const names = new Set();
  for (const m of playerJs.matchAll(/(?:^|[,;\n}])([A-Za-z_$][\w$]*)\s*=\s*(?:async\s+)?(?:function\b|class\b)/g)) {
    names.add(m[1]);
  }
  for (const m of playerJs.matchAll(/(?:^|[;\n}])function\s+([A-Za-z_$][\w$]*)\s*\(/g)) {
    names.add(m[1]);
  }
  const nameList = [...names];
  const collector = ';(function(){var o={};var names=['
    + nameList.map((x) => JSON.stringify(x)).join(',')
    + '];for(var i=0;i<names.length;i++){try{var v=eval(names[i]);'
    + 'if(typeof v==="function")o[names[i]]=v}catch(e){}}'
    + 'globalThis.__closureFns=o;})();';
  if (!/\}\)\(_yt_player\);\s*$/.test(playerJs)) {
    console.error('Хвост })(_yt_player); не найден.');
    process.exit(1);
  }
  playerJs = playerJs.replace(/\}\)\(_yt_player\);\s*$/, collector + '\n})(_yt_player);');
  console.log(`Экспорт замыкания: ${nameList.length} имён.`);

  const sandbox = {};
  sandbox.globalThis = sandbox;
  sandbox.URL = URL;
  sandbox.URLSearchParams = URLSearchParams;
  if (typeof TextEncoder !== 'undefined') sandbox.TextEncoder = TextEncoder;
  if (typeof TextDecoder !== 'undefined') sandbox.TextDecoder = TextDecoder;
  sandbox.console = console;
  vm.createContext(sandbox);

  vm.runInContext(shim, sandbox, { filename: 'browser_shim.js', timeout: 5000 });
  vm.runInContext(playerJs, sandbox, { filename: 'player.js', timeout: 15000 });
  console.log('player.js выполнен без исключений.');

  const yt = sandbox._yt_player;
  console.log(`_yt_player: ${Object.keys(yt).length} свойств; iO=${typeof yt.iO}, ji=${typeof yt.ji}`);
  console.log(`__closureFns: ${Object.keys(sandbox.__closureFns || {}).length}; ji там: ${typeof sandbox.__closureFns?.ji}`);

  console.log('\n== 4. Вызываю ji(innerUrl, sp, sig) ==');
  const src = `
    globalThis.__res = { ok: false };
    var JI = globalThis.__closureFns && __closureFns.ji ? __closureFns.ji : _yt_player.ji;
    try {
      var U = JI(${JSON.stringify(innerUrl)}, ${JSON.stringify(sigParam)}, ${JSON.stringify(sigS)});
      globalThis.__res = {
        ok: true,
        type: typeof U,
        kw: (U && typeof U.KW === "function") ? String(U.KW()) : null,
        getN: (U && typeof U.get === "function") ? String(U.get("n")) : null,
      };
    } catch (e) {
      globalThis.__res = { ok: false, err: String(e && e.message || e) };
    }
  `;
  vm.runInContext(src, sandbox, { filename: 'probe_ji.js', timeout: 10000 });
  const res = sandbox.__res;
  if (!res.ok) {
    console.error('ji бросил исключение:', res.err);
    process.exit(1);
  }
  console.log(`тип результата: ${res.type}`);

  let outUrlStr = res.kw;
  if (!outUrlStr) {
    console.log('KW() недоступен/пустой, get(n)=', res.getN);
    process.exit(1);
  }
  const outN = new URL(outUrlStr).searchParams.get('n');
  const outS = new URL(outUrlStr).searchParams.get('s');
  console.log(`n: "${realN}" -> "${outN}" (${outN === realN ? 'НЕ ИЗМЕНИЛСЯ' : 'изменён, длина ' + outN.length + ' vs ' + realN.length})`);
  const outSDecoded = outS ? decodeURIComponent(outS) : null;
  console.log(`s: ${outS ? 'присутствует (' + outSDecoded.length + ' симв. после decode): "' + outSDecoded + '"' : 'отсутствует'}`);
  console.log(`итоговый URL (первые 160): ${outUrlStr.slice(0, 160)}...`);

  if (outN === realN) {
    console.log('\nn не изменился — ji не трансформирует n (или триггер другой). Проверяю get("n") до KW():');
    console.log(`get("n") напрямую: ${res.getN}`);
  }
  console.log(`\nНаш результат для сравнения с solve_with_ytdlp.js: "${outN}"`);

  console.log('\n== 5. Реальный Range-запрос на итоговый URL ==');
  const http = await httpsGetBinaryFollow(outUrlStr.replace(/^https:/, 'https:'), {
    'User-Agent': desktopUA,
    'Range': 'bytes=0-1023',
    'Origin': 'https://www.youtube.com',
  });
  console.log(`HTTP ${http.status}, получено ${http.body.length} байт, content-type=${http.headers['content-type']}`);
  if (http.status === 200 || http.status === 206) {
    console.log('\nУСПЕХ: URL с трансформированным n отвечает 2xx.');
  } else {
    console.log('\nНЕУСПЕХ: сервер отклонил URL (403 = неверный sig/nsig).');
  }
}

main().catch((e) => {
  console.error('Ошибка:', e.message);
  console.error(e.stack);
  process.exit(1);
});
