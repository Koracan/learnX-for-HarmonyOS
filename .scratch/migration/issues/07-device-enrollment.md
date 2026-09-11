# 07: 设备登记 Enrollment

**What to build:** 浏览器中的设备登记：预填账号与口令、把本机设备指纹写入登录表单与信任登记请求、由用户完成短信验证、识别登录成功信号、把会话交给 HTTP 客户端并把凭据加密落盘。

**Blocked by:** 03（导航骨架 + 公告列表）、06（HTTP 客户端 + cookie jar + SM2 登录）

**Status:** verified-partial —— 统筹验收：2 条达成、1 条机制已证（合成凭据）、1 条部分闭环、1 条待用户操作；见 Comments 末尾「统筹验收」

- [ ] 真机完成一次完整登记（含短信验证），回到应用后处于已登录可用状态 —— **待用户操作**（短信门控）；短信之前的环节已在模拟器自测通过。口径：本轮只有模拟器证据，真机复验欠（归 ticket 18 前）
- [ ] 服务端登记的设备指纹与我们保存的凭据指纹是同一个值 —— **部分闭环**：三点脱敏等式的第①点已证（`formFieldDom=d4314739`），②③ 待用户提交后闭合
- [x] 凭据加密落盘；重启应用后仍处于已登记状态 —— **机制已证**：合成凭据走真实 asset 通道，杀进程重启后仍 `enrolled`（`07-probe-restart-enrolled.txt`）；真实账号的落盘随验收 1
- [x] 用户中途放弃或验证失败时回到登录页，且不残留半登记状态 —— 取消 + 重启两条独立证据（`07-final-cancel.txt` / `07-final-restart-after-cancel.txt`）
- [x] 指纹相关字段在日志中可诊断（脱敏），便于排查登记失败 —— 长度/布尔/前缀 + SHA256 前 8 位；日志里 UUID 形状与合成指纹字面量均 0 命中

## Comments

### 派单前的依赖澄清（统筹，2026-09-12）

**本文写的 "Blocked by: 03、06" 只描述实现依赖，而 06 的最终验收反过来依赖本 ticket 的一次真实运行**，
两者叠起来是一个环，直接按字面派单会把任意一边的验收悬空。先把环拆清楚：

- **实现依赖**：06 提供 HTTP 客户端（cookie jar + SM2 登录）→ 本 ticket 要把浏览器拿到的会话交给它；
  所以 06 的实现先落地。
- **验收依赖（反向）**：06 的验收第 1 条是「用**真实账号**完成纯 HTTP 登录」，账号口令来自本 ticket 的
  一次浏览器登记（用户手动完成短信验证）。所以 06 那条**只能在本 ticket 跑过一次之后**才可能勾选。

**因此实际顺序**：06（实现）→ 07（本 ticket）→ **用户手动登记一次** → 回头勾 06 的验收第 1 条、
并让 05 的三域真实抓取可测。06 与 05 都已把该条明确标为未勾选（06 Comments 第 6 节、05 待账号验证项），
**不要在那之前把它们标成完成**。

**给两边的接口约束（避免为了解环而互相读对方内部）**：
- 06 的登录能力应当**通过入参接收账号/口令**（端口或函数参数），**不要自己去读凭据库**——凭据落盘归本 ticket；
  这样 06 可以在没有账号的情况下把实现与单测做完。
- 本 ticket 负责凭据加密落盘（asset store，见 spec 第 4 节）与"重启后仍已登记"。
  **不要把会话 cookie 落盘**（ADR-0004）：cookie 只在内存，重启走 Re-auth（08）。

**另外两处落地时必须遵守的既有结论**：
- 注入面按 `spec.md` 第 5 节：页面自己会写好 `fingerPrint`/`fingerGenPrint3`/`singleLogin`，
  `fingerPrint` 与 `fingerGenPrint3` 直接读 DOM；**只有 `saveFinger` 的 XHR 需要注入**我们生成的指纹与 `deviceName`。
  `deviceName` 形如 `HarmonyOS,learnOH/{versionName} ({productModel})`，**仅登记时上报**。
