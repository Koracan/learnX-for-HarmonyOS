# 15: 分栏态右栏的进入/退出动画侵入左栏

**What to build:** 横屏分栏态下，右栏（详情）在**进入**（列表点进详情）与**退出**（返回）的动画过程中，内容会画到左栏（主栏）上。
要求动画被**裁剪在右栏自己的范围内**：动画期间任何一帧，分栏线以左（x 小于主栏宽）的区域都不应出现右栏内容。

**Blocked by:** None（可立即开始）

**Status:** ready-for-agent

**判据**
- [ ] **先复现并留帧**：分栏态下触发进入与退出，在动画**中间**各截至少一帧，帧里能看到越过分栏线的内容；同时记录分栏线位置（主栏宽 px）。
- [ ] **定位**：给出转场/动画配置与容器层级的 file:line，说明为什么越界（容器未裁剪？动画位移把内容带出父容器？动画挂错层级？）。
- [ ] **修完可自证**：同样的进入/退出各取**动画中间帧至少 3 帧**，逐帧做**像素扫描**，统计分栏线以左出现右栏内容的命中数；
      必须给出修前（命中）与修后（不命中）的**同口径**对照 + 扫描脚本。别只给一张看起来正常的静态帧。
- [ ] **几何不变**：主栏 786px、分隔条 2px、右栏取余量**一字不改**（dump 对照）。
- [ ] **单测**：动画逻辑里若有可测的纯判断（如是否需要裁剪 / 是否分栏）就加断言；没有可测缝就**说明为什么没有**，不硬造。
- [ ] **门禁**：单测 + assembleHap + 四个脚本（见下）。

**派单情报（统筹者初查，供起点，不是结论）**
- 相关：`features/shell/SplitView.ets`、`features/shell/ShellTabs.ets`，以及各详情页的进/退栈路径。上一轮在这里验证过「全屏（主栏隐藏）时隐藏底栏」与「分栏态底栏收敛到主栏宽」。
- 参考帧（账号所有者原始报告图，只读，**只是症状参考、不是证据**）：`C:\Users\korac\.dsh\attachments\v1\objects\84\849fa8406ddff5bdb471ed0fc3ab0859d14cbdbd96193ef38468eec80ae9ef4c`
  —— 画面是平板分栏：左栏（课程列表）右侧能见到一块**灰色矩形**盖进左栏，即报告说的动画侵入左栏。
- 已知的相邻现象（**不是本 ticket**，别顺手改）：全屏态最左残留 2px 分隔条（`Divider().visibility` 未跟 `masterHidden`）；`#191919` 空色带未归因。

**你的资源（独占，别人不得碰）**
- worktree：`D:\Koracan\source\harmony\learnOH-wt\t15`（分支 `wt/t15`，基于 main `68e488e`）。只在你这棵树里改与构建。
- 设备：`127.0.0.1:5559`（tablet，1440×960vp）。模拟器**不能**旋转/缩放，分栏态只能在这里取。

**硬禁止（会毁掉不可恢复的东西）**：不真的提交作业；不在真机上点「退出登录」；不改设备级永久设置（语言/分辨率/密度/时区）；
不动 `.scratch/migration/**`；**不提交图片**（帧/dump/日志只留本地）；不把文档编号写进代码注释。

**构建 / 门禁环境（照做，别自创）**
1. `$env:DEVECO_SDK_HOME='C:\Program Files\Huawei\DevEco Studio\sdk'`（不设会出现 `Configuration Error: Invalid value of 'DEVECO_SDK_HOME'` 且**一条测试都不跑**）。
2. hvigor 入口：`C:/Program Files/Huawei/DevEco Studio/tools/hvigor/bin/hvigorw.bat`（不在 PATH 上）。构建以分钟计，用**后台作业**跑并把输出重定向到 `.dsh/logs/`。
3. 单测：先删 `entry/.test`，再 `test --no-incremental`；判据是 `entry/.test/default/intermediates/test/coverage_data/test_result.txt` 里的 `Tests run:` 行 + **该文件的时间戳是本轮的**（只看 BUILD SUCCESSFUL 或退出码会被假绿骗）。
4. 打包：`assembleHap --no-incremental`，然后在日志里**搜** `ERROR` / `ErrorCode` / `COMPILE RESULT`，不能只看 BUILD SUCCESSFUL。
5. 四个脚本：`node scripts/check-domain-purity.mjs`、`check-import-graph.mjs`、`check-i18n-keys.mjs`、`check-generated-fresh.mjs`（最后一个在新 worktree 首跑可能假红，判据是 `git diff` 对那 6 个生成物为空）。
6. 指纹：**不要用 hap 文件 SHA256 当「装的是哪一笔」的判据**（容器不可复现）。要比就解包比 `ets/modules.abc` 的 SHA256，或用内容级检索。
7. 设备身份以 `hdc -t SERIAL shell param get const.product.devicetype` 实测为准（`devecocli device list` 的机型列会张冠李戴）。本机模拟器**不能**旋转/缩放/折叠。

