# ticket 15 · 分栏态右栏的进/出转场不再画进左栏

**结论**：修好了。判据是**像素扫描**的同口径 A/B 对照（同一台设备、同一套抓帧法、同一批点击坐标、同一帧数），
两态的唯一差异是六个页面右栏 `Navigation` 上的 `.clip(true)`（`git diff --stat` = 6 files / 18 insertions）。

| 方向 | 修前（A：HEAD `af163b4`） | 修后（B：+6 处 `.clip(true)`） |
| --- | --- | --- |
| 进入（列表 → 详情） | **10 / 72** 帧左栏出现右栏内容 | **0 / 72** |
| 退出（详情 → 返回） | **4 / 200** 帧命中 | **0 / 200** |

几何一字未改：主栏 `786px` / 分隔条 `2px` / 右栏取余量 `2092px`（三处 A、B 两态逐字相同，见下）。

---

## 1. 判据：像素扫描的窗口与它为什么可信

扫描窗口 **x∈[370,780] × y∈[860,1700]**（在 2880×1920 px 的帧上，每 4 px 采一点 ⇒ 21733 个采样点），
统计**非白**像素（通道均值 < 250）。选这段窗口的理由是**主栏在那里的内容集是空集**：
公告 tab 的列表只有两条，占 y∈[266,800]；页头与筛选片在 y<266；底栏在 y≥1752。
⇒ y∈[860,1700] 这一段左栏稳定态**必然是纯白**，任何非白像素都不可能来自主栏自身。

**阴性对照**（同一条扫描、同一窗口）：

| 帧 | 命中 |
| --- | --- |
| `Aenter-0-0.jpeg`（修前、点击前的稳定帧） | 0 / 21733 |
| `Aenter-0-1.jpeg` | 0 / 21733 |
| `Aenter-0-10.jpeg`（修前、点击后的稳定帧） | 0 / 21733 |
| `Benter-0-0.jpeg`（修后稳定帧） | 0 / 21733 |
| `B2exit-0-0.jpeg`（修后稳定帧） | 0 / 21733 |

即：稳定态（无论修前修后）恒为 0 命中 ⇒ 判据不会把稳定态误判成越界。

## 2. 抓帧方法，以及它可能漏掉哪一帧

**工具**：设备侧 `snapshot_display -f <path>`（JPEG，2880×1920）。单帧 280–450 ms，其中进程启动占大头
（实测 10 帧连拍 3798 ms ⇒ 约 380 ms/帧）。`uitest dumpLayout` 只能拿稳定态，所以动画帧只能靠连拍。

**关键做法**：**先让连拍循环跑起来，再把点击注入进去**。设备侧脚本 `tools/cap.sh` 在一个后台 subshell 里
连续 `snapshot_display`，主线程 `sleep 0.30` 后执行 `uitest uiInput click`，点击因此落在连拍窗口**内部**。

**为什么必须这样**：`uitest uiInput click` 自身要 350–800 ms 才返回（进程启动 + 无障碍注入）。
早期做法是「先点击、等它返回、再开始连拍」——等 `click` 返回时系统转场（几百毫秒）早已结束，
抓到的一律是稳定态。这就是我第一轮「8 帧只命中 1 帧」的原因：不是现象罕见，是采样整段落在动画之后。
改成「点击嵌进连拍窗口」之后，修前每个 trial 的第 3–4 帧稳定命中（见下），退出方向也从 1/72 提升到 4/200。

**它可能漏掉哪一帧**：帧间隔约 370–450 ms，而系统转场只有几百毫秒 ⇒ 一次转场里通常只覆盖到 1–2 帧，
**弹出方向尤其容易整段漏掉**（A 侧 200 帧里只有 16 帧右栏还有内容）。
所以：帧数不足时的「0 命中」**不能**读成「不存在」；本文的 A/B 因此用**同样的帧数与时序**，
并且 A 侧在同一批帧里命中过 —— 这才让 B 侧的 0 有意义。

