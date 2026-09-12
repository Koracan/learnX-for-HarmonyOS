# 16: 断点分栏（平板 / 2in1）

**What to build:** 宽度达到断点且横向时，主栏与详情人栏并排；从主栏进入详情落到右栏；旋转与窗口缩放时正在浏览的状态稳定。

**Blocked by:** 10（作业列表 + 详情）、11（文件列表 + 详情 + 下载 + 预览 + 分享）、12（课程列表 + 详情 + 学期选择）

**Status:** verified-partial（模拟器口径；验收 3 的运行期那半是环境能力缺口，已转 ticket 18 真机旋转复验）

- [ ] 宽度达到断点且横向时进入双栏，否则单栏
- [ ] 主栏选中项显示在右栏，主栏保留高亮状态
- [ ] 旋转或缩放窗口时正在浏览的详情不丢失、不重复请求
- [ ] 全屏切换后返回仍保持原布局状态
- [ ] 真机截图（单栏 + 双栏各一张）

## Comments

### 边界说明（2026-09-12，由 ticket 11.5 带入）—— 真机截图的基线变了

- **变了什么**：本 ticket 验收最后一条要的是"真机截图（单栏 + 双栏各一张）"。在此之前 ticket 11.5 已把
  **全应用底色**改成纯白（浅色）/ 中性深灰（深色），并把**所有 emoji 图标换成同源矢量字体图标**，
  页头信息架构也改了（作业页头不再有学期/覆盖徽标/未完成计数）。
- **你的证据还成立到哪一步**：本 ticket 尚未开工（`ready-for-agent`），所以**没有旧证据失效**——
  受影响的是**未来取证的基线**：真机截图必须是 **11.5 之后**的构建，截图里应当看到白底与矢量图标；
  若误用 11.5 之前的构建截图，会与模拟器口径不一致。
- **可观察量转移到哪里**：无需转移；只需在 ticket 16/18 的截图说明里注明"构建时间在 ticket 11.5 之后"。

### 取证设备已定（2026-09-13，统筹侦察；台账第 28 条）

- **双栏的达标设备是模拟器 `Mate X7`（foldable，HarmonyOS 6.1.0(23)，与工程 `compatibleSdkVersion` 同档）**，
  **不是** `MatePad Pro 13`：本机镜像库只有 `phone_all_x86`（无 `tablet_x86`、无 `pc_all_x86`），
  所以 tablet / 2in1 两个实例**根本起不来**。Mate X7 复用已下载的同一个镜像，实例已铺开，可直接启动。
  判据与命令原始输出见 `docs/reference-quirks.md` 第 28 条。
- **断点余量**：Mate X7 展开态约 **1008 vp**，高于 `spec.md:149` 定的 **750 vp** 断点；折叠态约 **345.6 vp**。
  即**同一台设备上就能同时拍到单栏与双栏**，而且"折叠 ↔ 展开"正是验收第 3 条要的"旋转 / 窗口缩放时状态不丢"的真实触发。
- **第 13 条验收口径的改判**：原文写"真机截图（单栏 + 双栏各一张）"。**真机只做最终一次性复验（`AGENTS.md`，时点卡在 ticket 18）**，
  而双栏的设计达标判定不需要真机——所以本 ticket 第 13 条按 **Mate X7 的双栏截图**判，真机那一层由 ticket 18 覆盖。
  截图说明里必须写清设备名与"模拟器"字样，**不要写成"真机"**。

### 平板模拟器已可用 + 登录页也是本 ticket 的对象（2026-09-13，实测）

- **`MatePad Pro 13` 现在能用了**：账号所有者下载了 `tablet_x86` 镜像并在 DevEco 里铺开实例；
  实测启动成功、串口 `127.0.0.1:5557`，**与 Pura 90 的 `5555` 同时在线**（本机可并行两台）。
  横向视口 `hw.lcd.single.width=2880`/`density=320` ⇒ **1440 vp × 960 vp**，高于 750vp 断点近一倍。
