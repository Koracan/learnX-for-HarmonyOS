/*
 * 登记页注入脚本（domain，纯逻辑）：把一段 JS **源码**拼出来，以及解析它经桥回传的值。
 *
 * 注入面（既有结论）——只有三件事：
 *   1. **预填**账号/口令并置 readonly（照参考实现 src/helpers/preval/sso.js:38-53）；
 *   2. 把**生效指纹**（方案 A：页面值优先）写进 #fingerPrint，并拦截 saveFinger 的 XHR，把
 *      deviceName / radioVal=是 换成我们的值（sso.js:12-36 的等价物）；**`fingerprint` 只在页面
 *      没给值时才写**——二次验证页自己已经在 body 里放了正确的指纹（D1 修复，见 patchSaveFinger）；
 *   3. 让页面自己把 localStorage 里的 fingerGenPrint 吐回 DOM（localstorageUtil.getFinger3FromLocal）。
 *
 * **明确不做**（idp-login-flow.md 里逐条列出的那一节）：旧实现对 jQuery.fn.submit 的猴补丁——它只是为了把
 * FormData 经 postMessage 回传 RN；我们的 HTTP 侧凭据由本工程自己持有，不需要那条通道。
 * 单测里有一条断言"产物里不含 jQuery.fn.submit"，防止有人日后把它加回来。
 *
 * 为什么写 #fingerPrint 而不是只读它：服务端把"信任浏览器"绑定在设备指纹上（ADR-0004 /
 * idp-login-flow.md），而**信任的判据必须是同一个值**——登记时 saveFinger 上报的值、
 * 登录表单提交的值、以及将来 HTTP 重登出示的值三者逐字相同。参考实现也是这么做
 * 的（sso.js 同时覆盖表单字段与 XHR）。页面自己的 fingerPrint 是 fingerprintjs2 的
 * canvas/webgl 指纹，纯 ArkTS 侧无法复算，"读 DOM 当凭据再回放"反而更弱。
 *
 * 设备实测的修正（都已如实登记）：
 *   - "信任该浏览器"复选框**只有 name（singleLogin）、没有 id**，且全新 profile 上页面并不勾选它
 *     （finger3.js 只在 localStorage 已有 "singleLoginKey"="yes" 时才勾选）——必须由我们按 name
 *     找到并勾上（参考实现 sso.js:69-74 的等价物），否则服务端不会登记 180 天信任；
 *   - 轮询**不设上限**（定时器随文档销毁自然结束）：页面的 promise 晚到会把它清掉，而"提交那一刻
 *     是勾上的"是 180 天信任的前提；另加一个 jQuery **公开 API** 的 submit 钩子（不是猴补丁），
 *     在提交前再断言一次。
 *
 *   - 另外两条是 2026-09-12 真实登记失败后加的：
 *     ① **提交前自检（gate）**：fingerGenPrint / fingerGenPrint3 为空时**拦住提交**并给出提示。
 *        理由是实测教训——这两个值为空时服务端必然拒绝信任（用户已因此白花一条短信），
 *        而"注定失败的提交"不该让用户先过短信；参考实现没有这个保护（
 *        这是**新增的防线**而非行为偏离）。
 *     ② **只读诊断（ENROLLMENT_DIAGNOSTICS_FOR_EVIDENCE）**：origin / 每个 XHR 的请求与响应摘要 /
 *        IndexedDB 往返回 / localforage 读写探测 / 页面 console。它不改变行为，只补上"失败时
 *        什么都没有留下"的观测缺口。
 *
 * 回传协议（两条通道，值/日志分离）：
 *   - report(kind, payload)：**只进日志**，payload 已脱敏（长度、布尔、host+path）；
 *   - values(payload)：k=v&k=v（值经 encodeURIComponent），给原生侧**保存**用，永不进日志。
 */

import { CredentialRecord, createCredentialRecord } from './CredentialRecord';

/** saveFinger 的服务端路径（sso.js:20 逐字相同）；用 indexOf 匹配，兼容相对与绝对 URL。 */
export const SAVE_FINGER_PATH: string = '/b/doubleAuth/personal/saveFinger';

/**
 * 轮询间隔：页面在解析末尾会写自己的 fingerprintjs2 指纹，"信任该浏览器"复选框也可能被页面的
 * promise 晚到后**清掉**（实测 ~1.5s 后清过一次）。所以这里**不设上限**——定时器随文档销毁
 * （导航到下一页）自然结束，把"提交那一刻仍是我们的值"的竞态窗口压到最小。
 */
export const TICK_MILLIS: number = 250;

/**
 * 取证开关：注入**只读诊断**（origin / XHR 请求与响应摘要 / IndexedDB 往返回 / localforage 探测 /
 * 页面 console）。**提交态 false**；它的实际生效值由原生侧打进 hilog（AGENTS.md「开关必须自证生效」）。
 *
 * 为什么需要：真实登记被服务端判为"隐私/匿名模式"而拒绝信任时，页面自己的
 * `console.log('getFinger3 error')` 与那次 `POST /b/doubleAuth/personal/getFinger3` 的响应
 * 没有留在任何日志里。这层观测**不改变行为**，只把"为什么拿不到指纹"变成可读的事实。
 */
export const ENROLLMENT_DIAGNOSTICS_FOR_EVIDENCE: boolean = false;

/** 注入脚本的输入。 */
export interface EnrollmentScriptSpec {
  username: string;
  password: string;
  fingerPrint: string;
  deviceName: string;
  bridgeName: string;
  /** 提交前自检不通过时显示给用户的文案（调用方从 i18n 取，不把文案写死在脚本里）。 */
  gateNoticeText: string;
}

