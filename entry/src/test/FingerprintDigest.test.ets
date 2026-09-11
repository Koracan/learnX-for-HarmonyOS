/*
 * 指纹摘要单测（ticket 07 验收第 2 条的"三点等式"工具）。
 *
 * 用 FIPS 180-4 / NIST 的公开向量逐条钉住 SHA-256 实现：
 *   - 空串（单块、纯填充）；
 *   - "abc"（单块）；
 *   - 112 字节的官方多块向量（两块）；
 * 再加一条业务断言：摘要只暴露 8 位十六进制，原值不再出现。
 *
 * 为什么值得自己实现并测：这个摘要要在**设备日志**里充当"服务端登记值 == 我们保存的凭据指纹"
 * 的判据。如果哈希本身错了，等式会给出**假阳性**（两个不同的值算出同一个错误摘要的概率极低，
 * 但"所有值都算成同一个固定值"这种坏实现会 100% 假阳性）。
 */

import { describe, it, expect } from '@ohos/hypium';
import { fingerprintDigest, sha256Hex } from '../main/ets/domain/auth/FingerprintDigest';
import { SYNTHETIC_FINGERPRINT } from './fixtures/EnrollmentFixtures';

/** FIPS 180-4 的多块向量（112 字节，跨两个 64 字节块）。 */
const TWO_BLOCK_INPUT: string =
  'abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu';

export default function fingerprintDigestTest() {
  describe('domain.FingerprintDigest', () => {
    it('matchesTheNistVectorForTheEmptyString', 0, () => {
      expect(sha256Hex('')).assertEqual('e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
    });

    it('matchesTheNistVectorForAbc', 0, () => {
      expect(sha256Hex('abc')).assertEqual('ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    });

    it('matchesTheNistVectorForATwoBlockMessage', 0, () => {
      expect(TWO_BLOCK_INPUT.length).assertEqual(112);
      expect(sha256Hex(TWO_BLOCK_INPUT))
        .assertEqual('cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1');
    });

    it('handlesUtf8AndTheFiftyFiveBytePaddingBoundary', 0, () => {
      // 55 字节是"单块里最后一个不需要额外填充块"的长度；56 字节必须多开一块。
      expect(sha256Hex('a'.repeat(55)))
        .assertEqual('9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318');
      expect(sha256Hex('a'.repeat(56)))
        .assertEqual('b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a');
      // 中文按 UTF-8 字节参与哈希（纯实现内部走 domain/parse/Utf8）
      expect(sha256Hex('密码')).assertEqual(sha256Hex('密码'));
      expect(sha256Hex('密码') === sha256Hex('密馬')).assertFalse();
    });

    it('producesAFixedLengthLowercaseDigest', 0, () => {
      const digest: string = sha256Hex('learnOH');
      expect(digest.length).assertEqual(64);
      expect(digest.match(/^[0-9a-f]{64}$/) !== null).assertTrue();
    });

    it('reducesAFingerprintToEightHexDigits', 0, () => {
      const digest: string = fingerprintDigest(SYNTHETIC_FINGERPRINT);
      expect(digest.length).assertEqual(8);
      expect(digest.match(/^[0-9a-f]{8}$/) !== null).assertTrue();
      expect(SYNTHETIC_FINGERPRINT.indexOf(digest)).assertEqual(-1);
      // 同一个值必须稳定（三点等式的基础），不同值必须不同
      expect(fingerprintDigest(SYNTHETIC_FINGERPRINT)).assertEqual(digest);
      expect(fingerprintDigest(SYNTHETIC_FINGERPRINT + 'x') === digest).assertFalse();
      expect(fingerprintDigest('')).assertEqual('empty');
    });
  });
}