- 失败处理：任何非预期响应一律**降级回 Enrollment**，不做静默重试循环，也不做过期主动提醒（spec 第 5 节 / Q25）。

## Comments

### 实现与门禁（2026-09-12，模拟器口径）

**交付清单**（新增，或对既有文件的扩展）：

| 文件 | 作用 |
| --- | --- |
| `core/asset/SecretStorePort.ets`（新） | 秘密存储端口（纯接口，零平台依赖）：读 / 写 / 删，单测注入假实现 |
| `core/asset/AssetSecretStore.ets`（新） | `@kit.AssetStoreKit` 实现：`Accessibility.DEVICE_UNLOCKED`、**无额外开关**；失败不抛（读→null、写/删→false）并落 hilog（含平台错误码） |
| `core/device/AppIdentity.ets`（新） | `appVersionName()`（bundleManager，取**应用自身信息**而不是源码里的 package.json）+ `deviceProductModel()` |
| `core/http/CookieJar.ets`（扩展） | 新增 `parseCookieHeaderPairs` + `absorbCookieHeader`（浏览器 `Cookie` 头 → 内存 jar）；既有接口与单测未动 |
| `core/web/SessionHeaderProvider.ets`（改） | `createSessionHeaderProvider()` 现在返回**进程内内存单例**，新增 `updateWebSessionHeader()` —— ticket 04 预留的注入点接上 |
| `data/auth/CredentialStore.ets`（新） | 凭据落盘 / 读回 / 清除；**不完整记录拒绝落盘**；损坏或未知版本一律当"没有凭据" |
| `data/auth/EnrollmentSession.ets`（新） | 把浏览器收割到的 cookie 交给 HTTP jar → GET 课程列表页取 CSRF/语言；失败分类、**不重试** |
| `data/auth/AuthSession.ets`（新） | 内存会话/凭据缓存（jar + Session + CredentialRecord），**无任何落盘调用** |
| `domain/auth/DeviceIdentity.ets`（新） | UUID v4 位规则、`deviceName` 组装、脱敏表示 |
| `domain/auth/CredentialRecord.ets`（新） | 凭据 payload 编解码 / 版本 / 完整性 / 脱敏描述 |
| `domain/auth/EnrollmentScript.ets`（新） | **注入脚本构建**（纯字符串拼接 → 可单测）+ 桥回传协议解析 / 粘性合并 / 脱敏描述 |
| `domain/auth/FingerprintDigest.ets`（新） | 纯 ArkTS SHA-256（+ 前 8 位摘要）："三点等式"的工具 |
| `data/remote/HttpFetchPort.ets`（接入） | 由 `AuthServices` 装配 → **首次进入可达路径**（`check-import-graph` 的 WARN 随之消失） |
| `features/auth/{AuthServices,AuthStore,LoginPage,EnrollmentWebView}.ets`（新） | 设备侧装配点 / 界面状态机 / 登录页（对齐参考 `Login.tsx`）/ ArkWeb 登记容器 |
| `pages/Index.ets`（改） | 认证门：LOADING → UNENROLLED（登录页）/ ENROLLED（ticket 03/04 的主壳） |
| `entry/src/test/{DeviceIdentity,CredentialRecord,EnrollmentScript,FingerprintDigest,EnrollmentFlow}.test.ets` + `fixtures/EnrollmentFixtures.ets`（新） | 48 条新单测 |

**门禁（真实输出）**

