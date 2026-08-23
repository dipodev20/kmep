// Быстрая проверка гипотезы "shim + player.js целиком выполняется без
// исключений" — через node, а не через Flutter/QuickJS.
//
//   node tool/test_harness.js

const fs = require('fs');
const vm = require('vm');

const shimPath = __dirname + '/browser_shim.js';
const dumpPath = __dirname + '/../player_js_dump.js';

if (!fs.existsSync(shimPath)) {
  console.error(`Не найден ${shimPath}.`);
  process.exit(1);
}
if (!fs.existsSync(dumpPath)) {
  console.error(`Не найден ${dumpPath}. Сначала прогони: dart run tool/player_js_probe.dart <videoId>`);
  process.exit(1);
}

const shim = fs.readFileSync(shimPath, 'utf8');
let playerJs = fs.readFileSync(dumpPath, 'utf8');
playerJs = playerJs.replace(/\bwindow=this\b/g, 'window=globalThis.window');

const sandbox = {};
sandbox.globalThis = sandbox;

// Node vm.createContext() даёт ЯЗЫКОВЫЕ builtins бесплатно, но НЕ host-API
// вроде URL/TextEncoder — прокидываем руками.
sandbox.URL = URL;
sandbox.URLSearchParams = URLSearchParams;
if (typeof TextEncoder !== 'undefined') sandbox.TextEncoder = TextEncoder;
if (typeof TextDecoder !== 'undefined') sandbox.TextDecoder = TextDecoder;
if (typeof atob !== 'undefined') sandbox.atob = atob;
if (typeof btoa !== 'undefined') sandbox.btoa = btoa;
sandbox.console = console;

vm.createContext(sandbox);

console.log('== Выполняю shim ==');
try {
  vm.runInContext(shim, sandbox, { filename: 'browser_shim.js', timeout: 5000 });
  console.log('OK: shim выполнился без исключений.');
} catch (e) {
  console.error('ПАДЕНИЕ на shim:', e.message);
  process.exit(1);
}

console.log('\n== Выполняю player.js (может занять несколько секунд) ==');
try {
  vm.runInContext(playerJs, sandbox, { filename: 'player.js', timeout: 15000 });
  console.log('OK: player.js выполнился без исключений!');
} catch (e) {
  console.error('ПАДЕНИЕ на player.js:', e.message);
  console.error('Stack:', e.stack);
  process.exit(1);
}

console.log('\n== Ищу экспортированные свойства _yt_player (g.XXX внутри IIFE) ==');
const ytPlayer = sandbox._yt_player;
if (!ytPlayer) {
  console.log('_yt_player не найден в sandbox.');
} else {
  const keys = Object.keys(ytPlayer).filter(k => typeof ytPlayer[k] === 'function');
  console.log(`Найдено ${keys.length} функций на _yt_player. Первые 50 имён:`);
  console.log(keys.slice(0, 50).join(', '));
}
