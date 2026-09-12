# ticket 17 取证（设置与子页 + Mock 模式）

**设备口径**：全部为**模拟器**（Emulator 6.1.1.300 / HarmonyOS 6.1.0(23)），**没有真机**取证。
- `Pura 90`（phone，`127.0.0.1:5555`）—— 只用来拍"已登录真实账号时的第一屏"（P0，用于说明 mock 入口为何进不去）；
- `MatePad Pro 13`（tablet，`127.0.0.1:5557`）—— 分栏 / 沉浸式 / 计数器正证（T 组）；
- `Mate X7`（foldable，`127.0.0.1:5555`，**临时启动的干净实例**）—— Mock 模式与退出登录（X 组）。
  > 两台既有模拟器都持有**真实账号凭据**（只能靠一次真实短信登记重建），而"走到登录页"必须先登出，
  > 所以 mock 与登出的取证只能在一台**没有凭据**的实例上做 —— 这就是 X 组的由来（统筹裁决 (b)）。
  > Mate X7 与 Pura 90 抢同一个串口 5555，因此取 X 组时**先停 Pura 90**，取完再停 Mate X7、重启 Pura 90（已复原）。
  > **代价**：Mate X7 上装了一份本 hap（它原本是干净镜像）；Pura 90 / 平板的数据与凭据**一字未动**。

**取证时的源码版本**：HEAD = `3a3f968291217637621d9df06ef9e076adca08aa`，工作区**脏**（含本 ticket 全部改动），
`git status --porcelain` 的 sha256 = `621d14497c33dad6add5bd34b3c66910103b399040c6091af342fc299f3a23c1`。
**产物**：`entry/build/default/outputs/default/entry-default-signed.hap`（4,992,248 B，构建于 2026-09-13 05:14:53），
其中 `ets/modules.abc` 的 SHA256 = `3175E133A246714C7ACE2ECC0CB86B51DC4437AD700D4405E40A8FA22A386A12`（1,738,416 B）。
内容级核对（解包后在 `modules.abc` 里搜符号）：`MockNoticeRepository` / `MockCourseRepository` / `MockFileRepository` /
`ui_mock_mode_active` / `loh_immersive_mode` 全部命中；**`PlaceholderTab` 已消失**（该模块被删除）。
**产物与源码的对应（内容级，不看时间戳）**：取证完成后只改过文档，源码在构建之后**没有**实质变更；
唯一被重写过的是一个生成物 `entry/src/main/ets/core/i18n/I18nKeys.ets` —— `gen-i18n-keys.mjs` 每次都无条件重写它（时间戳会变、**字节不变**），
已用"改前/改后 SHA256 相同"证明（C765E4A0…52814F）。

## 逐文件论断表（一个文件一条论断；**两个论断不复用同一份证据**）

