/*
 * 注入脚本单测（ticket 07，验收第 2/5 条的可测部分）。
 *
 * 断言的判据来自 idp-login-flow.md 第 3 节与 ticket Comments 的注入面收敛结论：
 *   1. 预填账号/口令（readonly）；
 *   2. 把**我们生成的**指纹写进 #fingerPrint，并拦截 saveFinger 的 XHR 替换 fingerprint/deviceName/radioVal；
 *   3. 让页面自己吐 fingerGenPrint；
 *   4. **不含** jQuery.fn.submit 猴补丁（旧实现为回传 FormData 才做的，本工程不需要）。
 *
 * 另外覆盖"敌意输入"：账号/口令里出现引号、反斜杠、换行、</script> 时脚本必须仍然是合法 JS
 * （用 JSON 转义嵌入），且不得把口令拼进任何单引号字面量。
 */

import { describe, it, expect } from '@ohos/hypium';
import {
  EnrollmentDomValues, SAVE_FINGER_PATH, buildEnrollmentScript, credentialRecordFor,
  describeEnrollmentDomValues, emptyDomValues, jsStringLiteral, mergeDomValues, parseEnrollmentValues
} from '../main/ets/domain/auth/EnrollmentScript';
import {
  SYNTHETIC_FINGERPRINT, SYNTHETIC_PASSWORD, SYNTHETIC_USERNAME
} from './fixtures/EnrollmentFixtures';

const DEVICE_NAME: string = 'HarmonyOS,learnOH/1.1.0 (PURA 90)';

function build(username: string = SYNTHETIC_USERNAME, password: string = SYNTHETIC_PASSWORD): string {
  return buildEnrollmentScript({
    username: username,
    password: password,
    fingerPrint: SYNTHETIC_FINGERPRINT,
    deviceName: DEVICE_NAME,
    bridgeName: 'learnOHEnrollmentBridge'
  });
}

