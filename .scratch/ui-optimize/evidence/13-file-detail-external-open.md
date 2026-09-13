# 文件详情顶栏「外跳」接上"交给系统打开方式"：设备取证清单

设备：**MatePad Pro 13（tablet）**，串口 `127.0.0.1:5559`（`hdc shell param get const.product.devicetype` 回 `tablet`）。
窗口 2880×1920 px，密度 2（1vp = 2px）。已安装包 `com.koracan.learnOH`。

> 这台机是**真实登录会话**（han-wang23）。全程没有点「退出登录」、没有点任何提交入口、没有改设备级设置。
> 第一轮点击过的按钮只有：底部 tab（文件 / 作业）、文件列表里的一个 ZIP、详情顶栏的「外跳」、以及系统对话框的「取消」；
> 补证轮另外点过：顶栏「刷新」、作业卡片与它的附件行（**没有**碰提交入口）；补证轮 2 又点了两次「外跳」（ZIP 与 PDF）。各轮的收尾都写在文末。
>
> **本文含三轮**：第一轮（首次交付，第 1–8 节）→ **补证轮**（未落盘帧 + 成功路径的证伪式搜索 + type 匹配的决定性对照）
> → **补证轮 2**（外跳改为不带 type 之后的门禁与成功路径实测）。两轮补证都在文末。

## 参考实现里这个动作到底是什么（**先读，别猜**）

参考实现**确实有这个动作**，它不是 `Linking.openURL`，也不是 `Share.share`：

| 出处 | 内容 |
| --- | --- |
| `reference/learnOH-old/src/screens/FileDetail.tsx:84-90` | `handleOpen = async () => { try { await openFile(path); } catch (e) { toast(t('openFileFailed'), 'error'); } }` |
| `reference/learnOH-old/src/screens/FileDetail.tsx:120-124` | 顶栏 `headerRight` 里 `<IconButton disabled={error \|\| !path} onPress={handleOpen} icon="open-in-new" />` |
| `reference/learnOH-old/src/screens/FileDetail.tsx:252-255` | 信息面板底部动作行里同名的 `open-in-new` 按钮 + `Text{t('open')}` |
| `reference/learnOH-old/src/helpers/fs.ts:171-179` | `openFile(path)` = `await FileViewer.open(path, { showOpenWithDialog: true })`（react-native-file-viewer） |
| `reference/learnOH-old/src/helpers/fs.ts:184-200` | 分享是**另一个函数** `shareFile` = `Share.open({...})`，顶栏另一个按钮 |

⇒ 语义是**把已落盘的路径交给系统、由系统决定"用什么打开"**（`showOpenWithDialog: true`），
触发条件是 `!error && path`（下载成功且文件已落盘），失败时给一条 toast。
**结论：本 ticket 不降级** —— 参考实现有这个动作，只是当时的移植有意去掉了它。

## 溯源

| 项 | 值 |
| --- | --- |
| `git rev-parse HEAD` | `90c6db8a6543f69b3a14260dc870c8eb4a222c88` |
| 工作区脏（改动未提交） | `logs/13-git-status.txt`，其 SHA256 = `FF41621030A782ACCE8A1C5A465EFF5B577B8DD844E504EFF90F0C112E2841E4` |
| 产物 `entry-default-signed.hap` | 5035511 字节，SHA256 = `EF3FEB94933E5BF54C5154A069145C9C00A2F2CFA0B42EDC21EC1EAE1E368294` |
| 产物（解包后）`ets/modules.abc` | 1768884 字节，SHA256 = `13C1AFC0317A0F3E4F78C0F917BEBA43B5D0494B7BC4E995A788B8DCEFD34D0E` |

产物内容级检查（`docs/agents/gates.md` 的"陈旧产物"判据；在解包出来的 `ets/modules.abc` 里逐字节搜）：

| 串 | 结果 |
| --- | --- |
| `ui_file_open_not_ready` | FOUND @59601（本次新增的文案键） |
| `externalOpenIntent` | FOUND @135152（本次新增的纯函数） |
| `canOpenExternally` | FOUND @135039（本次新增的纯函数） |
| `ohos.want.action.viewData` | FOUND @350648 |
| `loh_open_file_failed` | FOUND @55120（失败文案，复用参考实现的串） |
| `ui_file_open_pending_should_not_exist` | NOT FOUND（**对照组**：证明这次字节搜索找得到存在的串，NOT FOUND 不是假阴性） |