- **前置条件（别漏）**：跑登录前必须把它默认的 `hw.dataPartitionSize=6144` 改成 `16384`，
  否则会踩台账第 12 条的 `detectIncognito` 误判（隐私模式 ⇒ 二次验证页不渲染「信任该浏览器」）。
  **改分区会重建 userdata，顺序是先改再装应用。** 详见 `docs/reference-quirks.md` 第 28 条。
- **新增一处必须覆盖的界面：登录页**。实测平板上登录表单**整屏拉伸**——
  标题 `w=1536`、两个输入框与「登录」按钮各 `w=2848`（屏幕 2880px）⇒ 输入框横跨 1440vp 里的约 1424vp。
  它既不属于断点分栏的主从两栏，也不在本 ticket 原来列的课程/文件/作业三处之内，
  所以本 ticket 验收**加一条**：登录页在 ≥750vp 横向时**不得整屏拉伸**（须有可读的最大宽度约束并居中），单栏（电话形态）保持现状。
  证据：`.scratch/tablet-login/T1-tablet-launch.png`（2880×1920）+ `T1-layout.json`。
- **动手前先确认**：启动第二台模拟器会占 4 GB 内存与 4 核，**先确认构建锁/设备锁的空档**，别与别的 agent 的取证轮撞车。



### ticket 16 交付

**结论表（逐条验收 → 证据文件名；证据一律来自「模拟器」，详见 `.scratch/splitview/evidence/README.md`）**

| # | 验收 | 结论 | 证据 |
| --- | --- | --- | --- |
| 1 | 达断点且横向进双栏，否则单栏 | **通过** | 双栏：`A10-tablet-coldstart-split.png`、`A1-tablet-split-notices-empty-right.png`（master `786 px = 393 vp`）+ `A-log-tablet-coldstart.txt`（`active=true measured=1440x893`，MatePad Pro 13 模拟器）；单栏：`B1-phone-single-notices-list.png` + `B-log-phone-full.txt`（`active=false measured=377.14x749.14`，Pura 90 模拟器） |
| 2 | 主栏选中项显示在右栏、主栏保留高亮 | **通过** | `A2-tablet-split-notice-detail-right-highlight-left.png` + `-layout.json`（左栏第一行选中底色、右栏 `Scroll [788,…]` 是公告详情） |
| 3 | 旋转/缩放窗口时详情不丢、不重复请求 | **运行期未抓到**（机制由单测钉住） | `entry/src/test/SplitView.test.ets`（5 条，含 749/750/竖屏/退路尺寸/连续详情段）；**触发条件在本环境不可得**，原始反证见 `D-log-rotate-resize-unavailable.txt`、`D1-…-layout.json`、`D2-…png`，平台事实记入 `docs/reference-quirks.md` 第 31 条 |
| 4 | 全屏切换后返回仍保持原布局状态 | **通过** | `A7-tablet-file-detail-fullscreen-master-hidden.png`（主栏收成 0，`返回` 移到 x=34）→ `A8-tablet-exit-fullscreen-split-restored.png`（双栏原样恢复）→ `A9-tablet-back-from-detail-still-split.png`（返回后仍双栏、主栏仍在）；消费点日志见 `A-log-tablet-full.txt` 的 `fullscreen toggle: masterHidden=… split=true` |
| 5 | 真机截图（单栏 + 双栏各一张） | **改判为模拟器**：双栏 = `A2-…png`（MatePad Pro 13，模拟器）；单栏 = `B2-phone-single-notice-detail.png`（Pura 90，模拟器） | 真机那一层按 `AGENTS.md` 留到 ticket 18 一次性复验 |
| 6 | （ticket 11.5 边界说明）截图必须来自 11.5 之后的构建 | **通过** | 全部 A/B/C 证据取自 HEAD `92a080a`（含 11.5）之后的 `assembleHap --no-incremental` 产物；画面是纯白底 + 矢量字体图标（见 A1/A2/B1 截图） |
| 7 | （统筹 2026-09-13 追加）登录页在 ≥750vp 横向不得整屏拉伸 | **通过** | `C1-tablet-login-landscape-maxwidth.png` + `-layout.json`：两个 `TextInput` 与「登录」按钮都是 `[960,*,1920,*]` ⇒ **960 px = 480 vp**、居中（修复前同机是 `w=2848` ≈ 1424 vp）；单栏电话版式未动（B1/B2） |

