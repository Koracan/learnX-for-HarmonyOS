#!/usr/bin/env node
// check-i18n-keys.mjs
//
// One command that lists what is missing from the app's i18n resources, for
// every locale, plus the keys ArkTS source references that do not exist.
//
// Checks
//   1. MISSING  -- a manifest key has no entry in that locale's string.json
//   2. EMPTY    -- the entry exists but its value is empty/whitespace
//   3. EXTRA    -- a loh_*/ui_* entry exists in resources but not in the manifest
//   4. reference drift -- the reference dictionaries have a key the manifest lacks
//      (independent re-parse of reference/learnOH-old/src/assets/translations)
//   5. SOURCE   -- an ArkTS file references $r('app.string.x') / t('x') / tName('x')
//      for a key that is not in the manifest, or passes the wrong number of
//      placeholder arguments
//   6. UNTRANSLATED (informational) -- en_US value identical to zh_CN
//
// Usage:  node scripts/check-i18n-keys.mjs [--json]
// Exit code 0 iff checks 1-5 are clean.
import fs from 'node:fs';
import path from 'node:path';
import url from 'node:url';
import { buildRows } from './i18n-lib.mjs';
import { checkSourceKeys } from './i18n-source-keys.mjs';

const here = path.dirname(url.fileURLToPath(import.meta.url));
const root = path.resolve(here, '..');
const RES = path.join(root, 'entry', 'src', 'main', 'resources');
const MANIFEST = path.join(root, '.scratch', 'foundation', 'i18n-keys.json');
const REF = path.join(root, 'reference', 'learnOH-old', 'src', 'assets', 'translations');
const LOCALES = ['base', 'zh_CN', 'en_US'];
const I18N_PREFIXES = ['loh_', 'ui_'];

function isI18nName(name) {
  for (const prefix of I18N_PREFIXES) {
    if (name.startsWith(prefix)) return true;
  }
  return false;
}

function readElement(dir) {
  const file = path.join(RES, dir, 'element', 'string.json');
  if (!fs.existsSync(file)) return null;
  const parsed = JSON.parse(fs.readFileSync(file, 'utf8'));
  const map = new Map();
  const order = [];
  for (const entry of parsed.string || []) {
    map.set(entry.name, entry.value);
    order.push(entry.name);
  }
  return { map: map, order: order };
}

function difference(a, b) {
  const out = [];
  for (const n of a) if (!b.has(n)) out.push(n);
  return out;
}

// The manifest stores reference keys in camelCase; resources use loh_+snake_case.
// Reimplemented here on purpose: the checker must not trust the generator.
function toRefName(key) {
  return 'loh_' + key.replace(/([a-z0-9])([A-Z])/g, '$1_$2').toLowerCase();
}