- 单测：`Tests run: 207, Failure: 0, Error: 0, Pass: 207`，29 类（先删 `entry/.test` + `--no-incremental`；日志 `.dsh/logs/ticket07-test6.log`，`GenerateUnitTestResult` 有执行）。本轮 48 条：`domain.DeviceIdentity` 8 / `domain.CredentialRecord` 7 / `domain.EnrollmentScript` 15 / `domain.FingerprintDigest` 6 / `data.Enrollment` 12（159 + 48 = 207）。
- 领域纯度：`node scripts/check-domain-purity.mjs` → `PASS`（16 个领域源文件）。
- 导入图：`node scripts/check-import-graph.mjs` → `PASS`；WARN 只剩入口 `pages/Index.ets` 与 `EntryBackupAbility.ets`（属正常）。**`data/remote/HttpFetchPort.ets` 的 WARN 已消失**。
- i18n：`node scripts/check-i18n-keys.mjs` → `RESULT: OK`（231 键；本轮**未新增文案**，登录页与说明对话框全部复用 ticket 02 迁移过来的 `loh_*` 键）。
- 构建：`devecocli build` → `BUILD SUCCESSFUL`；最终产物 `entry-default-signed.hap` **1,468,839 B @ 07:15:40**（删 `entry/build` 后的强制全量构建，见「构建缓存坑」）。产物字节检索：不含 `EnrollmentProbe` / `TEMP-EVIDENCE`，含 `learnOHEnrollmentBridge`。

### 逐条验收

| # | 验收项 | 结论 | 证据 / 待办 |
| --- | --- | --- | --- |
| 1 | 真机完成一次完整登记（含短信验证），回到应用后处于已登录可用状态 | **待用户操作**（短信门控） | 短信**之前**的环节已自测：`07-final-id-page-injected.png`（预填 + 状态行 `fpChars=36 prefill=11 saveFinger=1 singleLogin=1`）、`07-final-inject.txt`。漫游、`saveFinger` 响应、会话收割与落盘需要用户本人在页面上完成；关闭方式见「未验证项 1」。口径：本条字面写"真机"，本轮只有**模拟器**证据，真机复验仍欠（归 ticket 18 前的一次性复验）。 |
| 2 | 服务端登记的设备指纹与我们保存的凭据指纹是同一个值 | **部分闭环（① 已证；② ③ 待用户提交）** | 三点**脱敏**摘要（SHA256 前 8 位）：① `point=formFieldDom=d4314739`（`07-final-inject.txt`）；② `saveFingerXhr`、③ `persistedReadBack` 由 `AuthStore.completeEnrollment` 一行打出 `enrollment fingerprint digest equation: formFieldDom=… saveFingerXhr=… persistedReadBack=… formEqualsPersisted=… xhrEqualsPersisted=…`，**只有用户提交表单、`saveFinger` 触发后才产生**。本轮 `saveFingerXhr=empty` 是预期，不是失败。 |
| 3 | 凭据加密落盘；重启应用后仍处于已登记状态 | **机制已证（合成凭据）** | 探针：`07-probe-seed.txt`（`credentials saved: ok=true` → 读回一致）→ 杀进程 `07-probe-restart-enrolled.txt`（**新 PID** `credentials loaded` → `startup: enrolled -> main shell (credentials from asset store)`）+ `07-probe-restart-shell.png`；`07-probe-clear.txt` + `07-probe-restart-unenrolled.txt` 证明状态确实由存储决定。**用的是合成占位凭据**（探针文件里写明的 probe-* 值，不是真实账号）。边界：asset 的加密由系统服务承担，本证据只证"走 asset 通道且读回一致"。 |
| 4 | 用户中途放弃或验证失败时回到登录页，且不残留半登记状态 | **达成** | 取消：`07-final-cancel.txt`（cancel tapped → `stage=cancelled` → `web cookies cleared: when=on-disappear`）+ `07-final-after-cancel.png`；重启：`07-final-restart-after-cancel.txt`（新 PID `no persisted credentials` → `not enrolled -> login page`）+ `07-final-restart-after-cancel.png`。代码层：`completeEnrollment` **先建会话、后落盘**，任一失败都回 UNENROLLED 且不写凭据；`CredentialStore.save` 拒绝不完整记录（单测 `refusesToPersistIncompleteCredentials`）。 |
| 5 | 指纹相关字段在日志中可诊断（脱敏） | **达成** | `07-final-inject.txt`：`fingerPrintChars=36 fingerPrintMatchInjected=1 fingerGenPrintChars=0 fingerGenPrint3Chars=0 pageDeviceName=other,Chrome/132 singleLogin=1 prefillUser=1 prefillPass=1 saveFingerPatched=1`；三点等式只打 SHA256 前 8 位。**反证检查（可复核）**：`Get-ChildItem .scratch/enrollment/evidence/*.txt | Select-String '[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}'` → **0 命中**；探针合成指纹字面量 `0f0f0f0f` → **0 命中**；脱敏形 `0f0f…(36)` → 15 命中。 |