**改动文件**

| 文件 | 改了什么 |
| --- | --- |
| `entry/src/main/ets/features/shell/SplitView.ets`（**新增**） | 断点常量（750 / 393 / 1px / 100ms）、纯判据 `resolveSplitViewActive`、白名单 `DETAIL_ROUTE_NAMES`（9 条）、迁移计划 `splitMigrationPlan`、四个迁移/入栈助手、AppStorage 键（含 `showMaster` 取反的那一个） |
| `entry/src/test/SplitView.test.ets`（**新增**）+ `entry/src/test/List.test.ets` | 断点边界（749/750/竖屏/实测为 0 退回退路）、白名单、迁移计划（含"课程详情→文件详情"两级） |
| `entry/src/main/ets/features/shell/ShellTabs.ets` | 根 `Column` 的 `onAreaChange` 实测渲染区 + `display` 退路（`fallbackSizeVp`），判据结果写 AppStorage；`Tabs + TabContent` 一字未改 |
| `features/{notices/NoticesPage,assignments/AssignmentsPage,files/FilesPage,courses/CoursesPage}.ets` | 每个 tab 加第二个 `NavPathStack`（右栏）；`build()` 改成 `Row` + `Divider` + 右栏；`routeTo(name,param,stack)` 让同一份路由表被两个导航容器共用；`onSplitViewChanged` 双向迁移；单栏版式与列表项 key 之外的行为未动；双栏时主栏选中行加 `surfaceVariant` 底色 |
| `features/files/FileDetailPage.ets` | 页头新增「全屏 / 退出全屏」按钮（只在双栏渲染），翻转 AppStorage 里的主栏隐藏标志 |
| `ui/icons/IconCatalog.ets` + `entry/src/test/IconCatalog.test.ets` | 加 MaterialIcons `fullscreen`(0xE5D0) / `fullscreen-exit`(0xE5D1)，测试期望表 22 → 24 |
| `scripts/generate-i18n-resources.mjs`（+ 生成物） | 加 2 条本地键 `loh_fullscreen` / `loh_exit_fullscreen`（全屏按钮的无障碍文案），生成 307 键 / 本地 8 条 |
| `features/auth/LoginPage.ets` | **补回参考实现 `Login.tsx:127-130` 的 `maxWidth: 480`**（外层另起可读宽度列 + 居中）；不是偏离，是移植时漏掉的一条 |
| `entry/src/test/I18n.test.ets` | 期望键数 305 → 307、本地键 6 → 8 |
| `docs/accepted-deviations.md` | **新增第 28 条**（分栏迁移：对称回迁 + 迁移粒度取"栈顶连续详情段"） |
| `docs/reference-quirks.md` | **新增第 31 条**（【平台事实】本环境模拟器不能旋转/缩放窗口） |
| `.scratch/splitview/evidence/` | 证据 + `README.md`（逐文件论断表） |

**门禁原始数字**

- `$env:DEVECO_SDK_HOME='C:\Program Files\Huawei\DevEco Studio\sdk'` 已设；先删 `entry/.test` 再跑 `test --no-incremental`。
- 单测：`entry/.test/default/intermediates/test/coverage_data/test_result.txt`（`LastWriteTime` **2026/9/13 2:00:51**）：
  ```
  Tests run: 367, Failure: 0, Error: 0, Pass: 367, Ignore: 0
  ```
  基线 362 ⇒ **+5**（`SplitView.test.ets` 一个 suite 五条）。日志 `.dsh/logs/t16-test-3.log`（`BUILD SUCCESSFUL` / `EXIT=0`）。
- `assembleHap --no-incremental`：`BUILD SUCCESSFUL in 14 s 893 ms`（`.dsh/logs/t16-hap-1.log`，hap 时间戳 02:01:19）；
  复原登录开关后的**最终**一次：`.dsh/logs/t16-hap-final.log`，hap 时间戳 **02:26:23**（已装机，见 A11）。