## 顶栏按钮：位置与点击区（layout dump 的 px）

同一状态（文件 tab → `Listening 3-1 (Extra Listening)` 详情、已落盘）。原始 dump：`logs/13-layout-03-downloading.json`。

```
Stack [820,102,900,182]      <- 返回        （80×80 px = 40vp×40vp）
Stack [2456,102,2536,182]    <- 全屏切换    （80×80）
Stack [2560,102,2640,182]    <- 刷新        （80×80）
Stack [2664,102,2744,182]    <- 分享        （80×80）
Stack [2768,102,2848,182]    <- 外跳        （80×80）   <-- 本次新增
```

按字形码位认人（避免"看着像"）：`U+E5C4` ARROW_BACK、`U+E5D0` FULLSCREEN、`U+E5D5` REFRESH、
`U+E80D` SHARE、`U+E89E` **OPEN_IN_NEW**（= `AppIcon.OPEN_IN_NEW`，见 `ui/icons/IconCatalog.ets`）。
**五个 Stack 的 bounds 宽高逐点相同**（都是 80×80 px），即新增按钮没有比顶栏其它按钮小。

## 逐文件论断表

| 文件 | 字节 | SHA256(前16) | 用途（一条主论断） |
| --- | ---: | --- | --- |
| 13-file-detail-topbar-ready.png | 285549 | 58CA8F237714CB5A | 文件详情顶栏出现「外跳」图标（`open-in-new` 字形已由随包字体画出来，右侧第 4 个按钮），文件已落盘故图标是主色 |
| 13-external-open-no-handler.png | 355072 | 31F447F9F49E62A1 | 点「外跳」后的**系统行为**：系统弹「暂无可用打开方式 / 暂无支持此类文件的应用」，同时本页顶栏下方出现可读失败文案（本机没有能接 ZIP 的应用） |
| 13-open-failure-note-persists.png | 300768 | F08CAC019AFAE8E2 | 关掉系统对话框后，那句可读失败文案**仍在页面上**（不是 2 秒就消失的 toast）；页面其余部分完好（信息面板还在） |
| logs/layout-03-downloading.json | — | — | 顶栏五个 Stack 的 bounds 原始 dump（过程文件，不入库） |
| logs/layout-04-after-open-click.json | — | — | 点击后的元素清单：本页文案 `文件打开失败。…` + 系统对话框 `暂无可用打开方式` 与两个按钮（过程文件，不入库） |
| logs/13-hilog-open.txt | — | — | 本次点击的 hilog 全量拉取（6382 行，本地过滤 `features.files.detail`）（过程文件，不入库） |

## 逐条验收

1. **参考实现里到底有没有这个动作** —— 见上表：有，`FileDetail.tsx:84-90` → `helpers/fs.ts:171-179` 的 `FileViewer.open(path, {showOpenWithDialog:true})`。**不降级**。
2. **顶栏出现"外跳"图标按钮，用 `AppIcon.OPEN_IN_NEW`** —— `13-file-detail-topbar-ready.png` + `logs/layout-03-downloading.json` 里码位 `U+E89E` 的 Text 挂在 `Stack [2768,102,2848,182]` 下。
3. **点击把已落盘的文件交给系统打开方式；未落盘 / 平台无接收方时给可读反馈，不静默失败** ——
   设备实测（`logs/13-hilog-open.txt`，本地过滤）：

   ```
   file detail external open uri: file://com.koracan.learnOH/data/storage/el2/base/haps/entry/cache/learnX-files/%E8%8B%B1%E8%AF%AD%E5%90%AC%E8%AF%B4%E4%BA%A4%E6%B5%81%EF%BC%88A%EF%BC%89/…/…Listening%203-1%20(Extra%20Listening).zip
   file detail external open want: action=ohos.want.action.viewData type=general.file flags=1 entities=0
   file detail external open failed at step=startAbility: code=16000019 message=No matching ability is found.
   ```

   本机没有能开 ZIP 的应用 ⇒ 走失败路径 ⇒ 页面出现 `文件打开失败。请重新下载文件或确保存在可打开此文件类型的应用。`
   （`13-external-open-no-handler.png`），并常驻到用户看完为止（`13-open-failure-note-persists.png`）。
   未落盘那一支由单测 `offersOpenOnlyForAFinishedDownloadWithALocalCopy` 钉住判定，点击时给 `ui_file_open_not_ready`。
