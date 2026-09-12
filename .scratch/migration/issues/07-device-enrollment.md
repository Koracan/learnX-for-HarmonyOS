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

#### 后置变更对本条验收的影响（统筹，2026-09-12，ticket 08 提出）

ticket 08 把认证门从「**有凭据** = 已登记（ENROLLED）」收紧为「**有凭据且会话真的建起来** = 已登记」（`AuthStore.loadPersisted` → `start()`，`pages/Index.ets` 改调 `start()`）。这是 08 验收第 3 条的必需项（主壳只能在会话可用时显示），**方向正确**。

它对本文验收第 3 条的影响：
- **结论不变**：本文验的机制（asset 通道写/读回、跨进程持久化）仍然成立，`07-probe-restart-enrolled.txt` 作为**机制证据仍然有效**。
- **复现路径作废**：那条证据用**合成凭据**模拟"已登记启动"。认证门收紧后，同一份合成凭据会让应用真发一次纯 HTTP 重登、失败后**显式回登录页**（这正是 08 要的行为）。所以"重启后显示已登记"这个**可观察量**现在需要一个**真实可用的会话**才能产生。
- 因此验收第 3 条的可观察部分**并入 ticket 08 验收第 1 条**（真实登记后杀进程重启 → 无需输入进主界面），随它一起关闭。
- 替代的复现物是 `.scratch/session/tools/run-session-probe.ps1`；`.scratch/enrollment/tools/EnrollmentProbe.ets` 已就地标记废弃（其引用的 `loadPersisted` 已被重命名，且语义已变——**故意不加兼容别名，因为加别名只会让一个不对的探针看起来还能用**）。

> 这是本工程**第二次**出现"后置 ticket 收紧前提，使已验收 ticket 的证据不再可复现"（第一次是 ticket 04 的 NavPathStack 使 ticket 03 验收第 1 条的证据早于该改造）。两次的处理方式相同：**不推翻当时的判定**（当时确实成立），但**记录边界并写明由谁补**。已验收不是"永不失效"，而是"失效时必须被记录"。



### 2026-09-12 真实登记失败后的诊断与「方案 A」（模拟器实测；**没有**再提交表单、没有消耗短信）

**症状（用户实测）**：用户完成完整登记、短信验证成功，但服务端拒绝授予信任：
「您的浏览器目前处于隐私或匿名模式，系统无法将该浏览器设置为信任浏览器」
（消息键 double_sfjbsbbjwxrsb3，见站点消息字典 /common/public/all-messages.js）。
当时状态行：stage=page fpChars=36 fgChars=0 fg3Chars=0 prefill=11 saveFinger=1 singleLogin=1 roaming=0。
**但 fgChars/fg3Chars 为 0 并不等于"这就是被拒的原因"**——见下。

#### 1. 三条证据

1. **离线 HTTP 探针**：POST https://id.tsinghua.edu.cn/b/doubleAuth/personal/getFinger3 匿名返回
   {"result":"error","msg":null,"object":null}；**带上刚取的登录页 JSESSIONID 再打仍是同一个 error**。
