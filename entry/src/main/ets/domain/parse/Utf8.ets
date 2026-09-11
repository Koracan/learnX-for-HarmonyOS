/*
 * UTF-8 编解码——**纯叶子工具**，零平台依赖（见 scripts/check-domain-purity.mjs）。
 *
 * `domain/` 默认不允许被 `core/` 反向依赖；本文件是 spec 第 2 节明确的**唯一例外**：
 * "纯叶子工具（无平台依赖、无领域实体、无业务规则，例如 domain/parse/Utf8.ets 的 UTF-8
 * 编解码）……放在 domain/ 下可获得 check-domain-purity.mjs 的自动纯度保护，而 core 允许引用它"。
 * 自查：本文件**没有任何 import**（无 @ohos.* / @kit.* / @hms.*，也不 import 任何领域实体），
 * 因此它只是一个受纯度保护的编解码工具，被 core/codec/TextCodec 与测试共同引用。
 *
 * 为什么要自己写而不是用平台 API：见 TestHelpers.ets 文件头的逐 API 实测表——
 * local 单测环境里 `util.TextEncoder.encodeInto` 返回空数组、`util.Base64Helper.decodeSync`
 * 解不出字节，而平台 `TextDecoder` 未被单独测出。把"字节 ↔ 文本"建立在平台 API 上会让
 * host 与设备行为不一致；自己实现后，生产与测试是同一份代码。
 *
 * 只实现 UTF-8（站点发出的就是 UTF-8），非法序列按 U+FFFD 处理，不抛异常。
 */

/** 文本 → UTF-8 字节。 */
export function encodeUtf8(text: string): Uint8Array {
  const bytes: number[] = [];
  for (let i = 0; i < text.length; i++) {
    const code: number = text.charCodeAt(i);
    if (code < 0x80) {
      bytes.push(code);
    } else if (code < 0x800) {
      bytes.push(0xc0 | (code >> 6), 0x80 | (code & 0x3f));
    } else if (code >= 0xd800 && code <= 0xdbff && i + 1 < text.length) {
      // 代理对：高代理 + 低代理 → 4 字节
      const low: number = text.charCodeAt(i + 1);
      if (low >= 0xdc00 && low <= 0xdfff) {
        const point: number = 0x10000 + ((code - 0xd800) << 10) + (low - 0xdc00);
        bytes.push(
          0xf0 | (point >> 18),
          0x80 | ((point >> 12) & 0x3f),
          0x80 | ((point >> 6) & 0x3f),
          0x80 | (point & 0x3f)
        );
        i++;
        continue;
      }
      bytes.push(0xef, 0xbf, 0xbd);
    } else if (code >= 0xd800 && code <= 0xdfff) {
      // 落单的代理 → U+FFFD
      bytes.push(0xef, 0xbf, 0xbd);
    } else {
      bytes.push(0xe0 | (code >> 12), 0x80 | ((code >> 6) & 0x3f), 0x80 | (code & 0x3f));
    }
  }
  const out = new Uint8Array(bytes.length);
  for (let i = 0; i < bytes.length; i++) {
    out[i] = bytes[i];
  }
  return out;
}

function replacement(): string {
  return String.fromCharCode(0xfffd);
}

/** UTF-8 字节 → 文本；非法序列按 U+FFFD 处理（不抛异常）。 */
export function decodeUtf8(bytes: Uint8Array): string {
  let out: string = '';
  let i: number = 0;
  while (i < bytes.length) {
    const first: number = bytes[i];
    let extra: number = 0;
    let point: number = 0;
    if (first < 0x80) {
      out += String.fromCharCode(first);
      i++;
      continue;
    } else if ((first & 0xe0) === 0xc0) {
      extra = 1;
      point = first & 0x1f;
    } else if ((first & 0xf0) === 0xe0) {
      extra = 2;
      point = first & 0x0f;
    } else if ((first & 0xf8) === 0xf0) {
      extra = 3;
      point = first & 0x07;
    } else {
      out += replacement();
      i++;
      continue;
    }
    if (i + extra >= bytes.length) {
      out += replacement();
      break;
    }
    let ok: boolean = true;
    for (let k = 1; k <= extra; k++) {
      const next: number = bytes[i + k];
      if ((next & 0xc0) !== 0x80) {
        ok = false;
        break;
      }
      point = (point << 6) | (next & 0x3f);
    }
    if (!ok) {
      out += replacement();
      i++;
      continue;
    }
    if (point > 0xffff) {
      const high: number = 0xd800 + ((point - 0x10000) >> 10);
      const low: number = 0xdc00 + ((point - 0x10000) & 0x3ff);
      out += String.fromCharCode(high) + String.fromCharCode(low);
    } else {
      out += String.fromCharCode(point);
    }
    i += extra + 1;
  }
  return out;
}