/** 桥回传的 DOM 事实（原生侧据此保存凭据并打脱敏日志）。 */
export interface EnrollmentDomValues {
  fingerPrint: string;
  fingerGenPrint: string;
  fingerGenPrint3: string;
  pageDeviceName: string;
  /** saveFinger 的 XHR **实际发出**的 fingerprint 参数（用于"三点一致"的等式证据）。 */
  saveFingerFingerprint: string;
  /** 提交前自检是否拦下过提交（远端拿到了值而 DOM 没接住）。取**末次观测**，不做粘性。 */
  gateBlocked: boolean;
  /** 生效指纹的来源：page（页面 fingerprintjs2 值，方案 A 的权威值）/ fallback（我们的 UUID）/ none。 */
  fingerPrintSource: string;
  /** 站点指纹的远端结果：1 成功 / 0 失败 / -1 还没试。 */
  finger3RemoteOk: number;
  singleLoginChecked: boolean;
  userPrefilled: boolean;
  passPrefilled: boolean;
  saveFingerPatched: boolean;
}

/** 空值，便于"还没收到桥回传"时安全读取。 */
export function emptyDomValues(): EnrollmentDomValues {
  return {
    fingerPrint: '', fingerGenPrint: '', fingerGenPrint3: '', pageDeviceName: '', saveFingerFingerprint: '',
    gateBlocked: false, fingerPrintSource: 'none', finger3RemoteOk: -1,
    singleLoginChecked: false, userPrefilled: false, passPrefilled: false, saveFingerPatched: false
  };
}

/** 把 TS 字符串安全地嵌进 JS 源码：JSON 转义 + 断掉 </script 与 U+2028/2029。 */
export function jsStringLiteral(value: string): string {
  const quoted: string = JSON.stringify(value);
  return quoted
    .split('</').join('<\\/')
    .split('\u2028').join('\\u2028')
    .split('\u2029').join('\\u2029');
}

/**
 * 注入脚本本体（模板）。
 *
 * 用 TS 模板字面量承载：脚本里**不含** ` 与 ${，因此不需要再套一层转义；
 * 占位符是 __LEARNOH_*__ 形式，由 buildEnrollmentScript 换成 JSON 转义后的字面量。
 */
