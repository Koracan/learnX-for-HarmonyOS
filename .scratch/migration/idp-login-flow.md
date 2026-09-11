# ID 登录流程 —— 取证与简化设计（事实）

取证方式：匿名 GET `https://id.tsinghua.edu.cn/do/off/ui/auth/login/form/bb5df85216504820be7bba2b0ae1535b/0`（HTTP 200，15202 字节，无需登录即可取），并下载其 5 个前端脚本到 `idp-js/`。

## 1. 登录页结构（事实）

- **静态隐藏字段**（HTML 里写死、初始为空）：`fingerPrint` `fingerGenPrint` `fingerGenPrint3` `deviceName`；表单 id = `theform`；`#sm2publicKey` 是页内元素（`$("#sm2publicKey").text()`）。
- **内联脚本**（页面末尾）：
  ```js
  var fingerStr = fingerprintUtil.getFingers();
  $("#fingerPrint").val(fingerStr);
  $("#deviceName").val(userAgentUtil.getUserAgentName());
  ```
  ⇒ `fingerPrint` **由客户端生成**，页面加载时即写入。
- **页内 `doLogin()`**：校验用户名/密码；若验证码可见则校验 `#i_code`（4 位）；然后
  ```js
  var publicKey = $("#sm2publicKey").text();
  var encryptPass = sm2Util.doEncryptStr(pass, publicKey);   // SM2 加密由页面自己做
  $("#sm2pass").val(encryptPass);
  localstorageUtil.getFinger3FromLocal().then(function(res){ $("#fingerGenPrint").val(res); $("#theform").submit(); });
  ```
  ⇒ **`fingerGenPrint` 只在提交瞬间从 localStorage 取值写入表单**。
- **`/res/selfservice/finger3.js`（全文 976 字节，已读）**：
  ```js
  localstorageUtil.getFinger3FromLocal().then(f => { if (f) $("#fingerGenPrint3").val(f); else localstorageUtil.getFinger3FromRemoteAndSave().then(f => $("#fingerGenPrint3").val(f)); });
  localstorageUtil.getSingleLoginKey().then(res => $('input[name="singleLogin"]').prop("checked", res === "yes"));  // 源码里紧邻的注释写着"默认是 yes"，但**注释与实现不一致**（见下方 2026-09-12 更正）
  ```
  ⇒ `fingerGenPrint3` 在**加载时**就已确定。`singleLogin` 在加载时也被**确定**，但**全新 profile 上确定的结果是"未勾选"**（见下方 2026-09-12 更正）。
- 有图形验证码通道（`/captcha.jpg`、`#c_code`、`refreshCaptcha()`，条件显示）与"国家网络身份认证"扫码登录（`smrzQ.js`）。**是否/何时触发，客户端不可知。**
- 相关脚本：`fingerprintUtil.js`(35KB)、`sm2Util.js`(43KB)、`localstorageUtil.js`(35KB)、`userAgentUtil.js`(2.6KB)，均已下载到 `idp-js/`。`saveFinger` **不在初始 HTML 中**，位于打包脚本内部（未进一步拆解 webpack）。
- 成功标志：跳到 `https://learn.tsinghua.edu.cn/f/j_spring_security_thauth_roaming_entry`。

## 2. 旧实现做了什么（`src/helpers/preval/sso.js`，118 行）

1. 猴补丁 `XMLHttpRequest.prototype.open/send`，当 URL 为 `/b/doubleAuth/personal/saveFinger` 时把 `fingerprint`/`deviceName`/`radioVal=是` 塞进 form body。
2. 猴补丁 `jQuery.fn.submit`：提交时把 `fingerPrint` 写进表单、勾选 `singleLogin`、把 `FormData` 经 `postMessage` 回传 RN（取 `fingerPrint/fingerGenPrint/fingerGenPrint3`）。
3. 用 `MutationObserver` + 100ms 轮询等待 jQuery，预填 `#i_user`/`#i_pass` 并设为 readonly。
4. RN 侧 `SSO.tsx` 用 `Math.random` 造 UUID 作 `fingerPrint` 注入脚本，`onShouldStartLoadWithRequest` 检测 roaming URL 后调 `login({...formData, reset:true})` 走 thu-learn-lib 的 HTTP 登录。

## 3. 由此得出的简化结论（供决策）

第 2 步里的 `jQuery.fn.submit` 猴补丁与 `saveFinger` XHR 拦截**在原理上可省**：

- `fingerPrint`/`fingerGenPrint3`/`deviceName`/`singleLogin` 页面加载时已就绪 ⇒ 一句 `runJavaScript` 直接读 DOM 即可。
- `fingerGenPrint` 可让页面自己吐出来：注入
  `localstorageUtil.getFinger3FromLocal().then(r => { document.getElementById('fingerGenPrint').value = r; })`
  再读 DOM（`localstorageUtil` 是页面全局对象）。
- 只需保留 `onLoadIntercept`/`onLoadIntercept` 检测 roaming URL 作为成功信号。
- SM2 只在我们自己做 **纯 HTTP 重登** 时才需要（页面已自带 `sm2Util`）。

## 4. 信任生命周期（用户提供的事实，2026-09-11）

- 登录页有"信任该浏览器"选项（就是 `singleLogin` 复选框）。
  **更正（2026-09-12，设备实测 + 源码复核）：它并非"默认勾选"。** `finger3.js` 的逻辑是 `if (res === "yes") checked = true else checked = false`，而 `getSingleLoginKey()` 就是 `localforage.getItem("singleLoginKey")`、**没有兜底**，全新 profile 返回 `null` ⇒ 走 `else` ⇒ **显式置为未勾选**。源码里那句 `//默认是yes` 的注释**与实现不一致**（本文件早先照抄了该注释，现已更正）。
  参考实现 `sso.js:69-74` 因此在**提交时**主动 `click()` 把它勾上。**新实现必须自己做这件事**：否则 ID 侧不把该浏览器记为可信，180 天信任不成立，ADR-0004 的纯 HTTP 重登路线失效。
- **信任有效期 180 天**：信任期内，同一浏览器（= 同一设备指纹）重新认证**不需要**二次验证。
- **二次验证 = 账号 + 密码 + 短信验证码**，仅在**未被信任的浏览器**上要求。
- 服务端识别"同一浏览器"依据的就是 `fingerPrint / fingerGenPrint / fingerGenPrint3` —— **信任绑定在设备指纹上**。这就是旧 `sso.js` 必须把**自己的** `fingerPrint` 注入 `saveFinger` XHR 与登录表单的原因：服务端登记的必须是将来 HTTP 重登要出示的同一个值。
- 推论：**Enrollment 只在两种时刻发生**——首次安装、以及信任过期后。其余冷启动都走纯 HTTP 重登（不碰 WebView）。
- 由此产生的边界（旧版未处理）：**第 181 天起 Re-auth 会失败并触发短信**，必须有显式降级到浏览器登录的路径，而不是仅在响应为 `'[]'` 时补救。

**待验证（决定"保持登录"路线）**：
1. Web 引擎 cookie 是否跨应用重启持久化（决定"信任浏览器"路线 A 是否成立）。
2. `cryptoFramework.createCipher` 接受的确切 SM2 变换字符串（决定凭据路线 B 是否可纯 ArkTS 实现；`SM2CipherTextSpec`/`SM2CryptoUtil.genCipherTextBySpec(spec, mode)` 的 `mode` 对应密文排列方式，与 `sm-crypto` 的 `04` 前缀格式需对齐）。
3. 服务端在无交互的 re-auth 请求上是否弹图形验证码（决定 A/B 是否都会退化到"用户手动登录"）。
