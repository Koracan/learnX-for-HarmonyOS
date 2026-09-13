# 18: 设置页三处小改：诊断串、重启半句、导出日志的保存位置

**What to build:** 账号所有者第三轮反馈里"可以顺带做的三个小问题"（2026-09-13）：

1. 沉浸式模式页正文里那行诊断串（统筹者上一轮报告的残留），**文件设置页里也有同样性质的串** —— 一并移除。
2. 沉浸式模式的说明文字里写着"**需要重启应用**"，现在**不需要**了 —— 删掉这半句，保留基本描述。
3. 设置里的"**导出日志为文本文件**"没说保存到哪，用户无从得知 —— 让用户能看到**确切位置**。

三条互不相关但都落在设置相关的三个页面上，合并成一条 ticket（同一次构建、同一台设备取证）。

**Blocked by:** None（可立即开始）

**Status:** verified（统筹者独立复核：门禁 427 绿 + 产物指纹与实现方逐字一致 + 在**另一台设备**上自己验了三处界面；见文末 2026-09-13 统筹者验收）

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

## Comments

### 2026-09-13 · wt/t18 交付（实现 agent）

**结论：三条都做完了；另外修掉一个既有缺陷（开关行的说明文字不随开关刷新），并如实登记若干未核实项。**

**改了哪些文件**

- `entry/src/main/ets/features/settings/ImmersiveSettingsPage.ets` —— 删掉 `this.message` 的正文渲染（`@State message` 一并去掉，诊断串只留 hilog）；文件头那段「说明文字仍按参考实现原样显示」的过时注释改写成事实。
- `entry/src/main/ets/features/files/FileSettingsPage.ets` —— 删掉 `Text(this.effectiveSummary)`；成功拨动不再拿诊断串当反馈（`message` 置空，失败分支保留）；**并修掉 `switchRow` 的原地陈旧**（见「修正 2」）。
- `entry/src/main/ets/features/settings/SettingsPage.ets` —— 导出成功后把 `LogExportResult.path` 的**完整路径**留在列表下方（Toast 同步显示）；失败分支仍只说原因。
- `entry/src/main/ets/ui/components/Toast.ets` —— `maxLines` 2 → 4（两行起步的导出提示不再被截断）。
- `scripts/i18n-ui-strings.mjs` —— `ui_exported` 加第三个占位符 `{2}` = 路径。
- `scripts/generate-i18n-resources.mjs` —— 新增 `REFERENCE_VALUE_OVERRIDES`（参考键的**值覆盖**，与 `LOCAL_ADDITIONS` 并列）+ 未知键抛错。
- 生成物：三份 `entry/src/main/resources/*/element/string.json`、`.scratch/foundation/i18n-keys.json`、`.scratch/foundation/i18n-key-map.md` —— 与上面两个生成器输入**同一次提交**。
- `entry/src/test/I18n.test.ets` —— `ui_exported` 那条断言改成三占位符。
- `docs/accepted-deviations.md` —— 追加**第 31 条**（带日期：变了什么 / 为什么 / 参考原值 / 替代验收标准 / 原证据还成立到哪一步），并在第 30 条那句「文案与行为不完全一致」上加了一行 2026-09-13 更正指针（那句已不成立，但不删原文）。
- `.scratch/ui-optimize/evidence/18-settings-copy-and-diagnostics.md`（文字证据，`git add -f` 入库）。

**门禁（都在本树 `wt/t18` 跑，每次前 `git rev-parse --show-toplevel` 自证）**：

| 门禁 | 数字 |
| --- | --- |
| 单测 | `Tests run: 427, Failure: 0, Error: 0, Pass: 427, Ignore: 0`；`test_result.txt` mtime **2026/9/13 18:01:16**（本轮）；`t18-test2.log` 里 `ERROR`/`ErrorCode`/`COMPILE RESULT` = **0 / 0 / 0**，`BUILD SUCCESSFUL` = 1。基线 427（`63af17b`；本轮没有增删任何 `it(`） |
| 打包 | `assembleHap --no-incremental` → `BUILD SUCCESSFUL` 1 次，`ERROR`/`ErrorCode`/`COMPILE RESULT` = **0**；hap mtime 18:04:56；解包 `ets/modules.abc` SHA256 `3399555710A864D0BCF4226230640F1A701AC29DEFFDDBD8C1DFD057BAE51C52` |
| 四脚本 | domain-purity **PASS** / import-graph **PASS**（WARN 仍是 `Index.ets`、`EntryBackupAbility.ets` 两个入口文件）/ i18n-keys **RESULT: OK**（manifest 309、reference 178、三语 missing/empty/extra=0）/ generated-fresh **PASS** |
| 产物级内容检索 | `ets/modules.abc` 里仍有 `immersive settings: immersiveMode=` 与 `file settings: useDocumentDir=`（日志没被删）；`resources.index` 里有 `隐藏导航栏和状态栏`、**没有** `需要重启应用` |