### 设备实测修正（一条，改了 spec/idp-login-flow 的前提）

**"信任该浏览器"复选框（`singleLogin`）在全新 profile 上是**未勾选**的，必须由我们勾上。**

- 页面 HTML 里是 `<input type="checkbox" name="singleLogin">`：**没有 `checked` 属性、也没有 `id`**（`document.getElementById('singleLogin')` 恒为 null——我的第一版探针因此把"勾选状态"读成了恒 false，这一处也说明**探针本身要能自证**）。
- `finger3.js` 的 `getSingleLoginKey().then(res => prop("checked", res === "yes"))`：`getSingleLoginKey` = localforage `getItem("singleLoginKey")`，**无兜底**；全新 profile 返回 null ⇒ 走 else ⇒ **显式置为未勾选**。源码里那句 `//默认是yes` 与它下面两行实现直接矛盾（idp-login-flow.md 原本照抄了该注释）。
- 参考实现 `sso.js:69-74` 因此在**提交时** `click()` 把它勾上。不勾选 = ID 侧不把该浏览器记为可信 ⇒ 180 天信任不成立 ⇒ ticket 08 的纯 HTTP 重登必然退化到短信，ADR-0004 的整条路线失效。
- 本轮实现（设备日志 `07-final-inject.txt`）：`[singleLogin] forced=1 pageLeftItUnchecked=1`（一行自证"页面原本没勾 + 我们勾了"）→ `summary … singleLogin=1`。因为页面的 promise 晚到会把它清掉（实测 1.5s 后清过一次），做法是**不设上限的轮询重 assert** + **jQuery 公开 API 的 submit 钩子**（`jq(form).on('submit', …)`，在 jQuery 的默认动作=原生 submit 之前再断言一次）。**没有替换 jQuery 的 submit，也没有回传表单数据**——单测 `doesNotMonkeyPatchJQuerySubmit` / `reassertsUntilTheDocumentGoesAwayAndHooksSubmitViaPublicApi` 守住。
- **这不是偏离参考实现，而是回到它**（该条已由统筹写进 spec 第 5 节与 idp-login-flow.md 的更正），因此**未改动 `docs/reference-quirks.md`**。

### 验收第 2 条的执行形式：三点脱敏等式

登记成功路径上打三行（同一份摘要函数 `domain/auth/FingerprintDigest`，只出 SHA256 前 8 位）：

1. `point=formFieldDom` —— 页面 DOM 里 `#fingerPrint` 的**实际值**（= 表单将要提交的值）；
2. `point=saveFingerXhr` —— 注入的 XHR 拦截器**实际拼进 body** 的 `fingerprint` 参数（不是"我们要发的值"，而是 `saveFingerSent`，从 `params.get('fingerprint')` 读回）；
3. `persistedReadBack` —— 落盘后**再从存储读回**的值（不是内存对象）。

闭合判据：`formFieldDom == saveFingerXhr == persistedReadBack`。第 1 点本轮已证；第 2、3 点要等用户提交。SHA-256 是**纯 ArkTS 实现**（不依赖平台摘要通道在当前环境是否可用），带 NIST 三组向量 + UTF-8/中英混排 + 55/56 字节填充边界，共 6 条单测。

