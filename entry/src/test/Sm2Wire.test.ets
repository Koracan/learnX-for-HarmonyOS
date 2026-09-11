/*
 * SM2 上线密文组装单测（ticket 06，验收第 3 条的可本地验证部分）。
 *
 * 用 [设备] 真实向量（模拟器产出，.scratch/migration/sm2-verify/arkts-wire.txt）锁定：
 * '04' + X(64) + Y(64) + C3(64) + C2，且各段按 32 字节**左侧补零**。
 * 平台加密本身（cryptoFramework）只能在设备上验，见 ticket 06 Comments 的未验证项。
 */

import { describe, it, expect } from '@ohos/hypium';
import {
  assembleCipherText, normalizeSm2PublicKey, leftPadHex32, isHex, bytesToHex
} from '../main/ets/core/crypto/Sm2Cipher';
import {
  SM2_WIRE, SM2_WIRE_X, SM2_WIRE_Y, SM2_WIRE_C3, SM2_WIRE_C2, SM2_WIRE_X_TRUNCATED, REAL_SM2_PUBLIC_KEY
} from './fixtures/AuthFixtures';

export default function sm2WireTest() {
  describe('core.Sm2Cipher', () => {
    it('reassemblesTheRealDeviceCipherText', 0, () => {
      // [设备] 逐字节复现模拟器产出的上线密文
      expect(SM2_WIRE.length).assertEqual(256);
      expect(assembleCipherText(SM2_WIRE_X, SM2_WIRE_Y, SM2_WIRE_C3, SM2_WIRE_C2)).assertEqual(SM2_WIRE);
      expect(SM2_WIRE.startsWith('04')).assertTrue();
      expect(SM2_WIRE_C2.length).assertEqual(62);
    });

    it('leftPadsCoordinatesThatLostLeadingZeroBytes', 0, () => {
      // 真丢零的形态：64 位里首位是 '0'，被截成 63 位后必须补回同一个值
      const fullX: string = '00' + SM2_WIRE_X.substring(2);
      const strippedX: string = fullX.substring(1);
      expect(fullX.length).assertEqual(64);
      expect(strippedX.length).assertEqual(63);
      expect(assembleCipherText(strippedX, SM2_WIRE_Y, SM2_WIRE_C3, SM2_WIRE_C2))
        .assertEqual(assembleCipherText(fullX, SM2_WIRE_Y, SM2_WIRE_C3, SM2_WIRE_C2));
      expect(leftPadHex32('abc')).assertEqual('0000000000000000000000000000000000000000000000000000000000000abc');
      expect(leftPadHex32(SM2_WIRE_X)).assertEqual(SM2_WIRE_X);
    });

    it('padsLengthButNeverGuessesADroppedNonZeroDigit', 0, () => {
      // 补零只恢复长度；丢掉的若不是 0，补出来的值**不等于**原密文——这条防止把"补零"当"还原"
      const padded: string = assembleCipherText(SM2_WIRE_X_TRUNCATED, SM2_WIRE_Y, SM2_WIRE_C3, SM2_WIRE_C2);
      expect(SM2_WIRE_X_TRUNCATED.length).assertEqual(63);
      expect(padded.length).assertEqual(SM2_WIRE.length);
      expect(padded === SM2_WIRE).assertFalse();
      // 截掉的是 'c'（非零），补位只能补 '0'：结果以 '0403' 开头（04 + 补的 0 + 剩下的 '3'）
      expect(padded.substring(0, 4)).assertEqual('0403');
    });

    it('normalisesCaseAndRejectsMalformedSegments', 0, () => {
      const upper: string = SM2_WIRE.toUpperCase();
      expect(assembleCipherText(upper.substring(2, 66), upper.substring(66, 130),
        upper.substring(130, 194), upper.substring(194))).assertEqual(SM2_WIRE);
      expect(assembleCipherText('zz', SM2_WIRE_Y, SM2_WIRE_C3, SM2_WIRE_C2)).assertEqual('');
      expect(assembleCipherText(SM2_WIRE_X, SM2_WIRE_Y, SM2_WIRE_C3, 'abc')).assertEqual('');
      expect(assembleCipherText(SM2_WIRE_X, SM2_WIRE_Y, SM2_WIRE_C3, '')).assertEqual('');
      const tooLong: string = SM2_WIRE_X + 'ab';
      expect(assembleCipherText(tooLong, SM2_WIRE_Y, SM2_WIRE_C3, SM2_WIRE_C2)).assertEqual('');
    });

    it('normalisesThePublicKeyFromTheLoginPage', 0, () => {
      // [抓取] 真实页面给的公钥带 04、130 hex
      const normalized: string = normalizeSm2PublicKey(REAL_SM2_PUBLIC_KEY);
      expect(normalized.length).assertEqual(128);
      expect(normalized.startsWith('04')).assertFalse();
      expect(normalizeSm2PublicKey(normalized)).assertEqual(normalized);
      expect(normalizeSm2PublicKey('  ' + REAL_SM2_PUBLIC_KEY + '\n')).assertEqual(normalized);
      expect(normalizeSm2PublicKey('04')).assertEqual('');
      expect(normalizeSm2PublicKey(normalized + 'ab')).assertEqual('');
      expect(normalizeSm2PublicKey('zz' + normalized.substring(2))).assertEqual('');
    });

    it('convertsBytesToLowercaseHex', 0, () => {
      const bytes = new Uint8Array(3);
      bytes[0] = 0;
      bytes[1] = 15;
      bytes[2] = 255;
      expect(bytesToHex(bytes)).assertEqual('000fff');
      expect(isHex('00ff')).assertTrue();
      expect(isHex('00ffz')).assertFalse();
      expect(isHex('')).assertFalse();
    });
  });
}