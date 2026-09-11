/*
 * UTF-8 编解码——**纯函数，零平台依赖**（见 scripts/check-domain-purity.mjs）。
 *
 * 为什么要自己写：平台侧 `util.TextDecoder.decodeWithStream` 在单测运行环境里返回
 * `undefined`（实测：同一个 `Uint8Array` 用 `decodeToString` 正常、用 `decodeWithStream`
 * 拿不到字符串），把"公告正文能不能解出来"和"平台 API 在这个环境里准不准"绑在了一起。
 * 自己实现之后：
 *   - 生产路径与单测路径**是同一份代码**，host 与设备行为一致；
 *   - 解析逻辑的正确性不再由平台解码器背书（Base64 → 字节仍走平台 `Base64Helper`，
 *     字节 → 文本用本文件）。
 *
 * 只实现 UTF-8（站点发出的就是 UTF-8），不含 BOM / 代理对以外的边界分支。
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
