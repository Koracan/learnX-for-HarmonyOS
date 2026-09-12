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
  ENROLLMENT_DIAGNOSTICS_FOR_EVIDENCE, EnrollmentDomValues, SAVE_FINGER_PATH, buildEnrollmentScript,
  credentialRecordFor, describeEnrollmentDomValues, emptyDomValues, jsStringLiteral, mergeDomValues,
  parseEnrollmentValues, resolveEnrollmentFingerPrint
} from '../main/ets/domain/auth/EnrollmentScript';
import {
  SYNTHETIC_FINGERPRINT, SYNTHETIC_PASSWORD, SYNTHETIC_USERNAME
} from './fixtures/EnrollmentFixtures';

const DEVICE_NAME: string = 'HarmonyOS,learnOH/1.1.0 (PURA 90)';

/** 提交前自检横幅的文案（真实文案由 features 层从 i18n 传入，这里只要可辨识）。 */
const GATE_NOTICE: string = 'fingerprint-not-ready';

function build(username: string = SYNTHETIC_USERNAME, password: string = SYNTHETIC_PASSWORD): string {
  return buildEnrollmentScript({
    username: username,
    password: password,
    fingerPrint: SYNTHETIC_FINGERPRINT,
    deviceName: DEVICE_NAME,
    bridgeName: 'learnOHEnrollmentBridge',
    gateNoticeText: GATE_NOTICE
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
      // **方案 A**：生效值 = 页面值；我们的 UUID 只作兜底，仍然出现在脚本里（var FP = …）
      expect(script.indexOf('var want = effectiveFingerPrint();') >= 0).assertTrue();
      expect(script.indexOf(SYNTHETIC_FINGERPRINT) >= 0).assertTrue();
    });

    it('patchesSaveFingerWithTheEffectiveFingerprintAndDeviceName', 0, () => {
      const script: string = build();
      expect(script.indexOf(SAVE_FINGER_PATH) >= 0).assertTrue();
      // 注入的是**生效值**（方案 A：页面值优先，缺失才兜底），而不是无条件的我们自己的 UUID
      expect(script.indexOf("params.set('fingerprint', effectiveFingerPrint())") >= 0).assertTrue();
      expect(script.indexOf("params.set('fingerprint', FP)") ).assertEqual(-1);
      expect(script.indexOf("params.set('deviceName', DEVICE_NAME)") >= 0).assertTrue();
      expect(script.indexOf("params.set('radioVal', '是')") >= 0).assertTrue();
      expect(script.indexOf('XMLHttpRequest') >= 0).assertTrue();
      expect(script.indexOf(DEVICE_NAME) >= 0).assertTrue();
    });

    it('neverOverwritesTheFingerprintThePageAlreadyPutInTheSaveFingerBody', 0, () => {
      const script: string = build();
      // **D1（2026-09-12 设备实测）**：页面自己在二次验证页的 saveFinger body 里已经放了正确的指纹
      // （doubleAuth.bundle.js 的组件构造函数里就调了 getFingers()）。我们的 XHR patch 曾经**无条件**
      // 用 effectiveFingerPrint() 覆盖它，而那一页**没有 #fingerPrint 字段**（那是登录页的），
      // 于是每次都回落成 36 字符的兜底 UUID，把页面 32 字符的值改掉 —— 表单 32 / saveFinger 36。
      expect(script.indexOf("var pageValue = params.get('fingerprint');") >= 0).assertTrue();
      expect(script.indexOf('var pageProvidedFingerprint = (pageValue !== null') >= 0).assertTrue();
      expect(script.indexOf('if (!pageProvidedFingerprint) {') >= 0).assertTrue();
      // 覆盖只发生在"页面没给值"的分支里（顺序也是判据：set 必须在 if 之后）
      expect(script.indexOf("params.set('fingerprint', effectiveFingerPrint());") >= 0).assertTrue();
      expect(script.indexOf('if (!pageProvidedFingerprint) {')
        < script.indexOf("params.set('fingerprint', effectiveFingerPrint());")).assertTrue();
      // 实际发出的值要能自证来源（pageBody / pageDom / fallback）
      expect(script.indexOf('pageProvidedFingerprint=') >= 0).assertTrue();
      expect(script.indexOf("'pageBody'") >= 0).assertTrue();
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

    it('allowsTheFirstEnrollmentWhenTheSiteFingerprintsAreEmpty', 0, () => {
      const script: string = build();
      // 放行分支：远端也拿不到（未登录会话恒 result=error）⇒ 判定为"首登的固有状态"，放行并打 reason。
      expect(script.indexOf("var reason = (fgChars > 0 && fg3Chars > 0) ? 'finger3Ready'") >= 0)
        .assertTrue();
      expect(script.indexOf(": (finger3RemoteOk === 0 ? 'firstEnrollmentEmptyFinger3'") >= 0).assertTrue();
      expect(script.indexOf("report('submitGate', 'allowed=1 reason=' + reason") >= 0).assertTrue();
    });

    it('blocksOnlyWhenTheRemoteValueWasObtainedButTheDomMissedIt', 0, () => {
      const script: string = build();
      // 判定**收窄过一次**（设备取证后）：对全新浏览器，fingerGenPrint/fingerGenPrint3 为空是
      // 站点固有行为（getFinger3 在未登录会话上恒为 result=error），按"为空就拦"会把每一次首登
      // 都拦死 = 变相禁用登记。只有"远端拿到了值、而 DOM 没接住"才是我们本可避免的失败。
      expect(script.indexOf('var domMissedRemote = (finger3RemoteOk === 1)') >= 0).assertTrue();
      expect(script.indexOf('if (domMissedRemote) {') >= 0).assertTrue();
      expect(script.indexOf('event.preventDefault()') >= 0).assertTrue();
      expect(script.indexOf(GATE_NOTICE) >= 0).assertTrue();
      // 拦不拦都要有 reason，否则将来分不清"判定为常态"与"门槛失效"
      expect(script.indexOf("report('preSubmitGate', 'blocked=1 reason=domMissedRemoteValue") >= 0)
        .assertTrue();
      expect(script.indexOf("report('submitGate', 'allowed=1 reason=' + reason") >= 0).assertTrue();
      expect(script.indexOf("'firstEnrollmentEmptyFinger3'") >= 0).assertTrue();
      expect(script.indexOf("'finger3Ready'") >= 0).assertTrue();
      expect(script.indexOf('gateBlocked = true;') >= 0).assertTrue();
    });

    it('takesThePageFingerprintAsTheAuthoritativeValue', 0, () => {
      const script: string = build();
      // 方案 A：页面自己算的 fingerprintjs2 值是权威值（只在页面没值时用我们的 UUID 兜底），
      // 这样登录报文与 stock 浏览器逐字段一致；三处（表单 / saveFinger / 落盘）仍同值。
      expect(script.indexOf('function effectiveFingerPrint()') >= 0).assertTrue();
      expect(script.indexOf("var pageValue = valueOf('fingerPrint');") >= 0).assertTrue();
      expect(script.indexOf('return pageValue.length > 0 ? pageValue : FP;') >= 0).assertTrue();
      expect(script.indexOf('var want = effectiveFingerPrint();') >= 0).assertTrue();
      expect(script.indexOf("params.set('fingerprint', effectiveFingerPrint())") >= 0).assertTrue();
      // 不能再出现"无条件写我们的 UUID"
      expect(script.indexOf('if (el.value !== FP) { el.value = FP; }') ).assertEqual(-1);
    });

    it('fetchesTheSiteFingerprintsItselfAndReassertsThemBeforeSubmit', 0, () => {
      const script: string = build();
      // 站点自己的 getFinger3() 在"远端成功但 localforage 写失败"时会 reject，DOM 永远不更新；
      // 我们直接调同一个 API，拿到值就写 DOM。
      expect(script.indexOf('lsu.getFinger3FromRemoteAndSave().then(function (v)') >= 0).assertTrue();
      expect(script.indexOf('function applyFinger3(value)') >= 0).assertTrue();
      expect(script.indexOf('if (finger3Value.length > 0) { applyFinger3(finger3Value); }') >= 0)
        .assertTrue();
      const values: EnrollmentDomValues =
        parseEnrollmentValues('fpSource=page&f3Remote=0&gateBlocked=0');
      expect(values.fingerPrintSource).assertEqual('page');
      expect(values.finger3RemoteOk).assertEqual(0);
      // 漫游后字段消失时不覆盖已有结论
      const merged: EnrollmentDomValues = mergeDomValues(values, parseEnrollmentValues('fpSource=none&f3Remote=-1'));
      expect(merged.fingerPrintSource).assertEqual('page');
      expect(merged.finger3RemoteOk).assertEqual(0);
      expect(describeEnrollmentDomValues(values).indexOf('fpSource=page f3Remote=0') >= 0).assertTrue();
    });

    it('keepsTheGateStateInTheValuesBridge', 0, () => {
      const blocked: EnrollmentDomValues = parseEnrollmentValues('gateBlocked=1&fingerGenPrint=');
      expect(blocked.gateBlocked).assertTrue();
      const open: EnrollmentDomValues = parseEnrollmentValues('gateBlocked=0&fingerGenPrint3=abc');
      expect(open.gateBlocked).assertFalse();
      // 自检状态取末次观测（它回答"此刻这一屏是否被拦下"），不做粘性
      const merged: EnrollmentDomValues = mergeDomValues(blocked, open);
      expect(merged.gateBlocked).assertFalse();
      expect(merged.fingerGenPrint3).assertEqual('abc');
      expect(describeEnrollmentDomValues(blocked).indexOf('gateBlocked=true') >= 0).assertTrue();
    });

    it('shipsWithTheDiagnosticsSwitchOff', 0, () => {
      // 开关本身 + 它在脚本里的实际生效值（AGENTS.md：开关必须自证生效）
      expect(ENROLLMENT_DIAGNOSTICS_FOR_EVIDENCE).assertFalse();
      const script: string = build();
      expect(script.indexOf('var DIAG = false;') >= 0).assertTrue();
      // 诊断块本身在（切到 true 就有用），但关闭时不产生任何报告
      expect(script.indexOf('function diagEnvironment()') >= 0).assertTrue();
      expect(script.indexOf('function diagIndexedDb()') >= 0).assertTrue();
      expect(script.indexOf('function diagLocalforage()') >= 0).assertTrue();
      expect(script.indexOf('if (!DIAG) { return; }') >= 0).assertTrue();
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
      expect(script.indexOf("jq(form).on('submit', function (event) {") >= 0).assertTrue();
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

    it('prefersThePageFingerprintOverOurFallbackInTheCredentialRecord', 0, () => {
      // 方案 A：页面值权威。DOM 里的 fingerPrint 与"我们生成的兜底值"不同时，取页面值。
      const dom: EnrollmentDomValues = parseEnrollmentValues(
        'fingerPrint=' + encodeURIComponent('0123456789abcdef0123456789abcdef'));
      const record = credentialRecordFor(SYNTHETIC_USERNAME, SYNTHETIC_PASSWORD, SYNTHETIC_FINGERPRINT, dom);
      expect(record.fingerPrint).assertEqual('0123456789abcdef0123456789abcdef');
      // 页面没给出值时（理论上的空 DOM）才回落到调用方给的兜底值
      const empty: EnrollmentDomValues = emptyDomValues();
      const fallback = credentialRecordFor(SYNTHETIC_USERNAME, SYNTHETIC_PASSWORD, SYNTHETIC_FINGERPRINT, empty);
      expect(fallback.fingerPrint).assertEqual(SYNTHETIC_FINGERPRINT);
    });

    it('prefersTheSaveFingerValueOverTheDomValueAndTheFallback', 0, () => {
      // **D1**：信任按指纹登记 ⇒ saveFinger 的 XHR 实际发出的值最权威，落盘值必须等于它
      // （否则 ticket 08 的纯 HTTP 重登出示的是另一个值，信任不可能命中）。
      const sent: EnrollmentDomValues = parseEnrollmentValues(
        'fingerPrint=' + encodeURIComponent('form-value')
          + '&saveFingerFingerprint=' + encodeURIComponent('sent-value'));
      const resolved = resolveEnrollmentFingerPrint(SYNTHETIC_FINGERPRINT, sent);
      expect(resolved.value).assertEqual('sent-value');
      expect(resolved.source).assertEqual('saveFingerXhr');
      expect(credentialRecordFor(SYNTHETIC_USERNAME, SYNTHETIC_PASSWORD, SYNTHETIC_FINGERPRINT, sent)
        .fingerPrint).assertEqual('sent-value');
      // 没有 saveFinger 观测时用登录页 DOM 值（方案 A）；两者都没有才回落我们生成的 UUID
      const domOnly: EnrollmentDomValues = parseEnrollmentValues('fingerPrint=form-value');
      expect(resolveEnrollmentFingerPrint(SYNTHETIC_FINGERPRINT, domOnly).source).assertEqual('formFieldDom');
      const empty: EnrollmentDomValues = emptyDomValues();
      expect(resolveEnrollmentFingerPrint(SYNTHETIC_FINGERPRINT, empty).source).assertEqual('generatedFallback');
      expect(resolveEnrollmentFingerPrint(SYNTHETIC_FINGERPRINT, empty).value)
        .assertEqual(SYNTHETIC_FINGERPRINT);
      // 连兜底都没有 ⇒ none（调用方据此显式失败，不猜）
      expect(resolveEnrollmentFingerPrint('', empty).source).assertEqual('none');
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
