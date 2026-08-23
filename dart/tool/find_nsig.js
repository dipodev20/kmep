// Главный рабочий диагностический скрипт. Делает всё сам:
//   1. Достаёт актуальный INNERTUBE_API_KEY со страницы.
//   2. Пробует клиентов ANDROID (без key) -> IOS -> WEB (с signatureTimestamp)
//      до первого успеха.
//   3. Достаёт реальный n из adaptiveFormats (прямой url или из вложенного
//      url внутри signatureCipher).
//   4. Бутстрапит browser_shim.js + player_js_dump.js (с патчем window=this)
//      в один JS-контекст.
//   5. Перебирает ВСЕ функции на _yt_player против реального n, ранжирует
//      кандидатов: не падает, возвращает строку, длина близка к входу,
//      отличается от входа.
//
//   node tool/find_nsig.js <videoId>

const https = require('https');
const fs = require('fs');
const vm = require('vm');

const videoId = process.argv[2];
if (!videoId) {
  console.error('Usage: node tool/find_nsig.js <videoId>');
  process.exit(1);
}

// Перебор кандидатов дёргает случайные внутренности player.js, часть из
// них планирует микротаски, падающие ПОСЛЕ выхода из main (были случаи:
// g.Fn IndexedDB-код, I_d планировщик). Это шум для диагностики — глушим.
process.on('unhandledRejection', function() {});

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

function extractN(fmt) {
  if (fmt.url) {
    try { return new URL(fmt.url).searchParams.get('n'); } catch (e) { return null; }
  }
  const cipher = fmt.signatureCipher || fmt.cipher;
  if (cipher) {
    const params = new URLSearchParams(cipher);
    const innerUrl = params.get('url');
    if (innerUrl) {
      try { return new URL(innerUrl).searchParams.get('n'); } catch (e) { return null; }
    }
  }
  return null;
}