**关于慢转场**：我试过用 `customTransition` 把时长拉到 3000 ms 来做「慢转场取证态」，
实测**没有**改变动画时长（动画仍然在两次抓帧之间完成），空 `event` 闭包的自定义转场看起来并未接管系统转场。
这条路没走通，最终没有引入任何取证开关：提交态里 `*_FOR_EVIDENCE` 一个都没新增/打开。

## 3. A/B 逐帧对照

### 3.1 进入方向：6 trial × 12 帧 = 72 帧/态

抓帧时序（`Aenter-2` 的 `tools/cap.sh` 时间线，设备毫秒时钟）：

```
SNAP 1789287273198  ← 连拍循环起跑
CLICK 1789287273505 ← 注入点击
SNAP 1789287273595 / 273989 / 274379 / 274895 / 275317 / …
```

修前命中帧（全部落在每个 trial 的第 3–4 帧）：

| 帧 | hit/21733 | bbox（x 范围） | 命中色主色 | 同帧右栏 |
| --- | --- | --- | --- | --- |
| `Aenter-0-3` | 20889 | [386,778] | `E7E7E7` | CONTENT 746 |
| `Aenter-1-3` | 21311 | [378,778] | `E6E6E6` | CONTENT 427 |
| `Aenter-1-4` | 21733 | [370,778] | `E6E6E6` | EMPTY 84 |
| `Aenter-2-3` | 21311 | [378,778] | `E6E6E6` | CONTENT 427 |
| `Aenter-3-3` | 6752 | [654,778] | `F8F8F8` | EMPTY 23 |
| `Aenter-3-4` | 21733 | [370,778] | `E6E6E6` | EMPTY 90 |
| `Aenter-4-3` | 19201 | [418,778] | `E9E9E9` | CONTENT 2474 |
| `Aenter-4-4` | 21733 | [370,778] | `E6E6E6` | EMPTY 84 |
| `Aenter-5-3` | 15614 | [486,778] | `EDEDED` | CONTENT 5840 |
| `Aenter-5-4` | 21733 | [370,778] | `E6E6E6` | EMPTY 84 |

**同一相位的配对帧**（这是最干净的一对）：

| | 帧 | 右栏度量 | 左栏命中 |
| --- | --- | --- | --- |
| 修前 | `Aenter-4-3` | CONTENT 2474 | **19201** |
| 修后 | `Benter-0-3` | CONTENT 2474（同一相位） | **0** |

修后：`bleedFrames=0/72`，其中 `contentFrames=32`（**右栏确实有内容**，所以 0 不是「详情没打开」的假阴性）。

### 3.2 退出方向：10 trial × 20 帧 = 200 帧/态

修前命中 4 帧，全部是第 1 帧，且**越界块的左缘单调右移** —— 正是详情页在弹出时向右滑走的签名：

| 帧 | hit/21733 | bbox 左缘 | 命中色 | 同帧右栏 |
| --- | --- | --- | --- | --- |
| `A2exit-2-1` | 14559 | x=506 | `EDEDED` | CONTENT 8181 |
| `A2exit-7-1` | 12449 | x=546 | `F0F0F0` | CONTENT 19049 |
| `A2exit-8-1` | 10339 | x=586 | `F2F2F2` | CONTENT 12038 |
| `A2exit-9-1` | 8440 | x=622 | `F4F4F4` | CONTENT 13764 |

修后：`bleedFrames=0/200`（`contentFrames=14`）。

## 4. 定位

分栏版式在六个页面逐页同构（`NoticesPage` / `AssignmentsPage` / `FilesPage` / `CoursesPage` / `SettingsPage` / `SearchPage`）：
`Row() { 主栏 Column(width=masterPaneWidth) ; Divider ; if (splitActive) Column(layoutWeight(1)) { Navigation(detailStack) { detailPane() } } }`。
越界被画出来的东西是**右栏 `Navigation` 的 `NavDestination`**（详情页真身），它在进/出转场期间被合成到了那个 `Navigation` 的矩形之外，
于是盖住左栏一截（实测宽约 415 px、高贯穿整栏，主色 `#E6E6E6`）。