### 与参考实现的有意差异（均已在此登记）

1. **不再二次纯 HTTP 登录**：参考实现拦到 roaming URL 后**取消**导航，再用 thu-learn-lib 完整登录一次（`SSO.tsx:54-67`）。本实现按 spec 第 5 节**放行**漫游让浏览器走完，然后从 Web 引擎收割会话 cookie 交给 HTTP jar（`EnrollmentSession`）。理由：用户的短信结果与应用会话是**同一个会话**，不存在"再登一次时服务端是否又要求二次验证"的不确定性。
2. **不做 `jQuery.fn.submit` 猴补丁**：旧实现需要它把 FormData 经 `postMessage` 回传 RN；本工程自己持有凭据，不需要那条通道。改用"有限次→不设上限轮询覆盖 + XHR 拦截 + jQuery 公开 API 的 submit 钩子"。**效果等价、手段不同**。
3. **`deviceName` 追加型号**：`HarmonyOS,learnOH/{versionName} ({productModel})`（参考实现只有 `HarmonyOS,learnOH/{version}`，`SSO.tsx:52`）。依据 spec 第 5 节；仅登记时上报，不参与信任绑定。
4. **收割会话后清 Web 引擎 cookie**（`WebCookieManager.clearAllCookiesSync()`，登记前/离开登记页各一次）：参考实现依赖 WebView 的 cookie 存储，本工程按 ADR-0004 只保留内存 jar；清掉引擎侧避免会话数据留在设备上。
5. **失败分类更细**：收割失败用 ticket 06 的 `FailReason`（`ERROR_SETTING_COOKIES` / `UNEXPECTED_STATUS` / `NOT_LOGGED_IN`），并**只尝试一次**（spec 第 5 节 / Q25：不做静默重试循环）。
6. **`#fingerPrint` 的写入时机**：参考实现在提交时写；本实现在页面写完之后盖回去并**持续重 assert**（页面不会在加载后重写该字段，但重 assert 把"我们停止轮询后被改写"这一窗口也关掉）。

### 未验证项（判据可复核，不要当成"应该没问题"）

1. **完整登记（验收 1）**：需要用户本人操作。步骤：装最终构建 → 登录页输入真实账号/口令 → 「登录」→ 确认对话框 → 在网页里完成短信验证 → 回到应用应进入主壳（五 tab）。产生的日志：`enrollment roaming reached`、`enrollment harvest: attempt=… entries=…`、`enrollment session: ok csrfChars=…`、`credentials saved: ok=true`、`startup: enrolled -> main shell`。失败时的判读出口：`enrollment session failed: reason=NOT_LOGGED_IN|UNEXPECTED_STATUS`（会话没被认）/ `enrollment aborted: #fingerPrint was never observed`（页面字段改名）。
2. **三点等式闭合（验收 2 的后两点）**：同一次真实登记后看 `enrollment fingerprint digest equation` 一行是否 `formEqualsPersisted=true` 且 `xhrEqualsPersisted=true`；若 `saveFingerObserved=false`，说明该流程没触发 `saveFinger`（那时第 2 点判不了，需要另找判据，不要用 1、3 两点代替）。
3. **fingerGenPrint / fingerGenPrint3 的真实值**：全新 profile 上两者都是**空串**（设备实测：`[finger3] localstorageUtil=absent` → `source=localstorage chars=0`；页面自己的 `getFinger3` 也未回填）。参考实现的默认值同样是空串，所以我们照发空串。**但服务端是否要求它们非空、以及它们是否会参与信任判定，无法在没有真实提交的情况下判断**——真实登记后应核对 `credentialRecord` 里这两个字段是否非空（`describeCredentialRecord` 已有对应日志）。
4. **asset store 在真机（API 24）上的行为**：只在模拟器 Pura 90（API 23）验过。真机复验归 ticket 18 前的一次性复验。
5. **`fingerPrint` 是否真的被服务端当作信任键**：这只能由 ticket 08 的"无短信纯 HTTP 重登成功"来证明。**勾选 `singleLogin` 与注入 `saveFinger` 只是"我们请求了信任"，不等于"信任已授予"**——不要用复选框状态或 XHR 发出就推断 180 天信任已建立。
6. **Web 引擎 cookie 是否真的不落盘**：本轮只在**行为上**清了引擎 cookie（日志 `web cookies cleared`），没有在文件系统层面核对 ArkWeb 的持久化目录；ticket 08 的"检查应用存储中不存在会话数据"应把这半补上。