const SCRIPT_TEMPLATE: string = `(function () {
  'use strict';
  var FP = __LEARNOH_FINGERPRINT__;
  var DEVICE_NAME = __LEARNOH_DEVICE_NAME__;
  var USERNAME = __LEARNOH_USERNAME__;
  var PASSWORD = __LEARNOH_PASSWORD__;
  var BRIDGE_NAME = __LEARNOH_BRIDGE__;
  var SAVE_FINGER_PATH = __LEARNOH_SAVE_FINGER_PATH__;
  var TICK_MILLIS = __LEARNOH_TICK_MILLIS__;
  var submitHookAttached = false;
  var DIAG = __LEARNOH_DIAGNOSTICS__;
  var GATE_NOTICE = __LEARNOH_GATE_NOTICE__;
  var gateBlocked = false;
  var finger3Value = '';
  var finger3RemoteOk = -1;
  var requestLogCount = 0;
  var consoleLogCount = 0;
  var lastSummary = '';
  var lastValues = '';
  var ticks = 0;
  var saveFingerSent = '';

  function bridge() { try { return window[BRIDGE_NAME]; } catch (e) { return null; } }

  function report(kind, payload) {
    try {
      var b = bridge();
      if (b && typeof b.report === 'function') { b.report(String(kind), String(payload)); }
    } catch (e) { }
  }

  function publishValues(payload) {
    try {
      var b = bridge();
      if (b && typeof b.values === 'function') { b.values(String(payload)); }
    } catch (e) { }
  }

  function field(id) { try { var el = document.getElementById(id); return el || null; } catch (e) { return null; } }

  // 注意：页面上的"信任该浏览器"复选框**只有 name、没有 id**
  // （<input type="checkbox" name="singleLogin">，见抓下来的登录页 HTML），
  // 所以必须按 name 查。第一版用 getElementById('singleLogin') 永远拿到 null，
  // 于是"勾选状态"与"强制勾选"都静默失效——这是设备实测抓出来的。
  function fieldByName(name) {
    try { return document.querySelector('input[name="' + name + '"]'); } catch (e) { return null; }
  }

  function singleLoginBox() { return fieldByName('singleLogin'); }

  function valueOf(id) { var el = field(id); return (el && typeof el.value === 'string') ? el.value : ''; }

  // 只取 scheme 之后的 host + path：查询串里可能有票据，不能进日志。
  function pathOf(url) {
    try {
      var text = String(url);
      var scheme = text.indexOf('://');
      if (scheme >= 0) { text = text.substring(scheme + 3); }
      var cut = text.indexOf('?');
      var noQuery = cut >= 0 ? text.substring(0, cut) : text;
      var hash = noQuery.indexOf('#');
      return hash >= 0 ? noQuery.substring(0, hash) : noQuery;
    } catch (e) { return 'unparsable'; }
  }

  // 站点只在 localStorage 里已存 "yes" 时才勾选"信任该浏览器"（finger3.js 的
  // getSingleLoginKey().then(...)）；**全新 profile 上它是未勾选的**（模拟器实测，见 ticket 07
  // Comments 的"设备实测修正"）。不勾选 = 服务端不登记 180 天信任 ⇒ ticket 08 的纯 HTTP 重登
  // 必然退化成短信验证。参考实现 sso.js:69-74 在提交时 click() 把它打开，这里做同样的事（幂等）。
  function ensureSingleLogin() {
    try {
      var box = singleLoginBox();
      if (!box) { return false; }
      if (box.checked) { return false; }
      box.checked = true;
      try {
        var event = document.createEvent('HTMLEvents');
        event.initEvent('change', true, false);
        box.dispatchEvent(event);
      } catch (e) { report('singleLogin', 'changeEventFailed=' + e); }
      report('singleLogin', 'forced=1 pageLeftItUnchecked=1');
      return true;
    } catch (e) { report('singleLogin', 'forceFailed=' + e); return false; }
  }

  // 参考实现是在**提交那一刻**确保该字段被勾上的（sso.js:69-74，紧挨着组装表单数据之前），
  // 那个位置没有竞态。这里用 jQuery 的**公开** API 做同一件事：页面自己用 $("#theform").submit()
  // 触发，jQuery 会先跑我们挂的 handler、再执行默认动作（原生 form.submit()）。
  // **不是**猴补丁：没有替换 jQuery 的 submit，也没有回传表单数据。
  function attachSubmitHook() {
    if (submitHookAttached) { return true; }
    try {
      var jq = window.jQuery;
      var form = field('theform');
      if (!jq || typeof jq !== 'function' || !form) { return false; }
      jq(form).on('submit', function (event) {
        var forced = ensureSingleLogin();
        writeFingerPrint();
        // 页面自己的 doLogin() 会在提交前用 local 值覆盖 #fingerGenPrint（local 为空时 jQuery 的
        // .val(null) 会把它清成空串）。我们把自己取到的值再断言回去；取不到就没有可断言的。
        if (finger3Value.length > 0) { applyFinger3(finger3Value); }
        var fgChars = valueOf('fingerGenPrint').length;
        var fg3Chars = valueOf('fingerGenPrint3').length;
        // 提交前自检（**新增防线**，参考实现没有）。判定收窄过一次：
        //   - "为空就拦"会把**每一次首登都拦死**（对全新浏览器为空是站点固有行为），所以不能那么判；
        //   - 只在"**远端确实拿到了值、而 DOM 没接住**"时拦——那才是我们本可避免的失败。
        // 无论拦不拦都打 reason，否则将来无法区分"判定为常态"和"门槛失效"。
        var domMissedRemote = (finger3RemoteOk === 1) && (fgChars === 0 || fg3Chars === 0);
        if (domMissedRemote) {
          gateBlocked = true;
          try { if (event && typeof event.preventDefault === 'function') { event.preventDefault(); } } catch (e) { }
          showGateNotice();
          report('preSubmitGate', 'blocked=1 reason=domMissedRemoteValue fgChars=' + fgChars
            + ' fg3Chars=' + fg3Chars + ' remoteOk=' + finger3RemoteOk);
          publish();
          return;
        }
        gateBlocked = false;
        hideGateNotice();
        var reason = (fgChars > 0 && fg3Chars > 0) ? 'finger3Ready'
          : (finger3RemoteOk === 0 ? 'firstEnrollmentEmptyFinger3' : 'finger3Unavailable');
        report('submitGate', 'allowed=1 reason=' + reason + ' singleLoginForced=' + (forced ? '1' : '0')
          + ' fgChars=' + fgChars + ' fg3Chars=' + fg3Chars + ' remoteOk=' + finger3RemoteOk);
        publish();
      });
      submitHookAttached = true;
      report('submitHook', 'attached=1');
      return true;
    } catch (e) { report('submitHook', 'attachFailed=' + e); return false; }
  }

  // 导航前的末次观测：提交"那一刻"的复选框与指纹状态（这是"信任请求是否带着正确值发出"的
  // 最后一手证据；勾上只等于"我们请求了信任"，不等于服务端已授予 —— 见 ticket Comments）。
  function reportLastObservation() {
    var box = singleLoginBox();
    var fp = valueOf('fingerPrint');
    report('navigationLastObservation', 'singleLogin=' + (box && box.checked ? '1' : '0')
      + ' fingerPrintMatchInjected=' + (fp === FP ? '1' : '0')
      + ' fingerPrintChars=' + fp.length
      + ' saveFingerFingerprintChars=' + saveFingerSent.length
      + ' url=' + pathOf(window.location ? window.location.href : ''));
    publish();
  }

  function prefill() {
    var u = field('i_user');
    var p = field('i_pass');
    var hits = 0;
    if (u) { u.value = USERNAME; u.readOnly = true; hits++; }
    if (p) { p.value = PASSWORD; p.readOnly = true; hits++; }
    return hits;
  }

  // **方案 A（2026-09-12 设备取证后改定）**：以**页面自己算出的 fingerprintjs2 值**为权威值，
  // 只有页面没有值时才用我们生成的 UUID 兜底。
  //
  // 为什么改：真实登记被服务端判为"隐私/匿名模式"而拒绝信任。把提交报文逐字段与"stock 浏览器"
  // 对比后，**唯一不同的一栏就是我们覆盖掉的 fingerPrint**（fingerGen* 对任何未登录会话都为空，
  // 是站点固有行为；deviceName 我们没动；singleLogin 是站点本意要勾的）。所以让它保持页面原值，
  // 报文就与 stock 浏览器一致。
  //
  // 为什么仍然满足"登记值 == 重登出示值"：生效值被**原样保存**并在重登时回放，
  // 不需要复算 fingerprintjs2（服务端记录的就是它收到的那一个）。
  function effectiveFingerPrint() {
    var pageValue = valueOf('fingerPrint');
    return pageValue.length > 0 ? pageValue : FP;
  }

  function writeFingerPrint() {
    var el = field('fingerPrint');
    if (!el) { return false; }
    var want = effectiveFingerPrint();
    if (el.value !== want) { el.value = want; }
    return true;
  }

  // 把站点指纹同时写进两个字段（页面自己也是同一个来源：local → 远端）。
  function applyFinger3(value) {
    finger3Value = value;
    var a = field('fingerGenPrint');
    if (a) { a.value = value; }
    var b = field('fingerGenPrint3');
    if (b) { b.value = value; }
  }

  // 取站点指纹（fingerGenPrint / fingerGenPrint3）。**不依赖页面那条 promise 链**：
  // 站点自己的 getFinger3() 在远端成功但 localforage 写失败时会 reject，于是 DOM 永远不更新；
  // 我们直接调同一个 API，拿到值就写 DOM（失败则如实记录原因，供提交前自检判定）。
  function collectFinger3() {
    try {
      var lsu = window.localstorageUtil;
      if (!lsu || typeof lsu.getFinger3FromLocal !== 'function') {
        report('finger3', 'localstorageUtil=absent');
        return;
      }
      lsu.getFinger3FromLocal().then(function (r) {
        if (r) {
          applyFinger3(String(r));
          report('finger3', 'source=localstorage chars=' + String(r).length);
          publish();
          return;
        }
        report('finger3', 'source=localstorage chars=0 -> tryRemote');
        if (typeof lsu.getFinger3FromRemoteAndSave !== 'function') {
          finger3RemoteOk = 0;
          report('finger3', 'remoteApi=absent');
          publish();
          return;
        }
        lsu.getFinger3FromRemoteAndSave().then(function (v) {
          if (v) {
            applyFinger3(String(v));
            finger3RemoteOk = 1;
            report('finger3', 'source=remote chars=' + String(v).length);
          } else {
            finger3RemoteOk = 0;
            report('finger3', 'remote resolved empty');
          }
          publish();
        }).catch(function (e) {
          finger3RemoteOk = 0;
          report('finger3', 'remote rejected ' + describeThing(e));
          publish();
        });
      }).catch(function (e) {
        finger3RemoteOk = 0;
        report('finger3', 'local rejected ' + describeThing(e));
        publish();
      });
    } catch (e) { report('finger3', 'throw=' + e); }
  }

  // ------------------------------------------------------------------
  // 只读诊断（DIAG=false 时全部空转）：真实登记失败时，页面自己的报错与那次
  // POST /b/doubleAuth/personal/getFinger3 的响应都没有留在日志里。以下都只记录，不改变行为。
  // ------------------------------------------------------------------
  function describeThing(value) {
    try {
      if (value === null) { return 'null'; }
      if (value === undefined) { return 'undefined'; }
      var type = typeof value;
      if (type !== 'object') { return type + ':' + String(value).substring(0, 60); }
      var keys = '';
      try { keys = Object.keys(value).slice(0, 6).join(','); } catch (e) { keys = ''; }
      var result = (value.result !== undefined && value.result !== null) ? String(value.result) : 'none';
      var message = (value.message !== undefined && value.message !== null)
        ? String(value.message).substring(0, 120) : '';
      return 'object result=' + result + ' keys=[' + keys + '] message=[' + message + ']';
    } catch (e) { return 'undescribable'; }
  }

  // 只记**参数名与长度**，不记值：实验时要能对照参考实现注入的三个参数
  // （fingerprint / deviceName / radioVal=是）是否都在，以及 body 到底是什么形态
  // （URL 编码表单？JSON？非字符串？——这是"我们的 URLSearchParams 改写是否改坏了它"的判据）。
  function describeBody(body) {
    try {
      if (typeof body !== 'string') { return 'bodyType=' + (typeof body); }
      var params = new URLSearchParams(body);
      var wanted = ['fingerprint', 'deviceName', 'radioVal'];
      var parts = [];
      for (var i = 0; i < wanted.length; i++) {
        var v = params.get(wanted[i]);
        parts.push(wanted[i] + '=' + (v === null ? 'absent' : 'len:' + String(v).length));
      }
      var all = [];
      try {
        params.forEach(function (value, key) {
          if (all.length < 12) { all.push(key + '(' + String(value).length + ')'); }
        });
      } catch (e) { }
      return 'bodyChars=' + body.length + ' ' + parts.join(' ') + ' allParams=' + all.join(',');
    } catch (e) { return 'describeFailed=' + e; }
  }

  function recordRequest(method, path) {
    try {
      if (!DIAG || requestLogCount >= 40) { return; }
      requestLogCount++;
      report('xhr', 'req method=' + method + ' path=' + path + ' n=' + requestLogCount);
    } catch (e) { }
  }

  // 记录一次 XHR 的结局；对 /b/doubleAuth/ 下的接口额外摘出 result 与 object 长度（**不含值**）。
  function attachResponseRecorder(xhr, path) {
    try {
      xhr.addEventListener('load', function () {
        var text = '';
        try { text = String(xhr.responseText || ''); } catch (e) { text = ''; }
        var shape = '';
        if (path.indexOf('/b/doubleAuth/') >= 0) {
          var result = 'none';
          var objectChars = 0;
          try {
            var parsed = JSON.parse(text);
            if (parsed && parsed.result !== undefined && parsed.result !== null) { result = String(parsed.result); }
            if (parsed && parsed.object !== undefined && parsed.object !== null) { objectChars = String(parsed.object).length; }
          } catch (e) { result = 'nonJson'; }
          shape = ' result=' + result + ' objectChars=' + objectChars;
        }
        report('xhr', 'res path=' + path + ' status=' + String(xhr.status) + ' chars=' + text.length + shape);
      });
      xhr.addEventListener('error', function () { report('xhr', 'err path=' + path); });
      xhr.addEventListener('timeout', function () { report('xhr', 'timeout path=' + path); });
    } catch (e) { report('xhr', 'recordFail=' + e); }
  }

  function diagEnvironment() {
    if (!DIAG) { return; }
    try {
      var href = window.location ? String(window.location.href) : '';
      var origin = window.location ? String(window.location.origin || '') : '';
      var cookieChars = 0;
      try { cookieChars = String(document.cookie || '').length; } catch (e) { cookieChars = -1; }
      var lsOk = false;
      try {
        window.localStorage.setItem('learnoh_ls_probe', '1');
        lsOk = window.localStorage.getItem('learnoh_ls_probe') === '1';
        window.localStorage.removeItem('learnoh_ls_probe');
      } catch (e) { lsOk = false; }
      var idbType = 'n/a';
      try { idbType = typeof window.indexedDB; } catch (e) { idbType = 'throw'; }
      var ua = '';
      try { ua = String(navigator.userAgent || ''); } catch (e) { ua = ''; }
      report('diag:env', 'origin=[' + origin + '] path=' + pathOf(href)
        + ' cookieChars=' + cookieChars + ' localStorageOk=' + lsOk
        + ' indexedDB=' + idbType + ' uaChars=' + ua.length
        + ' uaChrome=' + (ua.indexOf('Chrome') >= 0 ? '1' : '0')
        + ' diag=' + DIAG);
    } catch (e) { report('diag:env', 'throw=' + e); }
  }

  function diagIndexedDb() {
    if (!DIAG) { return; }
    try {
      if (!window.indexedDB) { report('diag:idb', 'unavailable'); return; }
      var request = window.indexedDB.open('learnoh-probe', 1);
      request.onupgradeneeded = function () { try { request.result.createObjectStore('kv'); } catch (e) { } };
      request.onerror = function () { report('diag:idb', 'openError=' + (request.error ? request.error.name : 'unknown')); };
      request.onblocked = function () { report('diag:idb', 'blocked=1'); };
      request.onsuccess = function () {
        var db = request.result;
        try {
          var tx = db.transaction('kv', 'readwrite');
          tx.objectStore('kv').put('v1', 'k1');
          tx.oncomplete = function () {
            var tx2 = db.transaction('kv', 'readonly');
            var get = tx2.objectStore('kv').get('k1');
            get.onsuccess = function () { report('diag:idb', 'roundTripOk=' + (get.result === 'v1')); };
            get.onerror = function () { report('diag:idb', 'readError=' + (get.error ? get.error.name : 'unknown')); };
          };
          tx.onerror = function () { report('diag:idb', 'writeError=' + (tx.error ? tx.error.name : 'unknown')); };
        } catch (e) { report('diag:idb', 'txThrow=' + e); }
      };
    } catch (e) { report('diag:idb', 'throw=' + e); }
  }

  // localforage 的**写→读→复原**往返（站点把 fingerKey / singleLoginKey / browser_fp 都放在这里）。
  // 只读诊断做不到这一条：IndexedDB 写失败时"读"可能只是返回空，看起来跟"没写过"一样。
  // 复原规则：原本没有值就 removeFinger3()，原本有值就写回原值——不留痕。
  function diagLocalforageRoundTrip() {
    if (!DIAG) { return; }
    try {
      var lsu = window.localstorageUtil;
      if (!lsu || typeof lsu.saveFinger3Local !== 'function' || typeof lsu.getFinger3FromLocal !== 'function') {
        report('diag:lfrt', 'api=absent');
        return;
      }
      var probe = 'learnoh-probe-' + String(Date.now());
      lsu.getFinger3FromLocal().then(function (before) {
        report('diag:lfrt', 'before type=' + (typeof before) + ' chars=' + (before ? String(before).length : 0));
        lsu.saveFinger3Local(probe).then(function () {
          report('diag:lfrt', 'writeOk=1');
          lsu.getFinger3FromLocal().then(function (after) {
            report('diag:lfrt', 'readBackMatch=' + (String(after) === probe ? '1' : '0'));
            try {
              if (before === null || before === undefined || before === '') {
                if (typeof lsu.removeFinger3 === 'function') {
                  lsu.removeFinger3();
                  report('diag:lfrt', 'restored=removed');
                }
              } else {
                lsu.saveFinger3Local(String(before));
                report('diag:lfrt', 'restored=original');
              }
            } catch (e) { report('diag:lfrt', 'restoreFailed=' + e); }
          }).catch(function (e) { report('diag:lfrt', 'readBackRejected ' + describeThing(e)); });
        }).catch(function (e) { report('diag:lfrt', 'writeRejected ' + describeThing(e)); });
      }).catch(function (e) { report('diag:lfrt', 'beforeRejected ' + describeThing(e)); });
    } catch (e) { report('diag:lfrt', 'throw=' + e); }
  }

  function diagLocalforage() {
    if (!DIAG) { return; }
    try {
      var lsu = window.localstorageUtil;
      if (!lsu) { report('diag:lf', 'localstorageUtil=absent'); return; }
      try {
        lsu.getFinger3FromLocal().then(function (v) {
          report('diag:lf', 'getFinger3FromLocal resolved type=' + (typeof v)
            + ' chars=' + (v ? String(v).length : 0) + ' falsy=' + (!v));
        }).catch(function (e) { report('diag:lf', 'getFinger3FromLocal rejected ' + describeThing(e)); });
      } catch (e) { report('diag:lf', 'getFinger3FromLocal throw=' + e); }
      try {
        lsu.getFinger3FromRemoteAndSave().then(function (v) {
          report('diag:lf', 'getFinger3FromRemoteAndSave resolved type=' + (typeof v)
            + ' chars=' + (v ? String(v).length : 0));
        }).catch(function (e) { report('diag:lf', 'getFinger3FromRemoteAndSave rejected ' + describeThing(e)); });
      } catch (e) { report('diag:lf', 'getFinger3FromRemoteAndSave throw=' + e); }
      try {
        var jq = window.jQuery;
        if (jq && typeof jq.post === 'function') {
          jq.post('/b/doubleAuth/personal/getFinger3', {}, function (t) {
            report('diag:getFinger3', 'direct ok ' + describeThing(t));
          }).fail(function (xhr, status) {
            report('diag:getFinger3', 'direct fail status=' + status
              + ' httpStatus=' + (xhr ? String(xhr.status) : '?'));
          });
        } else {
          report('diag:getFinger3', 'jQuery=absent');
        }
      } catch (e) { report('diag:getFinger3', 'throw=' + e); }
    } catch (e) { report('diag:lf', 'throw=' + e); }
  }

  // 页面 console 经桥转进我们自己的 hilog（只在 DIAG 下），用于抓页面自己的
  // console.log('getFinger3 error') 这类线索。上限 40 条、每条截断。
  function installConsoleTap() {
    if (!DIAG) { return; }
    try {
      var original = window.console ? window.console.log : null;
      if (!window.console || typeof original !== 'function') { report('diag:console', 'no-console'); return; }
      window.console.log = function () {
        try {
          if (consoleLogCount < 40) {
            consoleLogCount++;
            var parts = [];
            for (var i = 0; i < arguments.length; i++) { parts.push(describeThing(arguments[i])); }
            report('diag:console', 'log ' + parts.join(' | ').substring(0, 240));
          }
        } catch (e) { }
        return original.apply(window.console, arguments);
      };
      report('diag:console', 'tapped=1');
    } catch (e) { report('diag:console', 'tapFailed=' + e); }
  }

  // 提交前自检的提示横幅（只在拦下提交时出现）。
  function showGateNotice() {
    try {
      var node = document.getElementById('learnohGateNotice');
      if (!node) {
        node = document.createElement('div');
        node.id = 'learnohGateNotice';
        node.setAttribute('style', 'position:fixed;left:0;right:0;bottom:0;z-index:2147483647;'
          + 'background:#8b0000;color:#ffffff;font-size:14px;line-height:1.5;padding:10px 12px;');
        if (document.body) { document.body.appendChild(node); }
      }
      node.textContent = GATE_NOTICE;
    } catch (e) { report('preSubmitGate', 'noticeFailed=' + e); }
  }

  function hideGateNotice() {
    try {
      var node = document.getElementById('learnohGateNotice');
      if (node && node.parentNode) { node.parentNode.removeChild(node); }
    } catch (e) { }
  }

  // saveFinger 的 XHR 拦截：这里是唯一注入"服务端登记值"的地方。
  function patchSaveFinger() {
    try {
      var proto = window.XMLHttpRequest && window.XMLHttpRequest.prototype;
      if (!proto) { report('saveFinger', 'patchInstalled=0 reason=no-xhr'); return false; }
      if (proto.__learnohSaveFingerPatched) { return true; }
      var originalOpen = proto.open;
      var originalSend = proto.send;
      proto.open = function (method, url) {
        try {
          this.__learnohUrl = (typeof url === 'string') ? url : String(url);
          this.__learnohMethod = (typeof method === 'string') ? method : String(method);
        } catch (e) { }
        return originalOpen.apply(this, arguments);
      };
      proto.send = function (body) {
        var outgoing = body;
        try {
          var url = this.__learnohUrl ? String(this.__learnohUrl) : '';
          if (DIAG) {
            var method = this.__learnohMethod ? String(this.__learnohMethod) : 'GET';
            var reqPath = pathOf(url);
            recordRequest(method, reqPath);
            attachResponseRecorder(this, reqPath);
            if (reqPath.indexOf(SAVE_FINGER_PATH) >= 0) {
              report('saveFingerRequest', describeBody(body));
            }
          }
          if (url.indexOf(SAVE_FINGER_PATH) >= 0 && typeof body === 'string') {
            var params = new URLSearchParams(body);
            // **D1 修复（2026-09-12，设备实测）**：页面自己已经在 saveFinger 的 body 里放了正确的
            // 指纹（二次验证页的 doubleAuth.bundle.js 在组件构造函数里就调了 getFingers()）。
            // 旧代码**无条件**用 effectiveFingerPrint() 覆盖它，而那一页**没有 #fingerPrint 字段**
            // （那是登录页的；effectiveFingerPrint 只读 DOM），于是每次都回落成我们 36 字符的兜底
            // UUID，把页面 32 字符的值改掉 —— 表单 32 / saveFinger 36，"三处同值"被破坏。
            // 信任是按指纹登记的（参考实现 SSO.tsx:76 回读 data.requestBody.fingerPrint 正是为此），
            // 登记值与出示值不一致 ⇒ 信任不可能命中 ⇒ 下一轮 HTTP 重登还会再要一次短信。
            // 规则：**只在缺失或为空时才写入，绝不覆盖非空值**。
            var pageValue = params.get('fingerprint');
            var pageProvidedFingerprint = (pageValue !== null && String(pageValue).length > 0);
            if (!pageProvidedFingerprint) {
              params.set('fingerprint', effectiveFingerPrint());
            }
            params.set('deviceName', DEVICE_NAME);
            params.set('radioVal', '是');
            outgoing = params.toString();
            saveFingerSent = params.get('fingerprint') ? String(params.get('fingerprint')) : '';
            report('saveFinger', 'patched=1 path=' + pathOf(url)
              + ' pageProvidedFingerprint=' + (pageProvidedFingerprint ? '1' : '0')
              + ' deviceName=' + DEVICE_NAME
              + ' fingerprintChars=' + saveFingerSent.length
              + ' fingerprintSource=' + (pageProvidedFingerprint ? 'pageBody'
                : (saveFingerSent === FP ? 'fallback' : 'pageDom')));
            publish();
            try {
              this.addEventListener('load', function () {
                try { report('saveFingerResponse', 'status=' + String(this.status)); } catch (e2) { }
              });
            } catch (e3) { }
          }
        } catch (e) { report('saveFinger', 'patchError=' + e); }
        return originalSend.call(this, outgoing);
      };
      proto.__learnohSaveFingerPatched = true;
      report('saveFinger', 'patchInstalled=1 path=' + SAVE_FINGER_PATH);
      return true;
    } catch (e) { report('saveFinger', 'patchInstalled=0 reason=' + e); return false; }
  }

  function publish() {
    var fp = valueOf('fingerPrint');
    var fg = valueOf('fingerGenPrint');
    var fg3 = valueOf('fingerGenPrint3');
    var dn = valueOf('deviceName');
    var user = valueOf('i_user');
    var pass = valueOf('i_pass');
    var single = singleLoginBox();
    var patched = !!(window.XMLHttpRequest && window.XMLHttpRequest.prototype.__learnohSaveFingerPatched);
    var payload = 'fingerPrint=' + encodeURIComponent(fp)
      + '&fingerGenPrint=' + encodeURIComponent(fg)
      + '&fingerGenPrint3=' + encodeURIComponent(fg3)
      + '&pageDeviceName=' + encodeURIComponent(dn)
      + '&saveFingerFingerprint=' + encodeURIComponent(saveFingerSent)
      + '&gateBlocked=' + (gateBlocked ? '1' : '0')
      + '&fpSource=' + encodeURIComponent(fp.length === 0 ? 'none' : (fp === FP ? 'fallback' : 'page'))
      + '&f3Remote=' + String(finger3RemoteOk)
      + '&singleLogin=' + (single && single.checked ? '1' : '0')
      + '&userPrefilled=' + (USERNAME.length > 0 && user === USERNAME ? '1' : '0')
      + '&passPrefilled=' + (PASSWORD.length > 0 && pass === PASSWORD ? '1' : '0')
      + '&saveFingerPatched=' + (patched ? '1' : '0');
    if (payload !== lastValues) { lastValues = payload; publishValues(payload); }
    var summary = 'fingerPrintField=' + (field('fingerPrint') ? '1' : '0')
      + ' fingerPrintChars=' + fp.length
      + ' fingerPrintSource=' + (fp.length === 0 ? 'none' : (fp === FP ? 'fallback' : 'page'))
      + ' finger3ValueChars=' + finger3Value.length
      + ' finger3RemoteOk=' + finger3RemoteOk
      + ' fingerGenPrintChars=' + fg.length
      + ' fingerGenPrint3Chars=' + fg3.length
      + ' pageDeviceNameChars=' + dn.length
      + ' singleLogin=' + (single && single.checked ? '1' : '0')
      + ' prefillUser=' + (USERNAME.length > 0 && user === USERNAME ? '1' : '0')
      + ' prefillPass=' + (PASSWORD.length > 0 && pass === PASSWORD ? '1' : '0')
      + ' saveFingerPatched=' + (patched ? '1' : '0')
      + ' saveFingerFingerprintChars=' + saveFingerSent.length
      + ' fingerGenReady=' + (fg.length > 0 && fg3.length > 0 ? '1' : '0')
      + ' gateBlocked=' + (gateBlocked ? '1' : '0')
      + ' diag=' + (DIAG ? '1' : '0')
      + ' url=' + pathOf(window.location ? window.location.href : '');
    if (summary !== lastSummary) { lastSummary = summary; report('summary', summary); }
  }

  function tick() {
    ticks++;
    ensureSingleLogin();
    prefill();
    writeFingerPrint();
    attachSubmitHook();
    publish();
    // 不设上限：见 TICK_MILLIS 的注释。发布本身按"值有变化"去重，所以不会刷日志。
    setTimeout(tick, TICK_MILLIS);
  }

  patchSaveFinger();
  installConsoleTap();
  diagEnvironment();
  diagIndexedDb();
  diagLocalforage();
  diagLocalforageRoundTrip();
  tick();
  collectFinger3();
  try {
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', function () { prefill(); writeFingerPrint(); publish(); });
    }
    window.addEventListener('load', function () { prefill(); writeFingerPrint(); collectFinger3(); publish(); });
    window.addEventListener('pagehide', reportLastObservation);
    window.addEventListener('beforeunload', reportLastObservation);
  } catch (e) { report('setup', 'listenerFailed=' + e); }
})();
`;