export function check() {
  const manifest = JSON.parse(fs.readFileSync(MANIFEST, 'utf8'));
  const manifestKeys = manifest.keys.map((k) => k.name);
  const manifestSet = new Set(manifestKeys);
  const declaredReference = new Set(manifest.referenceKeys || []);

  // `reference/` is gitignored (it is the RN original), so the drift check is
  // skipped rather than fatal when it is absent from a fresh clone.
  let referenceRows = [];
  let referenceAvailable = true;
  try {
    referenceRows = buildRows(REF).rows;
  } catch (err) {
    referenceAvailable = false;
  }
  const referenceNames = referenceRows.map((r) => toRefName(r.key));
  const referenceSet = new Set(referenceNames);
  const referenceKeySet = new Set(referenceRows.map((r) => r.key));
  const drift = {
    manifestNotInReference: difference([...declaredReference].filter((k) => !referenceSet.has(toRefName(k))), referenceSet),
    referenceNotInManifest: difference([...referenceKeySet], declaredReference)
  };

  const report = {
    manifestCount: manifestKeys.length,
    referenceDictionaryCount: referenceNames.length,
    declaredReferenceCount: declaredReference.size,
    referenceAvailable: referenceAvailable,
    drift: drift,
    locales: {},
    source: null
  };
  const zh = readElement('zh_CN');
  for (const locale of LOCALES) {
    const found = readElement(locale);
    const result = {
      fileFound: found !== null,
      entryCount: found ? found.map.size : 0,
      missing: [], empty: [], extra: [], untranslated: [], outOfOrder: []
    };
    if (found === null) {
      result.missing = manifestKeys.slice();
      report.locales[locale] = result;
      continue;
    }
    for (const name of manifestKeys) {
      if (!found.map.has(name)) { result.missing.push(name); continue; }
      const value = found.map.get(name);
      if (typeof value !== 'string' || value.trim() === '') result.empty.push(name);
    }
    for (const name of found.order) {
      if (isI18nName(name) && !manifestSet.has(name)) result.extra.push(name);
    }
    if (locale === 'en_US' && zh !== null) {
      for (const name of manifestKeys) {
        if (found.map.has(name) && zh.map.has(name) && found.map.get(name) === zh.map.get(name)) {
          result.untranslated.push(name);
        }
      }
    }
    let cursor = -1;
    const position = new Map();
    found.order.forEach((n, i) => position.set(n, i));
    for (const name of manifestKeys) {
      if (!position.has(name)) continue;
      const at = position.get(name);
      if (at < cursor) result.outOfOrder.push(name);
      else cursor = at;
    }
    report.locales[locale] = result;
  }
  report.source = checkSourceKeys(root, manifest);
  report.ok = drift.referenceNotInManifest.length === 0
    && drift.manifestNotInReference.length === 0
    && (!referenceAvailable || declaredReference.size === referenceNames.length)
    && report.source.problems.length === 0
    && LOCALES.every((l) => {
      const r = report.locales[l];
      return r.fileFound && r.missing.length === 0 && r.empty.length === 0 && r.extra.length === 0;
    });
  return report;
}

function printReport(report) {
  const L = [];
  L.push('i18n key check');
  L.push('  manifest keys            : ' + report.manifestCount);
  L.push('  reference keys declared  : ' + report.declaredReferenceCount);
  L.push('  reference dictionary keys: ' + report.referenceDictionaryCount + (report.referenceAvailable ? '' : ' (reference/ absent: drift check skipped)'));
  if (report.drift.referenceNotInManifest.length) {
    L.push('  !! reference keys MISSING from the manifest: ' + report.drift.referenceNotInManifest.join(', '));
  }
  if (report.drift.manifestNotInReference.length) {
    L.push('  !! manifest reference keys absent from the dictionary: ' + report.drift.manifestNotInReference.join(', '));
  }
  for (const locale of Object.keys(report.locales)) {
    const r = report.locales[locale];
    L.push('  [' + locale + '] found=' + String(r.fileFound) + ' entries=' + String(r.entryCount)
      + ' missing=' + String(r.missing.length) + ' empty=' + String(r.empty.length)
      + ' extra=' + String(r.extra.length) + ' untranslated=' + String(r.untranslated.length));
    if (r.missing.length) L.push('      MISSING: ' + r.missing.join(', '));
    if (r.empty.length) L.push('      EMPTY  : ' + r.empty.join(', '));
    if (r.extra.length) L.push('      EXTRA  : ' + r.extra.join(', '));
    if (r.untranslated.length) L.push('      (en == zh, expected for brand/ASCII strings): ' + r.untranslated.join(', '));
  }
  if (report.source.problems.length) {
    L.push('  !! source references: ' + String(report.source.problems.length) + ' problem(s)');
    for (const p of report.source.problems) {
      L.push('      ' + p.file + ' [' + p.kind + '] ' + p.name + ' -- ' + p.reason);
    }
  } else {
    L.push('  source key references   : ' + String(report.source.usedCount) + ' distinct keys, all resolved');
  }
  L.push(report.ok ? 'RESULT: OK' : 'RESULT: FAIL');
  return L.join('\n');
}

const isMain = process.argv[1] && path.resolve(process.argv[1]) === path.resolve(url.fileURLToPath(import.meta.url));
if (isMain) {
  const report = check();
  if (process.argv.includes('--json')) console.log(JSON.stringify(report, null, 2));
  else console.log(printReport(report));
  process.exit(report.ok ? 0 : 1);
}
