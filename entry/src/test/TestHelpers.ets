/*
 * 测试辅助：把参考实现的"设备事件上报"换成可断言的普通回调。
 *
 * 这些是**测试专用**实现，放在 entry/src/test 下（不参与应用打包）。
 *
 * 文本编解码一律走 domain/parse/Utf8 的**纯实现**（生产路径同一份代码，见
 * core/codec/TextCodec）：平台 `util.TextDecoder.decodeWithStream` 在单测环境里
 * 返回 undefined，用它做断言辅助会把"解析是否正确"和"平台 API 在此环境是否可用"
 * 混在一起——本工程已经因为这类耦合浪费过时间（02 的 ICU 措辞问题）。
 * Base64 解码保留平台通道 `util.Base64Helper`（这一部分在本环境工作正常），
 * 解码出的字节再用纯 UTF-8 解码，与方法在生产中的组合完全一致。
 */

import util from '@ohos.util';
import { Base64Decoder } from '../main/ets/domain/parse/NoticeParser';
import { decodeUtf8, encodeUtf8 } from '../main/ets/domain/parse/Utf8';
import { UploadProgress } from '../main/ets/data/remote/Port';

export { decodeUtf8, encodeUtf8 };

/**
 * 与生产一致的 Base64 解码：平台 `Base64Helper` + 纯 UTF-8 解码。
 * 即 `core/codec/TextCodec.decodeBase64Text` 的同构实现（此处独立重写，
 * 是为了单测能在不 import core 的前提下验证解析器；两者行为由 Utf8.test 对齐断言）。
 */
export const deviceBase64Decoder: Base64Decoder = (encoded: string): string => {
  if (!encoded) {
    return '';
  }
  let decoded: Uint8Array;
  try {
    decoded = new util.Base64Helper().decodeSync(encoded);
  } catch (error) {
    return '';
  }
  return decodeUtf8(decoded);
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
 * 返回空串（见 core/codec/TextCodec）。本环境里 `@ohos.util` 不可用（实测返回空数组），
 * 所以解析用例注入这个纯实现来验证"解析器 + 解码容错"这一侧；
 * 平台通道本身需要在设备上复验（见 ticket 05 Comments）。
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