4. **新文案走 i18n 生成器，`check-i18n-keys` = OK / `check-generated-fresh` = PASS** —— 新增 1 个键 `ui_file_open_not_ready`（正文见交付回报的原始输出）。
5. **无障碍 label 可读、字体未就绪时回退成可读文案** —— `IconGlyph` 的 `label` 传 `$r('app.string.loh_open')`（=「打开」/「Open」，参考实现已有的串），不是图标短名。
6. **点击区 40vp×40vp** —— 见上节：`Stack [2768,102,2848,182]` = 80×80 px = 40vp×40vp（密度 2），与其余四个按钮逐点相同。
7. **单测只钉纯函数** —— `ExternalOpen.test.ets` 5 条：`hasLocalCopy` / `canOpenExternally` / `externalOpenIntent`（action / 空 entities / flags / type 归整 / uri 原样），
   **没有**断言"调用了哪个系统 API"。
8. **证据：按钮出现 + 点击后的系统行为 + layout dump 的 bounds** —— 见上面三节。

## 未达成 / 风险（本轮补证后更新）

1. **成功路径不存在（已搜索、不是没抓到）** —— 见下面「B. 成功路径的证伪式搜索」：6 个搜索面（2 个学期 × 文件 / 作业 / 公告），
   找到并实测了一个非 ZIP（作业附件 `Homework12.pdf`），点外跳仍然是 `16000019 No matching ability is found`。
2. **根因已定：阻塞项是 want 的 `type`** —— 见「B-2」的对照实验。本 ticket 现在的实际行为是：
   **只要文件落盘了、点外跳，就必然落到失败文案**，因为 `shareUtd()` 对 ZIP 与 PDF 都返回 `general.file`，
   而这一台上没有任何接收方声明 `general.file`。这与裁定 1 的前提（"粗粒度不算移植退化"）冲突，已提请重新拍板；
   本轮按要求**没有改功能代码**。
3. **一个未证的遗留**（若采纳"不带 type"的改法）：接收方能否真的**读**到应用沙箱里的那个文件，取决于
   `FLAG_AUTH_READ_URI_PERMISSION` 的授权是否被系统兑现 —— 这一步 shell 侧无法复现，只能在真机上点一次才知道。
4. `shareUtd()` 里"按扩展名取 UTD"的平台 API 在本工程实测会抛 401（见该方法注释），所以精确类型只能自建映射表，属新增面。

## 补证轮（统筹复核通过并合并后，2026-09-13）

### 统筹者的两条裁定（原文要点）

1. **`general.file` 维持现状，不要改**：参考实现的"打开"动作根本不传类型（`FileViewer.open` 只吃路径，类型由库按扩展名推），
   所以粗粒度不是移植退化；精确 UTD 那条路依赖在本工程实测会抛 401 的平台 API，要做就得自建"扩展名 → UTD"表，
   属于新增面、无验收条款，还会连带改掉已验收的分享动作。**按技术债记在工单里，不放进本 ticket。**
2. 不用为此单开降级或新 ticket；残留风险写进本文件的"未达成 / 风险"一节。

> 本节 B-2 的实验给裁定 1 的**前提**提供了新证据（阻塞项不是粒度，而是"带任何 type 都不匹配"的这台设备事实）。
> 裁定本身未被推翻（它主要是一条范围与风险取舍），但它的风险描述"粗粒度"需要按 B-2 更正。

### A. 「未落盘」那一支的设备帧

应用缓存里那两个 ZIP（166MB / 734MB）是先前取证下载的；本轮**不删文件**，改用顶栏「刷新」按钮
（`startDownload(true)`，绕过"文件存在即缓存命中"的短路）重新制造 DOWNLOADING 窗口。

