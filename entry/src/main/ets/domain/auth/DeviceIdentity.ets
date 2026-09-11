/*
 * 设备身份（domain，纯逻辑）：本机设备指纹的格式、deviceName 的组装、凭据字段的脱敏。
 *
 * 为什么这些放在 domain：它们**没有任何平台依赖**（不生成随机数、不读设备信息、不落盘），
 * 只是"值 → 文本"的规则，因此可以在 host 单测里逐条断言；随机源、设备型号与应用版本
 * 由 core 层注入（见 core/device/AppIdentity 与 features/auth 的装配点）。
 *
 * 与参考实现的关系（reference/learnOH-old/src/helpers/fingerprint.ts）：
 *   - 指纹是 **UUID v4 文本**（16 字节随机源，版本位 0x4x，变体位 0b10xxxxxx），逐位照搬；
 *   - 参考实现的 deviceName 只有 `HarmonyOS,learnOH/{version}`（src/screens/SSO.tsx:52），
 *     本工程按 spec 第 5 节追加 ` ({productModel})` —— 这条差异已在 ticket 07 Comments 登记。
 */

/** UUID v4 的第五段（末段）长度，用于形状校验。 */
const UUID_GROUPS: number[] = [8, 4, 4, 4, 12];

/**
 * 16 字节源 → UUID v4 文本。
 *
 * 逐位对齐参考实现 `generateFingerprint`（helpers/fingerprint.ts:8-28）：
 * `bytes[6] = (bytes[6] & 0x0f) | 0x40`、`bytes[8] = (bytes[8] & 0x3f) | 0x80`，
 * 其余字节十六进制小写、两位补零。
 *
 * @param bytes 至少 16 个字节（不足时用 0 补齐，多余忽略——不抛异常，便于设备侧容错）
 */
export function formatUuidV4(bytes: number[]): string {
  const normalized: number[] = [];
  for (let i = 0; i < 16; i++) {
    const value: number = i < bytes.length ? bytes[i] : 0;
    normalized.push((value & 0xff) + 0); // 保证 0..255
  }
  normalized[6] = (normalized[6] & 0x0f) | 0x40;
  normalized[8] = (normalized[8] & 0x3f) | 0x80;
  const hex: string[] = [];
  for (let i = 0; i < 16; i++) {
    const two: string = normalized[i].toString(16);
    hex.push(two.length === 1 ? '0' + two : two);
  }
  const text: string = hex.join('');
  const parts: string[] = [];
  let cursor: number = 0;
  for (let i = 0; i < UUID_GROUPS.length; i++) {
    parts.push(text.substring(cursor, cursor + UUID_GROUPS[i]));
    cursor += UUID_GROUPS[i];
  }
  return parts.join('-');
}

/** 是否是 UUID v4 形状（8-4-4-4-12、第三段以 4 开头、第四段首位 ∈ {8,9,a,b}）。 */
export function isUuidV4(value: string): boolean {
  const matched: RegExpMatchArray | null = value.match(
    /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
  return matched !== null;
}

/**
 * deviceName = `HarmonyOS,learnOH/{versionName} ({productModel})`。
 *
 * spec 第 5 节：**仅登记时上报**（HTTP 重登不带它，故不参与信任绑定）。
 * 型号缺失时退化成 `... ({unknown})` 而不是丢掉括号，便于日志里一眼看出是"没取到"。
 */
export function composeDeviceName(versionName: string, productModel: string): string {
  const version: string = versionName.length > 0 ? versionName : 'unknown';
  const model: string = productModel.length > 0 ? productModel : 'unknown';
  return 'HarmonyOS,learnOH/' + version + ' (' + model + ')';
}

/**
 * 凭据字段的**脱敏**表示：只保留前 4 个字符与总长度。
 *
 * 硬要求（验收第 5 条 / AGENTS.md「取证」）：指纹真值与口令**不得**进日志，
 * 但"字段有没有值、多长、两次是否同一个"必须可诊断。前 4 字符足以在两次日志之间
 * 目视比对"是不是同一个指纹"，又不足以还原整个 UUID。
 */
export function redactSecret(value: string): string {
  if (value.length === 0) {
    return 'empty';
  }
  const prefix: string = value.length <= 4 ? value : value.substring(0, 4);
  return prefix + '…(' + value.length.toString() + ')';
}

/** 两个值是否逐字符相同（用于"我们保存的指纹 == DOM 里的指纹"这类断言，结果只写布尔）。 */
export function sameSecret(left: string, right: string): boolean {
  return left.length === right.length && left === right;
}

/**
 * 指纹三字段的脱敏诊断串（验收第 5 条的落点）。
 *
 * `fingerPrint` 是我们注入并保存的那个值；`fingerGenPrint` / `fingerGenPrint3` 来自页面
 * 自己的 localStorage（我们不生成、只如实保存与回放）。三者都可能出现在排查里，
 * 因此统一走这里脱敏。
 */
export function describeFingerprints(fingerPrint: string, fingerGenPrint: string, fingerGenPrint3: string): string {
  return 'fingerPrint=' + redactSecret(fingerPrint)
    + ' fingerGenPrint=' + redactSecret(fingerGenPrint)
    + ' fingerGenPrint3=' + redactSecret(fingerGenPrint3);
}
