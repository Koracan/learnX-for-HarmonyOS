/*
 * SM2 口令加密（core/crypto）：产出与参考实现 `'04' + sm2.doEncrypt(password, publicKey)` 同构的密文。
 *
 * 变换串与排列的结论来自待验证项 #1（已设备实测通过，证据在
 * `.scratch/migration/sm2-verify/`）：
 *   - transformation = **`'SM2_256|SM3'`**（`'SM2|SM3'` 亦可；其它串见证据里的失败表）；
 *   - `initSync(ENCRYPT_MODE, pubKey, null)`（SM2 没有额外的模式参数）；
 *   - `doFinalSync` 出 **ASN.1 DER**；用 `SM2CryptoUtil.getCipherTextSpec(der, 'C1C3C2')` 取出
 *     x/y/C3/C2，各自按 32 字节左侧补零后拼 `'04' + X + Y + C3 + C2`（排列**不能**用 transformation 指定）；
 *   - 参考实现 `sm-crypto@0.3.14` 默认 `cipherMode = 1` = **C1C3C2**，且返回小写 hex、不带 `04`。
 *
 * 纯函数（`normalizeSm2PublicKey` / `leftPadHex32` / `assembleCipherText`）与平台调用分开：
 * 前者用真实设备产出的密文向量单测（`.scratch/migration/sm2-verify/arkts-wire.txt`），
 * 后者只能在设备上验（见未验证项）。
 */

import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { encodeUtf8 } from '../codec/TextCodec';

/** 站点点位长度（字节）。 */
const COORDINATE_HEX_LENGTH: number = 64;

/** 是否为合法 hex（偶数长度由调用方另判）。 */
export function isHex(text: string): boolean {
  if (text.length === 0) {
    return false;
  }
  return /^[0-9a-fA-F]+$/.test(text);
}

/**
 * 规范化登录页给出的公钥：可选 `04` 前缀 + 128 hex。
 * @returns 128 hex（小写）；非法返回空串。
 */
export function normalizeSm2PublicKey(raw: string): string {
  const trimmed: string = raw === undefined || raw === null ? '' : raw.trim();
  const body: string = trimmed.startsWith('04') || trimmed.startsWith('04'.toUpperCase())
    ? trimmed.substring(2)
    : trimmed;
  if (body.length !== 128 || !isHex(body)) {
    return '';
  }
  return body.toLowerCase();
}

/** 左侧补零到 32 字节（64 hex）；超长或非 hex 返回空串。 */
export function leftPadHex32(hex: string): string {
  if (!isHex(hex) || hex.length > COORDINATE_HEX_LENGTH) {
    return '';
  }
  let padded: string = hex.toLowerCase();
  while (padded.length < COORDINATE_HEX_LENGTH) {
    padded = '0' + padded;
  }
  return padded;
}

/**
 * 组装上线密文：`'04' + X(64) + Y(64) + C3(64) + C2(变长)`，全小写。
 *
 * 左侧补零是官方 FAQ 明确警告过的点（OpenSSL 会丢高位 0），见
 * `.scratch/migration/sm2-verify/doc-faq-31.txt`。
 * @returns 合法密文；任一段非法时返回空串（调用方按失败处理）。
 */
export function assembleCipherText(xHex: string, yHex: string, c3Hex: string, c2Hex: string): string {
  const x: string = leftPadHex32(xHex);
  const y: string = leftPadHex32(yHex);
  const c3: string = leftPadHex32(c3Hex);
  if (x.length === 0 || y.length === 0 || c3.length === 0) {
    return '';
  }
  if (!isHex(c2Hex) || c2Hex.length === 0 || c2Hex.length % 2 !== 0) {
    return '';
  }
  return '04' + x + y + c3 + c2Hex.toLowerCase();
}

/** 字节 → 小写 hex。 */
export function bytesToHex(bytes: Uint8Array): string {
  let text: string = '';
  for (let i = 0; i < bytes.length; i++) {
    const part: string = bytes[i].toString(16);
    text += part.length === 1 ? '0' + part : part;
  }
  return text;
}

/** 加密结果：不抛异常，失败也是结果（与 `FetchOutcome` 同一风格）。 */
export interface Sm2EncryptResult {
  ok: boolean;
  /** 上线密文（`04` 开头的 hex）；失败时为空串。 */
  cipherText: string;
  error?: string;
}

/** 口令加密器：登录流把它当依赖注入，于是登录流可以在单测里用替身跑通。 */
export type PasswordEncryptor = (password: string, publicKeyHex: string) => Sm2EncryptResult;

function failure(message: string): Sm2EncryptResult {
  const result: Sm2EncryptResult = { ok: false, cipherText: '' };
  result.error = message;
  return result;
}

/** 由 hex 公钥造 `PubKey`（照官方 FAQ doc-faq-38.txt:16-32）。 */
function buildPublicKey(normalized: string): cryptoFramework.PubKey {
  const x: string = normalized.substring(0, 64);
  const y: string = normalized.substring(64);
  const point: cryptoFramework.Point = {
    x: BigInt('0x' + x),
    y: BigInt('0x' + y)
  };
  const spec: cryptoFramework.ECCPubKeySpec = {
    params: cryptoFramework.ECCKeyUtil.genECCCommonParamsSpec('NID_sm2'),
    pk: point,
    algName: 'SM2',
    specType: cryptoFramework.AsyKeySpecType.PUBLIC_KEY_SPEC
  };
  return cryptoFramework.createAsyKeyGeneratorBySpec(spec).generatePubKeySync();
}

/**
 * 平台实现：把口令加密成参考实现同构的上线密文。
 *
 * **只能在设备上验**：cryptoFramework 是平台能力，本工程的 local 单测环境不提供实现
 * （与 `@ohos.util` 同类），所以单测只能覆盖纯函数那一段。
 */
export function encryptPasswordWithSm2(password: string, publicKeyHex: string): Sm2EncryptResult {
  const normalized: string = normalizeSm2PublicKey(publicKeyHex);
  if (normalized.length === 0) {
    return failure('invalid sm2 public key (expect optional 04 prefix + 128 hex)');
  }
  try {
    const cipher: cryptoFramework.Cipher = cryptoFramework.createCipher('SM2_256|SM3');
    const key: cryptoFramework.PubKey = buildPublicKey(normalized);
    cipher.initSync(cryptoFramework.CryptoMode.ENCRYPT_MODE, key, null);
    const plain: cryptoFramework.DataBlob = { data: encodeUtf8(password) };
    const encrypted: cryptoFramework.DataBlob = cipher.doFinalSync(plain);
    const spec: cryptoFramework.SM2CipherTextSpec =
      cryptoFramework.SM2CryptoUtil.getCipherTextSpec(encrypted, 'C1C3C2');
    const cipherText: string = assembleCipherText(
      spec.xCoordinate.toString(16),
      spec.yCoordinate.toString(16),
      bytesToHex(spec.hashData),
      bytesToHex(spec.cipherTextData)
    );
    if (cipherText.length === 0) {
      return failure('assembled cipher text is empty');
    }
    const result: Sm2EncryptResult = { ok: true, cipherText: cipherText };
    return result;
  } catch (error) {
    return failure((error as Error).message);
  }
}