### 构建缓存坑（本轮踩到，已修，值得留档）

用探针构建跑完"落盘/重启"证据后，`git checkout` 复原 `EntryAbility.ets` 并删除探针文件，再跑 `devecocli build`：**它报 BUILD SUCCESSFUL 且产物时间戳不变（判定 up-to-date）**，而装上去的应用启动即崩：

```
jscrash-com.koracan.learnOH-…-20260912065708.log
Reason: ReferenceError
Error message: cannot find record '&entry/src/main/ets/core/codec/EnrollmentProbe&'，
  please check the request path.'/data/storage/el1/bundle/entry/ets/modules.abc'
```

即**产物里仍带着已删除模块的引用**。修法与判据：
1. 删 `entry/build` 后强制全量重建（本轮 `BUILD SUCCESSFUL in 2 min 48 s` / 之后一次 `41 s`，产物 1,468,839 B @ 07:15:40）；
2. **不看退出码、也不看"BUILD SUCCESSFUL"，而是对产物做字节检索**：`EnrollmentProbe` → false、`TEMP-EVIDENCE` → false、`learnOHEnrollmentBridge` → true；
3. 装上去跑一次，确认 `data.auth.credentials … no persisted credentials` 这类本应用的日志出现（即应用没在启动期崩）。
06:57–07:04 之间采到的截图/日志（探针残留产物）**已全部删除并重采**；本目录现存文件的时间戳都在 07:05–07:22。

### 主要交付文件

`entry/src/main/ets/{core/asset/AssetSecretStore.ets, core/asset/SecretStorePort.ets, core/device/AppIdentity.ets, data/auth/{CredentialStore,EnrollmentSession,AuthSession}.ets, domain/auth/{DeviceIdentity,CredentialRecord,EnrollmentScript,FingerprintDigest}.ets, features/auth/{AuthServices,AuthStore,LoginPage,EnrollmentWebView}.ets}`；改动：`core/http/CookieJar.ets`、`core/web/SessionHeaderProvider.ets`、`pages/Index.ets`、`entry/src/test/List.test.ets`。证据：`.scratch/enrollment/evidence/`（`README.md` 含字节数与 SHA256，`git add -f` 只入 README；`revision.txt`）。一次性探针与脚本：`.scratch/enrollment/tools/`。

### 统筹验收（2026-09-12，模拟器口径）→ Status: verified-partial

**结论：2 条达成、1 条机制已证、1 条部分闭环、1 条待用户操作。不是 `verified`。**

#### 我独立重跑的（在 `982b2eb` 上）

- 单测：删 `entry/.test` + `--no-incremental` → **29 类 TOTAL=207 FAIL=0**（`test_result.txt` 07:26:53 重新生成）；本轮新增类逐类全绿（EnrollmentScript 15 / data.Enrollment 12 / DeviceIdentity 8 / CredentialRecord 7 / FingerprintDigest 6）。
- `check-domain-purity.mjs` PASS（16 个领域文件）；`check-import-graph.mjs` PASS（97 个源文件，WARN **只剩两个入口文件**——`HttpFetchPort` 的孤儿告警确实消失，它现在由 `AuthServices` 装配，终于受常设门禁的编译保护）。
- 工作区干净；`git grep` HEAD 里没有 `EnrollmentProbe` / `TEMP-EVIDENCE` 残留（探针都在源码树之外的 `.scratch/*/tools/`）。
- 证据新鲜度：`.scratch/enrollment/evidence/` 19 个文件，最早 **07:05:20** —— 与"污染窗口 06:57–07:04 已删除重采"一致。