**A-1 未落盘时按钮是次要色** —— `13-not-ready-while-downloading.png`（进度条读到 `281.77 MB / 700.48 MB` 的那一帧）。
放大裁剪 `13-not-ready-button-outline-crop.png`（原图 x 2420–2880 / y 90–200，×3 最近邻）里逐个认字形：
**「分享」仍是主色（紫），「外跳」是次要色（灰）**。这两枚按钮的判据**不同源**：分享只看 `localPath`，
外跳看 `canOpenExternally(phase === READY, localPath)`；此刻刷新触发的重下正在进行、`localPath` 还留着上一轮的路径，
所以分享亮、外跳灰。

> **layout dump 本身没有颜色字段**（只有 `type` / `bounds` / `text` / `clickable`），所以"次要色 / outline 态"这条论断
> 只能由**截图**承载，dump 承载不了 —— 这也是 A-1 用截图 + 裁剪而不是 dump 的原因。

**A-2 点它给出可读文案** —— `13-not-ready-note-on-click.png` + `logs/13b-layout-02-not-ready.json`，同一帧里三件事同时可见：

```
Stack "" [2768,102,2848,182] CLICKABLE          <- 外跳按钮命中区：80×80 px = 40vp×40vp
Text ""<U+E89E> [2784,118,2832,166]             <- AppIcon.OPEN_IN_NEW 的字形
Text "文件尚未下载完成，暂时不能交给其他应用打开。" [820,222,2848,250]   <- 本次新增的文案键 ui_file_open_not_ready
```

同一帧里还有 `下载中 643.54 MB / 700.48 MB` 的进度条，而且**没有系统对话框节点**（dump 里不存在 `Dialog`）——
说明这一次没有把任何东西交给系统。

hilog 原话（`logs/13b-hilog-a2.txt`）：

```
09-13 13:33:27.018 I [features.files.detail] file detail external open skipped: no local copy yet, path="/data/storage/el2/base/haps/entry/cache/learnX-files/英语听说交流（A）/1991990059_KJ_1787977419601777807b2f6-57f4-474e-bd5a-90aeb75dad84/英语听说交流（A）-Listening 2 (Video).zip"
09-13 13:33:43.229 I [features.files.detail] file detail ready: path=/data/storage/el2/base/haps/entry/cache/learnX-files/… bytes=734501365 fromCache=false
```

⇒ not-ready 那一支确实被走到；13:33:43 那次 ready 是同一轮刷新下载完成，与点击无关。

### B. 成功路径的证伪式搜索

**搜索面与结果**（都是 dump 原话，过程文件在 `logs/`）：

| 搜索面 | 怎么扫 | 结果 |
| --- | --- | --- |
| 文件 tab，站点当前学期 `2026-2027-1` | 冷启动后进文件 tab，dump | `全部 4`：1 门课（英语听说交流（A））× 4 条，**全部 ZIP**（212.0M / 166.0M / 700.0M / 196.0M） |
| 作业 tab，当前学期 | 进作业 tab，dump | `未完成 0 / 已完成 0 / 全部 0` + `暂无作业` —— 空态 |
| 公告 tab，当前学期 | 冷启动落地页就是公告 tab，dump | `全部 2` 两条公告；卡片上的字形只有 `U+F023B`（FLAG = 重要），**没有 `U+F0066`（ATTACHMENT）** |
| 文件 tab，`--ps lohSemester 2025-2026-2` | 学期覆盖冷启动后进文件 tab，dump | `全部 95`：**绝大多数是 PDF**（软件分析与验证：期末复习 / 16 abstractio and refinement / 样卷解析 / 期末考试样卷；偏微分方程：课件25/26/27；离散数学方法：总复习；算法分析与设计基础：第十四讲课件…） |
| 作业 tab，`2025-2026-2` | 同上，进作业 tab，dump | `未完成 0 / 已完成 57 / 全部 57`；其中 **3 张卡片带 `U+F0066` 附件标记**（演绎验证编程作业 / 第十二次作业 / 第十四周作业） |
| 公告 tab，`2025-2026-2` | 同上，dump | `全部 2`，仍只有 FLAG 标记，无附件 |

学期覆盖自证（`logs/13b-hilog-b1.txt`）：

```
[entry.ability]       semester override: want parameter "lohSemester"="2025-2026-2" accepted=true; constant="" runtime="2025-2026-2" effective="2025-2026-2" source=runtime-want-param
[data.courses.source] data.courses override active: siteCurrent=2026-2027-1 effective=2025-2026-2
```

