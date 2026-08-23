// Верификация ПРОД-ПАЙПЛАЙНА из lib/src/resolvers/stream_resolver.dart.
// Извлекает РЕАЛЬНЫЕ строки констант (_discoverResolveFnScript) и формат
// выражения (_defaultResolveUrlExpression) прямо из Dart-файла, бутстрапит
// их против живого player.js и проверяет итоговый URL Range-запросом.
// Гарантирует, что Dart-код и Node-диагностика не разошлись.
//
//   node tool/verify_prod_pipeline.js <videoId>

process.on('unhandledRejection', function () {});

const fs = require('fs');
const vm = require('vm');
const path = require('path');

const videoId = process.argv[2] || 'dQw4w9WgXcQ';

function extractDartRawString(dartSrc, constName) {
  const marker = `const String ${constName} = r'''`;
  const start = dartSrc.indexOf(marker);
  if (start === -1) throw new Error(`Не нашёл ${constName} в stream_resolver.dart`);
  const bodyStart = start + marker.length;
  const end = dartSrc.indexOf("''';", bodyStart);
  if (end === -1) throw new Error(`Не нашёл конец ${constName}`);
  return dartSrc.slice(bodyStart, end);
}

async function main() {
  const resolverPath = path.join(__dirname, '..', 'lib', 'src', 'resolvers', 'stream_resolver.dart');
  const dartSrc = fs.readFileSync(resolverPath, 'utf8');
  const discoverScript = extractDartRawString(dartSrc, '_discoverResolveFnScript');
  console.log('== 0. Константы извлечены из stream_resolver.dart ==');
  console.log(`discovery-скрипт: ${discoverScript.length} символов`);

  console.log('\n== 1. Свежий playerResponse (WEB) ==');
  const { fetchChallenge } = require(path.join(__dirname, 'fetch_challenge.js'));
  const ch = await fetchChallenge(videoId);
  console.log(`itag=${ch.itag}, sp="${ch.sp}", n=${ch.n}`);

  console.log('\n== 2. Бутстрап как в _ensureBootstrapped ==');
  const shimPath = path.join(__dirname, '..', '..', 'dart', 'tool', 'browser_shim.js');
  const shim = fs.readFileSync(shimPath, 'utf8');
  let playerJs = fs.readFileSync(path.join(__dirname, '..', 'player_js_dump.js'), 'utf8');
  playerJs = playerJs.replace(/\bwindow=this\b/g, 'window=globalThis.window');

  // Точная реплика _injectClosureExport из Dart (те же регэкспы).
  if (!/\}\)\(_yt_player\);\s*$/.test(playerJs)) {
    throw new Error('хвост })(_yt_player); не найден');
  }
  const names = new Set();
  for (const m of playerJs.matchAll(
      /(?:^|[,;\n}])([A-Za-z_$][\w$]*)\s*=\s*(?:async\s+)?(?:function\b|class\b)/g)) {
    names.add(m[1]);
  }
  for (const m of playerJs.matchAll(/(?:^|[;\n}])function\s+([A-Za-z_$][\w$]*)\s*\(/g)) {
    names.add(m[1]);
  }
  const nameList = [...names].map((x) => JSON.stringify(x)).join(',');
  const collector =
    ';(function(){var o={};var names=[' + nameList + '];'
    + 'for(var i=0;i<names.length;i++){try{var v=eval(names[i]);'
    + 'if(typeof v==="function")o[names[i]]=v}catch(e){}}'
    + 'globalThis.__closureFns=o;})();';
  playerJs = playerJs.replace(/\}\)\(_yt_player\);\s*$/, collector + '\n})(_yt_player);');
  console.log(`коллектор: ${names.size} имён`);

  const sandbox = {};
  sandbox.globalThis = sandbox;
  sandbox.URL = URL;
  sandbox.URLSearchParams = URLSearchParams;
  sandbox.console = console;
  vm.createContext(sandbox);
  vm.runInContext(shim, sandbox, { filename: 'browser_shim.js', timeout: 5000 });
  vm.runInContext(playerJs, sandbox, { filename: 'player.js', timeout: 15000 });
  vm.runInContext(discoverScript, sandbox, { filename: 'discovery.js', timeout: 30000 });

  const foundFn = sandbox.__kmepResolveFn;
  console.log(`__kmepResolveFn найден: ${typeof foundFn === 'function' ? 'ДА' : 'НЕТ'}`);
  if (typeof foundFn !== 'function') {
    process.exit(1);
  }

  console.log('\n== 3. Вызов через формат дефолтного выражения из Dart ==');
  // Реплика _defaultResolveUrlExpression(url, sp, s).
  const j = (x) => JSON.stringify(x);
  const expression =
    'globalThis.__kmepOut=(function(){'
    + 'var f=globalThis.__kmepResolveFn;'
    + 'if(!f||typeof f!=="function"){'
    + 'throw new Error("kmep: sig/nsig resolve function not discovered at bootstrap")}'
    + `return String(f(${j(ch.innerUrl)},${j(ch.sp)},${j(ch.s)}).KW())})()`;
  vm.runInContext(expression, sandbox, { filename: 'resolve.js', timeout: 15000 });
  const outUrl = String(sandbox.__kmepOut).trim();
  console.log(`итоговый URL (${outUrl.length} симв.): ${outUrl.slice(0, 120)}...`);

  const outN = new URL(outUrl).searchParams.get('n');
  console.log(`n: "${ch.n}" -> "${outN}"`);
  if (outN === ch.n) throw new Error('n не трансформировался');

  console.log('\n== 4. Range-запрос ==');
  const res = await new Promise((resolve, reject) => {
    const u = new URL(outUrl);
    require('https').get(
      { hostname: u.hostname, path: u.pathname + u.search, headers: { 'Range': 'bytes=0-1023' } },
      (r) => {
        const chunks = [];
        r.on('data', (c) => chunks.push(c));
        r.on('end', () => resolve({ status: r.statusCode, len: Buffer.concat(chunks).length }));
      },
    ).on('error', reject);
  });
  console.log(`HTTP ${res.status}, ${res.len} байт`);
  if (res.status !== 200 && res.status !== 206) {
    throw new Error(`сервер отклонил URL: ${res.status}`);
  }
  console.log('\nУСПЕХ: прод-пайплайн (Dart-константы) даёт рабочий URL.');
}

main().catch((e) => {
  console.error('ОШИБКА:', e.message);
  process.exit(1);
});
