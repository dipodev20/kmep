// Решает n-челлендж для НАШЕГО дампа player.js через официальный солвер yt-dlp (ejs).
// Вход: /tmp/opencode/challenge.json {n, innerUrl, s} (пишется probe_nsig_pipeline.js)
// Выход: трансформированный n от эталонного солвера.
//
//   node tool/solve_with_ytdlp.js

process.on('unhandledRejection', function () {});
const fs = require('fs');
const vm = require('vm');

const challenge = JSON.parse(fs.readFileSync('/tmp/opencode/challenge.json', 'utf8'));
const player = fs.readFileSync(__dirname + '/../player_js_dump.js', 'utf8');

const lib = fs.readFileSync('/tmp/opencode/ejs_lib.js', 'utf8');
const core = fs.readFileSync('/tmp/opencode/ejs_core.js', 'utf8');
const data = {
  type: 'player',
  player,
  requests: [
    { type: 'n', challenges: [challenge.n] },
    { type: 'sig', challenges: [challenge.s] },
  ],
};

const stdin = `${lib}\nObject.assign(globalThis, lib);\n${core}\nconsole.log(JSON.stringify(jsc(${JSON.stringify(data)})));\n`;

const { spawnSync } = require('child_process');
const res = spawnSync('node', ['-'], { input: stdin, maxBuffer: 256 * 1024 * 1024, timeout: 120000 });
if (res.status !== 0) {
  console.error('node solver failed:', res.stderr.toString().slice(0, 2000));
  process.exit(1);
}
const out = JSON.parse(res.stdout.toString().trim());
const rN = out.responses[0];
const rS = out.responses[1];
if (rN.type === 'error') {
  console.error('solver error (n):', rN.error);
  process.exit(1);
}
console.log('Эталонный (yt-dlp ejs) результат:');
console.log(`  n: "${challenge.n}" -> "${rN.data[challenge.n]}"`);
if (rS.type === 'error') {
  console.log(`  sig: ошибка — ${rS.error}`);
} else {
  const refS = rS.data[challenge.s];
  console.log(`  sig: "${challenge.s}" -> "${refS}"`);
}
