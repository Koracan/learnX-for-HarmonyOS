# 08: 保持登录 + 自动重登 + 降级

**What to build:** 冷启动时用持久化凭据静默重建会话，用户无需任何输入；任何非预期结果（含信任过期被服务端拒绝）都显式降级到登录页，而不是静默失败或停在加载态。

**Blocked by:** 05（移植数据处理器 + 解析单测）、07（设备登记 Enrollment）

**Status:** verified-partial —— 验收第 1 条**通过**（模拟器口径；代码在 `fe3a473`，统筹已独立复验）；第 4 条将由 ticket 09 的真实取数自然关闭；第 2、3 条（断网启动 / 信任过期降级）仍欠设备侧实操，排到 ticket 09 之后的一轮「会话生命周期」；真机（API 24）留给 ticket 18 之前。见 Comments 末尾「统筹验收（第三轮）」。

- [x] 杀掉应用重启后无需输入即进入主界面，日志证明会话由纯 HTTP 重建 —— **2026-09-12 用真实凭据在模拟器上实测：通过**（第一轮 `no ticket anchor` 失败 → 定位 cookie 吸收 + 修复 → 第三轮 `restore: session rebuilt via pure HTTP (no webview)`；见 Comments 末节三轮记录）。**真机（API 24）未验证**，留给 ticket 18 之前的一次性复验

- [ ] 断网启动不卡在加载态，给出可理解提示；网络恢复后重试能成功
- [ ] 会话失效或信任过期时显式回到登录页并说明需要重新验证，不出现空列表
- [ ] 并发请求只触发一次重登，不重复登录
- [ ] 会话 cookie 不落盘（检查应用存储中不存在会话数据）
- [ ] 真机截图（正常重启 + 降级到登录页）

## Comments

### 实现与门禁（2026-09-12，模拟器口径 / 提交见汇报）

**交付清单**（新增，或对既有文件的扩展；**没有重写 06 的任何机制**）：

| 文件 | 作用 |
| --- | --- |
| `data/auth/SessionRestore.ets`（新） | 冷启动会话重建的唯一出口：`SessionRestorer`（**已有会话直接复用** + 06 的 `ReAuthCoordinator` 单飞 + 整体超时 + 失败分类）+ `AuthedTaskRunner`（数据路径：先确保会话 → `SessionGate` 包任务 → 把"重登后仍失效 / 任何失败"翻成 `requiresEnrollment`）+ `credentialsFor`（凭据记录 → 登录表单字段的**唯一**映射） |
| `data/auth/AuthTypes.ets`（扩展） | 新增 `FailReason.NETWORK_UNREACHABLE`（"平台没拿到任何响应"，status=0）与 `isNetworkFailure()`；**既有分类的字符串值未动** |
| `data/auth/LoginClient.ets`（扩展） | 四个请求点（登录页 / 登录检查 / 漫游 / 课程列表）先判网络失败再判业务失败：断网不再被说成"登录页改版 / 取不到票据" |
| `data/auth/AuthSession.ets`（扩展） | `forgetSession()`：只丢会话、保留内存凭据（重试仍要凭据） |
| `features/auth/AuthServices.ets`（扩展） | 装配 `LoginClient`（jar 共用 `AuthSession` 那一个）+ `loginFromStoredCredentials`（**唯一 re-auth 出口**：成功才 adopt 会话，并同步 Web 会话注入点）+ `restorer` / `runner` |
| `features/auth/AuthStore.ets`（扩展） | `start()`（原 `loadPersisted`）：读凭据 → 纯 HTTP 静默重登 → 主壳；`retryRestore()`（用户手动重试，**一次动作一次尝试**）；`onSessionLost()`（运行期失效降级，给 ticket 09 接）；新增 `AuthFailure.REAUTH / OFFLINE`、`busy`、`restoreDiagnostic` |
| `features/auth/LoginPage.ets`（扩展） | REAUTH / OFFLINE 各自的可理解文案 + **重试按钮**（只在"有凭据但这次没登上"时出现）；重试进行中禁用登录按钮并显示"正在登录" |
| `pages/Index.ets`（改一行） | `loadPersisted()` → `start()`；注释更新（LOADING 现在含一次纯 HTTP 重登） |
| `entry/src/test/SessionRestore.test.ets`（新，18 条） | 四类分类、会话短路、并发单飞、整体超时、断网后重试成功、任务层并集、**重登后仍 '[]' → 显式降级**、重试用刷新后的会话、秘密存储零写入等 |
| `entry/src/test/List.test.ets`（改） | 注册新测试类 |
| `scripts/generate-i18n-resources.mjs`（扩展）+ 6 个生成物 | 新增 3 个本地键：`loh_session_expired` / `loh_network_unavailable` / `loh_retry`（参考实现没有对应文案，因为有意的差异就是"不再静默失败"） |
| `docs/reference-quirks.md` 第 2 条（改判） | 见「与参考实现的有意差异」 |
| `.scratch/session/tools/{SessionProbe.ets,run-session-probe.ps1,README.md}` | 一次性设备取证探针（**合成凭据** → 冷启动纯 HTTP 重登 → 抓 hilog/截图 → 杀进程扫存储 → clear → 复原 + 全量重建 + 解包产物级检查）；`.scratch/.gitignore` 加 `session/evidence` |