**报告要求**：结论先行；每条论断配**一个**证据（file:line、dump 的 px、帧、或 hilog 时间戳）；
做不到的如实写「没做到/存疑」，**没抓到不等于不存在**；在 `.scratch/ui-optimize/issues/你的ticket文件.md` 追加 Comment，
过程证据写进 `.scratch/ui-optimize/evidence/NN-slug.md`（可提交），图片留在 `.scratch/ui-optimize/evidence/` 且**不入库**。
收尾必须回报「**窗口关闭**」并说明设备与工作区状态（进程/画面/是否留了脏文件）。

## Comments

### 2026-09-13 · 统筹者派单
- 「动画中间帧」是本 ticket 的核心难点：`uitest dumpLayout` 抓的是稳定态，动画帧只能靠**连拍截图**或**录屏抽帧**。
  自己选一条可靠路径并在 Comment 里写明**抓帧方法**与**它可能漏掉哪一帧**（抓不到就说抓不到，不要用稳定态帧替代动画帧）。
### 2026-09-13 · 实现与自证

**结论：修好了。** 六个页面右栏的 `Navigation` 各加一处 `.clip(true)`（`git diff --stat` = 6 files / 18 insertions），进/出转场不再画进左栏。判据是像素扫描的同口径 A/B —— **进入 10/72 → 0/72**，**退出 4/200 → 0/200**；两态唯一差异就是那 6 处 clip。几何一字未改（主栏 786px / 分隔条 2px / 右栏取余量 2092px）。

**判据逐条**

- [x] **先复现并留帧**：分栏线（= 主栏宽）在 **x∈[786,788)**、宽 2px（1vp @ 密度 2），由像素扫描确定（dump 里没有 Divider 节点）。越界内容实测**宽约 415px、高贯穿整栏、主色 `#E6E6E6`**；进入方向 10 帧、退出方向 4 帧（明细见证据文件 §3）。
- [x] **定位**：越界被画出来的是右栏 `Navigation` 的 `NavDestination`（详情页真身），在转场期间被合成到那个 `Navigation` 的矩形之外。版式在六个页面同构：`Row() { 主栏 Column(width=masterPaneWidth) ; Divider ; if (splitActive) Column(layoutWeight(1)) { Navigation(detailStack) } }` —— 见 `NoticesPage.ets` 的 `build()` 里分栏 `Row` 的右栏那一段。修法就是在这个 `Navigation` 上就地 `.clip(true)`。（**存疑**：这是由结果反推的定位，我没有拿到框架侧的渲染节点树来正面证明「合成到了矩形之外」。）
- [x] **修完可自证**：同一套抓帧法、同一批点击坐标、同一帧数，逐帧像素扫描。**进入** 6 trial × 12 帧：修前 10 帧命中、修后 0 帧命中（修后 32 帧右栏确实有内容 ⇒ 0 不是「详情没打开」的假阴性）。最干净的一对是同相位帧：`Aenter-4-3`（右栏度量 2474）左栏命中 **19201** ↔ `Benter-0-3`（右栏度量同为 2474）左栏命中 **0**。**退出** 10 trial × 20 帧：修前 4 帧命中、修后 0 帧命中；修前那 4 帧的越界块左缘单调右移（x=506→546→586→622），正是详情页弹出时向右滑走的签名。扫描脚本与全部原始数字在 `.scratch/ui-optimize/evidence/15-split-right-pane-clip.md`。
- [x] **几何不变**：四张稳定帧（A/B × 进/出）在 y=900 一行的非白列都是 `786:C8C8C8 787:C3C3C3`，逐通道相同；提交态 dump：主栏 `[0,86][786,1752]` / `Divider [786,86][788,1752]` / 右栏 `[788,86][2880,1752]`（余量 2092），与基线逐字一致。
- [x] **单测**：**没有可测缝，不硬造**。修法是一处声明式 `.clip(true)` 属性，本项目单测是 host 侧纯逻辑（数字/字符串进、布尔/计划出，见 `SplitView.test.ets` 文件头），观测不到渲染层裁剪；造一个「是否要裁剪」的纯函数再断言恒真比没有更糟。既有 424 条断言全过、无回归（数字见下）。
- [x] **门禁**：单测 `Tests run: 424, Failure: 0, Error: 0, Pass: 424, Ignore: 0`（`test_result.txt` mtime 16:43:12，本轮）；`assembleHap --no-incremental` 搜 `ERROR`/`ErrorCode`/`COMPILE RESULT` 命中 0 行；四个脚本全绿。