**找到并实测的非 ZIP 文件**：`算法分析与设计基础 / 第十二次作业` 的作业附件 `Homework12.pdf`。
作业详情页 dump 原话（`logs/13b-layout-11-assignment-detail.json`）：

```
Column "" [788,464,2880,578] CLICKABLE
Text ""<U+F0066> [820,480,868,528]
Text "Homework12.pdf" [892,485,2848,523]
Text "作业附件" [820,536,909,562]
```

**只点了这一行**（center 1834,521），没有碰同页的「在线提交」入口，也没有碰右上角的上传按钮。
结果：**同样失败**。落盘 21071 字节后点外跳（`logs/13b-hilog-b4.txt`）：

```
file detail external open uri: file://com.koracan.learnOH/data/storage/el2/base/haps/entry/cache/learnX-files/%E7%AE%97%E6%B3%95…%E5%9F%BA%E7%A1%80-Homework12.pdf
file detail external open want: action=ohos.want.action.viewData type=general.file flags=1 entities=0
file detail external open failed at step=startAbility: code=16000019 message=No matching ability is found.
```

截图 `logs/13b-13-pdf-after-open.png`：系统「暂无可用打开方式 / 暂无支持此类文件的应用」+ 页面 `文件打开失败。…`。

**顺带记一条现场事实：外跳按钮的位置会随文件类型变化。** PDF 可预览，顶栏因此多一枚「详情 / 预览」按钮，
这一帧外跳在 `Stack [2664,102,2744,182]`（center 2704,142），而不是 ZIP 那帧的 `[2768,102,2848,182]`。
按码位逐个认过：`820 ARROW_BACK / 2352 FULLSCREEN / 2456 REFRESH / 2560 SHARE / 2664 OPEN_IN_NEW / 2768 INFO`。

⇒ **成功路径的结论是"已搜索、确实不存在"**，不是"没抓到"。

### B-2. 为什么匹配不到：`type` 是唯一阻塞项（决定性对照）

失败信息只说"没有匹配的应用"。为了分清"这台设备真的没有接收方"与"我们发错了东西"，
先看装了哪些应用（`bm dump -a`，**不是**没有接收方）：

```
com.huawei.hmos.filemanager   com.huawei.hmos.files     com.huawei.hmos.browser
com.huawei.hmos.photos        com.huawei.hmos.hipreview com.ohos.UserFile.ExternalFileManager
```

再把 skills 摊开（`bm dump -n <bundle>` + 本地解析，原文在 `logs/13b-bm-*.json`）——
**filemanager 明确声明了我们要的那条 action**：

```
[filemanager] actions=[ohos.want.action.viewData,ohos.want.action.sendData]  types=[]
[filemanager] actions=[ohos.want.action.viewData]  types=[general.zip-archive | org.7-zip.7-zip-archive | com.rarlab.rar-archive | general.tar-archive | org.gnu.gnu-zip-archive]
[hipreview]   actions=[ohos.want.action.viewData]  types=[text/plain | … | image/png | … | image/svg+xml]   （MIME 名，不是 general.*）
[browser]     actions=[ohos.want.action.viewData,action.system.home]  types=[application/x-mimearchive | text/html | application/pdf]
```

然后用 `aa start -A <action> -t <type> -U <uri>` 把 `type` 当作**唯一变量**做对照
（只启动应用，不改任何数据；`10103101` = `Failed to find a matching application for implicit launch.`）：

| # | type | uri | 结果 |
| --- | --- | --- | --- |
| T3 | （无） | 无 | `start ability successfully.` |
| T1 | `general.file` | 无 | `10103101` 失败 |
| T2 | `general.zip-archive` | 无 | 失败 |
| T4 | `general.pdf` | 无 | 失败 |
| T5 | `com.adobe.pdf` | 无 | 失败 |
| T6 / T16 | `general.image` | 无 | 失败（两次） |
| T11 | `general.text` | 无 | 失败 |
| T12 | `application/pdf` | 无 | 失败 |
| T7 | （无） | `file://com.koracan.learnOH/data/…/b.pdf` | `start ability successfully.` |
| T8 | （无） | `https://example.com/x` | `start ability successfully.` |
| T9 | `general.file` | `file://com.koracan.learnOH/data/…/b.pdf` | 失败 |
| T10 / T17 | `general.plain-text` | 无 | `start ability successfully.`（两次） |
| T13 | `image/png` | 无 | `start ability successfully.` |
| T14 | `text/plain` | 无 | `start ability successfully.` |
| T15 | `general.png` | 无 | `start ability successfully.` |

