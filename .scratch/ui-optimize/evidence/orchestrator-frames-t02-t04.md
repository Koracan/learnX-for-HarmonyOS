# 统筹者补帧：ticket 02 预览图标 + ticket 04 全屏底栏（设备取证）

**设备**：`127.0.0.1:5559`（`const.product.devicetype=tablet`、`const.ohos.apiversion=23`、`const.product.model=emulator`、视口 2880×1920 px / 1440×960 vp ⇒ 密度 2）。
**取证窗口**：2026-09-13 14:18–14:37（主机本地时间；设备 `date` 与主机一致，状态栏 "02:36" 是 12 小时制 = 14:36，**没有时钟偏移**）。
**未构建、未装机**：本轮只跑 `hdc` / `devecocli ui` / `aa force-stop` / `aa start` / `hilog`。5555 / 5557 全程未触碰。

## 溯源

| 项 | 值 |
| --- | --- |
| 取证开始时 `git rev-parse HEAD` | `7a173f4a2be18acd0f3daf9a54a2aa87bd430606` |
| 取证结束时 `git rev-parse HEAD` | `7487e44a6c415da0f8dba30934d3d86f14e31a48`（**共享工作区里别的线在本轮中途提交了**，非我所为） |
| `git status --porcelain` | 两次均为**空** |
| 任务书给的产物来源 | commit `675e742`（`675e742c68ebc962649148b71ab0d6930f5cbea3`，committer date `2026-09-13T14:13:30+08:00`），已确认是 HEAD 的祖先 |
| 本地产物 | `entry/build/default/outputs/default/entry-default-signed.hap`，5,000,382 B，mtime `2026-09-13 13:11:02`，SHA256 `D91B91D4E00E291A6EEA1D59868E8D67C33C7B53451E1C002940BE6BCB505CE6` |

**产物同一性：未取到，如实记账。**
设备上的 hap 读不到（`hdc shell find /data/app/el1/bundle/public/com.koracan.learnOH` ⇒ `Permission denied`），
因此无法给出"设备上装的这一份"的 `ets/modules.abc` 指纹。`bm dump` 只回 `versionName=2.0.0` / `versionCode=2000000`、
`hapPath=/data/app/el1/bundle/public/com.koracan.learnOH/entry.hap`、`firstInstallTime=installTime=1789230939346`
（= `2026-09-12 16:35:39 UTC` = `2026-09-13 00:35:39 CST`）。
**这条时间戳与本地产物（13:11:02 构建、14:13:30 才提交）对不上，也与设备本次开机时长（`uptime` 1:47）对不上**——
最可能是模拟器 userdata 镜像里带着一份旧安装记录。**我不据此下任何"装的是哪一笔"的结论**；
能站得住的只有：**本轮没有构建、没有重装，跑的就是设备上原有的那一份**，
而这份产物**确实包含** ticket 02 的图标顶栏与 ticket 04 的"底栏只占主栏"（见下面两组帧）。

---

## A 组 — ticket 04：「全屏（主栏隐藏）时底栏消失」

**操作序列与点击坐标**（全部是 layout dump 的 px）：

| 步 | 动作 | 坐标 | 依据 |
| --- | --- | --- | --- |
| A1 | 点「文件」tab | `(393, 1809)` | 底栏「文件」命中区 `[314,1754,472,1864]` 的中心 |
| A2 | 点第 1 个文件（`Listening 3-2 (Extra Listening)` ZIP） | `(400, 334)` | `ListItem [0,266,786,414]` 内 |
| A3 | 点顶栏**全屏**图标 | `(2496, 142)` | `Stack [2456,102,2536,182]` 的中心 |
| A4 | 再点一次（此时字形已变 `U+E5D1`） | `(2496, 142)` | 同一 `Stack`，bounds 未动 |

### A-1 分栏 + 文件详情（改动后基线）— `11-split-filedetail.png` + `e01-split-filedetail-layout.json`

底栏 5 个命中区（`Column`，均 `clickable`）原始行：

```
Column [0,1754,157,1864] 157x110 clickable      ← 公告  (字形 U+E7F4)
Column [157,1754,314,1864] 157x110 clickable    ← 作业  (字形 U+E878)
Column [314,1754,472,1864] 158x110 clickable    ← 文件  (字形 U+E2C7)
Column [472,1754,629,1864] 157x110 clickable    ← 课程  (字形 U+E5C3)
Column [629,1754,786,1864] 157x110 clickable    ← 设置  (字形 U+E8B8)
```

