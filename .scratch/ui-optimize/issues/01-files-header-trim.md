# 01: 文件页头去掉多余入口与裸计数

**What to build:** 文件 tab 的页头只保留真正有信息量的东西：标题、相对更新时间、搜索入口，以及（若保留）带标签的条数。
「文件设置」入口从页头移除——这个设置本来就能从设置页进入，页头那个入口是多余的；页头那个没有标签的裸数字也移除。
功能一个不少：文件设置仍然可用，只是不再有第二个入口。

**Blocked by:** None（可立即开始）

**Status:** verified（统筹者复核：主树 392 绿 + 产物级 NOT FOUND 独立复现 + 设置页入口未丢）

- [x] 文件页头不再出现「文件设置」入口，也不再出现没有标签的裸数字
- [x] 设置页里进入文件设置的那条路径仍然可用，两个文件设置仍然生效
- [x] 页头条数：要么带标签显示，要么不显示；不存在「光一个数字」的形态
- [x] 因删除入口而变成零引用的 i18n 键，连同多语言资源与键登记表一并清理，i18n 门禁仍然通过
- [x] 证据：一次页头 layout dump（元素清单）+ 同状态截图；文件设置页仍可从设置页打开
## Comments

### 2026-09-13 · 统筹者验收：verified

**我独立复核的东西（不采信自述）**：
1. **零引用清理**：在 `entry/src/main/ets/**/*.ets`、三份 `resources/*/element/string.json`、`scripts/i18n-ui-strings.mjs` 里搜 `ui_file_settings_open` = **0 处**；`ui_file_settings_title`（文件设置页自己的标题）仍在。
2. **设置页入口没丢**：`ROUTE_FILE_SETTINGS` / `FileSettingsPage` 仍被 `features/settings/SettingsPage.ets` 引用（它自己的路由表 + `openFileSettings()`）⇒ 文件设置只是少了「页头那第二个入口」，功能一个不少。
3. **产物级（防陈旧产物）**：解包主树 hap，在 `ets/modules.abc` 里搜 `ui_file_settings_open` = **NOT FOUND**，对照组 `ui_file_settings_title` = **FOUND**（证明不是假阴性）。
4. **主树合并态**：单测 `Tests run: 392, Failure: 0, Error: 0`；四门禁脚本 PASS / OK。

**两条判断**：
- 条数选了「**不显示**」：符合 spec 关键决策 3（直接删，不新造「展示判定」模块），ticket 验收第 3 条两种形态都允许。
- 顺带删掉 `FilesPage` 里 `ROUTE_FILE_SETTINGS` 的 `NavDestination` 分支：**接受** —— 页头入口删掉后该分支不可达，是死代码；设置页走的是它自己的路由表。它自述没在双栏态实测，属「未验」，但该分支已不可达，风险面为零。

**如实登记的弱点**：before 那帧 layout dump 来自改动前的装机版本，**源码版本没有记录**（它自己指出并给了 `git show` 的源码依据）。按证据纪律，那一帧只能算**过程证据**：主论断由 after 帧 + 产物级 NOT FOUND 检索承担，两者都不依赖 before 的溯源。