**修法**：在那个 `Navigation` 上就地 `.clip(true)`（六个页面各一处；行号为提交态实测 `git grep -n 'clip(true)'`）：

- `entry/src/main/ets/features/notices/NoticesPage.ets:747`（分栏 `Row` 的右栏）
- `entry/src/main/ets/features/assignments/AssignmentsPage.ets:777`
- `entry/src/main/ets/features/files/FilesPage.ets:673`
- `entry/src/main/ets/features/courses/CoursesPage.ets:702`
- `entry/src/main/ets/features/settings/SettingsPage.ets:524`
- `entry/src/main/ets/features/search/SearchPage.ets:675`

没有动版式：主栏宽度、分隔条宽度、右栏 `layoutWeight` 全部未改。

## 5. 为什么「裁剪」与「转场时长」无关

`clip(true)` 是**合成层**的约束：它把该节点的子树限制在它自己的矩形内再合成。
转场只决定子节点**什么时候、以多快**在两个位置之间移动，不改变子树的合成边界。
⇒ 只要某一帧把内容画到了矩形之外，裁剪就在**任何时长/曲线**下把它去掉；反过来说，如果没有任何一帧画到外面，裁剪就是空操作。
拉长转场时长改变的只是「有多少个不同的帧可被观测到」（采样密度），不改变「哪些像素被允许出现」。
所以本文的 A/B 都在**系统默认转场时长**下取得，唯一变量是那 6 处 `.clip(true)`；
取证开关（会改变时长的那个）最终一个都没有进提交态。

## 6. 几何不变（A/B 同口径）

同一条像素扫描（y=900 一行、x∈[700,900]）：

| 帧 | 非白列 |
| --- | --- |
| `Aenter-0-0`（修前稳定） | `786:C8C8C8 787:C3C3C3` |
| `A2exit-0-0`（修前稳定） | `786:C8C8C8 787:C3C3C3` |
| `Benter-0-0`（修后稳定） | `786:C8C8C8 787:C3C3C3` |
| `B2exit-0-0`（修后稳定） | `786:C8C8C8 787:C3C3C3` |

⇒ 分隔条 = x∈[786,788)，宽 2 px（1vp @ 密度 2），四张帧逐通道相同。

提交态 layout dump（`final-layout.json`，分栏 + 公告 tab）：

```
Navigation [0,86][2880,1920]      ← 根
Navigation [0,86][786,1752]       ← 主栏：786 px 宽
Divider    [786,86][788,1752]     ← 分隔条：2 px
Navigation [788,86][2880,1752]    ← 右栏：余量 2092 px
```

与仓库里记录的基线（786 + 2 + 2092 = 2880）逐字一致。

## 7. 同一性（这份证据对应哪一份产物）

| 项 | 值 |
| --- | --- |
| worktree | `D:/Koracan/source/harmony/learnOH-wt/t15`（`git rev-parse --show-toplevel` 实测） |
| 分支 / 起点 | `wt/t15` / `af163b4` |
| A 态工作区 | `git status --porcelain` 为空（就是 `af163b4`） |
| B 态工作区 | 6 个文件 modified（`git diff --stat` = 6 files / 18 insertions） |
| A 产物 | `ets/modules.abc` 1783796 B，SHA256 `966051B03318B8560E86D5282F1CFAD7B572AC1977E7095C1AEC72C3BAFDB480` |
| B 产物 | `ets/modules.abc` 1784036 B，SHA256 `9E0726FC94B154D297C129C6B9E8059D02CA722A54EF19E02971C3D7EEF38B40` |
| 设备 | `127.0.0.1:5559`，`const.product.devicetype=tablet`、`const.ohos.apiversion=23`、2880×1920 px / 1440×960 vp |
| 构建日志 | `.dsh/logs/t15-A-before.log`（41 s）、`t15-A2-before.log`（10.8 s）、`t15-B-after.log`（12.7 s）、`t15-B2-after.log`（9.5 s）：均 `BUILD SUCCESSFUL`，搜 `ERROR`/`ErrorCode`/`COMPILE RESULT` 命中 0 行 |

