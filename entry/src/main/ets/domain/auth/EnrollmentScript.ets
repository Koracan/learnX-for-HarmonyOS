/*
 * 登记页注入脚本（domain，纯逻辑）：把一段 JS **源码**拼出来，以及解析它经桥回传的值。
 *
 * 注入面（spec 第 5 节 + ticket 07 Comments 的既有结论）——只有三件事：
 *   1. **预填**账号/口令并置 readonly（照参考实现 src/helpers/preval/sso.js:38-53）；
 *   2. 把**我们生成的**设备指纹写进 #fingerPrint，并拦截 saveFinger 的 XHR，把
 *      fingerprint / deviceName / radioVal=是 换成我们的值（sso.js:12-36 的等价物）；
 *   3. 让页面自己把 localStorage 里的 fingerGenPrint 吐回 DOM（localstorageUtil.getFinger3FromLocal）。
 *
 * **明确不做**（idp-login-flow.md 第 3 节）：旧实现对 jQuery.fn.submit 的猴补丁——它只是为了把
 * FormData 经 postMessage 回传 RN；我们的 HTTP 侧凭据由本工程自己持有，不需要那条通道。
 * 单测里有一条断言"产物里不含 jQuery.fn.submit"，防止有人日后把它加回来。
 *
 * 为什么写 #fingerPrint 而不是只读它：服务端把"信任浏览器"绑定在设备指纹上（ADR-0004 /
 * idp-login-flow.md 第 4 节），而**信任的判据必须是同一个值**——登记时 saveFinger 上报的值、
 * 登录表单提交的值、以及将来 HTTP 重登出示的值（ticket 08）三者逐字相同。参考实现也是这么做
 * 的（sso.js 同时覆盖表单字段与 XHR）。页面自己的 fingerPrint 是 fingerprintjs2 的
 * canvas/webgl 指纹，纯 ArkTS 侧无法复算，"读 DOM 当凭据再回放"反而更弱。
 *
 * 回传协议（两条通道，值/日志分离）：
 * 设备实测的两处修正（都写进了 ticket Comments）：
 *   - "信任该浏览器"复选框**只有 name（singleLogin）、没有 id**，且全新 profile 上页面并不勾选它
 *     （finger3.js 只在 localStorage 已有 "singleLoginKey"="yes" 时才勾选）——必须由我们按 name
 *     找到并勾上（参考实现 sso.js:69-74 的等价物），否则服务端不会登记 180 天信任；
 *   - 轮询**不设上限**（定时器随文档销毁自然结束）：页面的 promise 晚到会把它清掉，而"提交那一刻
 *     是勾上的"是 180 天信任的前提；另加一个 jQuery **公开 API** 的 submit 钩子（不是猴补丁），
 *     在提交前再断言一次。
 *
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

/** 注入脚本的输入。 */
export interface EnrollmentScriptSpec {
  username: string;
  password: string;
  fingerPrint: string;
  deviceName: string;
  bridgeName: string;
}

/** 桥回传的 DOM 事实（原生侧据此保存凭据并打脱敏日志）。 */
export interface EnrollmentDomValues {
  fingerPrint: string;
  fingerGenPrint: string;
  fingerGenPrint3: string;
  pageDeviceName: string;
  /** saveFinger 的 XHR **实际发出**的 fingerprint 参数（用于"三点一致"的等式证据）。 */
  saveFingerFingerprint: string;
  singleLoginChecked: boolean;
  userPrefilled: boolean;
  passPrefilled: boolean;
  saveFingerPatched: boolean;
}