**设备证据（`127.0.0.1:5557`，hdc 实测 phone / API 23；帧与 dump 只留本地 `.dsh/logs/t18-frames/`）**

1. 沉浸式页：帧 `21-final-immersive.png` + dump `21-final-immersive.json` —— 正文只有开关与 `隐藏导航栏和状态栏`，**无** `immersive settings:`、**无**「重启」。
2. 文件设置页：`20-final-filesettings.json` —— **无** `file settings:`；`当前保存位置：/data/storage/el2/base/haps/entry/cache/learnX-files` 保留。
3. 日志照旧自证：`18:07:16 … immersive settings page appear: immersive settings: immersiveMode=false`；`18:06:17 … file settings page appear: file settings: useDocumentDir=false …`。
4. 导出日志：Toast 帧 `22-final-export-toast.jpeg` 与常驻行帧 `23-final-export-persistent.png` / dump（bounds `[0,2278,1320,2467]`）都含 `已导出 90 条 / 15164 字节` + `保存位置：/data/storage/el2/base/haps/entry/files/logs/learnOH-1789294109474.log`；与 hilog `18:08:29 … logs exported: path=…` **逐字符相同**（70 字符，`-ceq` = True）。

**派单情报的修正（都以我的复核为准）**

- **修正 1（前提变化）**：ticket 文件在**主树里是未跟踪的**（`?? .scratch/ui-optimize/issues/18-…`，17 号同样），`worktree add` 带不过来 ⇒ 我这棵树里原本**没有**这个文件。我按 8649 B、SHA256 `52EB2A34585B3958F3D89A25B285949D433586362572160AD43FF5AA554D80E8` **逐字节**从主树复制到我的分支，再在末尾追加本 Comment。**主树那份我没有动**（现在仍是 `??`）。统筹者若之后在主树提交同一文件，请用「取一份 + 保留本 Comment」收敛。
- **修正 2（意外发现，已修）**：`FileSettingsPage` 的开关行说明文字**不随开关原地刷新** —— 拨到 ON 后 caption 仍是「…缓存…」那句，退出再进才对。**这在 `63af17b` 上就能复现**：我 `git stash` 后在原树重编装机，`AB-02-toggled.json` 拨动后 caption 依旧、正文还同时出现**两行** `file settings: useDocumentDir=true …` ⇒ **既有缺陷，不是本次改动引入**。修法：`switchRow` 不再把 title/caption/isOn 当**值参数**传，改为在 builder 体内按 `key` 现读状态；修后原地跟随（`08` / `09`）。**这条超出 ticket 字面范围**，但第 1 条自己的理由（「开关本身 + 下面那行说明已经表达了状态」）在修前并不成立，所以我认为它属于本 ticket 的必要部分；若统筹者认为该拆成单独 ticket，请告知。
- **修正 3**：`FileDetailPage.ets:156` 也调用 `describeFileSettings`，但它只进日志（`settingsSummary` 不渲染）—— 不是「同性质的残留」，未动。

**没做到 / 存疑（如实）**

1. **没有独立核实导出文件真的落盘**：`hdc shell ls` 与 `hdc file recv` 都读不到 `/data/storage/el2/base/haps/entry/files/logs/`（应用私有沙箱，shell 用户看不到，返回 `No such file or directory`）。可核实的只有：导出调用**无异常正常返回**（hilog 无 `log export failed`、有 1 条 `logs exported`），界面与日志路径逐字一致。
2. `AB-02` 那张「两行诊断串」我只核了 dump，没有单独截图；它只是修前对照的旁证，不是判据。
3. 英文文案与英文 Toast 的路径**没有在英文界面下取帧**，只核了生成物与 `string.json` / `resources.index`。设备语言属硬禁止项，未动。
4. 单测基线 427 是**引用 ticket 14 / 16 的已合并数字**，我没有在 `63af17b` 上单独跑基线（本轮没有增删 `it(`，只改了一条断言的期望值）。
5. 第 2 条英文新值把 `. App restart required.` 半句连同句末句点一起去掉；ticket 只写了「去掉那半句」，标点取舍是我定的。