function substitute(script: string, token: string, value: string): string {
  return script.split(token).join(value);
}

/**
 * 拼出注入脚本。
 *
 * 所有可变值都经 jsStringLiteral 转义后嵌入，因此账号/口令里出现引号、反斜杠、换行甚至
 * </script> 都不会让脚本语法破掉（单测覆盖敌意输入）。
 */
export function buildEnrollmentScript(spec: EnrollmentScriptSpec): string {
  let script: string = SCRIPT_TEMPLATE;
  script = substitute(script, '__LEARNOH_FINGERPRINT__', jsStringLiteral(spec.fingerPrint));
  script = substitute(script, '__LEARNOH_DEVICE_NAME__', jsStringLiteral(spec.deviceName));
  script = substitute(script, '__LEARNOH_USERNAME__', jsStringLiteral(spec.username));
  script = substitute(script, '__LEARNOH_PASSWORD__', jsStringLiteral(spec.password));
  script = substitute(script, '__LEARNOH_BRIDGE__', jsStringLiteral(spec.bridgeName));
  script = substitute(script, '__LEARNOH_SAVE_FINGER_PATH__', jsStringLiteral(SAVE_FINGER_PATH));
  script = substitute(script, '__LEARNOH_TICK_MILLIS__', TICK_MILLIS.toString());
  script = substitute(script, '__LEARNOH_DIAGNOSTICS__',
    ENROLLMENT_DIAGNOSTICS_FOR_EVIDENCE ? 'true' : 'false');
  script = substitute(script, '__LEARNOH_GATE_NOTICE__', jsStringLiteral(spec.gateNoticeText));
  return script;
}