2. **设备诊断（加载期，.scratch/enrollment/evidence/07-diag-prefix-finger3-empty.txt）**：
   - [xhr] req method=POST path=/b/doubleAuth/personal/getFinger3 n=1
   - [xhr] res path=/b/doubleAuth/personal/getFinger3 status=200 chars=59 result=error objectChars=0
   - [diag:env] origin=[https://id.tsinghua.edu.cn] … cookieChars=0 localStorageOk=true indexedDB=object
   - [diag:idb] roundTripOk=true
   - [finger3] source=localstorage chars=0
   - [console] …/login/form/…:0 Uncaught (in promise) #<Object>
   页面自己的 getFinger3() 在**未登录会话**上必然 reject，两个字段永远填不上。
   **这是站点对"全新浏览器"的固有行为**（站点另有专门文案 double_finger_whqdzwxx =「未获取到指纹信息」，
   我们拿到的不是那一条）⇒ 不是我们能修的缺陷，也很可能不是被拒的原因。
3. **逐字段对比**：stock 浏览器提交那一刻是 fingerPrint=fingerprintjs2 的 **32 位十六进制**、
   fingerGenPrint=fingerGenPrint3=''、deviceName=other,Chrome/132、singleLogin=用户勾选。
   我们除了 singleLogin（按站点本意勾上）之外，**唯一不同的一栏就是 fingerPrint**。

#### 2. 两条嫌疑判死（含我自己的探针误读）

- **"我们的 XHR patch 弄坏了 jQuery 的 $.post"——判死**：请求确实发出并拿到响应，失败来自服务端 result=error。
- **"ArkWeb 没开 databaseAccess ⇒ localforage 写不进去 ⇒ 匿名模式"——判死**：diag:idb roundTripOk=true。
  **ArkWeb 里 IndexedDB 在 databaseAccess 默认 false 时依然可用**（那个开关管的是老的 Web SQL Database）——
  已写进 docs/reference-quirks.md 第 11 条【平台事实】。
- **自我更正**：diag:lf localstorageUtil=absent 是**探针时机**（document-start 时 <head> 的脚本还没定义全局），
  不是"站点对象不存在"；同一轮 load 期的调用正常。**探针本身也要能自证**，否则会生产假结论。

#### 3. 方案 A（统筹批准；推翻 b511a2f 里"页面值不可用"那条推理）

**生效指纹 = 页面自己算出的 fingerprintjs2 值**；只有页面没给出值时才用我们的 UUID 兜底。
三处同值：表单字段、saveFinger 的 XHR、凭据落盘与重登回放。**store-and-replay**：登记值与重登出示值
仍逐字相同（**不需要复算**页面值）。

加载期证据（07-planA-prefix.txt + 截图 07-planA-prefix.png）：
- [dom values] fingerPrintChars=32 … fpSource=page f3Remote=0 singleLogin=true
- [fingerprint digest] point=formFieldDom value=746a15a2 point=saveFingerXhr value=empty
- [finger3] source=localstorage chars=0 -> tryRemote
- [finger3] remote rejected object result=error keys=[result,msg,object] message=[]
- [summary] … fingerPrintSource=page … diag=0

状态行：stage=page fpChars=32 fpSource=page f3Remote=0 singleLogin=1（**32** = 页面值；此前 36 = 我们的 UUID）。
另外脚本现在**自己**调 getFinger3FromRemoteAndSave() 并把结果写进两个 DOM 字段（不再依赖页面那条 promise 链），
并在提交前再断言一次。

#### 4. 提交前自检（新增防线；判定收窄过一次）

- 原要求"fg3Chars==0 就拦"会把**每一次首登都拦死**（对全新浏览器为空是站点固有行为）⇒ 统筹同意收窄为：
  **只在"远端确实拿到了值、而 DOM 没接住"时拦**（finger3RemoteOk===1 && (fgChars===0||fg3Chars===0)）。
- 拦与不拦**都打日志**：submitGate allowed=1 reason=finger3Ready|firstEnrollmentEmptyFinger3|finger3Unavailable、
  preSubmitGate blocked=1 reason=domMissedRemoteValue——否则将来分不清"判定为常态"与"门槛失效"。
- 拦住的手段是 jQuery submit handler 里的 event.preventDefault()（阻止 jQuery 默认动作=原生 submit），**不是猴补丁**。
  单测 3 条：allowsTheFirstEnrollmentWhenTheSiteFingerprintsAreEmpty、
  blocksOnlyWhenTheRemoteValueWasObtainedButTheDomMissedIt、keepsTheGateStateInTheValuesBridge。
- **边界**：这两行运行时日志只在真正点提交时才会出现；本轮只验了脚本内容与协议解析。

#### 5. 下一次真实提交 = 一次实验（用诊断开关打开的构建）

- 诊断已记录**每个 XHR 的 req/res**；saveFinger 另有 saveFingerRequest 报告，只记**参数名与长度**
  （fingerprint/deviceName/radioVal 是否都在、body 是 URL 编码表单还是别的形态）。
- 判读：saveFinger **没发出** ⇒ 站点没走到登记那一步；**发出但被拒** ⇒ 问题在它的 body/参数
  （对照 sso.js 注入的三项逐项比）；A 成功 ⇒ 根因确认。
- 实验构建与提交态分开出；实验前工作区必须是已提交的干净态，实验后再按 AGENTS.md 做**产物级**复核。

#### 6. 有意偏离与台账（已按统筹要求登记）

- docs/reference-quirks.md **第 10 条（已复审）**：fingerPrint 取页面值（参考实现两处都写自己的值）；
  替代验收标准 = 验收第 2 条的**三点等式判据不变**，只是那个值来自页面。
- docs/reference-quirks.md **第 11 条（平台事实）**：IndexedDB 与 databaseAccess 的真相 +
  javaScriptOnDocumentStart 的时机坑（不构成保真约束）。
- docs/adr/0004 正文仍写"我们生成的设备指纹"，需随本 ticket 复核。

#### 7. 对 ticket 08 的影响（改前提要在两边留边界）

重登出示的 fingerPrint 现在来自**登记时页面算出的值**（store-and-replay），不再是我们的 UUID。
08 的调用契约不变（它只从凭据库取值），但**不要假设它是 UUID 形状**（旧的长度/形状断言会失效）。

### 2026-09-12 docs-only 更正：方案 A 的正当性来自「实测失败」，不是「更忠实于参考」

统筹复核参考实现源码时读出我之前读漏的一段：**参考自己也生成随机 UUID**——
`SSO.tsx:33-39` 的 `Math.random` UUID → `SSO.tsx:51` 注入脚本 → `sso.js:66` 写 `#fingerPrint`、
`sso.js:24` 写 `saveFinger` 的 XHR → `SSO.tsx:76` 再**回读表单实际提交的值**存为凭据。所以：

- 我先前写的「方案 A 更忠实于参考正文那句 fingerPrint 直接读 DOM」**不成立**——参考写的是它自己的值，
  与 stock 浏览器同样不一致（36 字符 UUID，形状与我们改造前一模一样）。
- 方案 A 的正当性只有一条：**参考那套在当前站点上实测失败**（2026-09-12 用户那次），
  且站点脚本带版本戳 `v=20260830062616`（2026-08-30 改版），晚于参考实现。

已把这段更正写进 `docs/reference-quirks.md` 第 10 条，替代验收标准明确为：**提交报文里的 fingerPrint
必须等于页面 fingerprintjs2 的值**（页面没给出值才用我们的 UUID 兜底），且三处同值（三点等式判据不变）。

另记两条：

1. **事实（不是偏离）**：`/b/doubleAuth/personal/saveFinger` **在登录页加载的任何脚本里都不存在**
   （把抓下来的全部站点脚本搜过；此前看到的 "saveFinger" 都是 `saveFinger3Local`/`saveFinger2Local` 的子串）。
   只能确定「登录页不调它」；用户看到的失败发生在「二次验证成功」**之后**那个本工程尚未抓到的页面，
   所以**它仍可能在那里被调用**。⇒ 实验里若诊断日志**没有** `saveFingerRequest`，那是**一条信息**
   （信任登记不走这个端点），**不是 bug**，不要去修。
2. **另一处已知偏离（本次实验不动）**：`deviceName` 参考是 `HarmonyOS,learnOH/{packageJson.version}`
   （`SSO.tsx:52`），本工程是 `HarmonyOS,learnOH/{versionName} ({productModel})`
   （`core/device/AppIdentity.ets:4`，依据 spec 第 5 节）。实验一次只动一个变量：deviceName 不改，
   但两个值（页面 DOM 里的与我们的）都会进日志，便于事后判断服务端看到的是哪一个。

### 2026-09-12 失败根因（已复核）+ 取证环境变更

**根因**：站点二次验证页内置的 `detectIncognito@1.5.1` 在 ArkWeb 上误判隐私模式——判据是
`Math.round(quota/1MB) < 2*Math.round(jsHeapSizeLimit/1MB)`，6 GiB 数据分区时 ArkWeb 报 `quota=3504MB`
而阈值 `2×2089MB=4178MB` ⇒ `isPrivate=true`；该页在 isPrivate 时**只渲染 `type=否`，「信任」选项根本不出现**。
与我们的注入无关：判据只用引擎上报的两个数；那次会话三次 `/b/doubleAuth/login` **全部 result=success**、
**没有 saveFingerRequest**、**没有 roaming**；方案 A 的 `fpSource=page` 已生效。台账：`reference-quirks` 第 12 条。

**请留档的推论**：**参考实现在这台模拟器上今天同样会失败**（它写不写自己的 UUID 都不影响这个判据）。

**离线验证（没有花短信）**：把模拟器数据分区 6 GiB → 16 GB 后，同一登录页探针读到
`quotaMb=9347 > thresholdMb=4178` ⇒ **`isPrivateByChromeRule=false`**。修复（环境）已被验证。

**决策留档**：**不实现**「把 `queryUsageAndQuota`/`storage.estimate` 包一层上报假配额」的代码层修法——
那是欺骗站点的反欺诈启发式，且只对小分区测试环境有意义（真实设备天然满足）。

**取证环境变更**：模拟器 Pura 90 的 `hw.dataPartitionSize` 6144→16384、`disk.dataPartition.size` 6g→16g、
`isCustomize` false→true；改前副本与一键回退见 `.dsh/logs/emulator-backup/`（含 SHA256 与 RECOVERY.md）。
**此前所有模拟器证据都出自 6 GiB 的旧配置**；`/data` 由 `5.7G/4.4G avail` 变为 `15G/14G avail`。
因数据分区重建，guest 数据被清空（应用需重装；设备侧 hilog 已全部取回）。

**下一轮取证缺口**：cookie 观测只有 `cookieChars=0`（两份文档 document-start）与 `web cookies cleared`，
谁下发什么、漫游带什么全无——若还要用户再跑一次，那一次必须能回答「信任登记到底靠什么落地」。

**未验证**：配额够了之后站点是否真的授予信任（仍需一次真实提交）；真机上该检测器是否自然通过（预测会，未验证）。
