/*
 * 指纹摘要（domain，纯逻辑）：为"服务端登记值 == 我们保存的凭据指纹"提供**可判定**的等式。
 *
 * 为什么需要一个摘要而不是直接打指纹：
 *   - 指纹真值不得进日志（AGENTS.md 的取证纪律）；
 *   - 但"三个点是不是同一个值"必须**可判定**。取 SHA256 的前 8 位十六进制做指纹摘要，
 *     既不泄漏原值，又能让 H1/H2/H3 三行日志逐字比对。
 *
 * 为什么自己实现 SHA256 而不是用 cryptoFramework：这个摘要要能进 host 单测（有 NIST 向量可
 * 逐条断言），而平台加密链在 host 环境不可用——本工程已因"把正确性绑在平台可用性上"付过代价
 * （见 core/codec/TextCodec 的文件头）。纯实现 = 设备与 host 同一份代码。
 */

import { encodeUtf8 } from '../parse/Utf8';

/** SHA-256 轮常量（FIPS 180-4），以十六进制字面量保存便于逐条核对。 */
const K_HEX: string[] = [
  '428a2f98', '71374491', 'b5c0fbcf', 'e9b5dba5', '3956c25b', '59f111f1', '923f82a4', 'ab1c5ed5',
  'd807aa98', '12835b01', '243185be', '550c7dc3', '72be5d74', '80deb1fe', '9bdc06a7', 'c19bf174',
  'e49b69c1', 'efbe4786', '0fc19dc6', '240ca1cc', '2de92c6f', '4a7484aa', '5cb0a9dc', '76f988da',
  '983e5152', 'a831c66d', 'b00327c8', 'bf597fc7', 'c6e00bf3', 'd5a79147', '06ca6351', '14292967',
  '27b70a85', '2e1b2138', '4d2c6dfc', '53380d13', '650a7354', '766a0abb', '81c2c92e', '92722c85',
  'a2bfe8a1', 'a81a664b', 'c24b8b70', 'c76c51a3', 'd192e819', 'd6990624', 'f40e3585', '106aa070',
  '19a4c116', '1e376c08', '2748774c', '34b0bcb5', '391c0cb3', '4ed8aa4a', '5b9cca4f', '682e6ff3',
  '748f82ee', '78a5636f', '84c87814', '8cc70208', '90befffa', 'a4506ceb', 'bef9a3f7', 'c67178f2'
];

/** 初始哈希值（FIPS 180-4）。 */
const H_HEX: string[] = [
  '6a09e667', 'bb67ae85', '3c6ef372', 'a54ff53a', '510e527f', '9b05688c', '1f83d9ab', '5be0cd19'
];

function rotr(value: number, bits: number): number {
  return ((value >>> bits) | (value << (32 - bits))) >>> 0;
}

function hex8(value: number): string {
  let text: string = (value >>> 0).toString(16);
  while (text.length < 8) {
    text = '0' + text;
  }
  return text;
}

/** SHA-256（FIPS 180-4）→ 64 位小写十六进制。 */
export function sha256Hex(text: string): string {
  const message: Uint8Array = encodeUtf8(text);
  const length: number = message.length;
  let paddedLength: number = length + 1;
  paddedLength += (56 - (paddedLength % 64) + 64) % 64;
  paddedLength += 8;
  const padded: Uint8Array = new Uint8Array(paddedLength);
  padded.set(message, 0);
  padded[length] = 0x80;
  // 位长度按大端 64 位写在末尾（本工程的输入都是短文本，高 32 位恒为 0，但仍按规范写全）
  const bitLengthHigh: number = Math.floor(length / 536870912);
  const bitLengthLow: number = (length * 8) >>> 0;
  padded[paddedLength - 8] = (bitLengthHigh >>> 24) & 0xff;
  padded[paddedLength - 7] = (bitLengthHigh >>> 16) & 0xff;
  padded[paddedLength - 6] = (bitLengthHigh >>> 8) & 0xff;
  padded[paddedLength - 5] = bitLengthHigh & 0xff;
  padded[paddedLength - 4] = (bitLengthLow >>> 24) & 0xff;
  padded[paddedLength - 3] = (bitLengthLow >>> 16) & 0xff;
  padded[paddedLength - 2] = (bitLengthLow >>> 8) & 0xff;
  padded[paddedLength - 1] = bitLengthLow & 0xff;

  const h: number[] = [];
  for (let i = 0; i < 8; i++) {
    h.push(Number.parseInt(H_HEX[i], 16) | 0);
  }
  const w: number[] = [];
  for (let i = 0; i < 64; i++) {
    w.push(0);
  }

  for (let offset = 0; offset < paddedLength; offset += 64) {
    for (let i = 0; i < 16; i++) {
      const base: number = offset + i * 4;
      w[i] = ((padded[base] << 24) | (padded[base + 1] << 16) | (padded[base + 2] << 8) | padded[base + 3]) | 0;
    }
    for (let i = 16; i < 64; i++) {
      const s0: number = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >>> 3);
      const s1: number = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >>> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) | 0;
    }
    let a: number = h[0];
    let b: number = h[1];
    let c: number = h[2];
    let d: number = h[3];
    let e: number = h[4];
    let f: number = h[5];
    let g: number = h[6];
    let hh: number = h[7];
    for (let i = 0; i < 64; i++) {
      const s1: number = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
      const ch: number = (e & f) ^ ((~e) & g);
      const temp1: number = (hh + s1 + ch + (Number.parseInt(K_HEX[i], 16) | 0) + w[i]) | 0;
      const s0: number = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
      const maj: number = (a & b) ^ (a & c) ^ (b & c);
      const temp2: number = (s0 + maj) | 0;
      hh = g;
      g = f;
      f = e;
      e = (d + temp1) | 0;
      d = c;
      c = b;
      b = a;
      a = (temp1 + temp2) | 0;
    }
    h[0] = (h[0] + a) | 0;
    h[1] = (h[1] + b) | 0;
    h[2] = (h[2] + c) | 0;
    h[3] = (h[3] + d) | 0;
    h[4] = (h[4] + e) | 0;
    h[5] = (h[5] + f) | 0;
    h[6] = (h[6] + g) | 0;
    h[7] = (h[7] + hh) | 0;
  }

  let out: string = '';
  for (let i = 0; i < 8; i++) {
    out += hex8(h[i]);
  }
  return out;
}

/**
 * 指纹摘要：SHA256 的前 8 位十六进制（空值 → \`empty\`）。
 *
 * 8 位十六进制 = 32 bit，对"同一台设备上两三个值是否相同"这种用途足够；它**不是**密码学意义上的
 * 隐藏（指纹本身也不是口令），但是"日志里不出现原值、又能逐字比对"的平衡点。
 */
export function fingerprintDigest(value: string): string {
  if (value.length === 0) {
    return 'empty';
  }
  return sha256Hex(value).substring(0, 8);
}
