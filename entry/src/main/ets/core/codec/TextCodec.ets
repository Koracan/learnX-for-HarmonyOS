/*
 * 文本编解码门面（core）：把平台能力收敛成领域层可注入的两个纯函数。
 *
 * 参考实现直接在 DataProcessorModule.ts 里 `new util.Base64Helper()` 与
 * `util.TextDecoder()`；移植后：
 *   - **Base64 → 字节仍走平台 `util.Base64Helper`**：设备上已复验正常
 *     （2026-09-12 模拟器 Pura 90 的 D4 探针：`input=PHA+5Yqh platform="<p>务" match=true`，
 *     见 .scratch/migration/issues/05-port-data-processor.md 的「D4 设备复验」）。
 *     local 单测环境里 `decodeSync` 解不出字节（返回空 / 抛异常），那是该环境对 `@ohos.util`
 *     的桩实现所致，不是生产代码的问题（逐 API 实测表见 entry/src/test/TestHelpers.ets 文件头）。
 *   - **字节 → 文本改用 domain/parse/Utf8 的纯实现**：生产与测试共用同一份代码，避免
 *     "解析是否正确"依赖"平台 API 在当前环境是否可用"。
 *     关于平台 `TextDecoder`：早前"其 `decodeWithStream` 在单测环境返回 undefined"的说法是
 *     **推断、未单独实测**（早期失败用例完全可由"上游 TextEncoder 返回空数组"解释），故不作为
 *     这里的依据；且 `TextDecoder`/`TextEncoder` 现已不在任何生产路径上（本文件只用 `Base64Helper`）。
 *     若将来有人把"字节 → 文本"改回平台实现，必须重新打开 D4 那一项复验。
 */

import util from '@ohos.util';
import { decodeUtf8, encodeUtf8 as encodeUtf8Pure } from '../../domain/parse/Utf8';

/** Base64 → 文本；解码失败返回空串（与参考实现同语义，异常不外抛）。 */
export function decodeBase64Text(encoded: string): string {
  if (!encoded) {
    return '';
  }
  let decoded: Uint8Array;
  try {
    const helper: util.Base64Helper = new util.Base64Helper();
    decoded = helper.decodeSync(encoded);
  } catch (error) {
    return '';
  }
  return decodeUtf8(decoded);
}

/** 文本 → UTF-8 字节（multipart 组装用）。 */
export function encodeUtf8(text: string): Uint8Array {
  return encodeUtf8Pure(text);
}

/** 去掉 `file://` 前缀（照参考实现 post 的路径处理）。 */
export function stripFileScheme(path: string): string {
  if (path.startsWith('file://')) {
    return path.substring(7);
  }
  return path;
}