- `node scripts/check-domain-purity.mjs` → `PASS domain 不依赖平台与应用层`（exit 0）
- `node scripts/check-import-graph.mjs` → `PASS 所有相对 import 均可解析`（exit 0；WARN 仍只有两个入口文件
  `pages/Index.ets`、`entrybackupability/EntryBackupAbility.ets` —— `SplitView.ets` **不在**孤儿列表里）
- `node scripts/check-i18n-keys.mjs` → `RESULT: OK`（307 键；`en == zh` 的两条仍是既有允许项）
- `node scripts/check-generated-fresh.mjs` → `PASS 生成物与其生成器输入一致`
- 版本：HEAD `92a080adf5ea2a3af011e75ea8a311f405dc8c6d`，工作区脏（21 项；`git status --porcelain` SHA256
  `B1A56B8FBE9D7F709D060AF4929DFC08BF5776D8E769C41D1227BB8BB4FC54D1`）。**未提交**。

**未验证项与复现条件**

1. **验收 3 的运行期一半（旋转 / 缩放窗口 → 详情双向迁移且不重复取数）没抓到。**
   - 已试过的触发手段与原始报错：`devecocli emulator rotate|fold` ⇒ `require Emulator 7.0 or later. Current 6.1.1.300`；
     `aa start --ww/--wh/--wl/--wt` 被全屏 stage 应用忽略；设备无 `wm`；WMS `hidumper` 只读；无 display density/orientation 参数；
     底部上滑进不了多任务。逐条见 `.scratch/splitview/evidence/D-log-rotate-resize-unavailable.txt`。
   - **复现条件**（任一满足即可补这一格）：① DevEco 模拟器窗口上的旋转按钮（GUI）；② Emulator ≥ 7.0 后用
     `devecocli emulator rotate --target 127.0.0.1:5557 left`；③ ticket 18 的真机上直接旋转，或用 2in1 拖拽窗口边缘改尺寸。
   - 复现时该看的消费点：`features.shell.split` 的 `split view decision: active=… measured=…`，
     以及 `split view enter/exit: tab=… moved=N masterRoutes=… detailRoutes=…`（两行都在 hilog 里）。
2. **"不重复请求"这一条没抓到**（依赖第 1 条）。可判据：迁移后不出现第二次 HTTP —— 文件详情应打
   `file detail ready: … fromCache=true` 且没有新的下载请求行；公告详情是参数驱动，迁移只重放同一份 `param`。
3. **登录页取证那次的开关自证日志没抓到**（`pages.index evidence login-page override`）：那次启动正好在设备锁屏期间，
   该时段 hilog 缓冲里没有应用域（`A04c4f`）的行。自证由消费点承担：屏幕上渲染的就是生产 `LoginPage`，
   其 input/button 的几何量就是第 7 条的判据；开关已复原（`git diff -- entry/src/main/ets/pages/Index.ets` 为空 +
   复原后重建装机见 `A11-tablet-shipped-build-shell-split.png`）。补丁留在 `.dsh/logs/t16-login-override.patch`。
4. **ticket 03 的"滚动位置保留"没有正面截图**：两台设备当前的可见条目数都少于半屏（电话 1 条公告且文件被
   全部屏蔽、平板公告 2 条 / 文件 4 条），列表**滚不动**，因此没有"滚动 → 切 tab → 切回"的 dump 对比。
   已取到的替代证据：`B3-phone-tab-switch-back-detail-kept.png` 与 `B2-…-layout.json` **逐字节相同**
   （切 tab 再切回时详情栈原样保留）。结构上 `Tabs + TabContent` 一行未改，单栏只是在外面多包了一层 `Row/Column`。

**代价与已知偏离**

1. **有意偏离（新记台账第 28 条）**：参考实现只在**进分栏**时迁移、且只迁栈顶一条；本实现加了**对称回迁**
   （退出分栏时把右栏详情搬回主栈）并把粒度放宽到"栈顶连续详情段"。理由是本 ticket 验收第 3 条
   （详情不丢 / 不重复请求）与参考实现那条单向迁移直接冲突（竖屏回退会把详情丢掉），且只迁一条会让右栏
   "返回"落到空白。替代验收标准与取证写在 `docs/accepted-deviations.md` 第 28 条。