⇒ **合计 x∈[0,786]**，与主栏宽相等。改动前基线（工单 04 Comments，`34dae55`）是 **5×576 横跨 2880**。

主栏 / 右栏：

```
Refresh [0,266,786,1752] 786x1486        ← 主栏（与工单记的基线 [0,266,786,1752] 逐字相同）
Stack [820,102,900,182] 80x80 clickable  ← 右栏详情页「返回」，字形 U+E5C4
Stack [2456,102,2536,182] 80x80 clickable ← 全屏，字形 U+E5D0
Stack [2560,102,2640,182] 80x80 clickable ← 刷新，字形 U+E5D5
Stack [2664,102,2744,182] 80x80 clickable ← 分享，字形 U+E80D
Stack [2768,102,2848,182] 80x80 clickable ← 外跳，字形 U+E89E
Text [820,751,2848,803] 2028x52           ← 右栏详情正文首行
```

**分隔条位置（像素扫描，不是 dump——dump 里没有 Divider 节点）**：
`x=786` 与 `x=787` 两列在 y∈[260,1700] 的 73 个采样行上**全部非白**，颜色 `R=G=B=199`；
`x=785` 与 `x=788` 为纯白 `255` ⇒ **分隔条 = x∈[786,788)，宽 2 px**（= 1vp @密度2）。
右栏 = `[788, 2880]`，正文左沿 `820 = 788 + 32`（contentPadding）自洽。

底栏顶边框（同一张图的像素扫描）：`y=1752` 与 `y=1753` 两行 `nonWhiteMinX=0 nonWhiteMaxX=785`；
`y=1750/1751` 只有 `786,787`（那是分隔条）。⇒ 底栏横跨 `x∈[0,786]`，**与 dump 的 5 个命中区一致**。

### A-2 全屏态（主栏隐藏）— `12-fullscreen.png` + `e02-fullscreen-layout.json`

**底栏：节点不存在。** 整棵树里 `y≥1700` 的节点一个都没有（A-1 里那 5 个 `Column` 全部消失）。
像素扫描同向：`y=1740..1772` 每一行的 `nonWhiteMaxX=1`——即**底栏顶边框那两行（y=1752/1753）不存在**，
整条底栏区域是纯白。

**顶栏（同一批 Stack，位置未动）**：

```
Stack [2456,102,2536,182] 80x80 clickable   ← 字形变成 U+E5D1（fullscreen-exit）
Stack [2560,102,2640,182] 80x80 clickable   ← U+E5D5
Stack [2664,102,2744,182] 80x80 clickable   ← U+E80D
Stack [2768,102,2848,182] 80x80 clickable   ← U+E89E
Stack [34,102,114,182] 80x80 clickable      ← 返回从 x=820 挪到 x=34（右栏吃满整屏）
```

分隔条：`x=0,1` 两列在全部采样行上 `R=G=B=199`——**与 A-1 里 x=786/787 的颜色逐通道相同**。
即：主栏宽收成 0 后，`SplitView` 里那根 `Divider().visibility(splitActive ? Visible : None)` **仍然可见**，
于是它落到了屏幕最左边 `x∈[0,2)`（右栏正文左沿 `34 = 2 + 32`，与 A-1 的 `788 + 32` 同一套 padding，自洽）。
这是**一条既有的 2px 残留线**，工单 04 没提过；不是我改的，如实记录，不改判定。

**主栏节点仍在 dump 里**，但宽度是 `393`：

```
Refresh [0,266,393,1752] 393x1486
```

这与代码对不上（`FileDetailPage` 的 `masterHidden` 消费点 `FilesPage.ets:277-282`：
`return this.masterHidden ? 0 : SPLIT_VIEW_MASTER_WIDTH` ⇒ 请求的是 **0**；分栏态请求的是 393vp = **786 px**）。
**所以我没有把 dump 里这个 393 当成"主栏的版式宽度"**，而是另做了一次判据：

> **主栏隐藏的独立判据（命中测试）**：在全屏态点 `(100, 380)`——它落在 dump 报告的
> `ListItem [0,266,393,414]` 里——随后重取 layout dump，与点击前**逐字节相同**
> （`a02-fullscreen-layout.json` 与 `a03-fullscreen-masterhitprobe-layout.json` 均 12,235 B，内容相同）。
> ⇒ 那条主栏子树**不可命中**，`393` 是隐藏子树的 dump 取值，不是可见版式。

