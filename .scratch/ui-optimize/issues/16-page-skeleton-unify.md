# 16: 页面骨架统一：返回图标与标题同行、内容靠上

**What to build:** 账号所有者第二轮反馈（2026-09-13）三项合并：
1. 文件页与课程页的返回按钮现在在标题**上一行** ⇒ 改到**与标题同一行**（标题随之上移）；
2. 设置页（含其子页，如学期切换）的返回按钮现在是**文字「返回」** ⇒ 改成**图标**，并且同样**与标题同一行**；
3. 文件页与设置页的内容现在**纵向居中** ⇒ 改成**靠上**。

**Blocked by:** None（可立即开始）

**Status:** ready-for-agent

**判据**
- [ ] **先盘一遍（交付物的一部分）**：列出所有带返回按钮的页面/页头（至少覆盖 文件、课程、设置及其子页、公告详情、作业详情），
      逐条给出「返回是文字还是图标」「返回与标题是否同一行」「内容是否纵向居中」的现状 + dump 证据。判据是**统一**，所以要先说清统一到哪一边。
- [ ] **返回=图标**：全部改为图标，**复用既有图标闭集里已有的返回箭头**（不新造字形），并**保留无障碍文案**（既有回退分支靠可读 label，别退化成图标短名）。
- [ ] **同行**：返回与标题在同一行、标题因此上移；给**修前/修后 dump 对照**（同页同状态：返回 bounds 与标题 bounds 的 y 区间关系）。
- [ ] **内容靠上**：文件页与设置页的内容容器不再纵向居中；给修前/修后 dump 对照（首个内容节点/列表首行的 y）。
- [ ] **不回归**：各页顶栏原有其它按钮（刷新/分享/搜索/提交…）位置与可点性不变（dump 命中区对照）。
- [ ] **门禁**：单测 + assembleHap + 四个脚本（见下）。

**派单情报（统筹者初查，供起点，不是结论）**
- 起点：`features/courses/CourseDetailPage.ets`（注释自称返回是图标）、`features/settings/SettingsPage.ets`、`features/settings/ImmersiveSettingsPage.ets`、
  `features/settings/SettingsRoutes.ets`、`features/files/FilesPage.ets`、`features/files/FileDetailPage.ets`、`features/courses/SemesterSelectionPage.ets`、
  `features/notices/NoticeDetailPage.ets` 与 `features/assignments/AssignmentDetailPage.ets`（这两个已用 MaterialIcons `arrow-back`，可作为统一样板）。
- 纵向居中候选：`FilesPage.ets` 的 `justifyContent(FlexAlign.Center)`（约 :542/:552）；设置页里 grep 没命中**不代表没有**（可能是别的写法），自查。
- 注意：单栏页头与分栏主栏页头**可能共用同一段骨架**（`SplitView.ets` / `ShellTabs.ets` 附近）；改的时候别把分栏几何（主栏 786px / 分隔条 2px）带坏。
- 参考帧（账号所有者原始报告图，只读，**只是症状参考、不是证据**）：
  - 课程详情：返回箭头在标题上一行 —— `C:\Users\korac\.dsh\attachments\v1\objects\04\04fb42075deb127c946dd594b98626ce4e494b7684c1abd7620aad1f11183f43`
  - 学期切换：文字「返回」在标题上一行 —— `C:\Users\korac\.dsh\attachments\v1\objects\14\14b06e95bbf4a87124158308766202efb8ece313cc1dd7cebc0167cec3aad861`
  - 全屏课程详情（另一形态）—— `C:\Users\korac\.dsh\attachments\v1\objects\72\72fff9e8d75f0be5dcda5eb25ae4dec59a9371fe300b67b97a64760704d1d9bc`

