// Точное извлечение функции по имени из player_js_dump.js — со сбалансированными
// скобками, а не grep -A N (может обрезать функцию посередине).
//
//   node tool/extract_function.js eAO
//   node tool/extract_function.js eAO player_js_dump.js

const fs = require('fs');

const name = process.argv[2];
if (!name) {
  console.error('Usage: node tool/extract_function.js <functionName> [path/to/player_js_dump.js]');
  process.exit(1);
}
const dumpPath = process.argv[3] || (__dirname + '/../player_js_dump.js');

if (!fs.existsSync(dumpPath)) {
  console.error(`Не найден ${dumpPath}`);
  process.exit(1);
}

const js = fs.readFileSync(dumpPath, 'utf8');
const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

const patterns = [
  new RegExp(`${escaped}\\s*=\\s*function\\s*\\(`),
  new RegExp(`function\\s+${escaped}\\s*\\(`),
];

let found = false;
for (const pattern of patterns) {
  const m = pattern.exec(js);
  if (!m) continue;
  found = true;

  const braceStart = js.indexOf('{', m.index);
  if (braceStart === -1) {
    console.log('Нашёл сигнатуру, но не нашёл открывающую скобку тела.');
    continue;
  }
  let depth = 0;
  let end = -1;
  for (let i = braceStart; i < js.length; i++) {
    if (js[i] === '{') depth++;
    if (js[i] === '}') {
      depth--;
      if (depth === 0) { end = i; break; }
    }
  }
  if (end === -1) {
    console.log('Не нашёл закрывающую скобку.');
    continue;
  }

  const fullDef = js.substring(m.index, end + 1);
  console.log(`=== Найдено (${fullDef.length} символов) ===`);
  console.log(fullDef);

  const calls = [...fullDef.matchAll(/\b([a-zA-Z_$][\w$]{0,10})\s*\(/g)]
    .map(x => x[1])
    .filter(n => n !== name && !['function', 'if', 'for', 'while', 'switch', 'catch', 'return'].includes(n));
  const uniqueCalls = [...new Set(calls)];
  if (uniqueCalls.length) {
    console.log(`\n--- Вызывает изнутри: ${uniqueCalls.join(', ')} ---`);
  }
  console.log('');
}

if (!found) {
  console.log(`Не нашёл ни "${name}=function(" ни "function ${name}(" в файле. `
    + `Возможно это свойство объекта (например "${name}:function(") — `
    + `попробуй grep -o '.\\{40\\}${name}[:=].\\{40\\}' ${dumpPath}`);
}