"主栏隐藏"因此由**截图**（`12-fullscreen.png` 左半屏没有任何列表/页头）
+ 右栏左沿从 820 移到 34 + 上述命中测试三者共同承载，**不靠 dump 的 393 这个数**。

### A-3 退出全屏 — `13-after-exit.png` + `e03-after-exit-layout.json`

- layout dump 与 A-1 **逐字节相同**（两份文件都 16,463 B，SHA256 均为 `14C1871957C8F8D6…`）。
- 5 个底栏命中区**回来了**，仍是 `[0,1754,157,1864] / [157,…] / [314,…472,…] / [472,…629,…] / [629,…,786,1864]`。
- 全屏图标字形**变回 `U+E5D0`**。
- 像素扫描：分隔条回到 `x=786,787`；底栏顶边框回到 `y=1752/1753, x∈[0,785]`。

⇒ **ticket 04 的三态在设备上闭合**：分栏+详情 ⇒ 底栏在主栏内（x∈[0,786]）；
全屏 ⇒ 底栏消失、主栏不可见、详情铺满；退出 ⇒ 底栏与分栏几何复原。

---

## B 组 — ticket 02：「详情 / 预览」图标的设备帧

### B-0 学期覆盖自证（含消费点，不只是"设上了"）

1. 先把应用停掉：`hdc shell aa force-stop com.koracan.learnOH`；`hilog -r` 清缓冲。
2. `hdc -t 127.0.0.1:5559 shell aa start -a EntryAbility -b com.koracan.learnOH --ps lohSemester 2025-2026-2`
3. 冷启动自证行（`b01-override-hilog.txt`）：
```
09-13 14:30:33.804 ... I A04c4f/entry.ability: ... [entry.ability] semester override: want parameter "lohSemester"="2025-2026-2" accepted=true; semester override: constant="" runtime="2025-2026-2" effective="2025-2026-2" source=runtime-want-param
```
4. **消费点**（点「文件」tab 之后才出现，`b02-override-hilog-files.txt`）：
```
09-13 14:31:09.673 ... [data.files.source] data.files semester override: constant="" runtime="2025-2026-2" effective="2025-2026-2" source=runtime-want-param
09-13 14:31:09.802 ... [data.files.source] data.files effective semester=2025-2026-2 source=override
09-13 14:31:10.090 ... [data.files.source] data.files snapshot semester=2025-2026-2 source=override courses=7 files=95
```
（对应 `21-override-files-tab.png` 与 `b03-override-files-tab-layout.json`：文件 tab 由 4 个 ZIP 变成 95 项、多为 PDF，
页头统计 `全部 95 / 未读 4`。）

### B-1 打开 PDF 详情 — `22-pdf-detail.png` + `b04-pdf-detail-layout.json`

点击：`(393, 1809)` 进文件 tab → `(400, 334)` 点第 1 项（`期末复习`，PDF 276K）。

顶栏**每一枚按钮**的 `Stack` bounds 与它内部字形的码位（全部 `80×80 px = 40vp×40vp`，间距 24px = 12vp）：

| # | Stack bounds | 字形码位 | 图标语义（源码 `FileDetailPage.ets:475-582` / `IconCatalog.ets`） |
| --- | --- | --- | --- |
| 1 | `[820,102,900,182]` | `U+E5C4` | 返回 `ARROW_BACK` |
| 2 | `[2352,102,2432,182]` | `U+E5D0` | 全屏 `FULLSCREEN` |
| 3 | `[2456,102,2536,182]` | `U+E5D5` | 刷新 `REFRESH` |
| 4 | `[2560,102,2640,182]` | `U+E80D` | 分享 `SHARE` |
| 5 | `[2664,102,2744,182]` | `U+E89E` | 外跳 `OPEN_IN_NEW` |
| 6 | `[2768,102,2848,182]` | **`U+E88E`** | **详情/预览切换**，当前显示的是 `INFO`（Material `info`） |

> 与 ZIP 详情（`e01` 那张 A-1 帧）对照：ZIP 详情只有 5 枚（**没有第 6 枚**），
> 因为切换按钮的渲染条件是 `previewable() && localPath.length > 0`（`FileDetailPage.ets:559`），
> 而 ZIP 不可预览、PDF 可预览且已落盘。**这正是工单 02 Comments 里"取不到那枚图标"的原因，现在取到了。**

