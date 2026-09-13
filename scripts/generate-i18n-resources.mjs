#!/usr/bin/env node
// generate-i18n-resources.mjs
//
// Repeatable generator. Inputs:  reference/learnOH-old/src/assets/translations/{zh,en}.ts (read-only)
//                               scripts/i18n-ui-strings.mjs (native-rewrite UI copy)
// Outputs:
//   entry/src/main/resources/base/element/string.json    (Chinese = default fallback)
//   entry/src/main/resources/zh_CN/element/string.json
//   entry/src/main/resources/en_US/element/string.json
//   .scratch/foundation/i18n-key-map.md   key-name mapping table
//   .scratch/foundation/i18n-keys.json    machine-readable manifest for the checker
import fs from 'node:fs';
import path from 'node:path';
import url from 'node:url';
import { buildRows, findPlaceholders, toResourceValue } from './i18n-lib.mjs';
import { UI_STRINGS } from './i18n-ui-strings.mjs';

const BT = String.fromCharCode(96);

const here = path.dirname(url.fileURLToPath(import.meta.url));
const root = path.resolve(here, '..');
const REF = path.join(root, 'reference', 'learnOH-old', 'src', 'assets', 'translations');
const RES = path.join(root, 'entry', 'src', 'main', 'resources');
const MAP_OUT = path.join(root, '.scratch', 'foundation', 'i18n-key-map.md');
const MANIFEST_OUT = path.join(root, '.scratch', 'foundation', 'i18n-keys.json');

// Rewrite an existing element file, preserving entries this generator does not own.
function writeElement(dir, additions) {
  fs.mkdirSync(dir, { recursive: true });
  const file = path.join(dir, 'string.json');
  let kept = [];
  if (fs.existsSync(file)) {
    const parsed = JSON.parse(fs.readFileSync(file, 'utf8'));
    kept = (parsed.string || []).filter((e) => !e.name.startsWith('loh_') && !e.name.startsWith('ui_'));
  }
  fs.writeFileSync(file, JSON.stringify({ string: kept.concat(additions) }, null, 2) + '\n', 'utf8');
}

function escapeCell(s) {
  return s.split('\\').join('\\\\').split('|').join('\\|').replace(/\r?\n/g, '\\n');
}

// Reference key (camelCase identifier) -> HarmonyOS resource name.
// The 'loh_' prefix guarantees no collision with template/other element names.
function buildReferenceRows() {
  const built = buildRows(REF);
  const rows = built.rows.map((r) => ({
    key: r.key, name: r.name, zhValue: r.zhValue, enValue: r.enValue,
    zhPlaceholders: r.zhPlaceholders, enPlaceholders: r.enPlaceholders,
    origin: 'reference'
  }));
  return { rows: applyReferenceValueOverrides(rows), zhCount: built.zhCount, enCount: built.enCount };
}

// Semester season words: the reference hard-coded them inside helpers/parse.ts,
// so porting that function needs them as resources.
//
// 冷启动重建会话追加三条：参考实现没有对应字符串（它的失败处理是静默的），但验收要求
// "显式回到登录页并说明需要重新验证"、断网要给出可理解的提示，所以必须新增文案。
const LOCAL_ADDITIONS = [
  ['loh_fall', '秋季学期', 'Fall'],
  ['loh_spring', '春季学期', 'Spring'],
  ['loh_summer', '夏季学期', 'Summer'],
  ['loh_session_expired', '登录状态已失效，需要重新验证。', 'Your session has expired. Please sign in again to verify.'],
  ['loh_network_unavailable', '网络不可用，请检查网络后重试。', 'Network unavailable. Check your connection and try again.'],
  ['loh_retry', '重试', 'Retry'],
  // 断点分栏追加两条：文件详情页头那个「全屏 / 退出全屏」按钮的无障碍文案。
  // 参考实现的 IconButton 只有图标、没有文字（screens/FileDetail.tsx:108-113），
  // 本工程的矢量图标同样需要一条可读的无障碍文案（与图标口径一致）。
  ['loh_fullscreen', '全屏', 'Full screen'],
  ['loh_exit_fullscreen', '退出全屏', 'Exit full screen']
];