2. **代价：进出分栏时详情页会被重建一次**（路由与参数原样搬到另一个 `NavPathStack`，页面组件重新构造）。
   三个详情页都是**参数驱动**的（不二次取数），文件详情另有下载缓存（`fromCache=true`），所以网络层不重复请求；
   但页面级的瞬时状态（例如文件详情的下载进度条）会在迁移那一刻重来。本环境没能拍到这一跳（见未验证项 1）。
3. **新增两处界面元素**（都属于"照参考实现补回"）：文件详情页头的全屏/退出全屏按钮（参考实现
   `FileDetail.tsx:108-113`），登录页的 480vp 最大宽度（参考实现 `Login.tsx:127-130`）。
4. **`showMaster`（主栏隐藏）放在 AppStorage 全局一份**，与参考实现放在 `SplitViewProvider` 里同粒度；
   因此"在文件详情里按了全屏"会同时影响四个 tab 的主栏宽度（四个 tab 各自的双栏状态本来就是全局判据）。
5. 单栏（电话）路径除了外面多一层 `Row/Column` 之外与改动前一致；列表行多了一个"选中底色"分支，
   但单栏下 `selected` 恒为 false、且列表项 key 才多一段常量后缀。


> 取证目录说明：`.scratch/splitview/evidence/` 被 `.scratch/.gitignore` 的 `**/evidence` 忽略
> （与 ticket 11/13/14 的取证目录同一条规则）。文件**在磁盘上**、README 里有逐文件论断表；
> 若要随提交入库，需要 `git add -f .scratch/splitview/evidence`。


6. **验收 4 的"全屏切换"取的是参考实现的那一个机制**：文件详情页头的 `fullscreen / fullscreen-exit`
   按钮翻转 `showMaster`（`FileDetail.tsx:108-113` + `SplitView.tsx:40,106,117`），不是系统窗口全屏。
   本工程没有沉浸式设置的入口（归 ticket 17），所以这是当前唯一可达的"全屏切换"。
   "返回仍保持原布局状态"的判据 = 退出全屏后双栏与 393vp 主栏原样恢复（A8），且从详情返回后仍是双栏（A9）。

---

### 统筹验收（2026-09-13，**模拟器**口径：MatePad Pro 13 `127.0.0.1:5557` / Pura 90 `127.0.0.1:5555`）→ Status: verified-partial

**我逐项自己重跑/重读**（两把锁当时都空，独立跑的）：

| 检查 | 我的独立结果 |
| --- | --- |
| HEAD / 工作区 | `92a080a` + 脏工作区；交付方报的 `git status --porcelain` sha256 `B1A56B8F…` 与之自洽 |
| 单测 | **Tests run: 367, Failure: 0, Error: 0, Pass: 367, Ignore: 0**（删 `entry/.test` + `--no-incremental`；`test_result.txt` mtime 02:32:10 为**新写入**）⇒ 基线 362 +5，**与交付一致** |
| 四项门禁 | domain-purity PASS(24) / import-graph PASS(176，孤儿仍只有两个入口，`SplitView.ets` 不在其中) / i18n `RESULT: OK`(307 键) / generated-fresh PASS |
| 分栏判定的**消费点** | `A-log-tablet-coldstart.txt` 实读两行：`active=true measured=0x0 fallback=1440x960` → 一帧后 `active=true measured=1440x893 fallback=1440x960`。**这行同时证实了参考实现的两处语义**：① 优先用**根布局实测尺寸**；② 未测到时**退回窗口尺寸**（`measured>0` 守卫）。手机侧反证同文件：`active=false measured=0x0 fallback=377.14…` |
| 全屏切换（验收 4） | `A-log-tablet-full.txt` 实读 `fullscreen toggle: masterHidden=true split=true` 与 `masterHidden=false split=true` ⇒ 隐藏的只是主栏、**分栏态未被破坏**，与参考实现 `showMaster` 的用途一致 |
| 登录页修复（追加第 7 条） | `C1-…-layout.json` 实读：两个 `TextInput` 与 `Button` 的 bounds 均 `[960, y, 1920, …]` ⇒ 宽 **960px = 480vp**、在 1440vp 视口里**居中**（修复前同机 `w=2848`≈1424vp） |
| 单栏态未被破坏 | 手机实测 `active=false`；`Tabs + TabContent` 一行未改 |
| 交付方 Status | **未动**（仍 `ready-for-agent`）⇒ 未自行置 verified |

