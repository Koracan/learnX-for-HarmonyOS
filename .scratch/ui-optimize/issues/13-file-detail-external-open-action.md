# 13: 文件详情顶栏的「外跳」图标接上"用系统打开"的动作

**What to build:** ticket 02 把图标闭集扩了 5 个成员，其中 `AppIcon.OPEN_IN_NEW` **只声明、零渲染** ——
当时本工程**有意去掉**了参考实现的"跳系统打开方式"，且没有对应的可读文案键，所以没有硬塞动作。
账号所有者 2026-09-13 裁定：**新增一张 ticket 把动作接上**。

**Blocked by:** None（ticket 02 已合并，`OPEN_IN_NEW` 与它的码位/fallback 都在）

**Status:** verified（合并 `3c76f9f`；两条残留：成功路径待证伪式搜索、「未落盘」帧补拍中）

- [x] 先读参考实现确认它到底做了什么：是 `Linking.openURL(fileUri)`、还是系统分享面板、还是 `startAbility` 带 want。
      **别猜**；把读到的出处（文件 + 行为）写进交付说明。若参考实现根本没有这个动作（只是引入了图标），就**如实说明并降级**为"不做动作"，不要为了凑验收造一个。
- [x] 文件详情顶栏出现"外跳"图标按钮，用已声明的 `AppIcon.OPEN_IN_NEW`
- [x] 点击把**已落盘的文件**交给系统打开方式；未落盘 / 平台无接收方时给出**可读反馈**，不静默失败
- [x] 新的可读文案走 i18n 生成器（`scripts/i18n-ui-strings.mjs`）；本 ticket 独占该输入，做完重跑生成器并让 `check-i18n-keys` = OK、`check-generated-fresh` = PASS
- [x] 无障碍 label 可读；字体未就绪时回退成**可读文案**而不是图标短名
- [x] 点击区尺寸与顶栏其它按钮一致（40vp×40vp，见 ticket 02 的实测）
- [x] 单测：按钮可见性判定 / 动作参数构造这类**纯函数**钉住输入 → 输出（不要在单测里断言"调用了哪个系统 API"）
- [x] 证据：设备截图（按钮出现）+ 点击后的系统行为截图 + layout dump 的 bounds

## Comments

### 2026-09-13 · 统筹者验收：verified（合并 `3c76f9f`；两条残留如实记录）

**我独立复核过的东西（不是转述交付回报）**：
- **参考实现逐行读过**：`reference/learnOH-old/src/screens/FileDetail.tsx:84-90` 的 `handleOpen` → `helpers/fs.ts:171-179` 的 `openFile(path)` = `FileViewer.open(path, { showOpenWithDialog: true })`；顶栏 `:115-124` 是**两个并列按钮**（`share` 与 `open-in-new`，都 `disabled={error || !path}`），`:184-200` 的 `shareFile` = `Share.open`。「把已落盘路径交给系统、由系统决定用什么打开」这个语义判断成立 ⇒ **不降级**是对的。
- **合并后的主树四门禁**（我在 `3c76f9f` 上重跑）：domain-purity PASS / import-graph PASS / i18n-keys **RESULT: OK**（manifest 309、ui 121、missing=0 empty=0 extra=0）/ generated-fresh PASS。
- **单测**：`entry/.test/default/intermediates/test/coverage_data/test_result.txt` 时间戳 `2026/9/13 13:19:04`、`Tests run: 405, Failure: 0, Error: 0, Pass: 405, Ignore: 0`（基线 400 → +5）。我核对的是**工作树里那份结果文件本身**，不是回报里的转述。
- **改动面**：14 个文件 +406/−38，与工单一一对应（含 `ExternalOpen.ets` / `ExternalOpen.test.ets` / 5 份生成物 / 三份 `string.json` / `scripts/i18n-ui-strings.mjs`）；**无 PNG、无二进制入库**。
- **接线复核**：`openReady()` = `canOpenExternally(this.phase === FileDetailPhase.READY, this.localPath)`（纯函数在 `domain/files/ExternalOpen.ets`）；失败与未落盘两条都写进同一个 `openNote`，由 `openNoteBar()` 渲染在顶栏下方、常驻到下一次动作或重新下载。

**达成的验收（逐条对着工单的勾选项）**：
1. 参考实现确有该动作（上列 5 个出处）⇒ **不降级**。
2. 顶栏第 5 枚按钮用 `AppIcon.OPEN_IN_NEW`（U+E89E），点击区 `Stack [2768,102,2848,182]` = 80×80 px = 40vp×40vp（密度 2），与其余四枚**逐点相同**（layout dump px）。
3. 平台无接收方时**不静默**：设备实测 `startAbility` 抛 `code=16000019 No matching ability is found.`，页面出现可读文案，**关掉系统对话框后仍在**（不是 2 秒 toast）；hilog 三行原话在证据文件里。
4. 新文案走生成器（`ui_file_open_not_ready`），`check-i18n-keys` = OK、`check-generated-fresh` = PASS；失败文案复用既有的 `loh_open_file_failed`，没有重复造键。
5. 单测只钉纯函数（5 条），**没有**断言"调用了哪个系统 API" —— 符合本仓"别拿桩去断言平台调用"的口径。

**残留（如实记录，不写成已达成）**：
1. **成功路径（真有应用接住 want）尚无设备证据**。交付回报给的理由是"设备上只有 4 个 ZIP、作业空态、公告无附件" —— 这是**否定性论断**，按证据纪律必须给出**搜索过程**。已就这一点派回一轮**证伪式搜索**：跨学期扫文件列表 / 带附件的公告 / 作业附件，只下载不提交；找到非 ZIP 就下载并点「外跳」取成功帧；确实没有就把"扫了哪些列表、各自返回什么"写进证据，明确写成**已搜索、不存在**。**"没抓到"不等于"不存在"。**
2. **「未落盘」那一支只有单测**：该支的**判定**由 `offersOpenOnlyForAFinishedDownloadWithALocalCopy` 钉住，反馈的**渲染机制**已由失败路径在设备上证明（同一行 `openNoteBar`）；但"点未落盘的按钮 ⇒ 出现 `ui_file_open_not_ready`"这一帧还没拍到 —— 同在这轮补证里（清 app cache，在下载窗口内点，**不必**等 166MB 下完）。

**裁定（账号所有者已授权统筹者在不确定时自行权衡）**：
- **`type` 维持 `general.file`，不改。** 参考实现的"打开"动作根本不传类型（`FileViewer.open` 只吃路径，类型由库按扩展名推），所以粗粒度**不是**移植退化；精确 UTD 所依赖的平台 API 在本工程实测会抛 401（见 `FileDetailPage.shareUtd` 的注释），要做只能自建"扩展名 → UTD"表 —— 新增面、无验收条款，且会连带改动**已验收的分享动作**。⇒ 作为技术债登记：*若真机上出现"明明有应用却匹配不上"，再考虑按常见类型补精确 UTD（一并覆盖分享）*。
- 不为上面两条新开 ticket、也不降级；两条都留在本节里，直到补证回来再改状态。