读法（T1 与 T10 各复现一次，结果稳定）：

- **T7 vs T9**：同一个 uri，去掉 `type` 就能匹配、带上 `general.file` 就匹配不到 ⇒ **阻塞项是 `type`，不是 uri**。
- 匹配是**按具体类型**做的：`general.file` / `general.image` 这类**父类型**在这一台上没有任何接收方声明；
  而 `general.plain-text` / `general.png` / `image/png` / `text/plain` 有（hipreview 与 browser 声明的正是 MIME 名那一组）。
- 于是本 ticket 现在的实际行为是：**只要文件落盘、点了外跳，就必然落到失败文案**（ZIP 与 PDF 都实测如此），
  因为 `shareUtd()` 对 ZIP 与 PDF 都返回 `general.file`（只有图片 → `general.image`、txt → `general.plain-text` 两条分支）。

一个与参考实现一致的最小候选改法（**本轮未实施**）：外跳动作**不带 `type`**——
`externalOpenIntent` 已经支持空 type（注释里就写着"调用方不要把它放进 Want"），这样会落到 filemanager 那条
无类型约束的 `viewData` skill（T7/T3 的路径）。

### 本轮新增 / 引用的过程文件

| 文件 | 用途（一条主论断） |
| --- | --- |
| `logs/13b-01-downloading-outline.png`、`logs/13b-03-not-ready-note.png` | A-1 / A-2 的原始帧（证据目录里的两份是它们的副本） |
| `logs/13b-layout-02-not-ready.json` | A-2 的 bounds 原话（外跳 Stack / U+E89E / 文案 [820,222,2848,250]） |
| `logs/13b-hilog-a2.txt` | `external open skipped: no local copy yet` 原话 |
| `logs/13b-layout-10-assignments-spring.json`、`logs/13b-layout-20..22-*.json` | B 轮搜索面：春季 95 个文件 / 57 条作业（3 条带附件）/ 两个学期的公告 |
| `logs/13b-layout-11-assignment-detail.json` | `Homework12.pdf` 附件行原话 |
| `logs/13b-hilog-b4.txt`、`logs/13b-13-pdf-after-open.png` | 非 ZIP（PDF）点外跳同样 `16000019` |
| `logs/13b-bm-filemanager.json`、`13b-bm-hipreview.json`、`13b-bm-browser.json` | 三个应用的 skills 原文（B-2 的唯一变量实验依据） |
| `logs/13b-hilog-b1.txt` | 学期覆盖自证：`siteCurrent=2026-2027-1 effective=2025-2026-2` |
| `logs/13b-hilog-cleanup.txt`、`logs/13b-layout-41-files-normal.json` | 收尾复原：`source=none`（覆盖是进程内的，不持久）+ 文件 tab 回到 `全部 4` |

### 本轮收尾

- 取证用的下载（`Listening 2 (Video)` 734501365 字节、`Homework12.pdf` 21071 字节）在截图后由 `aa force-stop` 结束，**没有让下载挂在后台**。
  应用缓存目录里留下了这些落盘物（另有先前取证下载的 166MB ZIP）——**未清理**：清缓存会同时删掉其它 ticket 可能仍在引用的落盘物，
  应用自己的「文件设置 → 清空文件缓存」是可用的清理入口。
- 学期覆盖是**进程内**的：重启后立即复原（hilog `source=none`），文件 tab 回到当前学期的 `全部 4`。
- 全程没有点「退出登录」、没有点任何提交入口、没有改设备级设置；只碰 `127.0.0.1:5559`。

## 补证轮 2：外跳改为不带 type（裁定 1 修订），成功路径拿到

### 改动（本轮唯一的代码改动）

`entry/src/main/ets/features/files/FileDetailPage.ets`（+15/−6，一个文件）：