async function main() {
  const watchUrl = `https://www.youtube.com/watch?v=${videoId}&hl=en&gl=US`;
  const desktopUA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36';

  console.log('== 1. Достаю актуальный INNERTUBE_API_KEY со страницы ==');
  const watchHtml = await httpsGet(watchUrl, { 'User-Agent': desktopUA });
  const keyMatch = watchHtml.match(/"INNERTUBE_API_KEY":"([^"]+)"/);
  if (!keyMatch) {
    console.error('Не нашёл INNERTUBE_API_KEY на странице. Возможно попали на consent/капчу.');
    process.exit(1);
  }
  const apiKey = keyMatch[1];
  console.log(`Ключ найден: ${apiKey.slice(0, 10)}...`);

  console.log('\n== 2. Запрашиваю youtubei/v1/player — перебираю клиентов до первого успеха ==');
  const androidUA = 'com.google.android.youtube/17.31.35 (Linux; U; Android 11) gzip';
  const iosUA = 'com.google.ios.youtube/19.09.3 (iPhone14,3; U; CPU iOS 17_1 like Mac OS X)';

  const stsMatch = watchHtml.match(/"STS":(\d+)/);
  const signatureTimestamp = stsMatch ? parseInt(stsMatch[1], 10) : null;
  console.log(`signatureTimestamp со страницы: ${signatureTimestamp}`);

  const clientAttempts = [
    {
      name: 'ANDROID (без key)',
      noKey: true,
      body: {
        videoId,
        context: {
          client: {
            clientName: 'ANDROID', clientVersion: '17.31.35',
            androidSdkVersion: 30, hl: 'en',
            timeZone: 'UTC', utcOffsetMinutes: 0,
          },
        },
        params: 'CgIIAQ==',
      },
      headers: { 'User-Agent': androidUA, 'X-YouTube-Client-Name': '3', 'X-YouTube-Client-Version': '17.31.35' },
    },
    {
      name: 'IOS',
      apiKey: 'AIzaSyB-63vPrdThhKuerbB2N_l7Kwwcxj6yUAc',
      body: {
        videoId,
        context: {
          client: {
            clientName: 'IOS', clientVersion: '19.09.3',
            deviceModel: 'iPhone14,3', osName: 'iOS', osVersion: '17.1.0.21B74',
            hl: 'en', gl: 'US',
          },
        },
        contentCheckOk: true, racyCheckOk: true,
      },
      headers: { 'User-Agent': iosUA, 'X-YouTube-Client-Name': '5', 'X-YouTube-Client-Version': '19.09.3' },
    },
    {
      name: 'WEB (с signatureTimestamp + thirdParty embedUrl)',
      apiKey: apiKey,
      body: {
        videoId,
        context: {
          client: { clientName: 'WEB', clientVersion: '2.20240808.00.00', clientScreen: 'WATCH', hl: 'en', gl: 'US', androidSdkVersion: 31 },
          thirdParty: { embedUrl: 'https://www.youtube.com/' },
        },
        ...(signatureTimestamp ? { playbackContext: { contentPlaybackContext: { signatureTimestamp } } } : {}),
        racyCheckOk: true, contentCheckOk: true,
      },
      headers: { 'User-Agent': desktopUA, 'Origin': 'https://www.youtube.com' },
    },
  ];

  let playerJson = null;
  let usedClient = null;
  for (const attempt of clientAttempts) {
    const url = attempt.noKey
      ? 'https://www.youtube.com/youtubei/v1/player'
      : `https://www.youtube.com/youtubei/v1/player?key=${attempt.apiKey}`;
    const resp = await httpsPost(url, attempt.body, attempt.headers);
    let json;
    try { json = JSON.parse(resp); } catch (e) { console.log(`[${attempt.name}] ответ не JSON, пропускаю`); continue; }
    const status = json.playabilityStatus?.status;
    const fCount = (json.streamingData?.formats?.length || 0) + (json.streamingData?.adaptiveFormats?.length || 0);
    console.log(`[${attempt.name}] status=${status}, форматов=${fCount}`);
    if (status === undefined && json.error) {
      console.log(`  -> похоже на ошибку API: ${JSON.stringify(json.error).slice(0, 200)}`);
    } else if (status === undefined) {
      console.log(`  -> playabilityStatus вообще нет в ответе, сырой JSON (первые 300 симв.): ${resp.slice(0, 300)}`);
    }
    if (fCount > 0) { playerJson = json; usedClient = attempt.name; break; }
  }

  if (!playerJson) {
    console.error('\nНи один клиент не отдал форматы.');
    process.exit(1);
  }
  console.log(`\nИспользую ответ от клиента: ${usedClient}`);

  const formats = [
    ...(playerJson.streamingData?.formats || []),
    ...(playerJson.streamingData?.adaptiveFormats || []),
  ];
  console.log(`Форматов в ответе: ${formats.length}`);

  let realN = null;
  let sourceInfo = null;
  for (const fmt of formats) {
    const n = extractN(fmt);
    if (n) { realN = n; sourceInfo = `itag=${fmt.itag}, has_url=${!!fmt.url}, has_cipher=${!!(fmt.signatureCipher || fmt.cipher)}`; break; }
  }

  if (!realN) {
    console.error('\nНе нашёл n ни в одном формате. Первый формат целиком для диагностики:');
    console.error(JSON.stringify(formats[0], null, 2)?.slice(0, 800) || '(форматов нет вообще)');
    process.exit(1);
  }

  console.log(`\nРеальный n найден: "${realN}" (длина ${realN.length}). Источник: ${sourceInfo}`);

  console.log('\n== 3. Загружаю player.js + browser_shim.js ==');
  const dumpPath = __dirname + '/../player_js_dump.js';
  const shimPath = __dirname + '/browser_shim.js';
  if (!fs.existsSync(dumpPath)) {
    console.error(`Не найден ${dumpPath}. Прогони сначала: dart run tool/player_js_probe.dart ${videoId}`);
    process.exit(1);
  }
  const shim = fs.readFileSync(shimPath, 'utf8');
  let playerJs = fs.readFileSync(dumpPath, 'utf8');

  const beforePatch = playerJs.length;
  playerJs = playerJs.replace(/\bwindow=this\b/g, 'window=globalThis.window');
  if (playerJs.length === beforePatch) {
    console.log('(патч window=this не нашёл совпадений — возможно синтаксис отличается в этой сборке)');
  } else {
    console.log('Патч window=this -> window=globalThis.window применён.');
  }

  // Экспорт замыкания: весь плеер — одна IIFE (function(g){...})(_yt_player),
  // все внутренние функции (включая VM nsig-трансформера, см. xm/Rz в районе
  // позиции ~75700) — локалы этого скоупа и НЕвидимы снаружи. Инжектим перед
  // закрывающей скобкой коллектор: прямой eval внутри IIFE видит локальный
  // скоуп и выгружает все достижимые функции в globalThis.__closureFns.
  const closureFnNames = [...new Set(
    [...playerJs.matchAll(/(?:^|[,;\n}])([A-Za-z_$][\w$]*)\s*=\s*function\b/g)].map((m) => m[1]),
  )];
  const collector = ';(function(){var o={};var names=['
    + closureFnNames.map((s) => JSON.stringify(s)).join(',')
    + '];for(var i=0;i<names.length;i++){try{var v=eval(names[i]);'
    + 'if(typeof v==="function")o[names[i]]=v}catch(e){}}'
    + 'globalThis.__closureFns=o;})();';
  if (!/\}\)\(_yt_player\);\s*$/.test(playerJs)) {
    console.error('Не нашёл хвост "})(_yt_player);" — структура player.js изменилась, правь инжект.');
    process.exit(1);
  }
  playerJs = playerJs.replace(/\}\)\(_yt_player\);\s*$/, collector + '\n})(_yt_player);');
  console.log(`Инжектирован экспорт замыкания (${closureFnNames.length} имён собрано статически).`);

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

  const ytPlayer = sandbox._yt_player;
  if (!ytPlayer) {
    console.error('_yt_player не найден в sandbox после выполнения.');
    process.exit(1);
  }

  console.log('\n== 4. Перебираю кандидатов на реальном n ==');
  // Основной источник кандидатов — функции, выгруженные из замыкания IIFE.
  const closureFns = sandbox.__closureFns || {};
  const closureNames = Object.keys(closureFns);
  console.log(`Функций выгружено из замыкания: ${closureNames.length}`);

  const candidates = [];
  const seen = new Set();
  function addCandidate(fn, thisArg, label) {
    if (typeof fn !== 'function') return;
    const key = `${label}|${thisArg}`;
    if (seen.has(key)) return;
    seen.add(key);
    candidates.push({ fn, thisArg, label });
  }
  for (const name of closureNames) {
    addCandidate(closureFns[name], undefined, `closure.${name}`);
  }
  if (!sandbox._yt_player) {
    console.error('_yt_player не найден в sandbox после выполнения.');
    process.exit(1);
  }
  for (const name of Object.keys(sandbox._yt_player)) {
    addCandidate(sandbox._yt_player[name], sandbox._yt_player, `_yt_player.${name}`);
  }
  console.log('Точек вызова: ' + candidates.length);

  // Вызов каждого кандидата — ОТДЕЛЬНЫМ vm.runInContext с таймаутом:
  // среди внутренних функций плеера есть блокирующие/вечные циклы, один
  // такой вызов в общем потоке вешает весь перебор (проверено на практике).
  const probeInput = realN;
  const N_JSON = JSON.stringify(probeInput);
  let timedOut = 0;
  function tryCall(fnExpr) {
    const src = `globalThis.__out = { ok: false };
      try { globalThis.__out = { ok: true, val: (${fnExpr})(${N_JSON}) }; }
      catch (e) { globalThis.__out = { ok: false, threw: String(e && e.message || e) }; }`;
    try {
      vm.runInContext(src, sandbox, { filename: 'candidate.js', timeout: 250 });
      return sandbox.__out;
    } catch (e) {
      timedOut++;
      return { ok: false, timeout: true };
    }
  }

  const results = [];
  let done = 0;
  for (const c of candidates) {
    done++;
    if (done % 500 === 0) {
      process.stdout.write(`  ...проверено ${done}/${candidates.length} (таймаутов: ${timedOut})\n`);
    }
    const expr = c.label.startsWith('closure.')
      ? `globalThis.__closureFns[${JSON.stringify(c.label.slice('closure.'.length))}]`
      : `_yt_player[${JSON.stringify(c.label.slice('_yt_player.'.length))}]`;
    let r = tryCall(expr);
    if (!r || !r.ok) continue;
    const out = r.val;
    if (typeof out !== 'string') continue;
    if (out === probeInput) continue;
    if (Math.abs(out.length - probeInput.length) > 3) continue;
    r = tryCall(expr);
    if (!r || !r.ok || r.val !== out) continue;
    results.push({ label: c.label, out });
  }
  console.log(`Перебор завершён: проверено ${done}, вызовов прервано по таймауту: ${timedOut}`);

  if (results.length === 0) {
    console.log('Ни один кандидат не прошёл фильтр (строка, длина близкая к входу, '
      + 'не no-op, детерминированный).');
  } else {
    console.log(`\nПрошли фильтр: ${results.length}. Все кандидаты:\n`);
    for (const r of results) {
      console.log(`${r.label}: "${probeInput}" -> "${r.out}"`);
    }
  }
}

main().catch((e) => {
  console.error('Ошибка:', e.message);
  console.error('Stack:', e.stack);
  process.exit(1);
});
