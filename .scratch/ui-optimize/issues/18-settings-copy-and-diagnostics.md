# 18: 设置页三处小改：诊断串、重启半句、导出日志的保存位置

**What to build:** 账号所有者第三轮反馈里"可以顺带做的三个小问题"（2026-09-13）：

1. 沉浸式模式页正文里那行诊断串（统筹者上一轮报告的残留），**文件设置页里也有同样性质的串** —— 一并移除。
2. 沉浸式模式的说明文字里写着"**需要重启应用**"，现在**不需要**了 —— 删掉这半句，保留基本描述。
3. 设置里的"**导出日志为文本文件**"没说保存到哪，用户无从得知 —— 让用户能看到**确切位置**。

三条互不相关但都落在设置相关的三个页面上，合并成一条 ticket（同一次构建、同一台设备取证）。

**Blocked by:** None（可立即开始）

**Status:** open

**判据**

第 1 条 —— 诊断串不再作为正文渲染
- [ ] 沉浸式模式页：`features/settings/ImmersiveSettingsPage.ets:170-180` 把 `this.message`（`:88` / `:107` 赋成
      `describeImmersiveSettings(...)`，形如 `immersive settings: immersiveMode=false`）当正文显示 —— 移除这处渲染。
      **日志照旧**（`describeImmersiveSettings` 仍要写 hilog，它是自证口径的一部分，不要删函数）。
- [ ] 文件设置页：`features/files/FileSettingsPage.ets:234-239` 把 `this.effectiveSummary`
      （`describeFileSettings(...)`，形如 `file settings: useDocumentDir=... override=...`）当正文显示 —— 移除。
      注意 `:76` / `:87` 的两处赋值、以及 `:91-93` 把它当作"保存成功"的反馈文案：**成功时不要显示诊断串**
      （开关本身 + 下面那行说明已经表达了状态），失败提示保留。