/**
 * 解析桥回传的 k=v&k=v（值经 encodeURIComponent）。
 *
 * 解码失败时该键留空而不是抛异常：桥的另一端是页面里的脚本，宁可少一个字段也不能让原生侧崩。
 */
export function parseEnrollmentValues(payload: string): EnrollmentDomValues {
  const values: EnrollmentDomValues = emptyDomValues();
  if (payload.length === 0) {
    return values;
  }
  const pairs: string[] = payload.split('&');
  for (let i = 0; i < pairs.length; i++) {
    const eq: number = pairs[i].indexOf('=');
    if (eq <= 0) {
      continue;
    }
    const key: string = pairs[i].substring(0, eq);
    const value: string = decodeComponent(pairs[i].substring(eq + 1));
    if (key === 'fingerPrint') {
      values.fingerPrint = value;
    } else if (key === 'fingerGenPrint') {
      values.fingerGenPrint = value;
    } else if (key === 'fingerGenPrint3') {
      values.fingerGenPrint3 = value;
    } else if (key === 'pageDeviceName') {
      values.pageDeviceName = value;
    } else if (key === 'saveFingerFingerprint') {
      values.saveFingerFingerprint = value;
    } else if (key === 'gateBlocked') {
      values.gateBlocked = value === '1';
    } else if (key === 'fpSource') {
      values.fingerPrintSource = value;
    } else if (key === 'f3Remote') {
      values.finger3RemoteOk = Number.parseInt(value, 10);
    } else if (key === 'singleLogin') {
      values.singleLoginChecked = value === '1';
    } else if (key === 'userPrefilled') {
      values.userPrefilled = value === '1';
    } else if (key === 'passPrefilled') {
      values.passPrefilled = value === '1';
    } else if (key === 'saveFingerPatched') {
      values.saveFingerPatched = value === '1';
    }
  }
  return values;
}

