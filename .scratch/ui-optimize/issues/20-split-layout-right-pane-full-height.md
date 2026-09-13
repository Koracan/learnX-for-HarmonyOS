# 20: 分栏态整体布局 —— 底栏只在左栏底部，**右栏拿到整屏高**

**What to build:** 账号所有者第五轮反馈（2026-09-13，原话）：

> 之前解决「分屏模式下底栏应在左侧」时采用的方法是**调整底栏宽度**，但是这样**右侧的下部会变成空白，而不能让给详情页使用**。
> 我希望的布局是：**分割线左侧放置底栏和列表，分割线右侧全部由详情页占据**。这里应该调整**整体的页面布局**。

**现状（统筹者读代码得到的机制，需你复核）**：`features/shell/ShellTabs.ets` 的根是一个 `Column`：
`[ Tabs（layoutWeight 1，五个 tab 页都画在这里） ; tabBar（height = barH，width = 主栏宽） ]`。
于是**内容区高度 = 屏高 − barH**（右栏的详情也跟着少了一条 barH 高的带子），而底栏只画在 x∈[0, 主栏宽] 内 ⇒
右栏下方那条带子**既没给底栏用、也没给详情页用**（账号所有者截图里红框圈的就是它）。
上一轮（ticket 04）只改了底栏**宽度**，没有改**高度分配** —— 本 ticket 改的就是后者。

**Blocked by:** None（可立即开始）

**Status:** verified

**判据（每条都要 layout dump 的 px 或单测）**

A. 分栏态（tablet，恒横屏）
- [ ] **右栏（详情）拿到整屏高**：右栏根容器（各页面 detailPane 的容器 / 其 Navigation）的 bounds **下边界 = 屏幕下边界**（本机 tablet = 1920px）。
      给**判别性**证据：同一次对照里，修前右栏容器下边界 < 1920、且右栏列表最后一条被截；修后下边界 = 1920，且**同一条列表能多显示至少一行**（dump 里多出一个 ListItem，或该行 bounds 完整落在 1920 以内）。
- [ ] **底栏仍在左栏底部且宽度不变**（上一轮已验收的判据不许回退）：命中区 x∈[0,786]、y∈[1920−barH,1920]；barH 与修前逐 px 相同。
- [ ] **主栏内容不被底栏遮挡**（本次改法最容易做错的一条）：左栏列表**最后一个可见项**的 bounds 下边界 ≤ 底栏上边界；即左栏内容仍留出 barH 的预留，不许「底栏浮在最后一行上面」。
- [ ] 右栏内容不被底栏遮挡 / 不被裁切：右栏底部区域（x>786）没有任何元素被底栏覆盖；详情列表滚到底时最后一行完整可见。
- [ ] 分隔线（1px）与主栏宽度（786px）不变。

B. 单栏态（phone）与全屏档不许回退
- [ ] **单栏**（phone）：底栏横跨整屏（x∈[0,全宽]）、内容区高度 = 屏高 − barH —— 与改前**逐字节兼容**（同一页面 dump 对比，允许相对时间文本这类已知差异）。
- [ ] **分栏 + 主栏隐藏**（文件详情的全屏档）：底栏整条隐藏、**不占位**（`bottomBarLayout` 的第三档语义不变）。

C. 单测
- [ ] 把「高度怎么分」抽成**纯函数**钉住（示例签名：输入 `splitActive` / `masterHidden` / 屏高 / barH ⇒ 输出：内容区高度、主栏底部预留、底栏可见性与宽度），
      并覆盖：单栏 / 分栏+主栏可见 / 分栏+主栏隐藏 / 边界（屏高比 barH 还小）。沿用 `entry/src/test/SplitView.test.ets` 的缝（那里已经在钉 `bottomBarLayout`）。
- [ ] **只有一处**决定 barH 与「主栏底部预留多少」—— 不许 shell 与 5 个页面各算一遍（`ShellTabs.barHeight()` 现在是私有方法，见下）。

D. 门禁与纪律
- [ ] 单测 + `assembleHap` + 四个脚本，全部在你这棵树里跑（见文末）。
- [ ] 不点「退出登录」、不改设备级永久设置、不动 `.scratch/migration/**`、**不提交图片**、不把台账或 ticket 编号写进代码注释。

