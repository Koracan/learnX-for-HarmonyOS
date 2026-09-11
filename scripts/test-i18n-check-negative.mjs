#!/usr/bin/env node
// test-i18n-check-negative.mjs
//
// Negative-validation suite for scripts/check-i18n-keys.mjs: proves the checker
// actually fails when a key is dropped, when an unknown key appears, when a
// reference key disappears from the manifest, and when a value is blanked out.
//
// Every case mutates a resource/manifest file, runs the checker, then restores
// the file from an in-memory backup (finally block). No ArkTS source is touched,
// so this can run while another agent owns the UI files.
//
// Usage:  node scripts/test-i18n-check-negative.mjs
// Exit code 0 iff the baseline passes and every injected defect is detected.
import fs from 'node:fs';
import { execFileSync } from 'node:child_process';

const RES = 'entry/src/main/resources';
const MANIFEST = '.scratch/foundation/i18n-keys.json';
const ZH = RES + '/zh_CN/element/string.json';
const EN = RES + '/en_US/element/string.json';

function runChecker() {
  try {
    const out = execFileSync('node', ['scripts/check-i18n-keys.mjs'], { encoding: 'utf8' });
    return { code: 0, out: out };
  } catch (err) {
    return { code: err.status === undefined ? -1 : err.status, out: String(err.stdout || '') };
  }
}

function report(title, result, expectFail) {
  const verdict = (result.code !== 0) === expectFail ? 'PASS' : 'UNEXPECTED';
  const interesting = result.out.split('\n').filter((l) => /MISSING|EXTRA|EMPTY|drift|!!|RESULT|source references/.test(l));
  console.log('=== ' + title);
  console.log('    exit=' + result.code + ' expectedFail=' + expectFail + ' -> ' + verdict);
  for (const line of interesting) console.log('    ' + line.trim());
  console.log('');
  return verdict === 'PASS';
}

function withRestore(file, mutate) {
  const backup = fs.readFileSync(file, 'utf8');
  try {
    mutate(file);
    return runChecker();
  } finally {
    fs.writeFileSync(file, backup, 'utf8');
  }
}

function editJson(file, mutate) {
  const j = JSON.parse(fs.readFileSync(file, 'utf8'));
  mutate(j);
  fs.writeFileSync(file, JSON.stringify(j, null, 2) + '\n', 'utf8');
}

let allPass = true;

allPass = report('baseline (no mutation)', runChecker(), false) && allPass;

allPass = report('delete loh_back from en_US -> MISSING', withRestore(EN, (file) => {
  editJson(file, (j) => { j.string = j.string.filter((e) => e.name !== 'loh_back'); });
}), true) && allPass;

allPass = report('append ui_bogus_key to zh_CN -> EXTRA', withRestore(ZH, (file) => {
  editJson(file, (j) => { j.string.push({ name: 'ui_bogus_key', value: '幽灵键' }); });
}), true) && allPass;

allPass = report('drop reference key back from the manifest -> drift', withRestore(MANIFEST, (file) => {
  editJson(file, (j) => { j.referenceKeys = j.referenceKeys.filter((k) => k !== 'back'); });
}), true) && allPass;

allPass = report('blank out loh_ok in zh_CN -> EMPTY', withRestore(ZH, (file) => {
  editJson(file, (j) => { for (const e of j.string) if (e.name === 'loh_ok') e.value = '   '; });
}), true) && allPass;

allPass = report('restored (no mutation)', runChecker(), false) && allPass;

console.log(allPass ? 'NEGATIVE SUITE: ALL PASS' : 'NEGATIVE SUITE: FAILED');
process.exit(allPass ? 0 : 1);