// Reference-key VALUE overrides.
//
// Same table shape as LOCAL_ADDITIONS above, but the opposite meaning: the key is
// still a reference key (its `loh_` resource name and its migration lineage are
// unchanged) and only its copy is replaced here. The reason this exists at all is
// that the reference dictionary is read-only INPUT: editing the generated
// `string.json` by hand would make `check-generated-fresh` fail, because the
// generator would immediately write the reference value back.
//
// immersiveModeDescription: the reference text promises "app restart required",
// while this rewrite applies the change immediately (no restart). The UI must not
// tell the user to do something the app does not need.
const REFERENCE_VALUE_OVERRIDES = new Map([
  ['immersiveModeDescription', {
    zh: '隐藏导航栏和状态栏',
    en: 'Hide the navigation bar and status bar'
  }]
]);

function applyReferenceValueOverrides(rows) {
  const seen = new Set();
  for (const row of rows) {
    const override = REFERENCE_VALUE_OVERRIDES.get(row.key);
    if (!override) continue;
    seen.add(row.key);
    const zhPh = findPlaceholders(override.zh);
    const enPh = findPlaceholders(override.en);
    row.zhValue = toResourceValue(override.zh, zhPh);
    row.enValue = toResourceValue(override.en, enPh);
    row.zhPlaceholders = zhPh.map((p) => p.token);
    row.enPlaceholders = enPh.map((p) => p.token);
  }
  for (const key of REFERENCE_VALUE_OVERRIDES.keys()) {
    if (!seen.has(key)) throw new Error('value override for unknown reference key: ' + key);
  }
  return rows;
}

function buildLocalRows() {
  return LOCAL_ADDITIONS.map((t) => ({
    key: '__' + t[0], name: t[0], zhValue: t[1], enValue: t[2],
    zhPlaceholders: [], enPlaceholders: [], origin: 'local'
  }));
}

function buildUiRows() {
  return UI_STRINGS.map((t) => {
    const zhPh = findPlaceholders(t[1]);
    const enPh = findPlaceholders(t[2]);
    return {
      key: '__' + t[0], name: t[0],
      zhValue: toResourceValue(t[1], zhPh), enValue: toResourceValue(t[2], enPh),
      zhPlaceholders: zhPh.map((p) => p.token), enPlaceholders: enPh.map((p) => p.token),
      origin: 'ui'
    };
  });
}

