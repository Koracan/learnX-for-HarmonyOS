#!/usr/bin/env node
// report-i18n-counts.mjs -- prints the actual key counts (no estimates).
// Evidence for the ticket: reference dictionary keys vs migrated resource keys.
import fs from 'node:fs';
import path from 'node:path';
import url from 'node:url';
import { readDict } from './i18n-lib.mjs';

const here = path.dirname(url.fileURLToPath(import.meta.url));
const root = path.resolve(here, '..');
const REF = path.join(root, 'reference', 'learnOH-old', 'src', 'assets', 'translations');
const RES = path.join(root, 'entry', 'src', 'main', 'resources');

const zh = readDict(path.join(REF, 'zh.ts'));
const en = readDict(path.join(REF, 'en.ts'));
const zhKeys = zh.map((r) => r[0]);
const enKeys = en.map((r) => r[0]);

function elements(locale) {
  const file = path.join(RES, locale, 'element', 'string.json');
  const parsed = JSON.parse(fs.readFileSync(file, 'utf8'));
  const all = parsed.string || [];
  return {
    file: path.relative(root, file),
    total: all.length,
    loh: all.filter((e) => e.name.startsWith('loh_')).length,
    ui: all.filter((e) => e.name.startsWith('ui_')).length,
    template: all.filter((e) => !e.name.startsWith('loh_') && !e.name.startsWith('ui_')).length
  };
}

const manifest = JSON.parse(fs.readFileSync(path.join(root, '.scratch', 'foundation', 'i18n-keys.json'), 'utf8'));
const keys = manifest.keys;

const lines = [];
lines.push('i18n key counts (measured from the files, not estimated)');
lines.push('');
lines.push('reference dictionaries (reference/learnOH-old/src/assets/translations, read-only):');
lines.push('  zh.ts keys : ' + zhKeys.length);
lines.push('  en.ts keys : ' + enKeys.length);
lines.push('  key sets identical: ' + String(JSON.stringify(zhKeys) === JSON.stringify(enKeys)));
lines.push('  entries with a {N} placeholder: ' + String(keys.filter((k) => k.origin === 'reference' && (k.zhPlaceholders || []).length > 0).length));
lines.push('');
lines.push('generated resources:');
for (const locale of ['base', 'zh_CN', 'en_US']) {
  const e = elements(locale);
  lines.push('  ' + locale.padEnd(6) + ' ' + e.file + '  total=' + e.total + ' (loh_=' + e.loh + ', ui_=' + e.ui + ', template=' + e.template + ')');
}
lines.push('');
lines.push('manifest (.scratch/foundation/i18n-keys.json):');
lines.push('  migrated reference keys : ' + String(manifest.referenceCount));
lines.push('  project-local additions : ' + String(manifest.localCount) + ' (semester season words)');
lines.push('  native-rewrite UI copy  : ' + String(manifest.uiCount));
lines.push('  total                   : ' + String(manifest.total));
lines.push('');
const migrated = keys.filter((k) => k.origin === 'reference').length;
const missing = zhKeys.filter((k) => !keys.some((r) => r.key === k)).length;
lines.push('coverage: ' + String(migrated) + '/' + String(zhKeys.length) + ' reference keys migrated, ' + String(missing) + ' missing');
lines.push('');
console.log(lines.join('\n'));
