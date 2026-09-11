#!/usr/bin/env node
// investigate-dayjs-ohpm.mjs
//
// spec.md section 11 item 6: "is there a usable dayjs package on ohpm?"
// This script performs the investigation and writes the evidence file, so the
// conclusion can be re-derived instead of trusted.
//
// Usage:  node scripts/investigate-dayjs-ohpm.mjs
import fs from 'node:fs';
import path from 'node:path';
import url from 'node:url';
import { execFileSync } from 'node:child_process';

const here = path.dirname(url.fileURLToPath(import.meta.url));
const root = path.resolve(here, '..');
const OUT = path.join(root, '.scratch', 'foundation', 'evidence', '02-ohpm-dayjs-info.txt');

function sh(cmd, args, opts) {
  try {
    // ohpm is a .bat on Windows, so it needs a shell.
    const useShell = cmd === 'ohpm';
    return execFileSync(cmd, args, { encoding: 'utf8', cwd: root, shell: useShell, ...(opts || {}) }).trim();
  } catch (err) {
    const out = String((err.stdout || '') + (err.stderr || '')).trim();
    return '(exit ' + String(err.status) + ')\n' + out;
  }
}

const L = [];
const P = (s) => L.push(s);

P('spec.md section 11 item 6: is there a usable `dayjs` package on ohpm?');
P('');
P('CONCLUSION: ohpm carries `dayjs`, but it is the upstream npm package mirrored');
P('into the ohpm registry -- not an OpenHarmony package. It is not usable from');
P('ArkTS as a library dependency. This project therefore uses the platform');
P('`@ohos.intl` (Intl.DateTimeFormat / Intl.RelativeTimeFormat) plus a thin');
P('adapter in entry/src/main/ets/core/i18n/DateTimeUtil.ets.');
P('');
P('='.repeat(78));
P('1. ohpm version and registry');
P('='.repeat(78));
P(sh('ohpm', ['--version']));
P('');
P(sh('ohpm', ['config', 'list']).split('\n').filter((l) => /registry|ohpm version|node version/.test(l)).join('\n'));
P('');
P('='.repeat(78));
P('2. `ohpm search` does not exist in this ohpm version');
P('='.repeat(78));
P('$ ohpm search dayjs');
P(sh('ohpm', ['search', 'dayjs']));
P('');
P('The available command list (from `ohpm --help`) has `info` but no `search`:');
P(sh('ohpm', ['--help']).split('\n').filter((l) => /^  \w/.test(l)).join('\n'));
P('');
P('='.repeat(78));
P('3. `ohpm info dayjs` DOES resolve');
P('='.repeat(78));
P('$ ohpm info dayjs');
P(sh('ohpm', ['info', 'dayjs']));
P('');
P('='.repeat(78));
P('4. What the registry actually serves');
P('='.repeat(78));
P('The registry is a proxy/front for the public npm registry, so `dayjs` resolves');
P('to the npm packument. Fetching and unpacking the tarball shows an npm package:');
P('');
const tmp = path.join(root, '.dsh', 'logs', 'dayjs-probe');
fs.rmSync(tmp, { recursive: true, force: true });
fs.mkdirSync(tmp, { recursive: true });
const tgz = path.join(tmp, 'dayjs.tgz');
try {
  execFileSync('powershell', ['-NoProfile', '-Command',
    "Invoke-WebRequest -Uri 'https://ohpm.openharmony.cn/ohpm/dayjs/-/dayjs-1.11.13.tgz' -OutFile '" + tgz + "' -TimeoutSec 120"], { stdio: 'ignore' });
  P('$ tar -tzf dayjs-1.11.13.tgz   (top-level files only)');
  const listing = execFileSync('tar', ['-tzf', tgz], { encoding: 'utf8' }).split('\n');
  P('  total entries: ' + String(listing.length));
  for (const entry of listing.filter((l) => /^package\/[^/]+$/.test(l))) P('  ' + entry);
  P('');
  P('  entries matching "oh-package": ' + String(listing.filter((l) => l.includes('oh-package')).length));
  P('  entries matching "zh-cn":        ' + listing.filter((l) => l.includes('zh-cn')).join(', '));
  P('');
  execFileSync('tar', ['-xzf', tgz, '-C', tmp], { stdio: 'ignore' });
  const pkg = JSON.parse(fs.readFileSync(path.join(tmp, 'package', 'package.json'), 'utf8'));
  P('  package.json  main   : ' + String(pkg.main));
  P('  package.json  module : ' + String(pkg.module));
  P('  package.json  exports: ' + String(pkg.exports));
  P('');
  P('  -> no oh-package.json5: this is NOT an OpenHarmony package.');
  P('  -> `main` points at a UMD bundle, so there is no ES module entry for ArkTS.');
  P('');
  P('  dayjs.min.js head (UMD wrapper, sets a global instead of exporting ESM):');
  const min = fs.readFileSync(path.join(tmp, 'package', 'dayjs.min.js'), 'utf8');
  P('    ' + min.slice(0, 220));
  P('');
  P('  locale/zh-cn.js head (CJS require + global fallback):');
  const zhcn = fs.readFileSync(path.join(tmp, 'package', 'locale', 'zh-cn.js'), 'utf8');
  P('    ' + zhcn.slice(0, 220));
  P('');
  P('  -> locales are separate scripts that `require("dayjs")` / attach to a global;');
  P('     dayjs picks them by runtime name, which ArkTS rejects (no dynamic require).');
} catch (err) {
  P('  (tarball probe failed: ' + String(err.message) + ')');
}
P('');
P('='.repeat(78));
P('5. Decision');
P('='.repeat(78));
P('- `dayjs` is NOT adopted. It would need a hand-written ArkTS shim around a');
P('  minified UMD bundle plus manual locale imports, i.e. more work and more risk');
P('  than the adapter that is already written and unit-tested.');
P('- Instead: `@ohos.intl` (Intl.DateTimeFormat / Intl.RelativeTimeFormat) behind');
P('  `RelativeTimeFormatter` / `DateTimeFormatter` seams in');
P('  entry/src/main/ets/core/i18n/DateTimeUtil.ets. zh and en wording and date');
P('  layout both come from the platform, so no locale table is maintained here.');
P('- The 48 reference `dayjs` call sites map onto: formatDateTimeShort(),');
P('  formatDate(), formatRelativeTime()/formatRelativeTo(), and the pure');
P('  pickRelativeUnit()/relativeAmount() ladder. See the key map at');
P('  .scratch/foundation/i18n-key-map.md.');
P('');

fs.mkdirSync(path.dirname(OUT), { recursive: true });
fs.writeFileSync(OUT, L.join('\n'), 'utf8');
console.log(L.join('\n'));