**你的资源（独占，别人不得碰）**
- worktree：`D:\Koracan\source\harmony\learnOH-wt\t16`（分支 `wt/t16`，基于 main `68e488e`）。只在你这棵树里改与构建。
- 设备：`127.0.0.1:5557`（Pura 90，phone）。单栏态在这里取；**分栏态不归你**，需要时先报告再申请平板。

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
- 这三项都是骨架/页头层面的统一，改一处会影响多个页面。**先给盘点表**，再动手；盘点表里若发现我上面列的页面清单有遗漏或认错，照实改判。
- 判据以**可观察的 dump px** 为准（返回与标题同一行 = 两者的 y 区间重叠；内容靠上 = 首个内容节点 y 明显小于修前）。
### 2026-09-13 · 实现与自证

**结论**：三项都已落地，但**两项的判定范围按实测改了**——「设置页内容纵向居中」不在设置 tab 根，
而在它**四个子页的 `Scroll`**；「文件页居中」不在文件列表，而在**加载/失败态**（列表本身就靠上）。
「返回=图标 + 与标题同行」的对象也从票面列的 6 个缩到**该改的 6 个**：公告详情 / 作业详情 / 文件详情
本来就是图标且已同行（**本来就是我这次用的样板**），被误列进候选。

**判据逐条**

- [x] **先盘一遍**：11 个页面/页头的现状表（文字/图标、同行与否、内容靠上与否）见证据文件 §2；
      两处派单情报修正见 §1。判据原文里让我「说清统一到哪一边」——以公告/作业/文件三个详情页为样板。
- [x] **返回=图标**：`AppIcon.ARROW_BACK`（闭集既有字形，未新造）；`loh_back` 仍作为 label 传入，
      字体未就绪的回退分支与无障碍朗读都还在（**未新增键、未删键**）。
- [x] **同行**：5 个页面的返回/标题 y 区间由「不重叠」变成「重叠」（`[206,290]` vs `[199,297]`），见 §4.1；
      课程详情页的返回从标题上一行移进标题那一行（该页设备对照取不到，见下）。
- [x] **内容靠上**：文件设置首节点 972→**404**、沉浸式 1023→**456**、帮助 674→**486**、关于 677→**486**（§4.2）；
      文件页加载/失败态加 `.align(Alignment.Top)`（失败态设备帧见「存疑」）。
- [x] **不回归**：文件 tab 页头（搜索入口 `x[1152,1236] y[220,304]`）与设置 tab 根页头逐字节未变；
      三个详情页顶栏未改（§4.3）。
- [x] **门禁**（合并后 HEAD `110dab8`）：单测 `Tests run: 427, Failure: 0, Error: 0, Pass: 427`
      （`test_result.txt` mtime 2026-09-13 16:25:09，是本轮）；`assembleHap --no-incremental` 日志
      `ERROR`/`ErrorCode` 命中 **0**、`CompileArkTS` 完成、`BUILD SUCCESSFUL in 13 s 109 ms`；
      四脚本 PASS / PASS / `RESULT: OK` / PASS。

**证据**：文字证据 `.scratch/ui-optimize/evidence/16-page-skeleton-unify.md`；帧与 layout dump 留本地
`.dsh/logs/`（`pre-*` = 修前、`fin-*` = 修后，同一设备同一状态）。取证对应提交 `110dab8`，
取证时工作区干净。

**如实说明（没抓到 ≠ 不存在）**

- **课程详情页的修前/修后设备对照取不到**：5557 上课程与文件列表均为 0 条
  （`semester resolution failed: no xnxq in current semester response: bytes=69`），没有可点进去的入口。
  该页只有源码级修前判据 + 与其余五页同一套 `Row` 的实现。
- **文件页失败态的「修后」帧没抓到**：该页一直走空态（`屏蔽 4`，全部 0），失败态要等站点失败才出现。
  它的「修前」有帧有 dump（失败文案 y0=1457，落在视口中部），「修后」只有源码改动。
- **分栏态未取证**：设备只有 phone（实测 `devicetype=phone`），分栏态不归本 ticket，未触碰 5559。
- **合并**：按统筹者提醒先合并 `main`（t14 的 `SemesterSelectionPage` 改动）；自动合并成功，
  t14 的 `activeSemesterId()` 读 `pendingSemesterId || semesterId` 与同步 `select()` 都在，
  我这边的返回图标 + 同行也都在。