### 逐条验收

| # | 验收项 | 结论 | 证据 / 待办 |
| --- | --- | --- | --- |
| 1 | 杀掉应用重启后无需输入即进入主界面，日志证明会话由纯 HTTP 重建 | **代码 + 单测达成；设备侧待用户登记** | 单测 `restoresASessionFromPersistedCredentials` / `singleFlightsConcurrentColdStartRestores`；静态：re-auth 路径（`data/auth`、`data/remote`、`core/http`、`core/crypto`）**零 ArkWeb import**，全工程只有 `data/remote/HttpClient.ets` 引 `@ohos.net.http`。设备日志判据：`startup: restoring session from persisted credentials (pure HTTP, no webview)` → `login: id form ok …` → `restore: session rebuilt via pure HTTP (no webview)` → `startup(startup): session rebuilt via pure HTTP, zero webview`。**需要一次真实登记**（用户手动短信），未做。 |
| 2 | 断网启动不卡在加载态，给出可理解提示；网络恢复后重试能成功 | **单测达成；设备侧断网未实操** | 单测 `classifiesANetworkFailureAsOffline` / `timesOutInsteadOfHangingInTheLoadingState`（20ms 注入超时）/ `succeedsWhenTheUserRetriesAfterTheNetworkComesBack`。界面：`loh_network_unavailable` + 「重试」按钮（`retryRestore` 一次动作一次尝试，无静默循环）。**未实操理由见「未验证项 2」**。 |
| 3 | 会话失效或信任过期时显式回到登录页并说明需要重新验证，不出现空列表 | **达成（注入式 + 代码可见）** | `applyRestoreResult` 的失败支只有两条出口（OFFLINE / REAUTH），没有任何"失败兜底"分支；`AuthedRunResult.fromGate` 把 `sessionLostAfterReAuth` 翻成 `requiresEnrollment=true` 且**不把 '[]' 往上传**。单测：`classifiesServerRejectionAsExplicitDegradation` / `degradesWhenTheListIsStillEmptyAfterReAuth`（断言 `value === ''`）/ `degradesOnLoginTimeoutAndRetriesOnlyOnce` / `treatsANetworkFailureInsideATaskAsDegradationNotAsAnEmptyList`。文案 `loh_session_expired` =「登录状态已失效，需要重新验证。」。**设备截图待用户登记**（当前服务端已明确拒绝授予信任，这条路径是最可能发生的那条）。 |
| 4 | 并发请求只触发一次重登，不重复登录 | **达成（单测）** | `singleFlightsConcurrentColdStartRestores`（5 并发 restore → 1 次登录）、`singleFlightsConcurrentRequestsIntoOneReAuth`（热会话后 5 并发任务同时失效 → 总登录数正好 2：1 冷启动 + 1 重登）、`reusesTheInMemorySessionWithoutLoggingInAgain`（已有会话不再登录）；06 的 `singleFlightsConcurrentReAuths` 未改动。 |
| 5 | 会话 cookie 不落盘（检查应用存储中不存在会话数据） | **单测 + 静态达成；设备存储扫描待设备窗口** | 单测 `keepsTheRestoredSessionOutOfAnyPersistentStore`（恢复全过程 `FakeSecretStore.writes` 不变，存储里 0 个 `JSESSIONID` / `TOKEN` / `csrf`）；`keepsTheCookieJarAndTheSessionInMemoryOnly`；静态：`data/auth/**` 无 preferences / 文件 / asset API（只出现在注释里），`JSESSIONID` 在 main 源码里只出现在 `core/http/CookieJar.ets`（内存 jar）。设备扫描命令与判据见「未验证项 3」。 |
| 6 | 真机截图（正常重启 + 降级到登录页） | **未达成** | 都需要先有一次真实登记；且按 `spec.md` 第 8 节口径，真机未接入期间**用模拟器取证并注明真机复验仍欠**。 |

### 未验证项（判据可复核，不要当成"应该没问题"）

1. **真实登记后的冷启动纯 HTTP 重建（验收第 1 条 + 第 6 条的正常重启截图）** —— **待用户登记**。
   关闭方式：用户完成一次登记（ticket 07 的登录页 → 网页里短信验证）→ 冷启动应用 → 看 hilog：
   `data.auth.credentials credentials loaded` → `data.auth.restore restore: silent re-auth #1 starting (pure HTTP, no webview)`
   → `data.auth.restore restore: session rebuilt via pure HTTP (no webview)` → `features.auth.store startup(startup): session rebuilt via pure HTTP, zero webview`，
   且**新 PID** 的界面直接是五 tab 主壳（无登录页）。失败时的判读出口：`restore: NOT rebuilt kind=rejected reason=… diag=…` 后跟 `-> login page (re-verification required)`。
2. **设备侧断网（验收第 2 条的一半）** —— **未实操，理由**：模拟器 `Pura 90` 上没有可靠的"关网络"手段（`svc wifi` / `ip link set` 需要 root，且会同时影响正在用同一台设备做登记的其他人），
   所以我**没有假装测过**。该分支由注入口覆盖：`LoginClient` 收到的注入响应是 `{ok:false, status:0}`（与设备侧 `HttpClient.failure` 同形状），
   单测 `classifiesANetworkFailureAsOffline` / `timesOutInsteadOfHangingInTheLoadingState` / `succeedsWhenTheUserRetriesAfterTheNetworkComesBack` 逐条断言。
   **"网络恢复后重试能成功"只在注入端口上验过，设备侧未验**。
