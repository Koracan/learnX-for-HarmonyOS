# ticket 03（导航骨架 + 公告列表）模拟器取证清单

设备：模拟器 **Pura 90**（串口 127.0.0.1:5555，HarmonyOS 6.1.0(23)）。**不是真机**（真机 3FYBB25407201890 / MatePad Air API 24 未连接，按 AGENTS.md 归 ticket 18 前的最终一次性复验）。

截图均为 1320x2856 全屏 PNG；refresh 帧由设备 snapshot_display 的 jpeg 转 PNG（该命令只接受 .jpeg 后缀）。
layout dump 是 `devecocli ui layout --format json --mode full` 的原始输出（剥掉首行 `- Dumping layout…`）。
源码追溯见 03-source-revision-*.txt 与 revision.txt：含 git rev-parse HEAD、git status --porcelain 的 SHA256、已安装包 versionName/versionCode（原始输出 03-bm-dump.txt）。

| 文件 | 字节 | SHA256(前16) | 用途 |
| --- | ---: | --- | --- |
| 03-bm-dump.txt | 18216 | 5b35a1751ef1fb45 | bm dump -n com.koracan.learnOH 原始输出（已安装包 versionName=1.1.0 / versionCode=1000042） |
| 03-empty-en-dark.png | 140115 | 612f0b0be4708809 | 验收3 + 主题：空态文案（英文 No notices）+ 深色主题（应用级 setColorMode，未动设备全局） |
| 03-empty-zh.png | 129221 | 4f7516026733cc66 | 验收3：空态文案（中文：暂无公告 / 未读 0） |
| 03-final-zh.png | 339909 | 1604fae9a1c947d7 | 收尾：四个取证开关翻回 false 后重新构建安装的最终界面 |
| 03-hilog-empty-en-dark.txt | 7466 | 7747b0bba7d33603 | 空态（英/深）时 hilog |
| 03-hilog-empty-zh.txt | 7261 | 08dd07acea41473c | 空态（中/浅）时 hilog |
| 03-hilog-final.txt | 4298 | 908094ea24f98251 | 最终构建 hilog（冷启动 + 首屏） |
| 03-hilog-refresh-pre.txt | 5192 | ea7eb9ff687585ff | 刷新前 hilog 缓冲快照 |
| 03-hilog-refresh.txt | 8619 | e3b37e9ba4e599fe | 下拉刷新全程 hilog（域 0x4C4F）：pull refresh state 1→2→3→4 与 refresh done |
| 03-layout-empty-en-dark.json | 16182 | 8f6d520cf6461e72 | 空态（英/深）无障碍树 |
| 03-layout-empty-zh.json | 16175 | dba2f9fd206a5d01 | 空态（中/浅）无障碍树 |
| 03-layout-final-zh.json | 53584 | a916172b0f247831 | 最终界面无障碍树（7 条公告、未读 2） |
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
| 03-pull-refresh-done-zh.png | 664532 | 443ee91c85546dac | 验收3 下半：刷新完成帧，页头「更新于 03:07:10」（刷新前为 03:06:55） |
| 03-pull-refresh-refreshing-2-zh.png | 605928 | 3cc21aaad9854e37 | 验收3 下半：刷新进行中第二帧（spinner 旋转中） |
| 03-pull-refresh-refreshing-zh.png | 594979 | 441346687d84761a | 验收3 下半：下拉刷新进行中——Refresh spinner + promptText「刷新」可见（取证期把 Mock 延迟临时调到 5s） |
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
| 03-unit-test-by-class.txt | 693 | 870f863d1d153088 | hypium 分类汇总（101 run / 0 fail，features.notices.* 15 条全绿） |
| revision.txt | 1232 | 7061326b3f2ef2d6 | 最近一次取证（final）时的源码/设备版本快照 |

## 这批取证对应哪份源码

取证期间工作区是**脏的**（ticket 03 的未提交改动 + ticket 05 的在途文件），所以：

- 截图分别对应磁盘上 02:53（refresh 构建）、03:10/03:14（空态构建）、03:19（final 构建）几次由本 agent 完成并立刻安装截图的构建；
- 截图不对应任何单个 commit；每张的 git HEAD 与工作区指纹见 03-source-revision-*.txt；
- 空态 / 深色 / 英文三张是在取证开关翻成 true 的构建上拍的，开关清单见下。

## 取证用临时开关（提交态全部 false）

- MOCK_EMPTY_FOR_EVIDENCE：Mock 返回空集合 → 空态两张截图；
- FORCE_DARK_FOR_EVIDENCE：应用级 setColorMode(DARK)（**不改设备全局深色模式**）→ 深色截图；
- FORCE_ENGLISH_FOR_EVIDENCE：应用级 setLanguage(en-Latn-US)（**不改设备全局语言**）→ 英文截图；
- SLOW_MOCK_FOR_EVIDENCE：Mock 延迟 700ms → 5000ms，用来稳定截到 refreshing 帧。

四个常量都在 entry/src/main/ets/features/notices/repository/NoticeRepositoryProvider.ets；提交态均为 false，03-final-zh.png 就是翻回 false 后重新构建安装的界面。
用应用级 setColorMode/setLanguage 而不是改设备全局设置：shell 身份无权 param set persist.global.*（errNum 1001），且全局改动会干扰并行工作的其他 agent。