抓帧用的都是**同一个页面状态**：公告 tab、分栏态、右栏初始为空；点击坐标 `(400,380)`（第 1 条列表项内）与 `(828,122)`（右栏返回按钮内），
两个坐标都取自 layout dump 的 px，不是截图目测。
每个 trial 前都 `aa force-stop` + `aa start` 冷启动，保证右栏 `detailStack` 为空；
退出方向在注入返回点击**之前**先轮询 layout dump 直到右栏返回按钮挂载为止（`bounds` 含 `[788,86][868,158]`），
避免把「详情没打开」的帧算成「退出正常」。

## 8. 未做到 / 存疑

1. **退出方向的中间帧覆盖薄**：A 侧 200 帧里只有 16 帧右栏还有内容、B 侧 14 帧（弹出比抓帧间隔快）。
   A 在同一批帧里命中过 4 帧，所以对照是同口径的；但 B 侧的「0 命中」强度低于进入方向，
   应读作**「这套采样下未复现到越界」**，不能读成「已证明弹出不可能越界」。
2. **根因是「由结果反推的定位」**：我证明了「在这个位置加 `clip(true)` 后现象消失」，
   但没有拿到框架侧（ArkUI/渲染节点树）的证据去正面证明「`NavDestination` 被合成到了 `Navigation` 矩形之外」。
   裁剪生效的位置就是越界内容所属的子树，这指向该 `Navigation` 的合成边界，但这不是框架源码级的确认。
3. **只对公告 tab 做了逐页像素扫描**；另外 5 个页面（作业/文件/课程/设置/搜索）的 `.clip(true)` 是按同一模子逐页落地的，
   **没有**为它们各自抓帧取证。搜索页分栏时进详情用的是 `animated=false`，本就没有那个转场。
4. **慢转场取证态没做成**：`customTransition` 拉时长实测无效（见 §2），所以本文没有慢转场的对照，
   也就没有引入 `SLOW_TRANSITION_FOR_EVIDENCE` 这类开关。
5. **单测没有可测缝**：修法是一处声明式的 `.clip(true)` 属性，本项目单测是 host 侧纯逻辑（数字/字符串进、布尔/计划出），
   观测不到渲染层的裁剪；硬造一个「是否要裁剪」的纯函数再断言恒真，比没有更糟。
   所以本 ticket 不加断言，只保证既有 `SplitView.test.ets` 等不回归（门禁数字见交付回报）。

## 9. 文件清单

**工具（可提交，不是证据）**：`.scratch/ui-optimize/evidence/t15/tools/`

| 文件 | 作用 |
| --- | --- |
| `cap.sh` | 设备侧连拍 + 把点击嵌进连拍窗口（本 ticket 抓帧方法的核心） |
| `run_trials.ps1` | 冷启动 + 调 `cap.sh` + 回拉帧与时间线；退出方向先轮询右栏已挂载 |
| `bleedscan.ps1` | 判据：左栏「必然纯白」窗口的非白像素计数（本文所有 hit 数都出自它） |
| `rightpane.ps1` | 右栏是否有内容的度量（用来排除「详情没打开」的假阴性） |
| `divider.ps1` | y=900 一行在 x∈[700,900] 的非白列（分隔条位置与宽度） |
| `pixelscan.ps1` / `charviz.ps1` / `flat.ps1` | 全窗口直方图 / 帧的字符化预览 / layout dump 展平 |

**帧（只留本地，不入库）**：`frames-A-enter/`、`frames-A-exit/`、`frames-A-exit2/`、`frames-B-enter/`、`frames-B-exit/`、`frames-B-exit2/`，
外加每 trial 一份 `*-tl.txt`（设备侧毫秒时间线，用来核对每一帧相对点击的位置）。
`final-layout.json` 是提交态的 layout dump。