3. **设备存储里的会话数据扫描（验收第 5 条）** —— **待设备窗口**。命令与判据已就绪（`.scratch/session/tools/run-session-probe.ps1`）：
   用**合成凭据**让应用真发一次纯 HTTP 重登（有网络时内存 jar 里会有一个**真实** `JSESSIONID`，日志 `login: id form ok … jar=cookies=N names=[…]`），
   然后 `aa force-stop` 并在 `/data/app/el2/100/{base,database}/com.koracan.learnOH` 上
   `grep -ra -E "JSESSIONID|SERVERID|CASTGC|TGT-|_csrf|csrfToken"` 应为 **0 命中**。
4. **服务端是否把 `fingerPrint` 当信任键** —— 只能由一次无短信的真实重登证明；本轮服务端**明确拒绝**授予信任（ticket 07 现场观测：隐私/匿名模式告警、`fgChars=0 fg3Chars=0`），所以验收第 1 条的设备侧现在还**不可能**通过。
5. **真机复验** —— 归 ticket 18 前的一次性复验（`spec.md` 第 8 节 / 第 11 节 #7）。

### 与参考实现的有意差异（均已登记）

1. **重登后仍返回 `'[]'` 时显式降级（不出现空列表）** —— 参考实现的原生路径会把它静默交给调用方（界面表现为空列表）。
   已按 AGENTS.md 的要求**先改台账再改代码**：`docs/reference-quirks.md` 第 2 条从「锁定（并已知其缺口）」改判为「**已复审**（触发并集仍锁定；「重登后仍 `'[]'`」这一支在 ticket 08 收口）」，并写明替代验收标准（单测 `degradesWhenTheListIsStillEmptyAfterReAuth`）。
   **触发条件那条一个字没动**：`SessionGate`（06 交付）未改一行语义，'[]' ∪ 403/login_timeout 的并集与"只重试一次"原样保留；偏离只发生在**调用方**（`AuthedTaskRunner`）对 `sessionLostAfterReAuth` 的处理上——而那个标记正是 06 留给"日后升级为 Enrollment"的口子。
2. **新增 `FailReason.NETWORK_UNREACHABLE`** —— 参考实现把网络失败与"页面改版/被拒"混在同一个出口（拿不到票据就是 `ERROR_FETCH_FROM_ID`）。
   单列一类的理由是**可行动性**：验收第 2 条要求断网给"检查网络"的提示，混在一起就永远走不到那条文案。既有分类的字符串值未改。
3. **`ENROLLED` 的含义收紧**：ticket 07 是"有凭据即已登记"，本 ticket 是"有凭据**且**会话已建立"。理由是验收第 3 条禁止空列表——主壳要发真实请求，不能带着不存在的会话渲染。
   **副作用**：07 那条"合成凭据重启后仍已登记"的**复现脚本**随之作废（其"asset 通道写/读回、跨进程持久化"的**机制证据仍然有效**）。详见下一节。
4. **不做 Mock / 空列表兜底**：`applyRestoreResult` 的失败支只有 OFFLINE / REAUTH 两条出口，代码里没有任何"抓不到就给空集合"的分支——这正是派单里点名的反模式。

### 单测抓到的一个真 bug（值得留档）

第一次跑单测时 `treatsANetworkFailureInsideATaskAsDegradationNotAsAnEmptyList` 失败。根因：06 的 `ReAuthRunResult.failure` **也**会把 `sessionLostAfterReAuth` 置 true（失败与"重登后仍失效"共用一个字段），
而我的 `AuthedRunResult.fromGate` 先判 `sessionLostAfterReAuth` 再判 `ok`，于是**所有登录失败都被误判成 `NOT_LOGGED_IN`**，断网（`NETWORK_UNREACHABLE`）永远走不到"检查网络"那条文案。
修法：先判 `!result.ok` 透传真实原因，再判 `sessionLostAfterReAuth`。这条在代码阅读时看起来完全合理，只有单测能揭出来。


### 与参考实现的逐行对照（`reference/learnOH-old/src/data/source.ts` 实读，不是转述）

