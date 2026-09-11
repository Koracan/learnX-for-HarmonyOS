/*
 * 文本编解码门面（core）：把平台能力收敛成领域层可注入的两个纯函数。
 *
 * 参考实现直接在 DataProcessorModule.ts 里 `new util.Base64Helper()` 与
 * `util.TextDecoder`；移植后 domain 层的解析器只声明 `Base64Decoder` 类型，
 * 具体实现由这里提供，于是解析逻辑可以脱离设备单测。
 */

import util from '@ohos.util';

/** Base64 → 文本；解码失败返回空串（与参考实现同语义，异常不外抛）。 */
export function decodeBase64Text(encoded: string): string {
  if (!encoded) {
    return '';
  }
  try {
    const helper: util.Base64Helper = new util.Base64Helper();
    const decoded: Uint8Array = helper.decodeSync(encoded);
    return new util.TextDecoder().decodeWithStream(decoded);
  } catch (error) {
    return '';
  }
}

/** 文本 → UTF-8 字节（multipart 组装用）。 */
export function encodeUtf8(text: string): Uint8Array {
  const encoded: Uint8Array = new util.TextEncoder().encodeInto(text);
  return encoded;
}

/** 去掉 `file://` 前缀（照参考实现 post 的路径处理）。 */
export function stripFileScheme(path: string): string {
  if (path.startsWith('file://')) {
    return path.substring(7);
  }
  return path;
}