- `openExternally()` 的 want **不再带 type**：调用从 `externalOpenIntent(uri, this.shareUtd())` 改成 `externalOpenIntent(uri, '')`；
  `if (intent.type.length > 0) want.type = …` 那条守卫保留（它现在恒不成立，但它是 `externalOpenIntent` 的契约：空 type 不该进 Want）。
  打点从 `step=utd` 改为 `step=intent`。
- `shareUtd()` **只服务分享**（注释改准）：`systemShare` 的 `SharedData` 仍需要 UTD，分享动作一个字未动。
- `domain/files/ExternalOpen.ets` 与它的单测**未改**（该模块本来就支持空 type）。

### 门禁（原始输出）

| 项 | 原始输出 |
| --- | --- |
| 单测 | `Tests run: 422, Failure: 0, Error: 0, Pass: 422, Ignore: 0`；`test_result.txt` 时间戳 **13:49:25**（读取时刻 13:49:57，本轮）；日志 `> hvigor BUILD SUCCESSFUL in 43 s 990 ms`，无 `ERROR:` / `COMPILE RESULT:FAIL` |
| 打包 | `assembleHap --no-incremental`：`> hvigor BUILD SUCCESSFUL in 19 s 127 ms`；**搜 `ERROR` / `ErrorCode` / `COMPILE RESULT` 无命中**；产物 `entry-default-signed.hap` 5063672 B，SHA256 `253155A4789ADBED0C88F26B16A02D3D760DF7CEEE35D3AE032C6EDC930E5FEE` |
| `check-domain-purity` | `PASS domain 不依赖平台与应用层`（扫 25 个领域源文件） |
| `check-import-graph` | `PASS 所有相对 import 均可解析`（203 个源文件；WARN 只有两个入口文件） |
| `check-i18n-keys` | `RESULT: OK`（zh_CN/en_US 各 311 条，missing/empty/extra=0；source 184 个键全解析） |
| `check-generated-fresh` | `PASS 生成物与其生成器输入一致` |

单测基线：合并 main（带入 ticket 12 的 `WebSessionCookie` 等）后从 405 → **422**；本 ticket 的 5 条 `ExternalOpen` 用例仍在并全过。

### 成功路径：两个已落盘文件各点一次外跳

两条都**不再是 `16000019`** —— `startAbility` 返回成功，hilog 打的是 `handed to the system`：

```
file detail external open want: action=ohos.want.action.viewData type=[] flags=1 entities=0      <- ZIP（Listening 3-1，fromCache=true）
file detail external open handed to the system: uri=file://com.koracan.learnOH/…Listening%203-1%20(Extra%20Listening).zip

file detail external open want: action=ohos.want.action.viewData type=[] flags=1 entities=0      <- PDF（Homework12，fromCache=true）
file detail external open handed to the system: uri=file://com.koracan.learnOH/…-Homework12.pdf
```

**ZIP → `com.huawei.hmos.filemanager`（文件管理）接住，但没有打开这个文件**（`13-external-open-handoff-zip.png`）。
AMS 侧确认 hand-off 发生过：`RecentlyUseController … "bundleName":"com.huawei.hmos.filemanager","moduleName":"pc","abilityName":"MainAbility",… "callerBundleName":"com.koracan.learnOH"`。
但接收方落在**它自己的主页**（`最近 | 0 项`、`共 0 个文件，5 个文件夹`），没有打开、也没有把 ZIP 列进「最近」。
（首次启动它弹了自己的隐私声明，为看到后续界面点了一次「同意」—— 那是系统自带应用的首次同意，**不是设备级设置**，如实记在这里。）

**PDF → `com.huawei.hmos.browser` 接住，并且真的把内容渲染出来了**（`13-external-open-pdf-rendered.png`）：

- 地址栏：`file:///storage/Users/currentUser/appdata/el2/base/com.koracan.learnOH/haps/entry/cache/learnX-files/%E7%AE%97%E6%B3%95…-Homework12.pdf`
- 查看器：文件名 `算法分析与设计基础-Homework12.pdf`、`1 / 1`、`100%`
- 正文可见：`Homework 12` / `Deadline: June 15, 2026` / `CLRS (4th Edition), Problems 26-2。` / `实验（二选一）…`
- AMS：`SCBMain: startSceneTransition:{… bundleInfo:MainAbility/com.huawei.hmos.browser/entry/0 … callerAbilityName: EntryAbility …}`