| 文件 | 论断 | 备注 |
| --- | --- | --- |
| `P0-phone-first-screen.png` | Pura 90 上应用**已登录真实账号**（公告 tab 有真实数据、底栏五 tab）⇒ 登录页不可达 | 说明为什么 mock 不能在这台机器上取证（**不是** mock 的证据） |
| `X0-matex7-first-screen.png` | Mate X7 是**干净实例**：冷启动后停在登录页（用户名/密码为空） | 统筹要求的"先确认状态再动手"那一帧 |
| `X1-matex7-credentials-typed.png` | 第一次 `ui text` 触发了系统输入法首启引导（小艺输入法隐私弹窗），**不是应用界面** | 设备设置噪音，保留以便复现 |
| `X1b-matex7-after-ime.png` | 同上（点击坐标错了一次，弹窗仍在） | 噪音 |
| `X1c-matex7-after-ime-agree.png` | 输入法"选择中文键盘布局"引导页 | 噪音 |
| `X1d-matex7-ime-step2.png` | 跳过键盘大小引导后，用户名框已填入 `guest` | 噪音（但可看出输入生效） |
| `X1e-matex7-both-typed.png` | 两个输入框分别是 `guest` 与六个圆点（密码），**未弹任何 SSO 说明框** | 证明 guest/guest 分支先于弹框 |
| `X2-matex7-mock-entered-notices.png` | 点「登录」后**直接进主壳**：公告 tab 显示 4 条样例公告（全部 4 / 未读 2），**没有**任何网页登记窗口 | **验收第 5 条**的界面证据（界面可用 + 数据为样例） |
| `X3-matex7-mock-settings.png` | 设置页：用户行是样例身份「测试学生 / 电子系」、自证行「Mock 模式（guest）：数据为样例，已发出的网络请求 = 0」、**没有**「沉浸式模式」这一行 | mock 用户不显示沉浸式（Settings.tsx:74-82）+ 零网络自证 |
| `X4-matex7-about.png` | 关于页：`v1.1.0 (build 1000042)`、© 2026 Han Wong、备案号（链接色）、维护者 / 特别感谢 / 开源依赖三段俱全 | **验收第 2 条**（版本与构建号） |
| `X5-matex7-help.png` | 帮助与反馈页：GitHub（推荐）+ 邮箱 + 问题反馈模板 | 验收第 2 条的链接入口 |
| `X6-matex7-external-link.png` | 点「创建新的 GitHub Issue」后**系统浏览器**打开 `github.com` | **验收第 2 条**（链接可打开）；与 X5 是两个论断（一个是页面、一个是外跳） |
| `X7-matex7-mock-assignments.png` | 作业 tab：未完成 2 / 已完成 2 / 全部 4，两条未交作业显示"未到期" | 样例数据覆盖"未到期/已截止"两种状态 |
| `X8-matex7-mock-files.png` | 文件 tab：全部 4 / 未读 2，四条样例文件带类型与体积 | 第三域样例 |
| `X9-matex7-mock-courses.png` | 课程 tab：2026-2027 学年秋季学期 + 3 门样例课程与三类计数（1/1/1、1/2/1、0/0/0） | 课程域样例，计数与 MockData 一致 |
| `X10-matex7-mock-course-detail.png` | 课程详情（数据结构）的"通知"标签页列出该课程的两条样例公告 | 证明样例**按课程归属**自洽 |
| ~~`X11-matex7-logout-dialog.png`~~ | （**已删除**）该文件名第一次写入的是"帮助页"（同名文件不被覆盖，第二次写入失败且被静默吞掉）—— 名不符实，故**删除**而不是留用 | AGENTS.md「证据文件名里的状态标签必须与画面内容一致」 |
| `X11b-matex7-logout-dialog.png` | 退出登录确认框：标题「退出登录」、正文「确定退出登录？该操作会清除你当前的所有设置。」、按钮「取消 / 确定」 | **验收第 4 条**前半（确认框） |
| `X12-matex7-after-logout.png` | 点「确定」后**回到登录页**（两个输入框为空、键盘弹出） | **验收第 4 条**后半（回到登录页） |
| `X13-matex7-relaunch-still-login.png` | `aa force-stop` + 重启后**仍在登录页**（凭据真的被清掉，不是内存态） | 与 X12 是**两个**论断：X12=回到登录页、X13=重启后仍无凭据 |
| `T0-tablet-shell.png` | MatePad 横屏：393vp 左栏 + 右栏空态「无内容」，左栏是真实公告 | 分栏基线（ticket 16 已交付，这里只作对照） |
| `T1-tablet-settings.png` | 平板设置页：用户行是真实账号 `han-wang23`、**有**「沉浸式模式」行、**没有** mock 自证行 | 与 X3 成对，证明"mock 才不显示沉浸式" |
| `T2-tablet-immersive-right-pane.png` | 从设置页点「沉浸式模式」→ 该子页出现在**右栏**，左栏仍是设置列表；两个开关 + 两行说明 + 自证行（`immersiveMode=false … avoidSwitchEnabled=false`） | 设置子页落右栏；第二开关此刻**禁用** |
| `T3-tablet-immersive-on.png` | 打开沉浸式开关后**状态栏立即消失**（对比 T2 顶部的 05:58/电量），第二开关转为可用 | **验收第 3 条**（即时生效） |
| `T4-tablet-immersive-persisted.png` | `aa force-stop` + 重启后**状态栏仍然没有**（截图顶部无时间/电量） | **验收第 3 条**（重启后保持） |
| `T5-tablet-immersive-off-restored.png` | 关掉开关后状态栏**立即恢复**（06:04/电量回来） | 复原设备状态；同时是"关"这一侧的即时生效 |
| `P1-phone-restored-real-account.png` | Pura 90 重启后**仍是原来的真实账号**（公告列表与 P0 一致、状态栏正常） | **环境复原核对**：本轮停过 Pura 90 给 Mate X7 让串口，这里证明它的凭据与数据一字未动 |

## 日志（hilog，应用域 `A04c4f`）