export default function enrollmentScriptTest() {
  describe('domain.EnrollmentScript', () => {
    it('prefillsBothFieldsAndMakesThemReadOnly', 0, () => {
      const script: string = build();
      expect(script.indexOf("field('i_user')") >= 0).assertTrue();
      expect(script.indexOf("field('i_pass')") >= 0).assertTrue();
      expect(script.indexOf('u.value = USERNAME') >= 0).assertTrue();
      expect(script.indexOf('p.value = PASSWORD') >= 0).assertTrue();
      expect(script.indexOf('u.readOnly = true') >= 0).assertTrue();
      expect(script.indexOf('p.readOnly = true') >= 0).assertTrue();
    });

    it('writesOurFingerprintIntoTheFormField', 0, () => {
      const script: string = build();
      // 页面在解析末尾会写自己的 fingerprintjs2 指纹，所以必须是我们盖回去（见文件头注释）
      expect(script.indexOf("field('fingerPrint')") >= 0).assertTrue();
      expect(script.indexOf('if (el.value !== FP) { el.value = FP; }') >= 0).assertTrue();
      expect(script.indexOf(SYNTHETIC_FINGERPRINT) >= 0).assertTrue();
    });

    it('patchesSaveFingerWithOurFingerprintAndDeviceName', 0, () => {
      const script: string = build();
      expect(script.indexOf(SAVE_FINGER_PATH) >= 0).assertTrue();
      expect(script.indexOf("params.set('fingerprint', FP)") >= 0).assertTrue();
      expect(script.indexOf("params.set('deviceName', DEVICE_NAME)") >= 0).assertTrue();
      expect(script.indexOf("params.set('radioVal', '是')") >= 0).assertTrue();
      expect(script.indexOf('XMLHttpRequest') >= 0).assertTrue();
      expect(script.indexOf(DEVICE_NAME) >= 0).assertTrue();
    });

    it('asksThePageItselfForTheSiteFingerprints', 0, () => {
      const script: string = build();
      expect(script.indexOf('window.localstorageUtil') >= 0).assertTrue();
      expect(script.indexOf('getFinger3FromLocal') >= 0).assertTrue();
      expect(script.indexOf("field('fingerGenPrint')") >= 0).assertTrue();
      // fingerGenPrint3 由页面自己的 finger3.js 在加载时写好，我们只读，不生成
      expect(script.indexOf("valueOf('fingerGenPrint3')") >= 0).assertTrue();
    });

    it('forcesTheTrustBrowserCheckboxBecauseThePageLeavesItOff', 0, () => {
      const script: string = build();
      // 设备实测（模拟器 Pura 90）：全新 profile 上页面**不勾选**"信任该浏览器"
      // （finger3.js 只在 localStorage 已有 "singleLoginKey"="yes" 时才勾选）。
      // 不勾选 = 服务端不登记 180 天信任 ⇒ ticket 08 的纯 HTTP 重登必然退化。参考实现
      // sso.js:69-74 在提交时 click() 打开它；这里做等价的事（幂等）。
      expect(script.indexOf('function ensureSingleLogin()') >= 0).assertTrue();
      // 复选框只有 name、没有 id（抓下来的登录页 HTML 实证），所以必须按 name 查
      expect(script.indexOf('function fieldByName(name)') >= 0).assertTrue();
      expect(script.indexOf('var box = singleLoginBox();') >= 0).assertTrue();
      expect(script.indexOf('box.checked = true') >= 0).assertTrue();
      expect(script.indexOf('ensureSingleLogin();') >= 0).assertTrue();
    });

    it('reportsTheFingerprintTheSaveFingerRequestActuallyCarried', 0, () => {
      const script: string = build();
      // 等式证据的第二点：不是"我们要发的值"，而是**实际拼进 body 的值**
      expect(script.indexOf("saveFingerSent = params.get('fingerprint')") >= 0).assertTrue();
      expect(script.indexOf("+ '&saveFingerFingerprint=' + encodeURIComponent(saveFingerSent)") >= 0)
        .assertTrue();
      const values: EnrollmentDomValues = parseEnrollmentValues(
        'saveFingerFingerprint=' + encodeURIComponent('sent-value'));
      expect(values.saveFingerFingerprint).assertEqual('sent-value');
      // 粘性：漫游之后页面没有这个字段，不能把已发出的事实擦掉
      const merged: EnrollmentDomValues = mergeDomValues(values, parseEnrollmentValues('saveFingerFingerprint='));
      expect(merged.saveFingerFingerprint).assertEqual('sent-value');
    });

    it('doesNotMonkeyPatchJQuerySubmit', 0, () => {
      const script: string = build();
      // 我们**用**jQuery（提交前断言一次），但**不替换**它的 submit，也不回传表单数据：
      // 猴补丁与 FormData 回传都是旧实现为了把值送回 RN 才需要的（idp-login-flow.md 第 3 节）。
      expect(script.indexOf('window.jQuery') >= 0).assertTrue();
      expect(script.indexOf('.fn.submit') ).assertEqual(-1);
      expect(script.indexOf('prototype.submit') ).assertEqual(-1);
      expect(script.indexOf('FormData')).assertEqual(-1);
      expect(script.indexOf('postMessage')).assertEqual(-1);
      expect(script.indexOf('ReactNativeWebView')).assertEqual(-1);
    });

    it('reassertsUntilTheDocumentGoesAwayAndHooksSubmitViaPublicApi', 0, () => {
      const script: string = build();
      // (a) 持续 re-assert：不设上限，定时器随文档销毁自然结束
      expect(script.indexOf('var MAX_TICKS') ).assertEqual(-1);
      expect(script.indexOf('setTimeout(tick, TICK_MILLIS);') >= 0).assertTrue();
      expect(script.indexOf('attachSubmitHook();') >= 0).assertTrue();
      // (b) 提交前的最后一次断言：jQuery 公开 API 挂 handler，先于默认动作（原生 submit）执行
      expect(script.indexOf("jq(form).on('submit', function () {") >= 0).assertTrue();
      expect(script.indexOf("report('submitHook', 'attached=1')") >= 0).assertTrue();
      // 导航前的末次观测（"提交那一刻"的状态）
      expect(script.indexOf('function reportLastObservation()') >= 0).assertTrue();
      expect(script.indexOf("window.addEventListener('pagehide', reportLastObservation)") >= 0)
        .assertTrue();
    });

    it('escapesHostileCredentialsInsteadOfBreakingOut', 0, () => {
      const hostilePassword: string = "p'; window.__pwned = 1; //";
      const hostileUser: string = "u'\"</script>\n";
      const script: string = build(hostileUser, hostilePassword);
      // 值必须以 JSON 字面量出现（引号被转义），而不是裸拼进单引号
      expect(script.indexOf('var PASSWORD = ' + jsStringLiteral(hostilePassword) + ';') >= 0).assertTrue();
      expect(script.indexOf('var USERNAME = ' + jsStringLiteral(hostileUser) + ';') >= 0).assertTrue();
      expect(script.indexOf("var PASSWORD = '") ).assertEqual(-1);
      expect(script.indexOf('</script>')).assertEqual(-1);
      expect(script.indexOf('<\\/script>') >= 0).assertTrue();
    });

    it('substitutesEveryPlaceholder', 0, () => {
      const script: string = build();
      expect(script.indexOf('__LEARNOH_')).assertEqual(-1);
      expect(script.indexOf('}();') < 0).assertTrue();
      // 脚本是 IIFE：能被当作函数体解析（这里只做结构性断言，真正解析由宿主 node 做过）
      expect(script.startsWith('(function () {')).assertTrue();
      expect(script.trim().endsWith('})();')).assertTrue();
    });

    it('escapesLineAndParagraphSeparators', 0, () => {
      expect(jsStringLiteral('a\u2028b')).assertEqual('"a\\u2028b"');
      expect(jsStringLiteral('a\u2029b')).assertEqual('"a\\u2029b"');
      expect(jsStringLiteral('</script')).assertEqual('"<\\/script"');
    });

    it('parsesTheBridgeValuesPayload', 0, () => {
      const payload: string = 'fingerPrint=' + encodeURIComponent(SYNTHETIC_FINGERPRINT)
        + '&fingerGenPrint=' + encodeURIComponent('gen 1')
        + '&fingerGenPrint3=' + encodeURIComponent('gen3')
        + '&pageDeviceName=' + encodeURIComponent('windows,Chrome/120')
        + '&singleLogin=1&userPrefilled=1&passPrefilled=0&saveFingerPatched=1&unknown=x';
      const values: EnrollmentDomValues = parseEnrollmentValues(payload);
      expect(values.fingerPrint).assertEqual(SYNTHETIC_FINGERPRINT);
      expect(values.fingerGenPrint).assertEqual('gen 1');
      expect(values.fingerGenPrint3).assertEqual('gen3');
      expect(values.pageDeviceName).assertEqual('windows,Chrome/120');
      expect(values.singleLoginChecked).assertTrue();
      expect(values.userPrefilled).assertTrue();
      expect(values.passPrefilled).assertFalse();
      expect(values.saveFingerPatched).assertTrue();
      // 空 payload / 坏转义都不能抛
      expect(parseEnrollmentValues('').fingerPrint).assertEqual('');
      expect(parseEnrollmentValues('fingerPrint=%E0%A4%A').fingerPrint.length > 0).assertTrue();
    });

    it('keepsNonEmptyDomValuesAcrossNavigations', 0, () => {
      let merged: EnrollmentDomValues = emptyDomValues();
      merged = mergeDomValues(merged, parseEnrollmentValues('fingerPrint=FP1&fingerGenPrint=G1&singleLogin=1'));
      // 漫游之后到了 learn 域：页面上没有这些字段，回传全空 —— 不能把上一页的事实擦掉
      merged = mergeDomValues(merged, parseEnrollmentValues('fingerPrint=&fingerGenPrint=&singleLogin=0'));
      expect(merged.fingerPrint).assertEqual('FP1');
      expect(merged.fingerGenPrint).assertEqual('G1');
      expect(merged.singleLoginChecked).assertTrue();
      // 新值可以覆盖旧值
      merged = mergeDomValues(merged, parseEnrollmentValues('fingerPrint=FP2'));
      expect(merged.fingerPrint).assertEqual('FP2');
    });

    it('buildsTheCredentialRecordFromTheInjectedFingerprint', 0, () => {
      const dom: EnrollmentDomValues = parseEnrollmentValues(
        'fingerPrint=' + encodeURIComponent(SYNTHETIC_FINGERPRINT)
          + '&fingerGenPrint=SITE1&fingerGenPrint3=SITE3');
      const record = credentialRecordFor(SYNTHETIC_USERNAME, SYNTHETIC_PASSWORD, SYNTHETIC_FINGERPRINT, dom);
      // 验收第 2 条：保存的指纹就是**我们注入的那一个**
      expect(record.fingerPrint).assertEqual(SYNTHETIC_FINGERPRINT);
      expect(record.fingerGenPrint).assertEqual('SITE1');
      expect(record.fingerGenPrint3).assertEqual('SITE3');
    });

    it('describesDomValuesWithoutAnyFingerprintValue', 0, () => {
      const dom: EnrollmentDomValues = parseEnrollmentValues(
        'fingerPrint=' + encodeURIComponent(SYNTHETIC_FINGERPRINT)
          + '&fingerGenPrint=SITE1&pageDeviceName=' + encodeURIComponent('windows,Chrome/120')
          + '&saveFingerFingerprint=' + encodeURIComponent('sent-value'));
      const text: string = describeEnrollmentDomValues(dom);
      expect(text.indexOf('sent-value')).assertEqual(-1);
      expect(text.indexOf('saveFingerFingerprintChars=10') >= 0).assertTrue();
      expect(text.indexOf(SYNTHETIC_FINGERPRINT)).assertEqual(-1);
      expect(text.indexOf('SITE1')).assertEqual(-1);
      expect(text.indexOf('fingerPrintChars=36') >= 0).assertTrue();
      expect(text.indexOf('pageDeviceName=windows,Chrome/120') >= 0).assertTrue();
      expect(text.indexOf('saveFingerPatched=false') >= 0).assertTrue();
    });
  });
}
