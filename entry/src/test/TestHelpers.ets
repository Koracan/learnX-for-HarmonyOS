/*
 * 测试辅助：把参考实现的"设备事件上报"换成可断言的普通回调。
 *
 * 这些是**测试专用**实现，放在 entry/src/test 下（不参与应用打包）：
 *   - `deviceBase64Decoder`：用设备上的 util.Base64Helper 做真实解码，
 *     验证的是"解析器拿到解码后的文本后怎么用"，而不是"base64 算法对不对"；
 *   - `deviceUtf8Encoder`：multipart 组装需要的 UTF-8 编码；
 *   - `RecordingProgressSink`：上传进度回调的记录器（参考实现走 `emitDeviceEvent`，
 *     移植后是普通回调，这里证明回调确实被调用）。
 */

import util from '@ohos.util';
import { Base64Decoder } from '../main/ets/domain/parse/NoticeParser';
import { UploadProgress } from '../main/ets/data/remote/Port';

/** 设备上的 Base64 → 文本解码器。 */
export class DeviceBase64Decoder {
  decode(encoded: string): string {
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
}

/** 供 NoticeParser 使用的解码器函数。 */
export const deviceBase64Decoder: Base64Decoder = (encoded: string): string => {
  return new DeviceBase64Decoder().decode(encoded);
};

/** 文本 → UTF-8 字节。 */
export function deviceUtf8Encoder(text: string): Uint8Array {
  return new util.TextEncoder().encodeInto(text);
}

/** 字节 → 文本（断言 multipart 组装结果用）。 */
export function decodeUtf8(bytes: Uint8Array): string {
  return new util.TextDecoder().decodeWithStream(bytes);
}

/** 上传进度的记录器。 */
export class RecordingProgressSink {
  readonly events: UploadProgress[] = [];

  sink = (progress: UploadProgress): void => {
    this.events.push(progress);
  };
}