**设备与工作区状态**：学期未动、未点「退出登录」、未改设备级永久设置；文件设置开关拨动过 ON → OFF 并已复原（hilog `file settings changed: … value=false …` + 界面 `当前保存位置：…/cache/learnX-files`）。工作区只剩本轮改动，无残留探针；帧 / dump / hilog / patch 全部只在本机（`.dsh/logs/`）。

### 2026-09-13 · 统筹者验收：**verified**（我自己重跑门禁 + 在另一台设备上复核了三处）

**A. 产物同一性**：我在 `wt/t18`（`c976b5a`）里自己跑 `assembleHap --no-incremental`，解包 `ets/modules.abc` = **1,793,988 B**、SHA256 **`3399555710A864D0BCF4226230640F1A701AC29DEFFDDBD8C1DFD057BAE51C52`** —— 与实现方报的**逐字符相同**。

**B. 门禁（我在它的树里重跑）**：删 `entry/.test` + `test --no-incremental` ⇒ `Tests run: 427, Failure: 0, Error: 0, Pass: 427, Ignore: 0`（`test_result.txt` mtime **18:12:52**，我这一轮）；日志搜 `ERROR`/`ErrorCode`/`COMPILE RESULT` 各 **0**、`BUILD SUCCESSFUL` 1；`assembleHap --no-incremental` 同样 0/0/0；四脚本 PASS / PASS / `RESULT: OK` / PASS，且跑完生成器后 `git status` **为空** ⇒ 6 个生成物能由已提交的输入复现（这才是 fresh 的真判据）。

**C. 我在设备 `127.0.0.1:5559`（tablet；我自己装的这份提交态产物，装机 `updateTime` ≈ 18:13:47）上复核三条**：
1. **沉浸式页**：dump 右栏只有开关与 `隐藏导航栏和状态栏` —— `hasImmersiveDiag=false`、`hasRestartCopy=false`；同一次会话的 hilog 仍有 `immersive settings page appear: immersive settings: immersiveMode=false` ⇒ **界面没了、日志还在**（两个论断各有各的证据）。
2. **文件设置页**：dump 里 **无** `file settings:`，`当前保存位置：/data/storage/el2/base/haps/entry/cache/learnX-files` **保留**；我自己拨了一次第一个开关 ON→OFF：caption 与「当前保存位置」**原地**跟着变（`…/files/learnX-files` → 拨回 `…/cache/learnX-files`），已复原 OFF。
3. **导出日志**：我自己的 dump 里那一行是 `已导出 … / 保存位置：/data/storage/el2/base/haps/entry/files/logs/learnOH-1789294660719.log`，与同次 hilog 的 `logs exported: path=…` **逐字符相同**（我在程序里做的字符串相等判断 = true）。

**D. 我认下的范围扩张**：实现方顺手修掉的「文件设置页开关行说明文字不随开关原地刷新」（`switchRow` 改为在 builder 体内按 key 现读状态）**接受为本 ticket 的一部分**：它正是第 1 条自身理由（「开关 + 说明已经表达了状态」）成立的前提，修后行为我在设备上复核过（C.2）。修前的陈旧只有它的 `AB-02` dump（未截图），我**没有**独立重做那半边的 A/B。

**E. 我确认的缺口（与实现方一致，均不阻塞判据）**：① 导出文件是否真落盘**没有**独立核实（私有沙箱 shell 读不到；可核实的只是调用无异常 + 界面与日志路径一致）；② 英文界面未取帧（设备语言是硬禁止项），只有资源级证据；③ 427 基线引自前几轮，本轮没有增删 `it(`。

**F. 合并**：`wt/t18` 已并入 main（`fa6cbb3`；唯一冲突是 ticket 文件本身 —— 主树那份是后提交的、分支那份带 Comment，取分支版收敛）。