function decodeComponent(raw: string): string {
  try {
    return decodeURIComponent(raw);
  } catch (error) {
    return raw;
  }
}

/**
 * 把最新的 DOM 事实合并进"粘性"快照。
 *
 * 为什么需要粘性：roaming 之后页面已经跳到 learn 域，那时 #fingerPrint 之类字段不存在，
 * 桥回传会变成空串；若直接覆盖就会把"登记时真正提交的值"丢掉。规则：
 *   - 指纹字段只在**非空**时覆盖；
 *   - 四个布尔只升不降（出现过 true 就保持 true）。
 */
export function mergeDomValues(previous: EnrollmentDomValues, fresh: EnrollmentDomValues): EnrollmentDomValues {
  const merged: EnrollmentDomValues = emptyDomValues();
  merged.fingerPrint = fresh.fingerPrint.length > 0 ? fresh.fingerPrint : previous.fingerPrint;
  merged.fingerGenPrint = fresh.fingerGenPrint.length > 0 ? fresh.fingerGenPrint : previous.fingerGenPrint;
  merged.fingerGenPrint3 = fresh.fingerGenPrint3.length > 0 ? fresh.fingerGenPrint3 : previous.fingerGenPrint3;
  merged.pageDeviceName = fresh.pageDeviceName.length > 0 ? fresh.pageDeviceName : previous.pageDeviceName;
  merged.saveFingerFingerprint = fresh.saveFingerFingerprint.length > 0
    ? fresh.saveFingerFingerprint : previous.saveFingerFingerprint;
  merged.singleLoginChecked = previous.singleLoginChecked || fresh.singleLoginChecked;
  merged.userPrefilled = previous.userPrefilled || fresh.userPrefilled;
  merged.passPrefilled = previous.passPrefilled || fresh.passPrefilled;
  merged.saveFingerPatched = previous.saveFingerPatched || fresh.saveFingerPatched;
  // 自检状态取**末次观测**（不粘性）：它要回答的是"此刻这一屏是不是被拦下了"。
  merged.gateBlocked = fresh.gateBlocked;
  // 来源与"远端是否成功"是**有意义才覆盖**：漫游到 learn 域后字段消失（source=none / remote=-1），
  // 那时要保留登录页上的结论（否则等式与自检判定会丢掉依据）。
  merged.fingerPrintSource = fresh.fingerPrintSource !== 'none' && fresh.fingerPrintSource.length > 0
    ? fresh.fingerPrintSource : previous.fingerPrintSource;
  merged.finger3RemoteOk = fresh.finger3RemoteOk >= 0 ? fresh.finger3RemoteOk : previous.finger3RemoteOk;
  return merged;
}