### B-2 按下切换按钮后的另一个字形 — `23-pdf-preview-state.png` + `b05-pdf-preview-state-layout.json`

点击：`(2808, 142)`（`Stack [2768,102,2848,182]` 的中心）。

两份 dump 的**唯一**差异（逐行 diff，1152 行对 1152 行，只有一行不同）：

```
DIFF[835] A=            "text": "",        ← U+E88E  (Material info)
DIFF[835] B=            "text": "󰈈",        ← U+DB80 U+DE08 = 代理对，合起来是 U+F0208
```

**`U+DB80 U+DE08` 是 `U+F0208` 的 UTF-16 代理对**，即 MaterialCommunityIcons 的 `eye`，
也就是源码里的 `AppIcon.PREVIEW`（`IconCatalog.test.ets:58`：`{ icon: AppIcon.PREVIEW, name: 'eye', family: MATERIAL_COMMUNITY, code: 0xF0208 }`）。
**码位按 dump 如实报**：请求里猜的 `U+E8B6` 是 `SEARCH`（页头搜索入口），**不是**这枚图标。

### B-3 必须记下的限定：这帧只证明了"图标"，没证明"预览内容"

两份 dump 除了那个字形**完全相同**——按 `showInfo` 翻转正文的代码（`FileDetailPage.ets:849-853`）
本该让正文在「预览」与「信息面板」之间切换，但设备上没有切换。
真因在 hilog（`b06-pdf-preview-hilog.txt`）：

```
09-13 14:32:40.858 ... W A04c4f/features.files.detail: [features.files.detail] file detail preview pdf unavailable on this platform: Cannot read property PdfDocument of undefined
```

⇒ 这台 API 23 模拟器上 `@kit.PDFKit` 的 `pdfService.PdfDocument` 不存在，`previewUnsupported=true`，
正文因此始终走 `infoPanel()`（并带那句「该文件类型不支持应用内预览，可下载后分享给其他应用。」）。
**所以 B-2 帧承载的是"切换按钮的第二个字形存在且可点"，不是"看到了 PDF 预览"。**
换到图片（`previewBody` 的 IMAGE 分支）是否能真出预览，本轮**没验**。

---

## 复原：应用已回到无覆盖状态，并留了 hilog 行

`aa force-stop` → `aa start`（**不带** `--ps`）→ 点「文件」tab，`b07-restored-hilog.txt`：

```
09-13 14:35:15.805 ... [entry.ability] semester override: want parameter "lohSemester" absent; semester override: constant="" runtime="" effective="" source=none
09-13 14:35:35.415 ... [data.files.source] data.files semester override: constant="" runtime="" effective="" source=none
09-13 14:35:35.512 ... [data.files.source] data.files effective semester=2026-2027-1 source=site-current
09-13 14:35:35.626 ... [data.files.source] data.files snapshot semester=2026-2027-1 source=site-current courses=2 files=4
```

`30-restored-files-tab.png` / `b08-restored-files-tab-layout.json`：分栏态、文件 tab、`全部 4`（回到站点当前学期）。

**对设备做过的写操作仅**：`aa force-stop` / `aa start`（含一次 `--ps`，进程内、已复原）、UI 点击与滑动、
`hilog -r` 清日志缓冲（两次）、`snapshot_display` 写 `/data/local/tmp/wakecheck.jpeg`（**已 `rm`**）。
未点退出登录、未提交/上传、未改设备级设置、未清应用缓存、未卸载。
副作用一条：为取 PDF 帧，应用往自己的 cache 落了一个 283,252 B 的 `期末复习.pdf`。

期间设备息屏过一次（模拟器静置），导致第一次 `ui screenshot` 失败、第二次拍到
**1920×2880 竖屏黑帧**、唤醒后第三次拍到**锁屏壁纸**。
那张被误命名为退出态的锁屏帧已改名挪到 `probes/04-LOCKSCREEN-misnamed-not-exit-state.png`，
**没有**留在交付帧里（以免状态词与画面不符）。

---

## 文件清单（均在 `.scratch/ui-optimize/evidence/frames-t02-t04/`，整个 `**/evidence` 被 `.scratch/.gitignore` 忽略，未入库）