| 文件 | 论断 |
| --- | --- |
| `.dsh/logs/17-hilog-mock.txt` | mock 全链路自证：`login: mock credentials detected -> mock mode (no request, no webview)` / `mock mode entered: … network audit: attempts=0` / `mock login accepted: phase=ENROLLED (zero network, zero webview)` / `notice repository wired: source=mock` / `mock notices served: items=4 networkAttempts=0` |
| `.dsh/logs/17-hilog-logout.txt` | 登出链路：`logout tapped: showing the confirmation dialog` / `logout requested: clearing session and persisted credentials` / `credentials cleared: ok=true` / `logout complete: credentialsCleared=true phase=unenrolled`（全程 `network audit: attempts=0`） |
| `.dsh/logs/17-hilog-relaunch.txt` | 重启后：`startup: restoring session from persisted credentials` → `no persisted credentials` → `no persisted credentials -> login page`；另有 `immersive restored on startup: persisted=false applied=true` |
| `.dsh/logs/17-hilog-immersive-on.txt` | 打开沉浸式：`immersive settings save ok: immersiveMode=true` / `apply immersive: requested=true layoutFullScreenOk=true systemBarEnableOk=true` / `immersive toggled: … appliedToWindow=true`，并且系统侧 `SYS_UI: onImmersiveChange, isImmersive = true` |
| `.dsh/logs/17-hilog-immersive-restart.txt` | 重启后：`apply immersive: requested=true … applyCount=1`（新进程）+ `immersive restored on startup: persisted=true applied=true`；**同一份日志里**还有 `network request #1 … #10`（真实账号） |
| `.dsh/logs/17-hilog-immersive-off.txt` | 关掉：`apply immersive: requested=false …` |
| `.dsh/logs/17-test-run3.log` | 单测：`hvigor BUILD SUCCESSFUL`，无 `ERROR` / `ErrorCode` / `COMPILE RESULT:FAIL`；`entry/.test/.../test_result.txt` 的 `Tests run: 389, Failure: 0, Error: 0, Pass: 389, Ignore: 0`（文件时间戳 2026/9/13 5:14:06，与本轮一致） |
| `.dsh/logs/17-assemble.log` | 构建：`hvigor BUILD SUCCESSFUL`，无 `ERROR` / `ErrorCode` |

## "Mock 模式不发起真实网络请求"是怎么证的（两条**独立**证据）

1. **计 0**：ticket 17 给两个**真实 HTTP 出口**加了进程内计数（`data/remote/NetworkAudit`，接在 `HttpClient.request` 与
   `HttpDownloadPort.download` 的第一行）。Mock 模式下走的是 `data/mock/Mock*Repository`，**不经过这两处**；
   于是全程（进入 → 浏览四个 tab → 打开课程详情 → 登出）计数一直为 **0**，并且这个 0 被**打印在设置页屏幕上**
   （`X3` 的自证行）与 **5 条 hilog** 里（`17-hilog-mock.txt` / `17-hilog-logout.txt`）。
2. **计数器本身是活的**：同一份构建、同一个计数器，在**真实账号**冷启动时打出了 `network request #1 … #10`
   （`17-hilog-immersive-restart.txt`）。⇒ "0" 不是"计数器坏了"，而是"没有请求"。
   **这两条证据来自两份不同的日志 / 两个不同的进程**，不复用。

## 未抓到 / 未验证（如实登记）

- **深色模式下的设置页截图**：未抓（本轮没有开 `FORCE_DARK_FOR_EVIDENCE`，也没有走系统深色）。
- **平板横屏下"旋转一次后沉浸式页仍留在右栏"**：未抓。本机模拟器的 scene 命令不可用
  （`docs/reference-quirks.md` 第 31 条：Emulator 6.1.1.300 要 ≥7.0），旋转只能靠 GUI 按钮；
  能证明的只是"进子页时落在右栏"（`T2`）与 hilog 里的 `split view enter/exit: tab=settings moved=…`。
- **学期选择子页**：未抓截图（从设置页点进去会触发一次课程取数；本轮把设备窗口用在了 mock 与沉浸式上）。
  entry 的代码路径与 ticket 12 的页面相同，风险低，但**没有**本轮截图。
- **导出日志**：未点（只截到了那一行 `X3`）。`exportLogs` 的落盘路径与字节数没有本轮证据。
- **隐私政策那一行的外跳**：未单独截（外跳机制由 `X6` 的 GitHub 外链承担 —— 同一个 `openExternalUrl`）。
- **`mailto:`**：未验证系统里是否有邮件应用接管。
- **服务端登出**：本工程不发这个请求（见 `docs/accepted-deviations.md` 第 30 条 D2），因此"服务端会话是否仍有效"未测。
- **从设置页切学期是否联动课程 tab**：**不联动**（已知缺口，工单交付节与 ticket 12 Comments 都有边界说明）。
- **学期选择子页的持久化**：本工程的学期选择**不落盘**（重启后回到站点当前学期）—— 这是 ticket 12 的既有口径
  （参考实现的 `semesters.current` 会被 redux-persist 落盘）。本 ticket 只复用了那个页面，**没有**改它的持久化行为，
  因此验收第 1 条里"持久化"这一半对**学期选择**这一项**不成立**（文件设置与沉浸式两项都成立：前者是 ticket 11 的 preferences，后者本轮已用重启证明）。