/** 生效指纹 + 它的来源（来源要进日志：要求可诊断）。 */
export interface EnrollmentFingerPrint {
  value: string;
  /** saveFingerXhr（服务端登记值） / formFieldDom（登录页表单值） / generatedFallback（我们的 UUID） / none。 */
  source: string;
}

/**
 * 生效指纹的**唯一一处**定义（登记、落盘、重登回放都必须用它）。
 *
 * 权威顺序（2026-09-12 的 D1 修复 + 方案 A 合起来的结果）：
 *   1. `saveFingerXhr` —— saveFinger 的 XHR **实际发出**的 fingerprint（页面自己算的，或页面没给时
 *      我们写的那个）。**它最权威**：服务端按它登记信任，将来 HTTP 重登出示的必须是同一个值；
 *   2. `formFieldDom` —— 登录页 #fingerPrint 的值（方案 A 的权威值；saveFinger 没被触发时用它）；
 *   3. `generatedFallback` —— 页面既没给字段也没发 saveFinger 时才用我们生成的 UUID；
 *   4. `none` —— 三者都空（调用方据此显式失败，不猜）。
 */
export function resolveEnrollmentFingerPrint(injectedFingerPrint: string,
  dom: EnrollmentDomValues): EnrollmentFingerPrint {
  if (dom.saveFingerFingerprint.length > 0) {
    return { value: dom.saveFingerFingerprint, source: 'saveFingerXhr' };
  }
  if (dom.fingerPrint.length > 0) {
    return { value: dom.fingerPrint, source: 'formFieldDom' };
  }
  if (injectedFingerPrint.length > 0) {
    return { value: injectedFingerPrint, source: 'generatedFallback' };
  }
  return { value: '', source: 'none' };
}

