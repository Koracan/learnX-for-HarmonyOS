/*
 * 设备身份单测：UUID v4 的位规则、deviceName 组装、脱敏输出。
 *
 * 为什么值得测：`fingerPrint` 是**信任绑定的键**（ADR-0004）。它的位规则写错（版本位/变体位）
 * 不会让任何请求失败，但会让"我们的指纹"与页面自己的指纹库混淆；而脱敏写错会把凭据写进
 * 日志。这两类都是"肉眼看不出来"的错误。
 */

import { describe, it, expect } from '@ohos/hypium';
import {
  composeDeviceName, describeFingerprints, formatUuidV4, isUuidV4, redactSecret, sameSecret
} from '../main/ets/domain/auth/DeviceIdentity';

/** 0x00..0x0f 的 16 字节，便于逐位验证版本位与变体位。 */
const BYTES_0_TO_15: number[] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15];

export default function deviceIdentityTest() {
  describe('domain.DeviceIdentity', () => {
    it('setsTheVersionAndVariantBitsLikeTheReference', 0, () => {
      // 参考实现 helpers/fingerprint.ts:10-13：bytes[6] = (b & 0x0f) | 0x40、bytes[8] = (b & 0x3f) | 0x80。
      // 源字节 6=0x06、8=0x08 → 0x46、0x88。
      const value: string = formatUuidV4(BYTES_0_TO_15);
      expect(value).assertEqual('00010203-0405-4607-8809-0a0b0c0d0e0f');
      expect(isUuidV4(value)).assertTrue();
    });

    it('padsSingleHexDigitsAndIgnoresExtraBytes', 0, () => {
      const short: string = formatUuidV4([1, 2, 3]);
      expect(short).assertEqual('01020300-0000-4000-8000-000000000000');
      const long: string = formatUuidV4([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 99]);
      expect(long).assertEqual('01020304-0506-4708-890a-0b0c0d0e0f10');
    });

    it('masksBytesToEightBits', 0, () => {
      const negative: string = formatUuidV4([-1, 256, 255, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
      expect(negative.startsWith('ff00ff00')).assertTrue();
    });

    it('acceptsOnlyUuidV4Shapes', 0, () => {
      expect(isUuidV4('aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee')).assertTrue();
      // 第三段不是 4 开头（v1/v3/v5 的指纹不该被当成 v4）
      expect(isUuidV4('aaaaaaaa-bbbb-1ccc-8ddd-eeeeeeeeeeee')).assertFalse();
      // 变体位不是 10xx
      expect(isUuidV4('aaaaaaaa-bbbb-4ccc-7ddd-eeeeeeeeeeee')).assertFalse();
      // 大写与长度不符都不接受
      expect(isUuidV4('AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE')).assertFalse();
      expect(isUuidV4('')).assertFalse();
    });

    it('composesTheSpecDeviceName', 0, () => {
      // HarmonyOS,learnOH/{versionName} ({productModel})
      expect(composeDeviceName('1.1.0', 'PURA 90')).assertEqual('HarmonyOS,learnOH/1.1.0 (PURA 90)');
      expect(composeDeviceName('', '')).assertEqual('HarmonyOS,learnOH/unknown (unknown)');
      expect(composeDeviceName('2.0.0', '')).assertEqual('HarmonyOS,learnOH/2.0.0 (unknown)');
    });

    it('redactsSecretsToPrefixAndLength', 0, () => {
      expect(redactSecret('')).assertEqual('empty');
      expect(redactSecret('abcdef')).assertEqual('abcd…(6)');
      expect(redactSecret('abc')).assertEqual('abc…(3)');
      const secret: string = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
      const redacted: string = redactSecret(secret);
      expect(redacted).assertEqual('aaaa…(36)');
      expect(redacted.indexOf('bbbb')).assertEqual(-1);
      expect(redacted.length < secret.length).assertTrue();
    });

    it('comparesSecretsWithoutLeakingThem', 0, () => {
      expect(sameSecret('abc', 'abc')).assertTrue();
      expect(sameSecret('abc', 'abd')).assertFalse();
      expect(sameSecret('abc', 'abcd')).assertFalse();
      expect(sameSecret('', '')).assertTrue();
    });

    it('describesFingerprintsWithoutValues', 0, () => {
      const fp: string = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
      const text: string = describeFingerprints(fp, 'genprint-1', '');
      expect(text.indexOf(fp)).assertEqual(-1);
      expect(text.indexOf('genprint-1')).assertEqual(-1);
      expect(text.indexOf('fingerPrint=aaaa…(36)') >= 0).assertTrue();
      expect(text.indexOf('fingerGenPrint=genp…(10)') >= 0).assertTrue();
      expect(text.indexOf('fingerGenPrint3=empty') >= 0).assertTrue();
    });
  });
}
