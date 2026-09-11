#!/usr/bin/env node
/**
 * 生成物新鲜度检查（统筹新增，2026-09-12）。
 *
 * 起因：i18n 的生成物是**共享的单写者状态**，而两个 agent 同时改了它的输入
 * （一个改 generate-i18n-resources.mjs、一个改 i18n-ui-strings.mjs），生成物于是
 * 同时含两边的键；此时任一方只提交自己那份输入，都会让提交点上的生成物无法由
 * 已提交的输入复现。这类问题靠人记得是不可靠的。
 *
 * 做法：对生成物取哈希 -> 重跑生成器 -> 再取哈希。**若发生变化就 FAIL**，说明
 * 工作区里的生成物与其生成器输入不一致（脚本已经把正确结果写回去了，所以修法
 * 就是检查 git diff 并把它和**所有生成器输入**放进同一次提交）。
 * 一致时本脚本不改动任何文件。
 *
 * 用法：node scripts/check-generated-fresh.mjs
 * 退出码：0 = 一致；1 = 不一致（已就地重生）；2 = 生成物缺失或生成器执行失败。
 */

import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { readFileSync, existsSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');

const GENERATED = [
  'entry/src/main/resources/base/element/string.json',
  'entry/src/main/resources/zh_CN/element/string.json',
  'entry/src/main/resources/en_US/element/string.json',
  'entry/src/main/ets/core/i18n/I18nKeys.ets',
  '.scratch/foundation/i18n-keys.json',
  '.scratch/foundation/i18n-key-map.md',
];

const GENERATORS = ['scripts/generate-i18n-resources.mjs', 'scripts/gen-i18n-keys.mjs'];

const missing = GENERATED.filter((rel) => !existsSync(join(REPO_ROOT, rel)));
if (missing.length > 0) {
  console.error('[generated-fresh] FAIL 找不到生成物：' + missing.join(', '));
  process.exit(2);
}

function digest(rel) {
  return createHash('sha256').update(readFileSync(join(REPO_ROOT, rel))).digest('hex');
}

const before = new Map(GENERATED.map((rel) => [rel, digest(rel)]));

for (const generator of GENERATORS) {
  try {
    execFileSync(process.execPath, [join(REPO_ROOT, generator)], {
      cwd: REPO_ROOT,
      stdio: 'ignore',
    });
  } catch (error) {
    console.error('[generated-fresh] FAIL 生成器执行失败：' + generator + ' -> ' + error.message);
    process.exit(2);
  }
}

const drifted = GENERATED.filter((rel) => digest(rel) !== before.get(rel));
console.log('[generated-fresh] 检查 ' + GENERATED.length + ' 个生成物，跑过 ' + GENERATORS.length + ' 个生成器');
if (drifted.length > 0) {
  console.error('[generated-fresh] FAIL 以下生成物与当前生成器输入不一致（已就地重生）：');
  for (const rel of drifted) {
    console.error('  - ' + rel);
  }
  console.error('[generated-fresh] 修法：检查 git diff，把生成物与所有生成器输入放进同一次提交。');
  process.exit(1);
}
console.log('[generated-fresh] PASS 生成物与其生成器输入一致');