| 参考实现 | 行号 | 本实现 | 等价性 |
| --- | --- | --- | --- |
| 登录前 `clearLoginCookies()`（`clearAll(true)` + id 域 `JSESSIONID` 置空） | `:11-28, 37` | `LoginClient.login()` 第 1 步 `jar.reset()` + `resetIdDomainSession(ID_ORIGIN)` | 等价（内存 jar 版；不依赖"反正空着"） |
| provider 从 store 读凭据（`state.auth.*`） | `:60-69` | `AuthServices.loginFromStoredCredentials()` ← `CredentialStore.load()` | 等价；**读盘归 features**，`LoginClient` 只接收入参（06 的边界） |
| 自定义 fetch 强制桌面 Chrome UA | `:55-57` | `LoginClient.headersFor()` 用 `Requests.USER_AGENT`（逐字相同） | 等价；06 的单测断言**每个**请求都带它 |
| `if (result === '[]')` 精确字符串比较 | `:104` | `LoginParsers.isEmptyListResult(body)`（`body === '[]'`）经 `SessionGate` | 等价（**未改语义**） |
| 单飞 `reAuthPromise` | `:87, 111-121` | `ReAuthCoordinator.ensureSession()`（06 交付） | 等价；`SessionRestorer` 复用同一个 coordinator，**没有第二个 inFlight** |
| 重登后**重新取** cookie/token 再重试一次 | `:123-124` | `AuthedTaskRunner` 的闭包每次取 `currentSession()`（重登后是刷新过的会话） | 等价，且更强（单测 `retriesOnceWithTheRefreshedSessionWhenTheResultIsAnEmptyList` 断言第二次用的是新 cookie） |
| 只重试一次、无循环 | `:121-129` | `SessionGate.run()`（06） | 等价 |
| **缺口**：服务端直接拒绝不会返回 `'[]'`，这条路径不重登 | `:104` 之外 | 并集：`403` ∪ URL/响应体含 `login_timeout`（thu-learn-lib `:21, 46-71`） ∪ `'[]'` | **补齐**（台账第 2 条的"更正与补强"；台账已登记的既有语义） |
| **缺口**：重登后仍是 `'[]'` 时静默返回空列表 | `:104-131` | `sessionLostAfterReAuth` → `requiresEnrollment=true`，值不上传 | **有意偏离**，已改台账第 2 条为"已复审"并写明替代验收（见上） |
| 参考实现**没有**"冷启动静默重建会话"的独立入口（靠 `provider` 在请求时惰性登录） | — | `SessionRestorer.restore()` 在 `AuthStore.start()` 里显式跑一次 | **新增**（验收第 1 条要求的可观察时机；登录机制本身逐行照搬） |

### 与 ticket 07 的边界（会作废它的一条复现脚本）

- `AuthStore.loadPersisted()` 更名为 `start()`：07 的 `.scratch/enrollment/tools/EnrollmentProbe.ets` 调的是旧名，**我提交后它编译不过**。我没有加兼容别名——即使名字兼容，它的**语义也已作废**（同一条合成凭据现在会去真发一次重登并显式回登录页），加别名只会让一个已经不对的探针看起来还能用。
- 07 验收第 3 条的**结论**仍然成立（asset 通道 + 跨进程持久化）；作废的是"用合成凭据模拟已登记启动"这条复现路径。新的复现入口是 08 的 `run-session-probe.ps1`（它证的是 08 自己的断言）。
- 07 的 `ENROLLMENT_DIAGNOSTICS_FOR_EVIDENCE` 在其诊断期间为 `true`，会让他自己的 `shipsWithTheDiagnosticsSwitchOff` 失败——这是**他**的取证状态，不是 08 的回归。
- 按 AGENTS.md「改动一条已被已验收 ticket 依赖的前提时，必须在两边都留下边界说明」与统筹的授权，我在**本提交**里给那两个已入库的 07 工具文件各加了一段**文件头废弃说明**（只改文件头，不动其它内容）：
  `.scratch/enrollment/tools/EnrollmentProbe.ets` 与 `run-enrollment-probe.ps1`——写明"模拟已登记启动"这条路径已被 08 的认证门作废、可运行的替代物是 `.scratch/session/tools/run-session-probe.ps1`、旧命令不要照抄。
  这是"改接口的人负责处理调用点"的例外；**07 的其它文件（`EnrollmentScript.ets` / `EnrollmentWebView.ets` / `.test.ets` / `i18n-ui-strings.mjs`）我一行未动**。

### 取证计划（设备窗口，命令已就绪）

设备是**模拟器 Pura 90**（`127.0.0.1:5555`，HarmonyOS 6.1.0(23)）。`pwsh -File .scratch/session/tools/run-session-probe.ps1` 一次跑完：
seed（**合成**凭据，日志自证 `syntheticCredentials=1 (NOT a real account)`）→ 冷启动（纯 HTTP 重登 + 降级）→ 抓 hilog + 截图 →
杀进程 → 扫应用存储 → clear → 复原探针 → **全量重建** + 解包 `ets/modules.abc` 内容检索（`SessionProbe=0 / TEMP-EVIDENCE=0 / SessionRestorer>0`）+ 装机确认提交态正常。
本目录（`.scratch/session/evidence/`）只入 `README.md`（含字节数与 SHA256，`git add -f`）；`gitignore` 已加 `session/evidence`。


### 测量口径更正 + ticket 08 提交点门禁（本次，2026-09-12）

**这条是给 ticket 07 那次「232 条单测」的边界说明（AGENTS.md「改动一条已被已验收 ticket 依赖的前提时，必须在两边都留下边界说明」）。**

- 07 ticket 里那个 **232** 出自 `entry/.test/default/intermediates/test/coverage_data/test_result.txt` 的最后一行，
  **不是**日志里的行——`hvigorw test` 的日志里没有 `Tests run`；看日志判条数会误判。
