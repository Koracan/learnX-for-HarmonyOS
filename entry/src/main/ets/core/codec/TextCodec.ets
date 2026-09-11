/*
 * 文本编解码门面（core）：把平台能力收敛成领域层可注入的两个纯函数。
 *
 * 参考实现直接在 DataProcessorModule.ts 里 `new util.Base64Helper()` 与
 * `util.TextDecoder()`；移植后：
 *   - Base64 → 字节仍走平台 `util.Base64Helper`（这部分在本环境工作正常）；
 *   - 字节 → 文本改用 domain 的纯 UTF-8 解码（平台 `decodeWithStream` 在单测环境里
 *     返回 undefined，且生产与测试不该用两套解码）。
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
