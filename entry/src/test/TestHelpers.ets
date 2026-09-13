/*
 * 测试辅助：解析用例的注入实现 + 平台通道探针。
 *
 * ## 为什么文本编解码用纯实现（实测记录）
 *
 * 本工程的 **local 单测运行时**（`hvigorw ... test`，不占设备）对 `@ohos.util` 只提供
 * 部分实现。逐 API 的实测结论如下（观测通道：Utf8.test.ets → core.textChannels →
 * logsPlatformTextChannelAvailability 写入 hilog，tag `test.textchannels`）：
 *
 * | 平台 API | 本环境的实测结果 | 观测证据 |
 * | --- | --- | --- |
 * | `util.TextEncoder().encodeInto('务a')` | **返回空的 Uint8Array**（长度 0） | `platformEncoderAgreesWithPureEncoder` 失败时 actual 为 `''`，而纯实现为 `e58aa161` |
 * | `util.Base64Helper().decodeSync(合法 base64)` | **解不出字节**（返回空 / 抛异常被吞） | `base64DecodersAgreeWithTheProductionChannel` 失败时 actual 为 `''`，纯实现为 `<p>务` |
 * | `util.TextDecoder().decodeWithStream/decodeToString` | **未单独测出**：早期解码失败用例完全可以由"上游编码器返回空"解释，因此不能据此判定解码器坏。设备窗口再单独观测 | 见同一探针日志 |
 *
 * 结论：解析器依赖的"字节 ↔ 文本"这一步**不能**建立在平台 API 之上，否则 host 与设备
 * 行为不一致（本项目已因同类耦合付过代价）。因此：
 *   - `domain/parse/Utf8.ets` 提供**纯** UTF-8 编解码，生产（core/codec/TextCodec）与
 *     本文件都走它，host 与设备是同一份实现；
 *   - Base64 → 字节在生产里仍走平台 `Base64Helper`（设备上可用；local 环境不可用），
 *     字节 → 文本走纯实现。
 *
 * ## 平台探针
 *
 * `platformProbeBase64Decoder` **只在设备上有效**（local 环境返回空），它存在的唯一目的
 * 是让"平台 Base64 通道"复验有一条可执行的观测路径；它**不参与任何断言**。
 */

import util from '@ohos.util';
import { Base64Decoder } from '../main/ets/domain/parse/NoticeParser';
import { decodeUtf8, encodeUtf8 } from '../main/ets/domain/parse/Utf8';
import { UploadProgress } from '../main/ets/data/remote/Port';

export { decodeUtf8, encodeUtf8 };

/**
 * 平台 Base64 通道的探针（**仅设备上有效**；local 单测环境里 `@ohos.util` 不工作）。
 * 用途：在设备上复验 `util.Base64Helper.decodeSync` 能否解出字节（待验证项）。
 * 任何用例都**不得**基于它的返回值做断言——它只把结果写进日志供人工比对。
 */
export const platformProbeBase64Decoder: Base64Decoder = (encoded: string): string => {
  if (!encoded) {
    return '';
  }
  try {
    return decodeUtf8(new util.Base64Helper().decodeSync(encoded));
  } catch (error) {
    return '';
  }
};

/** 纯 JS 的 Base64 → 字节（不依赖任何平台 API），用作对照实现。 */
export function pureBase64ToBytes(encoded: string): Uint8Array {
  const alphabet: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  const clean: string = encoded.replace(/[^A-Za-z0-9+/]/g, '');
  const out: number[] = [];
  let buffer: number = 0;
  let bits: number = 0;
  for (let i = 0; i < clean.length; i++) {
    const value: number = alphabet.indexOf(clean.charAt(i));
    if (value < 0) {
      continue;
    }
    buffer = (buffer << 6) | value;
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      out.push((buffer >> bits) & 0xff);
    }
  }
  const bytes = new Uint8Array(out.length);
  for (let i = 0; i < out.length; i++) {
    bytes[i] = out[i];
  }
  return bytes;
}

/** 纯 JS 的 Base64 → 文本。 */
export function pureBase64Decoder(encoded: string): string {
  return decodeUtf8(pureBase64ToBytes(encoded));
}

/**
 * 与**生产同语义**的 Base64 解码器：先按 base64 形状校验，非法输入返回空串。
 *
 * 生产路径用平台 `util.Base64Helper.decodeSync` —— 它对非法输入抛异常，被捕获后同样
 * 返回空串（见 core/codec/TextCodec）。local 单测环境里平台通道不可用（见文件头实测表），
 * 所以解析用例注入本实现来验证"解析器 + 解码容错"这一侧；平台通道本身由
 * `platformProbeBase64Decoder` 在设备窗口复验。
 */
export const strictPureBase64Decoder: Base64Decoder = (encoded: string): string => {
  if (encoded.length === 0 || encoded.length % 4 !== 0) {
    return '';
  }
  if (/[^A-Za-z0-9+/=]/.test(encoded)) {
    return '';
  }
  return pureBase64Decoder(encoded);
};

/** 文本 → UTF-8 字节（与生产同一实现）。 */
export function deviceUtf8Encoder(text: string): Uint8Array {
  return encodeUtf8(text);
}

/** 上传进度的记录器。 */
export class RecordingProgressSink {
  readonly events: UploadProgress[] = [];

  sink = (progress: UploadProgress): void => {
    this.events.push(progress);
  };
}