- 关键：那次运行是在**脏工作区**上做的，而工作区里已经含有**本 ticket（08）尚未提交**的
  `entry/src/test/SessionRestore.test.ets`（18 条）。所以 **232 是「07 + 08 脏工作区」的数**，
  **提交 `0324d43` 单独的门禁数从未被测量过**。
- 本次（08 的提交点）：先把 ticket 08 的全部改动放在工作区里，删 `entry/.test` + `--no-incremental` 重跑，
  测得 **232 条**（`Tests run: 232, Failure: 0, Error: 0, Pass: 232, Ignore: 0`，
  `test_result.txt` 时间戳 2026-09-12 08:43:33.637）。这是仓库第一次把「测出来的数」与产物**内容级**对齐核对：
  解包 `ets/modules.abc` 可搜到 `SessionRestorer` / `AuthedTaskRunner` / `credentialsFor` /
  `restore: session rebuilt via pure HTTP (no webview)`，说明这 232 里确实含 08 的模块。
- **需要如实标注的一点**：本 ticket 的代码在测量时仍在工作区里（未提交），
  因此这次测得的 232 与 07 那次 232 是**同一个口径**（都含 08 的 18 条）。
  本次**没有**用 `git stash` 去测「`0324d43` 裸 HEAD 的 214 条」——
  `stash` 会改动共享工作区，而当前工作区里还有别的 agent 未提交的文件，风险大于收益。
  因此「`0324d43` 单独 = 214」是**由差集推出的、未实测**的数；07 那个 232 的可信区间就是**「含 08 的 232」**。
- 本 ticket 提交后，08 的 18 条测试随代码一起入库，后续任何人再跑门禁都会得到 232 —— 数字巧合一致，
  但**口径**已经变了（从此 232 = 期望值，且产物内容级核对证明 08 的模块在产物里）。

### 2026-09-12 冷启动复验（**真实凭据**，模拟器）：验收第 1 条 **未通过** —— 失败在"票据解析"，不在信任

**这一节是 ticket 07 第 4 次真实登记（免短信成功）之后，用**真实**凭据做的冷启动复验。**
完整归因见 `.scratch/migration/issues/07-device-enrollment.md` 的 Comments「第 4 次真实登记」第 8 节；此处只记结论与复现。

**复现命令（设备窗口，模拟器 Pura 90 / `127.0.0.1:5555`）**

```powershell
# 前置：用户已完成一次真实登记（ticket 07），凭据已落 asset store
hdc -t 127.0.0.1:5555 shell "hilog -w start -f learnoh_cold2 -l 8M -n 20"
hdc -t 127.0.0.1:5555 shell "aa force-stop com.koracan.learnOH"
hdc -t 127.0.0.1:5555 shell "aa start -a EntryAbility -b com.koracan.learnOH"
Start-Sleep -Seconds 35
hdc -t 127.0.0.1:5555 shell "hilog -x -D 0x4C4F" | Select-String 'restore|reauth|re-auth|startup'
```

**实测结果（提交态产物，PID 3802 @12:13:31；armed 构建 @12:11:50 逐字相同）**

```
12:13:31.629 W [features.auth.services] re-auth session NOT adopted: reason=no ticket anchor in id login check response diag=no ticket anchor: status=200 bytes=1280 idLoginPage=false doubleAuthMentions=0
12:13:31.630 W [features.auth.store] startup(startup): session NOT rebuilt kind=rejected reason=no ticket anchor in id login check response offline=false -> login page (re-verification required)
```

界面：登录页 + 红字「登录状态已失效，需要重新验证。」（截图 `07-coldstart-commit.png`，SHA256 `EBBA49EE…`，在
`.scratch/enrollment/evidence/experiment-success/`）。**没有**出现短信页、**没有**空列表（降级本身是**对的**，符合本 ticket 验收第 3 条）。

**判定**
- **验收第 1 条未通过**：`restore: session rebuilt via pure HTTP (no webview)` 从未出现。**不要勾选。**
- 失败点在 `LoginClient` 第 4 步 `extractTicket`（`data/auth/LoginParsers.ets:41-61`）——取不到票据 ⇒ `NO_TICKET_IN_RESPONSE`。
  解析器与参考实现**逐字一致**（`bundle.harmony.js` @2044751 的 `getRoamingTicket`：首个 `<a href>` → 最后一个 `=` 之后）。
- **站点这次没有要求短信**（`doubleAuthMentions=0`、`idLoginPage=false`），所以 `singleLogin='on'` 的信任**看起来**是生效的；
  但"纯 HTTP 能否在信任期内重登"这件事**目前不成立**。
- 这条**打在 ADR-0004 的前提上**：`docs/adr/0004-browser-enrollment-plus-http-reauth.md:5` 写「站点信任机制以设备指纹为键，因此信任期内可以纯 HTTP 重登」——
  现在证据显示已信任分支的 `/login/check` 返回的是一张**由站点 JS 驱动的页**（`scripts=[jquery.min.js, localstorageUtil.js, genprint.js]`、`formAction=none`、无 `<a>` 锚点）。
  该 ADR 第 7 行同时**否决过**"隐藏 WebView 静默重登"。⇒ **先分清 W1/W2（票据是否仍在 HTTP 响应里）再决定改代码还是改 ADR**，判别计划见 ticket 07 的 Comments。