function writeKeyMap(referenceRows, localRows, uiRows) {
  fs.mkdirSync(path.dirname(MAP_OUT), { recursive: true });
  const L = [];
  L.push('# i18n 键名映射表');
  L.push('');
  L.push('**由 ' + BT + 'scripts/generate-i18n-resources.mjs' + BT + ' 自动生成，不要手工编辑。**');
  L.push('');
  L.push('来源（只读）：' + BT + 'reference/learnOH-old/src/assets/translations/{zh,en}.ts' + BT + '。');
  L.push('');
  L.push('## 规则');
  L.push('');
  L.push('- 参考键（camelCase）→ 资源名 = ' + BT + 'loh_' + BT + ' + camelCase→snake_case。');
  L.push('- 资源值插值：参考字典若用 ' + BT + '{N}' + BT + '，资源里写成 HarmonyOS 位置占位符 ' + BT + '%(N+1)$s' + BT + '。');
  L.push('- ' + BT + 'base' + BT + ' 与 ' + BT + 'zh_CN' + BT + ' 内容相同（中文是默认回退），' + BT + 'en_US' + BT + ' 是英文。');
  L.push('- 取串：UI 用 ' + BT + "$r('app.string.<资源名>')" + BT + '；逻辑层用 ' + BT + 'core/i18n' + BT + ' 的 ' + BT + 't()' + BT + '（' + BT + 'ResourceManager.getStringByNameSync' + BT + '）。');
  L.push('');
  L.push('## 统计');
  L.push('');
  L.push('| 类别 | 数量 | 命名空间 |');
  L.push('| --- | --- | --- |');
  L.push('| 参考实现迁入 | ' + referenceRows.length + ' | ' + BT + 'loh_' + BT + ' |');
  L.push('| 本工程新增（学期季节词） | ' + localRows.length + ' | ' + BT + 'loh_' + BT + ' |');
  L.push('| 本工程新增（原生重写 UI 文案） | ' + uiRows.length + ' | ' + BT + 'ui_' + BT + ' |');
  L.push('| 合计 | ' + (referenceRows.length + localRows.length + uiRows.length) + ' | |');
  L.push('');
  L.push('## 参考实现迁入键（' + referenceRows.length + '）');
  L.push('');
  L.push('| # | 参考键 | 资源名 | 占位符 | 中文 | 英文 |');
  L.push('| --- | --- | --- | --- | --- | --- |');
  referenceRows.forEach((r, idx) => {
    L.push('| ' + (idx + 1) + ' | ' + BT + r.key + BT + ' | ' + BT + r.name + BT + ' | ' + (r.zhPlaceholders.join(',') || '-') + ' | ' + escapeCell(r.zhValue) + ' | ' + escapeCell(r.enValue) + ' |');
  });
  L.push('');
  L.push('## 本工程新增键（' + (localRows.length + uiRows.length) + '）');
  L.push('');
  L.push('| # | 类别 | 资源名 | 占位符 | 中文 | 英文 |');
  L.push('| --- | --- | --- | --- | --- | --- |');
  localRows.concat(uiRows).forEach((r, idx) => {
    L.push('| ' + (idx + 1) + ' | ' + r.origin + ' | ' + BT + r.name + BT + ' | ' + (r.zhPlaceholders.join(',') || '-') + ' | ' + escapeCell(r.zhValue) + ' | ' + escapeCell(r.enValue) + ' |');
  });
  L.push('');
  fs.writeFileSync(MAP_OUT, L.join('\n') + '\n', 'utf8');
}

export function generate() {
  const it = buildReferenceRows();
  const referenceRows = it.rows;
  const localRows = buildLocalRows();
  const uiRows = buildUiRows();
  const all = referenceRows.concat(localRows, uiRows);
  const seen = new Set();
  for (const r of all) {
    if (seen.has(r.name)) throw new Error('duplicate resource name: ' + r.name);
    seen.add(r.name);
  }
  writeElement(path.join(RES, 'base', 'element'), all.map((r) => ({ name: r.name, value: r.zhValue })));
  writeElement(path.join(RES, 'zh_CN', 'element'), all.map((r) => ({ name: r.name, value: r.zhValue })));
  writeElement(path.join(RES, 'en_US', 'element'), all.map((r) => ({ name: r.name, value: r.enValue })));
  writeKeyMap(referenceRows, localRows, uiRows);
  fs.mkdirSync(path.dirname(MANIFEST_OUT), { recursive: true });
  fs.writeFileSync(MANIFEST_OUT, JSON.stringify({
    total: all.length,
    referenceCount: referenceRows.length,
    localCount: localRows.length,
    uiCount: uiRows.length,
    referenceKeys: referenceRows.map((r) => r.key),
    keys: all
  }, null, 2) + '\n', 'utf8');
  return {
    referenceZhKeys: it.zhCount,
    referenceEnKeys: it.enCount,
    migratedReferenceKeys: referenceRows.length,
    localAdditions: localRows.length,
    uiStrings: uiRows.length,
    totalResources: all.length,
    map: MAP_OUT,
    manifest: MANIFEST_OUT
  };
}

const isMain = process.argv[1] && path.resolve(process.argv[1]) === path.resolve(url.fileURLToPath(import.meta.url));
if (isMain) {
  console.log(JSON.stringify(generate(), null, 2));
}
