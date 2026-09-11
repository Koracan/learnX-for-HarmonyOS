/*
 * 附件文件名的纯规则 —— **零平台依赖**（见 scripts/check-domain-purity.mjs）。
 *
 * 逐字移植参考实现 `reference/learnOH-old/src/helpers/fs.ts:215-226`：
 *
 *   getExtension(name)   = name.split('.').length > 1 ? 末段 : undefined
 *   stripExtension(name) = name.split('.').length > 1 ? 去掉末段后 join('.') : name
 *
 * 注意两处照抄的行为（不是 bug）：
 *   - 以点结尾（`a.`）时扩展名是空串，`getExtension` 返回 `''` 而不是 `undefined`；
 *   - 隐藏文件形态（`.gitignore`）会被当成 "无扩展名" 的 `gitignore` + 扩展名 `gitignore`。
 * 移植的完成定义是与参考实现行为一致，故这里不改。
 */

/** 扩展名（不含点）；文件名里没有点时返回 `undefined`（对齐参考实现）。 */
export function getExtension(filename: string): string | undefined {
  const parts: string[] = filename.split('.');
  if (parts.length <= 1) {
    return undefined;
  }
  return parts[parts.length - 1];
}

/** 去掉最后一个扩展名；没有点时原样返回。 */
export function stripExtension(filename: string): string {
  const parts: string[] = filename.split('.');
  if (parts.length <= 1) {
    return filename;
  }
  return parts.slice(0, parts.length - 1).join('.');
}