**抓帧方法（本 ticket 的核心难点）**

`uitest dumpLayout` 只能抓稳定态，所以动画帧靠**连拍**；设备侧 `snapshot_display` 单帧 280–450ms（实测 10 帧 3798ms）。关键不是连拍本身，而是**先让连拍循环跑起来、再把点击注入进去**：设备侧脚本在后台 subshell 里连续截图，主线程 `sleep 0.30` 后执行 `uitest uiInput click`，点击因此落在连拍窗口**内部**。

我第一轮用的是「先点击、等 `click` 返回、再开始连拍」——`uitest uiInput click` 自身要 350–800ms 才返回，等它返回时几百毫秒的转场早已结束，抓到的一律是稳定态（8 帧里只命中 1 帧）。这不是现象罕见，是**采样整段落在动画之后**。改成「点击嵌进连拍窗口」后，修前每个 trial 的第 3–4 帧稳定命中，退出方向也从 1/72 提到 4/200。

**它可能漏掉哪一帧**：帧间隔约 370–450ms，而系统转场只有几百毫秒 ⇒ 一次转场通常只覆盖到 1–2 帧；**弹出方向尤其容易整段漏掉**（修前 200 帧里只有 16 帧右栏还有内容）。所以帧数不足时的「0 命中」**不能**读成「不存在」，本文的 A/B 因此用同样的帧数与时序，并且修前在同一批帧里命中过 —— 这才让修后的 0 有意义。

**顺带记一条失败的尝试**：我先试过用 `customTransition` 把转场时长拉到 3000ms 做「慢转场取证态」，实测**没有**改变动画时长（空 `event` 闭包的自定义转场看起来并未接管系统转场），这条路没走通。因此本 ticket **没有**引入任何取证开关：提交态里 `*_FOR_EVIDENCE` 一个都没新增/打开，A/B 都在系统默认转场时长下取得。

**为什么「裁剪」与「转场时长」无关**：`clip(true)` 是**合成层**的约束（把子树限制在该节点矩形内再合成），而转场只决定子节点「什么时候、以多快」在两个位置之间移动，不改变子树的合成边界 —— 所以只要某一帧把内容画到了矩形外，裁剪在**任何时长/曲线**下都会去掉它；没有一帧画到外面时，裁剪就是空操作。拉长时长只改变「有多少个不同的帧可被观测」（采样密度），不改变「哪些像素被允许出现」。

**没做到 / 存疑**

1. **退出方向的中间帧覆盖薄**：修前 200 帧里只有 16 帧右栏还有内容（弹出比抓帧间隔快），修后 14 帧。修前在同一条件下命中 4 帧 ⇒ 对照同口径；但修后的「0 命中」强度低于进入方向，应读作**「这套采样下未复现到越界」**，**不能**读成「已证明弹出不可能越界」。
2. **根因是由结果反推的**（见上「定位」的存疑）：我证明了「在这个位置加 clip 后现象消失」，但没有框架侧证据正面证明「NavDestination 被合成到了 Navigation 矩形之外」。
3. **只对公告 tab 做了逐帧像素扫描**；另外 5 个页面（作业/文件/课程/设置/搜索）的 clip 是按同一模子逐页落地的，没有分别为它们抓帧。搜索页分栏时进详情用的是 `animated=false`，本就没有那个转场。
4. **新 worktree 的既知假红**：`reference/` 在本树缺失时 `check-i18n-keys` 与 `check-generated-fresh` 会先红（`gates.md` 有记）。我用目录联接把主树的 `reference/` 接到本树后两个脚本转绿，`git status` 不受影响。

**过程证据**：`.scratch/ui-optimize/evidence/15-split-right-pane-clip.md`（含抓帧脚本、判据窗口与阴性对照、逐帧数字、未做到项）。帧与 layout dump 只留本地不入库。