**派单情报（统筹者初查，均需你自己复核）**
- 根布局：`ShellTabs.ets:330-396`（`Column` + `Tabs.layoutWeight(1)` + `this.tabBar()`；`.alignItems(HorizontalAlign.Start)` 是上一轮为了「底栏停在左端」加的）。
- barH 的来源：`ShellTabs.barHeight()` = `theme.sizes.controlHeight + theme.sizes.space4`（`ShellTabs.ets:244-246`）—— 目前是私有方法，其它地方算不出来。
- 底栏宽度三档：`SplitView.bottomBarLayout()`（`SplitView.ets:136-144`）＋ `SplitView.test.ets` 的单测。
- **分栏是两个 pane 都在页面里画的**：`features/{notices,assignments,files,courses,settings}/*Page.ets` 各自渲染 `masterPane`（宽 786px）+ `Divider` + `detailPane`（`layoutWeight(1)`），它们订阅 `SPLIT_VIEW_ACTIVE_KEY`。
  ⇒ `ShellTabs` 只画 `Tabs` + 底栏，**看不到** divider 与右栏；要让右栏拿整屏高，要么让内容区高度 = 屏高（并由每个页面在自己的**主栏**底部留出 barH），要么把底栏下放到各页的 master pane 里。两条路都行，**你选一条并写出理由**；关键是 A.3（主栏不被遮）。
- 参考实现（RN）的做法**不同构**：它是两个独立 NavigationContainer 并列（`App.tsx:885-896`），底栏在 `SplitView.tsx` 里属于**左栏**那一支 —— 所以「底栏在左栏内部、右栏占满高度」本来就更接近参考实现；本工程现在这版是「整宽 Column + 收窄底栏」，属于移植时的简化。**参考实现只是标尺**，这里以账号所有者的要求为准。
- 设备限制：本机模拟器**不能旋转 / 缩放窗口**（`docs/agents/environment.md`）⇒ 单栏那一档在 tablet 上排不出来，必须用 phone 复核（已给你一台）。

**你的资源（独占，别人不得碰）**
- worktree：`D:\\Koracan\\source\\harmony\\learnOH-wt\\t20`（分支 `wt/t20`，基于 main `c9b37c2`）。`ohpm install` 与 `reference/` 已由统筹者做好。只在这棵树里改与构建；开工前 / 每次构建前 / 每次取证前 `git rev-parse --show-toplevel` 自证。
- 设备：**`127.0.0.1:5559`（tablet）** —— 本机**唯一**能出分栏的机器，A 组全部取证用它；**`127.0.0.1:5555`（phone）** 归你做 B 组单栏回归。**`127.0.0.1:5557` 是 ticket 19 的，不要碰。** 两台都用显式 `--device` / `-t`。
- 锁屏会给黑帧：取窗前 `hdc shell power-shell wakeup` 并上滑解锁（实测设备会自己锁屏）。

**构建 / 门禁环境（照做，别自创）**
1. `$env:DEVECO_SDK_HOME='C:\\Program Files\\Huawei\\DevEco Studio\\sdk'`（不设会一条测试都不跑）。
2. hvigor 入口 `C:/Program Files/Huawei/DevEco Studio/tools/hvigor/bin/hvigorw.bat`；构建以分钟计，用后台作业 + 重定向到 `.dsh/logs/`。
3. 单测：先删 `entry/.test`，再 `test --no-incremental`；判据是 `test_result.txt` 的 `Tests run:` 行 **+ 该文件时间戳是本轮的**（基线：合并后的 main 上是 **441** 条）。
4. 打包 `assembleHap --no-incremental` 后搜 `ERROR` / `ErrorCode` / `COMPILE RESULT`（不能只看 BUILD SUCCESSFUL）。
5. 四脚本：`check-domain-purity.mjs` / `check-import-graph.mjs` / `check-i18n-keys.mjs` / `check-generated-fresh.mjs`。
6. 指纹：不要用 hap 文件 SHA256；要比就解包比 `ets/modules.abc` 的 SHA256（只在同一棵树内可比）。
7. 取几何用 `devecocli ui layout --format json`，坐标一律取 dump 的 px（不要目测截图）。

