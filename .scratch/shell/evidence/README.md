# ticket 03（导航骨架 + 公告列表）模拟器取证清单

设备：模拟器 **Pura 90**（串口 127.0.0.1:5555，HarmonyOS 6.1.0(23)）。**不是真机**（真机 3FYBB25407201890 / MatePad Air API 24 未连接，按 AGENTS.md 归 ticket 18 前的最终一次性复验）。

截图均为 1320x2856 全屏 PNG；部分帧由设备 `snapshot_display` 的 jpeg 转 PNG（该命令只接受 .jpeg 后缀）。
layout dump 是 `devecocli ui layout --format json --mode full` 的原始输出（剥掉首行 `- Dumping layout…`）。
源码追溯见 `03-source-revision-*.txt` 与 `revision.txt`：含 `git rev-parse HEAD`、`git status --porcelain` 的 SHA256、已安装包 versionName/versionCode（原始输出 `03-bm-dump.txt`）。

## 验收后修复（统筹复核发现）

统筹在 `03-pull-refresh-refreshing-zh.png` 里发现**同时出现两个 indicator**：Refresh 自己的 spinner/promptText 之外，列表正中还叠了一个居中 LoadingProgress。
根因：`NoticesPage.listBody()` 用 `store.isBusy()`（= LOADING **或** REFRESHING）决定是否盖居中指示器，于是下拉刷新也叠了一层。
修法：`NoticeListStore` 新增 `isInitialLoading()`（`phase === LOADING && items.length === 0`），居中指示器只用它；`isEmpty()` 里用 `isBusy()` 抑制空态闪烁的逻辑保持不变。
修复后证据：`03-pull-refresh-refreshing-zh.png`（只有 Refresh 一个指示器，列表照常可见）、`03-pull-refresh-refreshing-2-zh.png`、`03-pull-refresh-done-zh.png`；
首屏加载反馈仍在：`03-initial-loading-zh.png`（冷启动首次加载的居中 spinner）；恢复提交态后的界面：`03-final-zh.png`。

