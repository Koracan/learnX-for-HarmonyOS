# 文件详情顶栏「外跳」接上"交给系统打开方式"：设备取证清单

设备：**MatePad Pro 13（tablet）**，串口 `127.0.0.1:5559`（`hdc shell param get const.product.devicetype` 回 `tablet`）。
窗口 2880×1920 px，密度 2（1vp = 2px）。已安装包 `com.koracan.learnOH`。

> 这台机是**真实登录会话**（han-wang23）。全程没有点「退出登录」、没有点任何提交入口、没有改设备级设置。
> 点击过的按钮只有：底部 tab（文件 / 作业）、文件列表里的一个 ZIP、详情顶栏的「外跳」、以及系统对话框的「取消」。

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

## 没抓到 / 存疑（如实写）

- **成功路径（真的有应用接住）没有取证**：本机文件 tab 只有 4 个 ZIP，作业 tab 当前是空态（`暂无作业`），
  公告列表也没有带附件的公告 ⇒ 设备上没有任何非 ZIP 的落盘文件可以试。系统直接回了 `16000019 No matching ability is found`。
  ⇒ "want 能被某个真实应用接住"这一条**只有代码依据、没有设备证据**。
- 传给系统的 `type` 用的是 `general.file`（与既有分享动作同一套三常量映射，见 `FileDetailPage.shareUtd`），
  没有按扩展名细分（平台那个按扩展名取 UTD 的 API 在本工程实测会抛 401，见该方法的注释）。
  若某个 ZIP 应用只声明更具体的类型，可能会匹配不上 —— 属于后续可改项，不在本 ticket 的验收内。