**报告要求**：结论先行；每条论断配**一个**证据（dump 的 bounds px、单测、file:line）；做不到的如实写；
在 `.scratch/ui-optimize/issues/20-split-layout-right-pane-full-height.md` 追加 Comment，过程证据写进 `.scratch/ui-optimize/evidence/20-<slug>.md`（可提交），图片只留本地。
收尾回报「**窗口关闭**」，说明两台设备是否都已复原（学期 / 画面 / 是否留了脏文件）。

## Comments

### 2026-09-13 · 实现方（wt/t20）汇报：判据全绿，两处口径偏差如实写在 §6

**结论先行**：分栏态改成「分割线左侧 = 底栏 + 列表，右侧 = 详情占满整屏高」。
右栏下边界 **1752 → 1864**（1864 = 本应用渲染区下边界 = 底栏下边界），底栏几何**逐值未变**，
主栏列表底部仍停在底栏上边界 1752，phone 单栏 dump 与改前**逐节点 0 差异**。
完整原始数字、判据 ↔ 证据表、未做到项见 `.scratch/ui-optimize/evidence/20-split-right-pane-full-height.md`。

**路线（先选后做）**：选「内容区拿满高 + 各页主栏底部预留 barH」。理由：① 底栏是壳层的东西（要 activeIndex / switchTo），
下放到 5 个页面意味着 5 份底栏 UI 与一条回调链，而 C.2 要的正是「只有一处」；② 下放会把底栏节点搬进页面子树，
单栏 dump 的树路径整段改变，而 B.1 要求逐字节兼容 —— 现在这条路在单栏态的两个新修饰符取值为 0，等于没动版式；
③ 参考实现本来就更接近这一条。

**实现**：`features/shell/SplitView.ets` 新增 `bottomBarHeight(theme)`（barH 的**唯一**算法，原 `ShellTabs` 私有方法已删）、
`masterPaneBottomReserve(theme, split, hidden)`、`splitHeightBudget(split, hidden, 屏高, barH)`；
壳层分栏态给底栏 `margin.top = −barH`（不占流内高度、盒子仍落 `[屏高−barH, 屏高]`，实测位置与单栏逐值相同）；
五个页面各自主栏加 `padding({ bottom: masterPaneBottomReserve(...) })`。**没有新增任何尺寸常量**。

**关键原始数字（tablet 5559 = 2880×1920px @密度2，barH = 56vp = 112px）**

| 判据 | 改前 → 改后 | 结论 |
| --- | --- | --- |
| A.1 右栏容器下边界 | `[788,86,2880,1752]` → `[788,86,2880,1864]`（+112）；空态图标中心 y 875 → 931 | 成立（1864 = 应用渲染区下边界，见下 §口径） |
| A.1 同一文档多显示 | Web 文档容器 h 1390 → 1502；尾部图片可见高 646 → 758（+112） | 成立（帧上原先被切半截的那一行整行可读） |
| A.2 底栏 | `Row [0,1752,786,1864]` + 5 命中区 x∈[0,786]/y∈[1754,1864]，**逐值相同** | 成立 |
| A.3 主栏不被遮 | `Refresh`/`List` `[0,266,786,1752]`，ListItem `[0,266,786,532]`/`[0,534,786,800]` 逐值相同 | 成立 |
| A.4/A.5 | 底栏 x_max=786、右栏节点 x≥788；`Divider [786,86,788,…]` 2px、主栏 786px 未变 | 成立 |
| B.1 单栏 | phone 改前/改后 dump 逐节点 **0 差异**（76 节点） | 成立 |
| B.2 全屏档 | 底栏节点在 dump 里**一个都不在**、主栏容器 `[0,0,0,0]`、详情铺满 x∈[34,2848] | 成立 |
| C.1/C.2 | 2 条新单测（三档 + 单栏残留 masterHidden + 边界 屏高<barH / =barH / =0；跨四档断言页面侧与壳层侧预留同值） | 成立 |