- [ ] **保留** `FileSettingsPage.ets:229` 的「当前保存位置：<path>`（`ui_file_settings_root`）—— 那是给用户的信息，不是诊断串。
- [ ] 设备证据：两个页面各一张帧（或 dump），**看不到** `immersive settings:` / `file settings:` 开头的文本；
      同时给一行 hilog 证明这条自证串**照旧**在打（"界面上没了"≠"日志里没了"）。

第 2 条 —— 删掉"需要重启应用"
- [ ] 目标是资源键 `loh_immersive_mode_description`（三份 `entry/src/main/resources/*/element/string.json`）。
      它的值**是生成物**，来源是参考实现词表（只读）：
      `reference/learnOH-old/src/assets/translations/zh.ts:208` = `'隐藏导航栏和状态栏，需要重启应用'`、
      `en.ts:215-216` = `'Hide the navigation bar and status bar. App restart required.'`。
      ⇒ **不要手改生成物**。修法是在 `scripts/generate-i18n-resources.mjs` 里加一条**参考键的覆盖**
      （与既有的 `LOCAL_ADDITIONS` 并列、但语义是"覆盖参考键的值"），然后重跑
      `node scripts/generate-i18n-resources.mjs` 与 `node scripts/gen-i18n-keys.mjs`，
      **把生成物与生成器输入放进同一次提交**（`check-generated-fresh.mjs` 就在验这件事）。
- [ ] 新值：中文 `隐藏导航栏和状态栏`；英文把 `. App restart required.` 那半句去掉，保留前半句。三种语言都要一致。
- [ ] 这是**有意偏离参考实现**（参考只是标尺，不是完成定义）：按 `docs/agents/porting.md` 的口径在
      `docs/accepted-deviations.md` **追加一条带日期的说明**（变了什么 / 为什么 / 参考原值是什么）。
      代码注释里**不要**写台账或 ticket 编号。
- [ ] 设备证据：沉浸式设置页帧里那一行说明文字只有前半句（截图可读）。
- [ ] 顺手确认：文件头 `ImmersiveSettingsPage.ets:21-27` 里"那句说明文字仍按参考实现原样显示 …… 这处不一致是有意保留的"
      这段注释**已经过时**，一并改写成事实（不要让注释骗人）。

第 3 条 —— 导出日志告知保存位置
- [ ] 现状：`features/settings/SettingsPage.ets:213-230` 只提示 `ui_exported`（"已导出 {0} 条 / {1} 字节"），
      而 `core/log/LogBuffer.ets:92-105` 的返回值里**已经有** `path`（`<filesDir>/logs/learnOH-<ts>.log`）。
- [ ] 要求：导出成功后用户能知道**确切位置**（完整路径，不是"已保存到文件"这种废话）。
      `ui_exported` 需要加一个占位符（`scripts/i18n-ui-strings.mjs:25` 是它的定义处，改完要重跑第 2 条里那两个生成器），
      并同步更新 `entry/src/test/I18n.test.ets:235-237` 里那条断言。呈现形式你自己定（提示带路径 / 弹一个能读到完整路径的浮层），
      但**必须能在帧或 dump 里读到那条路径**。
- [ ] 设备证据：导出一次，dump 或帧里读到完整路径，且与 hilog 的 `logs exported: path=...` 逐字符一致。
- [ ] 失败分支不要退化：`ui_export_failed`（含原因）保持不变。

门禁与通用要求
- [ ] 单测 + `assembleHap` + 四个脚本，**全部在你这棵树里跑**（见文末"构建 / 门禁环境"）。
- [ ] 三处改动都**不要**碰学期、不要点「退出登录」、不要改设备级永久设置。

**派单情报（统筹者初查，均需你自己复核）**
- 诊断串的唯一实现：`data/settings/ImmersiveSettings.ets:139-141`（`describeImmersiveSettings`）与
  `data/settings/FileSettings.ets:207-209`（`describeFileSettings`）。两者都被日志使用，**函数不要删**。
- 生成器结构：`scripts/generate-i18n-resources.mjs` 的 `buildReferenceRows()` 来自参考词表、
  `LOCAL_ADDITIONS` 是本工程新增、`buildUiRows()` 来自 `scripts/i18n-ui-strings.mjs`。
  `writeElement()` 会重写 `loh_*` 与 `ui_*` 两类键、保留其他键 ⇒ 覆盖参考键要在这里落。
- 生成物共 6 个：三份 `string.json` + `core/i18n/I18nKeys.ets` + `.scratch/foundation/i18n-keys.json` + `.scratch/foundation/i18n-key-map.md`。
- 本轮另有一条线（ticket 17）也会改 `scripts/i18n-ui-strings.mjs`。**你照常改、照常提交生成物**；
  合并时的冲突由统筹者用"取一侧 + 重跑两个生成器"收敛。

**你的资源（独占，别人不得碰）**
- worktree：`D:\Koracan\source\harmony\learnOH-wt\t18`（分支 `wt/t18`，基于 main `63af17b`）。
  `ohpm install` 与 `reference/` 目录联接**已由统筹者做好**。**只在这棵树里改与构建，主树不要动。**
  开工前、每次构建前、每次取证前都 `git rev-parse --show-toplevel` 自证你在哪棵树。
- 设备：`127.0.0.1:5557`（`hdc` 实测 `devicetype=phone`，**这台只有你用**）。
  `devecocli device list` 会把它报成 Pura 90 —— 别信那列。**不要动这台设备的学期**（另一条线在用它验证切换）。

**硬禁止（会毁掉不可恢复的东西）**：不真的提交作业；不在真机上点「退出登录」；不改设备级永久设置（语言 / 分辨率 / 密度 / 时区）；
不动 `.scratch/migration/**`；**不提交图片**（帧 / dump / 日志只留本地）；不把台账或 ticket 编号写进代码注释。

**构建 / 门禁环境（照做，别自创）**
1. `$env:DEVECO_SDK_HOME='C:\Program Files\Huawei\DevEco Studio\sdk'`（不设会出现
   `Configuration Error: Invalid value of 'DEVECO_SDK_HOME'` 且**一条测试都不跑**）。
2. hvigor 入口：`C:/Program Files/Huawei/DevEco Studio/tools/hvigor/bin/hvigorw.bat`（不在 PATH 上）。
   构建以分钟计，用**后台作业**跑并把输出重定向到 `.dsh/logs/`。
3. 单测：先删 `entry/.test`，再 `test --no-incremental`；判据是
   `entry/.test/default/intermediates/test/coverage_data/test_result.txt` 里的 `Tests run:` 行 **+ 该文件的时间戳是本轮的**。
4. 打包：`assembleHap --no-incremental`，然后搜 `ERROR` / `ErrorCode` / `COMPILE RESULT`。
5. 四个脚本：`node scripts/check-domain-purity.mjs`、`check-import-graph.mjs`、`check-i18n-keys.mjs`、`check-generated-fresh.mjs`。
   本条的改动**直接落在生成器输入上**，所以 `check-generated-fresh` 与 `check-i18n-keys` 是重点，别只看 exit code。
6. 指纹：**不要用 hap 文件 SHA256**；要比就解包比 `ets/modules.abc` 的 SHA256 或用内容级检索。

**报告要求**：结论先行；每条论断配**一个**证据（file:line、dump 的 px、帧、或 hilog 时间戳）；
做不到的如实写"没做到 / 存疑"；在 `.scratch/ui-optimize/issues/18-settings-copy-and-diagnostics.md` 追加 Comment，
过程证据写进 `.scratch/ui-optimize/evidence/18-<slug>.md`（可提交），图片只留本地。
收尾必须回报「**窗口关闭**」并说明设备与工作区状态。