- **保留本 ticket 的一条改判**：「与参考实现的有意差异」第 3 条（`ENROLLED` 收紧为"会话已建立"）**本身没问题**，
  它把"凭据在、会话不在"变成**可复现的登录页**——正是本轮观察到的状态，应当保留。

**边界（AGENTS.md「改动一条已被已验收 ticket 依赖的前提时，必须在两边都留下边界说明」）**：
本 ticket 验收第 3 条（显式降级）的证据在本轮由**真实凭据**强化（不再是注入式）——降级动作正确；
但第 1 条的证据是**反向**的：一次真实冷启动实测失败。请统筹按此重排本 ticket 的状态。

### 统筹：状态改为 in-progress（2026-09-12，W1/W2 探针轮）

- 验收第 1 条**未通过**已确认（我复核了 `.dsh/logs/cold-commit-appdomain.txt:39-42`：提交态产物复现、与 armed 构建逐字同因，**不是**探针污染）⇒ 本 ticket **不再是** `ready-for-agent`，而是**重新进入取证/实现**。
- 正在跑**只读探针轮**：把 `/login/check` 那张 1280 字节响应的正文（含 inline script）落进 hilog，并跟一跳，用来判别 **W1**（跳转信息在 HTTP 正文里 ⇒ 纯 HTTP 路线成立，补解析即可）还是 **W2**（票据由站点 JS 运行时生成 ⇒ 必须改 ADR-0004，属决策变更，需用户签字）。
- **W1/W2 判清之前不许改 `extractTicket()`**：在 W2 下放宽解析不会让它工作，却会让"取不到票据"这个**正确的失败信号**消失。
- 触发方式：装探针构建后**冷启动一次** —— 应用自己的 `SessionRestorer` 会发出**唯一一次**登录 POST，那就是探针；不需用户动手机、不走登记、不发短信。

---

### 第二轮：cookie 吸收修复（2026-09-12，模拟器口径）—— 先证明「我们发出去的请求是完备的」

**这一轮的转折**：W1/W2 探针（armed 构建，HEAD `66a06e3`）证明**原前提是错的**——
纯 HTTP 的 `POST /do/off/ui/auth/login/check` 拿回来的那张 1280 字节页**不是** genprint 页
（`anchorTag=0 · scriptTag=0 · formTag=0 · candidateUrlCount=0 · inlineScriptCount=0`；
形态是 GBK 通用报错页 + `window.close()` 按钮）。⇒「跳转指令只可能在那张页里」这条排除法**没有对象**，
W1/W2 退回**待重新定义**。真正的第一性问题变成：**我们发出去的请求是不是完备的？**

**答案是"不完备"，而且原因在我们自己**：

| 观察（设备侧，模拟器 Pura 90 / 127.0.0.1:5555） | 原文 |
| --- | --- |
| 平台 `response.cookies` 的形态 | `#HttpOnly_id.tsinghua.edu.cn<TAB>FALSE<TAB>/<TAB>FALSE<TAB>0<TAB>JSESSIONID<TAB>FB9C…` |
| 吸收了两条响应的 Set-Cookie 之后 jar 的状态 | `jarAfterProbe cookies=1 domains=[id.tsinghua.edu.cn] names=[JSESSIONID] valueChars=0` |
| 发往 learn 域的请求带了多少 cookie | `probeKnownReq … cookieNamesSent=[]` |
| 已知漫游 URL 直打（`/f/` 与 `/b/`，同一次运行，未重复登录） | `status=401 bytes=2628 csrfChars=0 sessionEstablished=false` |

**根因**：平台给的是 **Netscape cookie-file 制表符行**，而 `CookieJar.parseSetCookie` 只认
`name=value; attrs`（`first.indexOf('=') <= 0 ⇒ undefined`）⇒ `setFromResponse` **一条都不存**；
jar 里那条 `JSESSIONID` 是 `login()` 第 1 步 `resetIdDomainSession` 预置的**空值**，
空值又被 `cookieHeaderFor` 丢掉 ⇒ 请求**连 `Cookie` 头都没有**。
服务端于是按"会话失效"回一张通用报错页——**不是站点改版，也不是需要改 ADR-0004。**

**本轮实现**（`entry/src/main/ets/core/http/CookieJar.ets` + `data/auth/LoginClient.ets`）：

1. 新增 `looksLikeNetscapeCookieLine()` / `parseNetscapeCookieLine()` / `parseSetCookieResponse()`：
   **逐行**判定形态；`#HttpOnly_` 前缀 ⇒ httpOnly 且域剥前缀；7 个制表符字段
   （domain / includeSubdomains / path / secure / expiry / name / value）；`expiry=0` ⇒ 会话 cookie；
   域可带前导点；**值里可有 `=`**；多行 ⇒ 多 cookie；`#` 注释行仍跳过（但 `#HttpOnly_` **不跳**）。
2. **标准 `Set-Cookie` 形态保留**（`response.header['set-cookie']` 那边给的是标准形态）——
   两条入口并存，`source` 取 `netscape | standard | mixed | empty`。