**门禁**（都在本树 `D:/Koracan/source/harmony/learnOH-wt/t20` 跑）：单测 `Tests run: 443, Failure: 0, Error: 0, Pass: 443`，
`test_result.txt` 时间戳 2026/9/13 19:30:04（本轮；基线 441，+2 = 本次新增）；`assembleHap --no-incremental` SUCCESSFUL 且日志零 ERROR；
四个脚本 PASS / PASS / OK / PASS（`check-generated-fresh` 首跑即绿）。
**产物指纹**：改前 `ets/modules.abc` = `ADB87D7E…`，改后 = `F5A1B56E…`；收尾重新构建一次仍得 `F5A1B56E…` ⇒ 设备上跑的就是这笔。
（两次构建都在同一棵树里做：`git stash push -- entry` → 编 → 装 → `stash pop` → 编 → 装。）

**两处口径偏差（如实报，不拿「看起来好了」填空）**

1. **A.1 写的「= 1920px」是物理屏高，应用排不到**：本机应用渲染区实测 `y∈[86,1864]`（上 86px 状态栏、下 56px 系统手势条安全区），
   改后右栏下边界 = **1864 = 底栏下边界 = 应用能排到的最后一像素**。要落到 1920 得先扩安全区，那会同时把底栏推下去、直接违反 A.2，不在本 ticket 内。
   （ticket 04 已验收的分栏帧里底栏也是 `[…,1864]`，本工程几何基线一直是 1864。）
2. **A.1 的「多出一个 ListItem」拿不到**：本账号右栏没有任何会溢出的列表 —— 学期列表 9×112=1008px（视口 1554/1666）、
   课程文件列表 4×120=480px（视口 1398/1510）、主栏列表各 2 条。替代证据 = 同一文档同一滚动位多显示 112px + 帧上被切半截的行整行可读。
   抓不到就说抓不到。

**另记一条未归因、无可见后果的异常**：改后 `Tabs`/`Swiper` 的盒报 `[0,86,2880,1920]`（比父 Column 与自己的 `TabContent` 各高 56px）——
内容盒（TabContent / 页面 Row / 两栏）都在 1864 收住、两帧无可见异常，超出的那 56px 落在系统手势条安全区里；机制未查明，已记入证据文档 §6.3。

**范围外**：`SearchPage` 同样画「主栏+分隔线+右栏」，但它挂在根栈上整屏盖住底栏，其下没有底栏要预留，未动（ticket 点名的 5 个页面都已改）。

**改动文件**：`SplitView.ets`、`ShellTabs.ets`、`SplitView.test.ets`、5 个页面（notices/assignments/files/courses/settings），共 8 个。

**状态**：`5559`（tablet）与 `5555`（phone）都装着改后产物、已冷启停在公告 tab 单栏/分栏正确形态；**学期未改**（只打开过学期切换页）；
未碰 `5557`；未 merge/rebase/push。副作用一条：验收全屏档时打开过一个 212MB ZIP 的文件详情，按既有行为自动下载进了应用内 cache。

### 复核 Comment（统筹者，merge `8156708`）

**结论：通过。** 关键判据由我自己重做：先在工树里重跑门禁，再在 **5559** 上做 before/after 两态 A/B
（before = 合并前主树 19:11 的产物，after = 工树 19:33 的产物），**不采信实现者自报的数字**。

**我自己的 A/B（5559 tablet，2880×1920px @2，barH=112px；全部 `devecocli ui layout --mode full` 的 px）**
- 空详情态（重启后冷启停公告 tab）：右栏整条链 `Column / Navigation / NavBar / NavBarContent`
  `[788,86,2880,1752] → [788,86,2880,1864]`（**+112 = barH**）；空态图标中心 y 875→931（+56，居中）。
- 打开同一份公告（同一滚动位）：右栏 `Navigation / NavigationContent / NavDestination / NavDestinationContent / Column / Scroll / Web / rootWebArea / genericContainer`
  全部 `1752 → 1864`；文档容器 `[820,362,2848,1752] → [820,362,2848,1864]`；
  文档尾部那张图 `[820,1106,2460,1752] → [820,1106,2460,1864]` ⇒ **可见高 646 → 758（+112）**。
- **A.3 主栏没被遮**（我最担心的一条）：主栏 `Navigation [0,86,786,1752]`、`Refresh [0,266,786,1752]`、
  `List [0,266,786,1752]`、两个 `ListItem` 在两种状态下**逐值不变** ⇒ 列表底 1752 = 底栏上边界。
