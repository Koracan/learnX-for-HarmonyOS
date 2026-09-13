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

**Status:** open

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