3. **可观察量**：`setFromResponseDetailed()` 返回「来源 / 吸收数 / 跳过行数」，
   `absorbCookies()` **无论吸收到几条都落一行**（原来只在 `stored > 0` 才打，
   于是"一条都没吸收到"这种最该看见的情况恰好无声——这次静默正是误判的来源）；
   新增 `cookieSummaryFor(url)`，登录路径在**表单 GET / login-check POST / 漫游 GET / 课程页 GET**
   四处各落一行 `sent=N names=[NAME(len),…]`。**只落名字与长度，绝不落值。**

**单测**（`entry/src/test/CookieJar.test.ets` +7 条，夹具在 `fixtures/AuthFixtures.ets`）：
设备逐字行、多行多 cookie + 前导点域 + `secure=TRUE` + expiry、值含 `=` + 自定义 path、
标准形态与混发、**预置空 JSESSIONID 不得覆盖已吸收的真实值**、以及"标准形态不得被误判成 Netscape"。
全量 **242 条全绿**（原 235 + 7）。

**未验证项**

1. **修复是否让冷启动重登成功**——见下方「第三轮：设备验证」。
2. **登录表单响应是否也曾被丢**：本轮的吸收自证日志会直接给出答案（第一次真实取值时确认）。
3. **平台 `expectDataType: ARRAY_BUFFER` 是否真能拿到原始 GBK 字节**（那张报错页的可读文本仍未知）——
   **未试**，需要改 `HttpClient` 端口，超出本轮边界。平台给 JS 的字符**不是**逐字节 Latin-1 映射
   （码点实测 `U+00B9 U+0631 U+0562`），两种候选复原法都失败。
4. **同一个 POST 为什么给 ArkWeb 与我们两份不同响应**——本轮**未定论**；cookie 修好后这条可能自然消失，
   也可能暴露出第二个原因（UA / 信任 cookie）。**不换 UA、不发第二次 POST**（未获批准）。

**复现命令**

```powershell
$env:DEVECO_SDK_HOME='C:\Program Files\Huawei\DevEco Studio\sdk'
Remove-Item -Recurse -Force entry/build; & devecocli build *> .dsh/logs/T08b-build-cookiefix.log
hdc install -r entry/build/default/outputs/default/entry-default-signed.hap
hdc shell "aa force-stop com.koracan.learnOH"
hdc shell "hilog -w start -f learnoh_w12b -l 8M -n 5"
hdc shell "aa start -a EntryAbility -b com.koracan.learnOH"
# 判据行：login: absorb … source=netscape stored=1 / login: check request sent=1 names=[JSESSIONID(41)]
#         / restore: session rebuilt via pure HTTP（成功时）
# 离线复刻（不需要设备）：
node .dsh/logs/T08-e3-cookie-v2.cjs
```

**取证**：`.scratch/enrollment/evidence/experiment-w12/`（探针轮：`E3`/`E4`/`E5`/`E7`/README）、
`.scratch/enrollment/evidence/experiment-w12b/`（本轮：修复后设备验证）。

**第三轮：设备验证（2026-09-12 13:08:44，模拟器 Pura 90 / 127.0.0.1:5555）—— 通过**

修复后的构建（hap 1,582,091 B，SHA256 `9B082C4F08256D2AB5B11784BF97199EC6FC635E39AE52F4FE7295F2F5EF6BC7`）
装到模拟器后 `aa force-stop` + `aa start` **一次冷启动 = 一次登录 POST**，7 步全部走通：

```
login: id form request sent=0 names=[] url=…/login/form/bb5df85216504820be7bba2b0ae1535b/0
login: absorb setCookie=present rawChars=97 source=netscape stored=1 skippedLines=0 path=/do/off/ui/auth/login/form/… cookies=1 domains=[id.tsinghua.edu.cn] names=[JSESSIONID] valueChars=41
login: id form ok status=200 publicKeyChars=130 jar=… valueChars=41
login: check request sent=1 names=[JSESSIONID(41)] … fields=[i_user,i_pass,singleLogin,fingerPrint,fingerGenPrint,fingerGenPrint3,i_captcha]
login: absorb setCookie=present rawChars=61 source=netscape stored=1 skippedLines=0 path=/do/off/ui/auth/login/check cookies=1 … valueChars=41
login: ticket ok status=200 ticketChars=36 doubleAuthMentions=0
login: roam request sent=0 names=[]
login: absorb setCookie=present rawChars=197 source=netscape stored=2 skippedLines=0 path=/b/j_spring_security_thauth_roaming_entry cookies=3 domains=[id.tsinghua.edu.cn,learn.tsinghua.edu.cn] names=[JSESSIONID,XSRF-TOKEN] valueChars=119
login: roam ok status=200 jar=… valueChars=119
login: course list request sent=2 names=[JSESSIONID(42),XSRF-TOKEN(36)]
login: success status=200 csrfChars=36 cookieChars=102 language=zh jar=… valueChars=119
re-auth session adopted: language=zh cookies=3 … valueChars=119
reAuth: login ok
restore: session rebuilt via pure HTTP (no webview) kind=restored language=zh reason=none diag=ok
startup(startup): session rebuilt via pure HTTP, zero webview language=zh … diag=reason=none diag=ok
features.shell: shell ready: tabs=notices,assignments,files,courses,settings locale=zh-Hans
```