- **A.2 底栏没被改回去**：`Row [0,1752,786,1864]` 与 5 个命中区 `x∈[0,157/157,314/…/629,786]`、`y∈[1754,1864]` 逐值不变。
- 两次 dump 都是 109 个节点，差异**只落在高度链**上（没有节点位移或消失）。
- **B.1 单栏逐字节**：5555（phone）改前/改后 dump **SHA256 相同**（`FA786D42…`，64501 B）⇒ 单栏 0 差异，我自己复现。
- 合并后的主树产物也装到两台设备：空态 dump 与工树产物 dump **逐字节相同**（5559 `675388C6…`、5555 `FA786D42…`）；
  5559 上打开公告的分栏帧**渲染出内容**，文档末行「群聊：形式语言与自动机 2026 秋」完整可见（改前那版这行在底边被切）；
  hilog 消费点自证 `split height budget: appH=960 barH=56 barWidth=393 barVisible=true shellContentBottomInset=0 barMarginTop=-56 masterPaneBottomInset=56 masterContentH=904 detailContentH=960`。

**门禁（我自己跑的）**
- 工树 `wt/t20`：`Tests run: 443, Failure: 0, Error: 0, Pass: 443, Ignore: 0`（test_result.txt mtime 19:32:51）；
  `assembleHap --no-incremental` BUILD SUCCESSFUL ×1、`ERROR / ErrorCode / COMPILE RESULT` = 0；四脚本 PASS / PASS / RESULT: OK / PASS；
  解包 `ets/modules.abc` `F5A1B56E…`（1,826,096 B）—— 与实现者自报逐字一致。
- 合并后主树 `8156708`：`Tests run: 454`（441 + 19 的 11 + 20 的 2，mtime 19:40:11）、assemble 0/0/0、四脚本全绿、`git status` 干净。
- 合并过程：唯一冲突是本 ticket 文档（add/add）；`SettingsPage.ets` 自动合并成功，我逐行确认 **ticket 19 的导出改动**
  （`LogExport` import / `exportInFlight` / `log export reported`）与**本 ticket 的预留**（`masterPaneReserve` / `padding({ bottom })`）都在。

**对我自己判据的一处纠正**：我在 ticket A.1 里写的「右栏下边界 = 1920（屏底）」是**我写错了** ——
这台平板的**应用渲染区**是 `y∈[86,1864]`（上 86px 状态栏、下 56px 手势区），底栏（ticket 04 已验收）下边界本来就是 1864；
1920 只有扩安全区才够得到，而那样会同时把底栏推下去、违反 A.2。**能站住的判据是「+barH 且与底栏下边界相等」**，这条成立，
实现者把它改成这个说法是对的。

**我没能独立复现的（如实记）**
1. **B.2 全屏档（分栏 + 主栏隐藏）**：要走到它得「文件 tab → 打开文件详情 → 点全屏按钮」，本轮我没有走完这条路，
   只有实现者的帧 + 单测（`splitHeightBudget(true, true, …)` 的三档 invariant）。这是**回归护栏**，不是本 ticket 的要害。
2. `Tabs/Swiper` 盒报 `[0,86,2880,1920]` 而 `TabContent [0,86,2880,1864]`：我的 dump **逐值复现**了这个溢出，
   帧上看不出后果（多出的部分落在系统手势区）。实现者已记为未归因，我同意保留观察、不阻塞。
3. 取证方法的一条环境事实：反复 `hdc install -r` 之后，**5559 的 Web 表面在截帧里是黑的**（before/after 两版一样黑），
   而同一时刻 layout dump 的 Web 子树是完整的（有 paragraph / image 节点）⇒ 这是截帧与合成的环境问题，不是本次改动；
   我 `reboot` 之后同一个产物就能渲染出内容（本 Comment 提到的那帧就是重启后拍的）。以后遇到「右栏一片黑」先重启设备再判断。
4. 设备副作用（实现者已声明、我复核确认）：验收全屏档时打开过一个 212MB ZIP 的文件详情，按既有行为下载进了应用内 cache，未落用户目录。