| 文件 | 字节 | SHA256 前 16 | 承载的论断 |
| --- | --- | --- | --- |
| `11-split-filedetail.png` | 286,223 | `05555FB9D529787F` | 分栏+详情：底栏在主栏内、主栏/分隔条在 |
| `e01-split-filedetail-layout.json` | 16,463 | `14C1871957C8F8D6` | 同上（bounds/码位） |
| `e01-split-filedetail-pixelscan.txt` | 1,622 | `488A0F18B6B83DDB` | 分隔条 x=786,787；底栏顶边框 x∈[0,785] |
| `12-fullscreen.png` | 195,434 | `087C7AF5CB88AB41` | 全屏：底栏与主栏都不在画面上 |
| `e02-fullscreen-layout.json` | 12,235 | `1AF9F79F5381F46A` | 全屏：底栏节点不存在；`U+E5D0`→`U+E5D1` |
| `e02-fullscreen-pixelscan.txt` | 1,515 | `E322BB0FFE103D8A` | 全屏：无底栏边框；x=0,1 是残留分隔条（199/199/199） |
| `13-after-exit.png` | 286,068 | `2A4443B4F233F05E` | 退出全屏：底栏回来 |
| `e03-after-exit-layout.json` | 16,463 | `14C1871957C8F8D6` | 退出全屏：与 e01 **逐字节相同** |
| `e03-after-exit-pixelscan.txt` | 1,616 | `EB56EA95D24A8EA1` | 退出全屏：分隔条回到 786,787 |
| `21-override-files-tab.png` | 276,808 | `954C79CA994E84CD` | 覆盖生效：文件 tab = 95 项 |
| `b03-override-files-tab-layout.json` | 22,759 | `6E4E40ED76E3D9D6` | 同上 |
| `22-pdf-detail.png` | 345,364 | `B1284F58E82438D9` | PDF 详情 6 枚图标（第 6 枚 = info） |
| `b04-pdf-detail-layout.json` | 27,611 | `15D82854A9A6BB12` | 6 枚 Stack 的 bounds + `U+E88E` |
| `23-pdf-preview-state.png` | 345,707 | `A0D7EB9276BAD081` | 切换后第 6 枚变成 eye |
| `b05-pdf-preview-state-layout.json` | 27,612 | `CD2EEDF595736563` | 唯一差异 = `U+DB80 U+DE08`（= `U+F0208`） |
| `20-override-notices.png` | — | — | （已挪进 `probes/`） |
| `30-restored-files-tab.png` | 206,618 | `75CD929171AA3004` | 复原：分栏 文件 tab、全部 4 |
| `b08-restored-files-tab-layout.json` | 11,999 | `A2D4E6A5B3EEC1E8` | 同上 |
| `b01-override-hilog.txt` | 409,019 | `18688BD20E4E85EE` | 冷启动 want 自证行 |
| `b02-override-hilog-files.txt` | 602,932 | `EDBE3A280AE70926` | `data.files` 消费点 source=override |
| `b06-pdf-preview-hilog.txt` | 685,889 | `0F03041DC0CD14B3` | PDF 预览平台能力缺失那一行 |
| `b07-restored-hilog.txt` | 562,301 | `39B5C044AFC51A42` | 复原：`source=none` |
| `a01-filedetail-split-pixelscan.txt` | 1,622 | `1F5DB586C5E6BA9D` | 第一次序列的同一张扫描（与 e01 同内容） |
| `probes/` | — | — | 过程件：侦察帧、锁屏误拍帧、主栏命中探针 dump、第一批序列帧、工具脚本 |
| `tools/` | — | — | `dump-tree.ps1`（打印 bounds+码位）、`scan.ps1`（像素扫描）、`summarize*.ps1` |

## 未闭合 / 未验

1. **设备上那枚 PDF 预览图标按钮的"预览内容"没验**（平台缺 `PdfDocument`，见 B-3）。图标本身两个字形都取到了。
2. **图片预览**（`previewBody` 的 IMAGE 分支）本轮没试，能不能出预览未知。
3. **单栏态设备帧**（工单 04 另一条未达成项）本轮**没取**——5559 是平板、恒横屏；那是 phone 上的活。
4. **产物指纹没取到**（`/data/app/el1/bundle/public/…` 权限拒绝），见开头"溯源"。
5. **全屏态主栏 `Refresh` 报 393px 这个数没归因**；我只证明了它不可命中，没解释它为什么是 393 而不是 0 或 786。
6. **全屏态左边缘残留 2px 分隔条**是我新发现的现象，**没归因**，也没改任何东西。