**验收第 1 条（杀掉应用重启后无需输入即进入主界面，日志证明会话由纯 HTTP 重建）：达成**
——模拟器口径、真实凭据、零 WebView。视觉级辅助证据：冷启动后五 tab 主壳、公告列表有内容
（截图 `08b-cookiefix-coldstart-shell.jpeg`；公告 tab 的 `source=mock` 是既定计划，与会话无关）。
**真机（MatePad Air，API 24）仍未验证**——留给 ticket 18 之前的一次性复验。

**这一轮最重要的教训（比修复本身值钱）**：我们一度把"响应里没有票据"升级成"要不要改 ADR-0004"的决策，
真因却是 `CookieJar` 解析不了平台的 Netscape 制表符行 ⇒ 请求带着**空 JSESSIONID**（等于没有 `Cookie` 头）
发出。**在断言"站点给了奇怪的响应"之前，先证明我们发出去的请求是完备的。**
本轮把那件事变成了常设可观察量：`source=netscape|standard|mixed|empty stored=N skippedLines=M` 与
逐请求的 `sent=N names=[NAME(len)]`。已同步登记到 `docs/reference-quirks.md` 第 15 条与 `AGENTS.md`。

**取证**：`.scratch/enrollment/evidence/experiment-w12b/`（`README.md` + `F1`–`F5` + `E9` + 原始 gz + 截图 + 解压全文）。

### 统筹验收（第三轮，2026-09-12，模拟器口径）→ Status: verified-partial

**结论：验收第 1 条（杀进程重启无需输入即进主界面，日志证明会话由纯 HTTP 重建）通过。** 我在**提交态产物**上**独立复跑过一次冷启动**，下列不是转述：

- 现场：`HEAD=fe3a4737ca8191857cca8c2558c96b68e5283e38`；工作区只有三份文档改动（`entry/` 干净 ⇒ 现场产物对应 HEAD）；hap `1,582,091 B @12:59:42`，SHA256 `9B082C4F08256D2AB5B11784BF97199EC6FC635E39AE52F4FE7295F2F5EF6BC7`；设备 = **模拟器** Pura 90 / `127.0.0.1:5555` / HarmonyOS 6.1.0(23)。
- 命令：`aa force-stop` → `aa start -a EntryAbility -b com.koracan.learnOH` → 15s → `hilog -x -D 0x4C4F`（PID 27073，13:13:59）。
- 判据行：`login: check request sent=1 names=[JSESSIONID(41)]` → `login: ticket ok … ticketChars=36 doubleAuthMentions=0` → `login: roam ok` → `login: success … csrfChars=36 language=zh` → `restore: session rebuilt via pure HTTP (no webview) kind=restored` → `shell ready: tabs=notices,assignments,files,courses,settings`。全程 **325 ms**，**只发过一次登录 POST**。
- 视觉证据：`F6-coordinator-coldstart-verify.jpeg`（SHA256 `ABB90FAD92FCA4D29E1C84668D3AC2B4F3910E9DFCBDC6706982D874291E6F75`）落在**主壳「公告」页**（五 tab、更新于 13:14:00），**不是**登录页。
- 证据文件：`.scratch/enrollment/evidence/experiment-w12b/F6-coordinator-coldstart-verify.txt`（一论断一文件）。

**我另外独立核过的**：`git show --stat fe3a473`（4 个文件全在 `entry/`，+434/−25）；hap 的 SHA256 与产物时间戳；`test_result.txt` 最后一行 **242/242**；平台 `response.cookies` 的 Netscape 形态与 `parseSetCookie` 的 `first.indexOf("=") <= 0` 签名落空（读 `CookieJar.ets:200-206` 与调用链 `HttpFetchPort:77 → HttpClient:163 → LoginClient:253`）；`fe3a473` 之后 `entry/` 相对 HEAD 无改动。

**未关闭项（本 ticket 因此不是 `verified`）：**

| # | 项 | 处置 |
| --- | --- | --- |
| 2 | 断网启动不卡在加载态、网络恢复后重试能成功 | **仍欠设备侧实操**（单测只覆盖超时与分类）⇒ 排到 ticket 09 之后的一轮「会话生命周期」 |
| 3 | 会话失效 / 信任过期显式回登录页 | 有**真实凭据**下的降级实测（修复前那两次冷启动）＋ 单测，但**未在当前产物上**复现 ⇒ 与 #2 同轮关闭 |
| 4 | 并发请求只触发一次重登 | **由 ticket 09 的真实取数自然关闭**（本轮日志已显示 `silent re-auth #`=1 / `check request`=1；单飞单测全绿） |
| — | 真机（MatePad Air，API 24） | ticket 18 之前一次性复验 |

**一处更正（撤回一个说法）**：`CookieJar.test.ets:123` 与 `fixtures/AuthFixtures.ets:102` 的注释把 `.scratch/enrollment/evidence/experiment-w12/E5` 说成「tracked 目录」——**不对**：`git ls-files -- .scratch/enrollment/evidence` 只有顶层 `README.md`，逐次取证的子目录是**本地保留、不入库**（沿用本仓库既有约定）。引用本身没问题（夹具已把设备逐字行内联进 `AuthFixtures`），但「tracked」这个词要撤回；清单改在顶层 `README.md` 维护（已补）。