/** 空值，便于"还没收到桥回传"时安全读取。 */
export function emptyDomValues(): EnrollmentDomValues {
  return {
    fingerPrint: '', fingerGenPrint: '', fingerGenPrint3: '', pageDeviceName: '', saveFingerFingerprint: '',
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
      jq(form).on('submit', function () {
        var forced = ensureSingleLogin();
        writeFingerPrint();
        report('submitHook', 'fired=1 singleLoginForced=' + (forced ? '1' : '0'));
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

  // 页面在解析末尾写自己的指纹，所以这里要反复盖回去（有限次；之后页面不会再改这个字段）。
  function writeFingerPrint() {
    var el = field('fingerPrint');
    if (!el) { return false; }
    if (el.value !== FP) { el.value = FP; }
    return true;
  }

  // 让页面自己算 fingerGenPrint（值在 localStorage，原生侧算不出来，只能读）。
  function collectFinger3() {
    try {
      var lsu = window.localstorageUtil;
      if (!lsu || typeof lsu.getFinger3FromLocal !== 'function') {
        report('finger3', 'localstorageUtil=absent');
        return;
      }
      lsu.getFinger3FromLocal().then(function (r) {
        var el = field('fingerGenPrint');
        if (el && r) { el.value = r; }
        report('finger3', 'source=localstorage chars=' + (r ? String(r).length : 0));
        publish();
      }).catch(function (e) { report('finger3', 'error=' + e); });
    } catch (e) { report('finger3', 'throw=' + e); }
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
        try { this.__learnohUrl = (typeof url === 'string') ? url : String(url); } catch (e) { }
        return originalOpen.apply(this, arguments);
      };
      proto.send = function (body) {
        var outgoing = body;
        try {
          var url = this.__learnohUrl ? String(this.__learnohUrl) : '';
          if (url.indexOf(SAVE_FINGER_PATH) >= 0 && typeof body === 'string') {
            var params = new URLSearchParams(body);
            params.set('fingerprint', FP);
            params.set('deviceName', DEVICE_NAME);
            params.set('radioVal', '是');
            outgoing = params.toString();
            saveFingerSent = params.get('fingerprint') ? String(params.get('fingerprint')) : '';
            report('saveFinger', 'patched=1 path=' + pathOf(url)
              + ' deviceName=' + DEVICE_NAME + ' fingerprintChars=' + FP.length);
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
      + '&singleLogin=' + (single && single.checked ? '1' : '0')
      + '&userPrefilled=' + (USERNAME.length > 0 && user === USERNAME ? '1' : '0')
      + '&passPrefilled=' + (PASSWORD.length > 0 && pass === PASSWORD ? '1' : '0')
      + '&saveFingerPatched=' + (patched ? '1' : '0');
    if (payload !== lastValues) { lastValues = payload; publishValues(payload); }
    var summary = 'fingerPrintField=' + (field('fingerPrint') ? '1' : '0')
      + ' fingerPrintChars=' + fp.length
      + ' fingerPrintMatchInjected=' + (fp === FP ? '1' : '0')
      + ' fingerGenPrintChars=' + fg.length
      + ' fingerGenPrint3Chars=' + fg3.length
      + ' pageDeviceNameChars=' + dn.length
      + ' singleLogin=' + (single && single.checked ? '1' : '0')
      + ' prefillUser=' + (USERNAME.length > 0 && user === USERNAME ? '1' : '0')
      + ' prefillPass=' + (PASSWORD.length > 0 && pass === PASSWORD ? '1' : '0')
      + ' saveFingerPatched=' + (patched ? '1' : '0')
      + ' saveFingerFingerprintChars=' + saveFingerSent.length
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
  return merged;
}

/**
 * 登记成功时该保存的凭据：fingerPrint 取**我们注入的那一个**（验收第 2 条的落点），
 * 另外两个站点指纹取页面 DOM 里的实际值（可能是空串，参考实现的默认值也是空串）。
 */
export function credentialRecordFor(username: string, password: string, injectedFingerPrint: string,
  dom: EnrollmentDomValues): CredentialRecord {
  return createCredentialRecord(username, password, injectedFingerPrint, dom.fingerGenPrint, dom.fingerGenPrint3);
}

/**
 * DOM 事实的**脱敏**诊断串（验收第 5 条的落点，可直接进日志/导出文件）。
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
    + ' saveFingerPatched=' + dom.saveFingerPatched.toString();
}