/**
 * 登记成功时该保存的凭据：fingerPrint 取**生效值**（见 resolveEnrollmentFingerPrint；
 * 应用侧指纹的落点），另外两个站点指纹取页面 DOM 里的实际值（可能是空串，参考实现的默认值也是空串）。
 */
export function credentialRecordFor(username: string, password: string, injectedFingerPrint: string,
  dom: EnrollmentDomValues): CredentialRecord {
  // 权威判定放在这里（而不是调用点）是有意的：调用方可能来自不同 ticket 的编排代码，
  // 让"哪个值权威"只有一处定义，重登（ticket 08）读到的就是同一个生效值。
  const effective: string = resolveEnrollmentFingerPrint(injectedFingerPrint, dom).value;
  return createCredentialRecord(username, password, effective, dom.fingerGenPrint, dom.fingerGenPrint3);
}

/**
 * DOM 事实的**脱敏**诊断串（可直接进日志/导出文件）。
 *
 * 只给长度与布尔：三个指纹的真值一个都不出现。`pageDeviceName` 是页面自己算的 UA 名
 * （形如 `windows,Chrome/120`），不是秘密，照原样记录——排查"服务端看到的浏览器是谁"时最有用。
 */
export function describeEnrollmentDomValues(dom: EnrollmentDomValues): string {
  return 'fingerPrintChars=' + dom.fingerPrint.length.toString()
    + ' fingerGenPrintChars=' + dom.fingerGenPrint.length.toString()
    + ' fingerGenPrint3Chars=' + dom.fingerGenPrint3.length.toString()
    + ' pageDeviceName=' + (dom.pageDeviceName.length > 0 ? dom.pageDeviceName : 'empty')
    + ' saveFingerFingerprintChars=' + dom.saveFingerFingerprint.length.toString()
    + ' singleLogin=' + dom.singleLoginChecked.toString()
    + ' prefill=(' + dom.userPrefilled.toString() + ',' + dom.passPrefilled.toString() + ')'
    + ' saveFingerPatched=' + dom.saveFingerPatched.toString()
    + ' gateBlocked=' + dom.gateBlocked.toString()
    + ' fpSource=' + dom.fingerPrintSource
    + ' f3Remote=' + dom.finger3RemoteOk.toString();
}
