/*
 * 凭据记录单测（ticket 07）：编解码往返、版本/损坏/缺字段的降级、脱敏输出。
 *
 * 判据来自 spec 第 5 节「任何非预期响应一律降级到 Enrollment」：一条读不出来的凭据必须
 * 表现成"没有凭据"（undefined），而不是抛异常或拿半条记录去重登。
 */

import { describe, it, expect } from '@ohos/hypium';
import {
  CREDENTIAL_SCHEMA_VERSION, CredentialRecord, createCredentialRecord, decodeCredentialRecord,
  describeCredentialRecord, encodeCredentialRecord, isCredentialRecordComplete
} from '../main/ets/domain/auth/CredentialRecord';
import {
  SYNTHETIC_FINGERPRINT, SYNTHETIC_FINGER_GEN_PRINT, SYNTHETIC_FINGER_GEN_PRINT3,
  SYNTHETIC_PASSWORD, SYNTHETIC_USERNAME
} from './fixtures/EnrollmentFixtures';

function sample(): CredentialRecord {
  return createCredentialRecord(SYNTHETIC_USERNAME, SYNTHETIC_PASSWORD, SYNTHETIC_FINGERPRINT,
    SYNTHETIC_FINGER_GEN_PRINT, SYNTHETIC_FINGER_GEN_PRINT3);
}

export default function credentialRecordTest() {
  describe('domain.CredentialRecord', () => {
    it('stampsTheSchemaVersionOnCreate', 0, () => {
      expect(sample().schemaVersion).assertEqual(CREDENTIAL_SCHEMA_VERSION);
    });

    it('roundTripsEveryField', 0, () => {
      const encoded: string = encodeCredentialRecord(sample());
      const decoded: CredentialRecord | undefined = decodeCredentialRecord(encoded);
      expect(decoded !== undefined).assertTrue();
      expect(decoded?.username).assertEqual(SYNTHETIC_USERNAME);
      expect(decoded?.password).assertEqual(SYNTHETIC_PASSWORD);
      expect(decoded?.fingerPrint).assertEqual(SYNTHETIC_FINGERPRINT);
      expect(decoded?.fingerGenPrint).assertEqual(SYNTHETIC_FINGER_GEN_PRINT);
      expect(decoded?.fingerGenPrint3).assertEqual(SYNTHETIC_FINGER_GEN_PRINT3);
      expect(decoded?.schemaVersion).assertEqual(CREDENTIAL_SCHEMA_VERSION);
    });

    it('keepsASingleLineSoItFitsOneAssetSecret', 0, () => {
      const encoded: string = encodeCredentialRecord(
        createCredentialRecord('u', 'p', 'f', 'g1', 'g2'));
      expect(encoded.indexOf('\n')).assertEqual(-1);
      expect(encoded.indexOf('"username":"u"') >= 0).assertTrue();
      expect(encoded.indexOf('"schemaVersion":1') >= 0).assertTrue();
    });

    it('returnsUndefinedForCorruptOrUnknownPayloads', 0, () => {
      expect(decodeCredentialRecord('') === undefined).assertTrue();
      expect(decodeCredentialRecord('not json at all') === undefined).assertTrue();
      expect(decodeCredentialRecord('{}') === undefined).assertTrue();
      // 高版本：我们读不懂就不猜（升级/降级都要走重新登记）
      expect(decodeCredentialRecord('{"schemaVersion":99,"username":"u","password":"p","fingerPrint":"f"}') === undefined)
        .assertTrue();
      // 版本字段不是数字
      expect(decodeCredentialRecord('{"schemaVersion":"1","username":"u","password":"p","fingerPrint":"f"}') === undefined)
        .assertTrue();
    });

    it('requiresUsernamePasswordAndOurFingerprint', 0, () => {
      const missingUser: string = '{"schemaVersion":1,"username":"","password":"p","fingerPrint":"f"}';
      expect(decodeCredentialRecord(missingUser) === undefined).assertTrue();
      const missingPass: string = '{"schemaVersion":1,"username":"u","password":"","fingerPrint":"f"}';
      expect(decodeCredentialRecord(missingPass) === undefined).assertTrue();
      const missingFp: string = '{"schemaVersion":1,"username":"u","password":"p","fingerPrint":""}';
      expect(decodeCredentialRecord(missingFp) === undefined).assertTrue();
      // 站点指纹可以缺（对齐参考实现 auth.ts:32-33 的默认空串）
      const noGen: CredentialRecord | undefined =
        decodeCredentialRecord('{"schemaVersion":1,"username":"u","password":"p","fingerPrint":"f"}');
      expect(noGen !== undefined).assertTrue();
      expect(noGen?.fingerGenPrint).assertEqual('');
      expect(noGen?.fingerGenPrint3).assertEqual('');
    });

    it('judgesCompletenessLikeTheReferenceLoginGuard', 0, () => {
      expect(isCredentialRecordComplete(sample())).assertTrue();
      expect(isCredentialRecordComplete(createCredentialRecord('', 'p', 'f', '', ''))).assertFalse();
      expect(isCredentialRecordComplete(createCredentialRecord('u', '', 'f', '', ''))).assertFalse();
      expect(isCredentialRecordComplete(createCredentialRecord('u', 'p', '', '', ''))).assertFalse();
    });

    it('describesTheRecordWithoutSecrets', 0, () => {
      const text: string = describeCredentialRecord(sample());
      expect(text.indexOf(SYNTHETIC_PASSWORD)).assertEqual(-1);
      expect(text.indexOf(SYNTHETIC_FINGERPRINT)).assertEqual(-1);
      expect(text.indexOf('usernameChars=' + SYNTHETIC_USERNAME.length.toString()) >= 0).assertTrue();
      expect(text.indexOf('passwordChars=' + SYNTHETIC_PASSWORD.length.toString()) >= 0).assertTrue();
      expect(text.indexOf('fingerPrint=aaaa…(36)') >= 0).assertTrue();
    });
  });
}