#### 产物级复核：我自己解包 hap 查了内容

你报的"字节检索确认不含探针残留"我**没有直接采信**——**对 `.hap` 直接做字节检索是不可靠的**（zip 条目是压缩的，搜不到会给假阴性，一个真残留也可能"搜不到"）。我把 hap 复制成 `.zip` 解开，在 `ets/modules.abc` 里查：

- `learnOHEnrollmentBridge` → **命中**（当前代码确实在产物里）
- `EnrollmentProbe` → **0 命中**
- `TEMP-EVIDENCE` → **0 命中**

提交态产物是干净的，你"删 `entry/build` 全量重建"的修法有效。

#### 你抓到的构建缓存坑，我已固化进 `AGENTS.md`

这条是本轮最有价值的产出：**`devecocli build` 可以报 BUILD SUCCESSFUL 却给出陈旧产物**——时间戳不变、`modules.abc` 仍引用已删除的探针模块、装机启动 `ReferenceError`。危害在于它是**静默**的：命令成功、门禁全绿、测试全过，只有装机才炸。
我把它写进了门禁节，并提炼出那条推论：**"我把开关翻回 false / 把探针删了并重新构建过"不是证据**；取证态→提交态的转变必须给出**产物级或视觉级**证据。这一条同时回头解释了为什么 ticket 03/04 的收尾截图（`03-final-zh.png`、`04-final-detail-zh.png`）是必要的——它们正是那种"产物级视觉证据"。

#### `singleLogin`：你的升级版我认可

"不设上限轮询重 assert + jQuery 公开 API 的 submit 钩子"，加上 `[submitHook] attached=1` 的自证——正好覆盖了我上一条担心的竞态。你在 Comments 里写明"勾选只是请求信任 ≠ 已授予，端到端证明归 08"，这句边界写对了。

#### 未验证项（我认可，不阻塞）

1. 验收 1（完整登记）——待用户操作。
2. 验收 2 的等式 ②③（`saveFingerXhr` / `persistedReadBack`）——要等用户提交才可能闭合；`saveFingerXhr=empty` 是**预期**。
3. `fingerGenPrint`/`fingerGenPrint3` 在真实提交时是否非空（本轮全新 profile 上页面自己也没回填）。
4. asset 在真机 API 24 的行为（归 ticket 18 前一次性复验）。
5. "服务端确实把指纹当信任键"——只能由 08 的无短信重登证明。
6. ArkWeb 引擎 cookie 的**文件系统层面**不落盘（本轮只在行为上 clear 了）。

#### 两点我要补进记录

1. **指纹每次登记会重新生成**：`formFieldDom` 从上一轮的 `97435e8e` 变成 `d4314739`。这是对的（凭据与本次提交值同源），但要记住一个边界：**若用户在一次已经提交的登记之后才取消/失败，服务端可能已登记了一个我们随后丢弃的指纹。** 我们保证的是"本地无半登记状态"；服务端是否已部分登记不在我们控制内（参考实现同样如此）。这不算缺陷，但要写进已知边界，免得 08 排查时误判。
2. 本轮改动了 `core/http/CookieJar.ets`、`core/web/SessionHeaderProvider.ets`、`pages/Index.ets`（分别是 ticket 06 与 04 的文件）。diff 规模（+55/+23/+29）看起来是必要的扩展（Cookie 头导入、内存单例、认证门）。可以接受，但**这三个文件现在已被三个 ticket 依次改过**，下一个人动它们时要多一分小心。

