#!/usr/bin/env node
/**
 * domain 纯度检查（A 项的自动检查）。
 *
 * 断言 entry/src/main/ets/domain/** 的源码**不引用**：
 *   - 平台：@ohos.* / @kit.* / @hms.*
 *   - 上层：core/、data/、ui/、features/（相对路径解析后越出 domain/）
 *   - 领域目录内的 oh-package.json5 也不得声明上述平台依赖
 *
 * 用法：node scripts/check-domain-purity.mjs
 * 退出码：0 = 通过；1 = 有违规；2 = 没扫到任何领域源文件（防止空跑误判为通过）。
 *
 * 依赖方向：features → data → domain，domain 不依赖任何上层。
 */

import { readdirSync, readFileSync, statSync, existsSync } from 'node:fs';
import { dirname, join, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const DOMAIN_DIR = join(REPO_ROOT, 'entry', 'src', 'main', 'ets', 'domain');
const SOURCE_EXTENSIONS = ['.ets', '.ts', '.mts'];
const FORBIDDEN_PLATFORM = /^@(?:ohos|kit|hms)(?:[./]|$)/;
const FORBIDDEN_LAYERS = ['core', 'data', 'ui', 'features'];

/** 提取一条源文件里的所有模块引用：import / export-from / 动态 import / require。 */
const REFERENCE_PATTERNS = [
  /\bfrom\s*['"]([^'"]+)['"]/g,
  /\bimport\s*['"]([^'"]+)['"]/g,
  /\bimport\s*\(\s*['"]([^'"]+)['"]\s*\)/g,
  /\brequire\s*\(\s*['"]([^'"]+)['"]\s*\)/g,
];

function walk(dir) {
  const found = [];
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) {
      found.push(...walk(full));
    } else if (SOURCE_EXTENSIONS.some((ext) => entry.endsWith(ext))) {
      found.push(full);
    }
  }
  return found;
}

function isInsideDomain(absolutePath) {
  const rel = relative(DOMAIN_DIR, absolutePath);
  return rel.length > 0 && !rel.startsWith('..') && !rel.startsWith('..' + sep);
}

function relativeToRepo(absolutePath) {
  return relative(REPO_ROOT, absolutePath).split(sep).join('/');
}

const violations = [];
const warnings = [];

if (!existsSync(DOMAIN_DIR)) {
  console.error('[domain-purity] FAIL 领域目录不存在：' + relativeToRepo(DOMAIN_DIR));
  process.exit(2);
}

const files = walk(DOMAIN_DIR);
if (files.length === 0) {
  console.error('[domain-purity] FAIL 领域目录下没有任何源文件，检查会空跑通过，拒绝放行：' + relativeToRepo(DOMAIN_DIR));
  process.exit(2);
}

for (const file of files) {
  const text = readFileSync(file, 'utf8');
  const lines = text.split(/\r?\n/);
  const specifiers = new Map();
  for (const pattern of REFERENCE_PATTERNS) {
    pattern.lastIndex = 0;
    let match;
    while ((match = pattern.exec(text)) !== null) {
      if (!specifiers.has(match[1])) {
        specifiers.set(match[1], text.slice(0, match.index).split(/\r?\n/).length);
      }
    }
  }

  for (const [specifier, lineNumber] of specifiers) {
    const location = relativeToRepo(file) + ':' + lineNumber;
    if (FORBIDDEN_PLATFORM.test(specifier)) {
      violations.push(location + '  平台依赖被禁止：' + specifier + " ('" + lines[lineNumber - 1].trim() + "')");
      continue;
    }
    if (specifier.startsWith('.')) {
      const target = resolve(dirname(file), specifier);
      if (!isInsideDomain(target)) {
        violations.push(location + '  越出 domain 的引用：' + specifier + " ('" + lines[lineNumber - 1].trim() + "')");
      }
      continue;
    }
    if (FORBIDDEN_LAYERS.some((layer) => specifier === layer || specifier.startsWith(layer + '/'))) {
      violations.push(location + '  上层依赖被禁止：' + specifier);
      continue;
    }
    warnings.push(location + '  非相对引用（需人工确认是否为纯逻辑包）：' + specifier);
  }
}

// 领域目录内若出现 oh-package.json5，也不得声明平台依赖。
const packageFiles = [];
(function collectPackageFiles(dir) {
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) {
      collectPackageFiles(full);
    } else if (entry === 'oh-package.json5') {
      packageFiles.push(full);
    }
  }
})(DOMAIN_DIR);

for (const packageFile of packageFiles) {
  const text = readFileSync(packageFile, 'utf8');
  for (const name of text.match(/@(?:ohos|kit|hms)[\w./-]*/g) ?? []) {
    if (text.includes('"' + name + '"')) {
      violations.push(relativeToRepo(packageFile) + '  平台依赖被禁止：' + name);
    }
  }
}

console.log('[domain-purity] 扫描 ' + files.length + ' 个领域源文件（' + relativeToRepo(DOMAIN_DIR) + '）');
for (const warning of warnings) {
  console.log('[domain-purity] WARN ' + warning);
}
if (violations.length > 0) {
  console.error('[domain-purity] FAIL 发现 ' + violations.length + ' 处违规：');
  for (const violation of violations) {
    console.error('  - ' + violation);
  }
  process.exit(1);
}
console.log('[domain-purity] PASS domain 不依赖平台与应用层');
