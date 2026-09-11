#!/usr/bin/env node
/**
 * 导入图检查（统筹新增，2026-09-12）。
 *
 * 起因（实测）：data/upload/UploadForm.ets 从 ticket 05 起就 import 了一个不存在的路径
 * "../../domain/parse/Multipart"（真身在 data/upload/Multipart.ets），而 ticket 05 的
 * devecocli build 与 116 条单测**全绿**。原因是 ArkTS 的编译按**入口可达性**进行：
 * 没有任何可达者 import 的模块不会被编译，其中的硬错误（含无法解析的 import）不会让
 * 门禁变红。直到 ticket 06 第一次 import 它，编译才报错。
 *
 * 本脚本做两件事：
 *   1. FAIL：任何**相对** import 解析不到实际文件 -> 退出码 1。这与可达性无关，纯属
 *      路径写错，必须在提交前拦住。
 *   2. WARN：列出**没有任何可达者 import** 的 main 源文件（孤儿模块）。它们从未被编译过，
 *      其"编译通过"未被验证。入口文件（ability / pages / 被 module.json5 引用者）会出现在
 *      该列表里，属正常。
 *
 * 用法：node scripts/check-import-graph.mjs
 * 退出码：0 = 无不可解析的相对 import；1 = 有；2 = 没扫到任何源文件（防空跑误判通过）。
 */

import { readdirSync, readFileSync, statSync, existsSync } from 'node:fs';
import { dirname, join, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const ROOTS = [join(REPO_ROOT, 'entry', 'src', 'main', 'ets'), join(REPO_ROOT, 'entry', 'src', 'test')];
const EXTS = ['.ets', '.ts', '.mts', '.js'];

const REFERENCE_PATTERNS = [
  /\bfrom\s*['"]([^'"]+)['"]/g,
  /\bimport\s*['"]([^'"]+)['"]/g,
  /\bimport\s*\(\s*['"]([^'"]+)['"]\s*\)/g,
  /\brequire\s*\(\s*['"]([^'"]+)['"]\s*\)/g,
];

function walk(dir) {
  const found = [];
  if (!existsSync(dir)) return found;
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) {
      found.push(...walk(full));
    } else if (EXTS.some((ext) => entry.endsWith(ext))) {
      found.push(full);
    }
  }
  return found;
}

function resolveSpecifier(fromFile, specifier) {
  const base = resolve(dirname(fromFile), specifier);
  const candidates = [base];
  for (const ext of EXTS) candidates.push(base + ext);
  for (const ext of EXTS) candidates.push(join(base, 'index' + ext));
  for (const candidate of candidates) {
    if (existsSync(candidate) && statSync(candidate).isFile()) return candidate;
  }
  return null;
}

function relativeToRepo(absolutePath) {
  return relative(REPO_ROOT, absolutePath).split(sep).join('/');
}

const files = ROOTS.flatMap(walk);
if (files.length === 0) {
  console.error('[import-graph] FAIL 没扫到任何源文件，空跑会被误判为通过，拒绝放行');
  process.exit(2);
}

const violations = [];
const imported = new Set();

for (const file of files) {
  const text = readFileSync(file, 'utf8');
  const lineOf = new Map();
  for (const pattern of REFERENCE_PATTERNS) {
    pattern.lastIndex = 0;
    let match;
    while ((match = pattern.exec(text)) !== null) {
      const specifier = match[1];
      if (!specifier.startsWith('.')) continue;
      if (!lineOf.has(specifier)) {
        lineOf.set(specifier, text.slice(0, match.index).split(/\r?\n/).length);
      }
    }
  }
  for (const [specifier, lineNumber] of lineOf) {
    const target = resolveSpecifier(file, specifier);
    if (target === null) {
      violations.push(relativeToRepo(file) + ':' + lineNumber + '  无法解析的相对 import：' + specifier);
    } else {
      imported.add(target);
    }
  }
}

const mainEts = join(REPO_ROOT, 'entry', 'src', 'main', 'ets');
const orphans = walk(mainEts)
  .filter((file) => !imported.has(file))
  .map(relativeToRepo)
  .sort();

console.log('[import-graph] 扫描 ' + files.length + ' 个源文件（main + test）');
if (orphans.length > 0) {
  console.log('[import-graph] WARN 以下 main 源文件没有任何可达者 import（从未被编译过；入口文件属正常）：');
  for (const orphan of orphans) {
    console.log('[import-graph]   - ' + orphan);
  }
}
if (violations.length > 0) {
  console.error('[import-graph] FAIL 发现 ' + violations.length + ' 处不可解析的相对 import：');
  for (const violation of violations) {
    console.error('  - ' + violation);
  }
  process.exit(1);
}
console.log('[import-graph] PASS 所有相对 import 均可解析');