> **那个未知之处被正面回答：接收方真的能读到沙箱里的文件。** 浏览器把 `file://com.koracan.learnOH/…`
> 解析成了真实路径 `file:///storage/Users/currentUser/appdata/el2/base/com.koracan.learnOH/…` 并读出了 PDF 内容，
> 说明 `FLAG_AUTH_READ_URI_PERMISSION`（`flags=1`）被系统兑现了 —— 这不是「它自己报了自己的错」，是**内容真的画出来了**。
>
> 截图里另一个标签页 `Example Domain` 是上一轮 T8 实验（`aa start -U https://example.com/x`）留下的，与本 ticket 无关；
> 它还在那里只是因为浏览器被复用、没有开隐私模式。记在这里避免误读。

**两条合起来的结论**：改完之后外跳从「必然弹错误」变成「系统稳定接住」。PDF 这一类（浏览器能渲染的类型）是**真正可用**的成功路径；
ZIP 这一类**被接住但接收方不打开**（filemanager 那条无类型约束的 skill 是它的主页入口，不看 uri）——
比改动前的「点了报错」好，但也不是「打开成功」。这个差异是**接收方的行为**，不是我们 want 形状的问题（同一形状对 PDF 就成功）。

### 不回归：「无接收方 ⇒ 可读文案」

**本轮没能在设备上重现，而且这一台上它现在不可达。** 依据：

- type-less 的 `viewData` 在这台上有**至少两个**声明者：`filemanager` 的 `types=[]` 那条，与 `browser` 的 `types=[ | | text/plain]` 那条。
  于是任何 type-less 的 viewData 都能匹配到接收方 —— 上一轮的 T3 / T7 / T8 三次无类型试验**全部** `start ability successfully`，
  其中 T7 用的就是我们这种 `file://com.koracan.learnOH/…` uri。
- 所以「平台无接收方」这条输入在这一台上已经造不出来了（不改代码、不改设备的前提下）。
- 代码上那条分支**一点没动**：`catch` 仍在、仍按 `step` 打点、仍写 `openNote = loh_open_file_failed`；
  它在本 ticket 第一轮（带 type 的产物）**已经在设备上实测过**（`13-external-open-no-handler.png` 与 `13-open-failure-note-persists.png`）。
  本轮唯一的相关改动是「不再把 type 塞进 Want」，没有触及失败分支。

### 本轮产物

| 文件 | 字节 | SHA256(前16) | 用途（一条主论断） |
| --- | ---: | --- | --- |
| `13-external-open-handoff-zip.png` | 270047 | 234ABC0681BF26ED | 点 ZIP 外跳后：接收方（文件管理）被拉起、停在它自己的主页，未打开该文件 |
| `13-external-open-pdf-rendered.png` | 311257 | 203C9F894A928E42 | 点 PDF 外跳后：浏览器把沙箱文件解析成真实路径并**渲染出 PDF 正文**（读权限确实被兑现） |
| `logs/13c-layout-01/04-*.json` | — | — | 两个文件的详情页 dump：都 `fromCache=true`；PDF 那帧外跳在 `[2664,…]`（多一枚详情/预览） |
| `logs/13c-hilog-2/5.txt` | — | — | 两次点击的 `type=[]` + `handed to the system` 原话 |
| `logs/13c-layout-02/03/05-*.json` | — | — | 接收方界面 dump（filemanager 隐私声明 → 主页；browser 的地址栏与标签页） |
| `logs/13c-hilog-restore.txt`、`logs/13c-layout-09-restored.json` | — | — | 收尾复原：`semester override … source=none`、文件 tab 回到 `全部 4` |

### 本轮收尾

- 设备复原：`aa force-stop` 后不带 `--ps` 重启 → `data.files semester override: … effective="" source=none`，文件 tab `全部 4`。
- **没有清缓存**（按要求）：166MB / 734MB 两个 ZIP 与 `Homework12.pdf` 都仍在应用缓存里，别的 ticket 可继续引用。
- 只碰 `127.0.0.1:5559`；没有点退出登录、没有点任何提交入口、没有改设备级设置。
- 唯一一处落在应用外部的状态变更：`com.huawei.hmos.filemanager` 的首次隐私声明被点了一次「同意」（为了看到它接住之后的行为）。