| 文件 | 字节 | SHA256(前16) | 用途 |
| --- | ---: | --- | --- |
| 03-bm-dump.txt | 18216 | 5b35a1751ef1fb45 | bm dump -n com.koracan.learnOH 原始输出（已安装包 versionName=1.1.0 / versionCode=1000042） |
| 03-empty-en-dark.png | 140115 | 612f0b0be4708809 | 验收3 + 主题：空态文案（英文 No notices）+ 深色主题（应用级 setColorMode，未动设备全局） |
| 03-empty-zh.png | 129221 | 4f7516026733cc66 | 验收3：空态文案（中文：暂无公告 / 未读 0） |
| 03-final-zh.png | 339567 | 6afa265654b4dfd6 | 收尾：开关全 false、MOCK_LATENCY=700 重新构建安装后的最终界面（修复后重拍） |
| 03-hilog-empty-en-dark.txt | 7466 | 7747b0bba7d33603 | 空态（英/深）时 hilog |
| 03-hilog-empty-zh.txt | 7261 | 08dd07acea41473c | 空态（中/浅）时 hilog |
| 03-hilog-final.txt | 4676 | 3ea9a0768060caec | 最终构建 hilog（冷启动 + 首屏，修复后重采） |
| 03-hilog-refresh-30s.txt | 5192 | 5be3c8a6fe287c44 | 30s 延迟会话 hilog：冷启动首次加载 + 下拉刷新状态机（修复后取证） |
| 03-hilog-refresh-pre.txt | 5192 | ea7eb9ff687585ff | 刷新前 hilog 缓冲快照 |
| 03-hilog-refresh.txt | 8619 | e3b37e9ba4e599fe | 下拉刷新全程 hilog（域 0x4C4F，700ms 会话）：pull refresh state 1→2→3→4 与 refresh done |
| 03-initial-loading-zh.png | 125009 | 81e17e8b9acc754b | 验收后修复 2：冷启动**首次加载**的居中 spinner（证明改条件没把首屏加载反馈去掉；30s 延迟下抓） |
| 03-layout-empty-en-dark.json | 16182 | 8f6d520cf6461e72 | 空态（英/深）无障碍树 |
| 03-layout-empty-zh.json | 16175 | dba2f9fd206a5d01 | 空态（中/浅）无障碍树 |
| 03-layout-final-zh.json | 53584 | bb10567f34211099 | 最终界面无障碍树（7 条公告、未读 2） |
| 03-layout-refresh-after.json | 53584 | 900a9c210c9c0411 | light 阶段刷新后无障碍树（更新于 02:44:46） |
| 03-layout-refresh-before.json | 53584 | 8a96dde3ff7c7756 | light 阶段刷新前无障碍树（更新于 02:42:08） |
| 03-layout-refreshframe-after.json | 53584 | 0a335783d0f3d189 | 刷新帧采集后无障碍树 |
| 03-layout-refreshframe-before.json | 53584 | f17d7be24a22ef1e | 刷新帧采集前无障碍树 |
| 03-layout-scroll-after.json | 56518 | 5c434b9dd03919a0 | 滚动保持 D1 切回后无障碍树（与 before 逐字节相同 = 位置未变） |
| 03-layout-scroll-before.json | 56518 | 5c434b9dd03919a0 | 滚动保持 D1 切走前无障碍树 |
| 03-layout-scroll2-after.json | 56518 | 5c434b9dd03919a0 | 滚动保持 D2 切回后无障碍树（与 before 逐字节相同） |
| 03-layout-scroll2-before.json | 56518 | 5c434b9dd03919a0 | 滚动保持 D2 切走前无障碍树 |
| 03-layout-step-swipe.json | 53584 | f17d7be24a22ef1e | 刷新帧采集时列表容器真实 bounds（swipe 坐标来源） |
| 03-layout-swipe.json | 56518 | 5c434b9dd03919a0 | light 阶段滚动容器真实 bounds |
| 03-layout-tabs-zh.json | 53584 | 8a96dde3ff7c7756 | 首屏无障碍树（五个 tab 文案与真实 bounds） |
| 03-layout-tap.json | 9491 | 450ca76872ddd8a5 | 点击目标解析时无障碍树 |
| 03-list-after-refresh-zh.png | 338718 | ac57cfd7eba15ad9 | 验收3 上半：light 阶段刷新完成后页头「更新于」更新为 02:44:46 |
| 03-pull-refresh-done-zh.png | 665345 | 3b166ae47a2fa84b | 刷新完成帧：页头「更新于」已更新，列表恢复 |
| 03-pull-refresh-refreshing-2-zh.png | 593752 | f4a7249e1a0cb9a0 | 同上，刷新中第二帧（spinner 旋转中） |
| 03-pull-refresh-refreshing-zh.png | 584245 | 1366a68e39cbd13b | 验收3 + 验收后修复 1：下拉刷新进行中——**只有** Refresh 的 spinner + promptText「刷新」，列表照常可见，无第二个居中指示器 |
| 03-refresh-hilog-empty-en-dark.txt | 1304 | a60ee405649edf92 | 空态（英/深）时 features.notices 过滤行 |
| 03-refresh-hilog-empty-zh.txt | 1956 | 36d2900562dfe08e | 空态（中/浅）时 features.notices 过滤行 |
| 03-refresh-hilog-refresh.txt | 4299 | 0393aeaee825ead3 | 上者过滤版（只留 features.notices 刷新相关行） |
| 03-scroll-after-switch-zh.png | 328291 | 3d12a06bf322d65e | 验收1 方向一：切到设置再切回公告后位置不变（切回后） |
| 03-scroll-before-switch-zh.png | 328137 | e57ec1a0b77fa740 | 验收1 方向一：公告列表滚到中段（切走前） |
| 03-scroll2-after-switch-zh.png | 327728 | 52cc20581a75fc07 | 验收1 方向二：切到课程再切回公告后位置不变（切回后） |
| 03-scroll2-before-switch-zh.png | 328096 | 5377c3a94fd68b06 | 验收1 方向二：继续下滚一段（切走前） |
| 03-shell-tabs-zh.png | 339307 | 30b069c926c44819 | 提交态首屏：五个 tab 可见 + 公告列表（中文/浅色） |
| 03-source-revision-light-end.txt | 1287 | 9bce2df410cee7a5 | light 取证结束时快照（指纹与开始一致） |
| 03-source-revision-light.txt | 1815 | d8a27799bfc6800b | light 取证开始时的源码/设备版本快照 |
| 03-source-revision-refresh.txt | 1232 | 7061326b3f2ef2d6 | refresh 取证时快照 |
| 03-tab-courses-placeholder-zh.png | 121444 | 199cb1096fc3644b | 课程 tab 占位页（点击底栏切换后） |
| 03-unit-test-by-class.txt | 724 | 8176d7e3e406b966 | hypium 分类汇总（101 run / 0 fail，features.notices.* 15 条全绿；修复后重跑） |
| revision.txt | 1232 | 7061326b3f2ef2d6 | 最近一次 Save-Revision（refresh 阶段）时的源码/设备版本快照 |

## 这批取证对应哪份源码

取证期间工作区是**脏的**（ticket 03 的未提交改动 + ticket 05 的在途文件），所以：

- 截图分别对应磁盘上 02:53 / 03:10 / 03:14 / 03:19 / **03:36（修复验证）** / **03:40（最终）** 几次由本 agent 完成并立刻安装截图的构建；
- 截图不对应任何单个 commit；每张的 git HEAD 与工作区指纹见 `03-source-revision-*.txt`；
- 空态 / 深色 / 英文三张是在取证开关翻成 true 的构建上拍的；修复验证三张是在 `MOCK_LATENCY_MILLIS=30000` 的构建上拍的。

## 取证用临时开关 / 临时值（提交态全部复原）

- `MOCK_EMPTY_FOR_EVIDENCE`：Mock 返回空集合 → 空态两张截图；
- `FORCE_DARK_FOR_EVIDENCE`：应用级 `setColorMode(DARK)`（**不改设备全局深色模式**）→ 深色截图；
- `FORCE_ENGLISH_FOR_EVIDENCE`：应用级 `setLanguage(en-Latn-US)`（**不改设备全局语言**）→ 英文截图；
- `SLOW_MOCK_FOR_EVIDENCE`：Mock 延迟 700ms → 5000ms；修复验证时改为临时把 `MOCK_LATENCY_MILLIS` 置 **30000**（5s 不够：`devecocli ui`/`hdc` 单次调用 15-35s，必然错过窗口）。

提交态：四个常量 false、`MOCK_LATENCY_MILLIS=700`（`03-final-zh.png` 即复原后重新构建安装的界面）；深色/英文走应用级 API 而非设备全局设置（shell 无权 `param set persist.global.*`，且不干扰并行 agent）。