**判定：verified-partial。** 1 / 2 / 4 / 5 / 6 / 7 条**通过**，第 3 条**按环境能力记为未闭合**（见下）。

#### 第 3 条为什么只能 partial —— 这是环境能力缺口，不是实现问题

它逐条穷举了本机所有触发旋转/缩放的手段并留了**原始输出**（`.scratch/splitview/evidence/D-log-rotate-resize-unavailable.txt`），我抽读确认原文：

- `devecocli emulator rotate|fold` ⇒ `Emulator scene control commands require Emulator 7.0 or later. Current Emulator version is 6.1.1.300.`（**整组 scene 命令都不可用**，不是用法错误）；
- `aa start --ww/--wh` ⇒ `start ability successfully` 但 layout dump 仍是 `[0,0,2880,1920]`（全屏 stage 应用忽略窗口参数）；
- 设备无 `wm`、WMS `hidumper` 只读、无 display density/orientation 参数、上滑进不了多任务。

⇒ 已登记为 quirks 第 31 条【平台事实】。**可迁移的判据只有单测**（`SplitView.test.ets` 的 `splitMigrationPlan` 边界）。
**这条已转 ticket 18 的真机复验**：真实平板/2in1 的旋转与窗口缩放是系统能力，正好补这一格。

#### 我改写了它的一条台账定性（改动已落在文件里）

`docs/accepted-deviations.md` 第 28 条初版写的是「参考实现**只单向迁栈顶一条**、中间几级会被丢掉」，并据此把"整段迁移"记为偏离。
**逐行复核后这个定性是错的**：

- `showMain` 在 `App.tsx:720` 定义、全仓**没有 setter**（`grep -n 'showMain' App.tsx` 只返回 `:720`/`:873`/`:904`）⇒ 恒为 true ⇒ 分栏后 `showDetail` 恒真 ⇒ **每进一个详情都触发迁移**；
- `do { goBack() } while (白名单里)` 是**循环**，剥掉的是**整段**顶部详情链；

⇒ **"整段迁移"与参考实现一致，不是偏离**（判据是"进分栏那一次"的说法也不对）。真正的偏离只有一处：**退出分栏时的对称回迁**（参考实现只是隐式地整段卸载详情容器）。
我已把第 28 条的标题、两行表格与理由段全部改写为更正后的定性，并在其中注明"2026-09-13 统筹更正定性"。
另外它把**右栏不移植 `EmptyDetail` 空屏**这一条也登记了 —— 那条**确实**是差异（参考实现右栏"返回"落到空白页），登记正确，我保留并补了"手机形态下无对应物"的理由。

#### 一处定性我确认它做对了

登录页 `maxWidth` 它标为「**修复漏移植**，不是偏离」—— 我核了参考实现 `src/screens/Login.tsx:127-130`：`inputs: { width:'100%', maxWidth: 480 }` **确实存在**，所以这是**该抄没抄**，不是故意偏离。定性正确，不进 accepted-deviations。

#### 仍未闭合（全部转 ticket 18，已写进其清单）

① 第 3 条的运行期触发（旋转/缩放）；② "不重复请求"的迁移时刻取数对比；③ 登录页那次取证的**开关自证 hilog 行未抓到**（当次启动正在锁屏，缓冲无应用域行）——它改由**消费点**承担自证（渲染的就是生产 `LoginPage` 及其几何量），并留了 `.dsh/logs/t16-login-override.patch`、经 `git diff -- Index.ets` 为空 + 复原后重建装机（`A11-tablet-shipped-build-shell-split.png`）核对，处置可接受；④ ticket 03「切 tab 保留浏览位置」无正面 dump 对比（两台设备可见条目都不足半屏、列表滚不动），替代证据 `B3` 与 `B2` 的 layout JSON **逐字节相同**（sha256 `8d22be3a…b879`）＝切 tab 再切回详情栈原样保留，判据成立但强度弱于正面滚动对比。

