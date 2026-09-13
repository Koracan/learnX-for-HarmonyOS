# ticket 18 证据：设置相关三处小改（诊断串 / 「需要重启」半句 / 导出日志的保存位置）

- 树：`wt/t18` @ `D:/Koracan/source/harmony/learnOH-wt/t18`（每次构建与取证前 `git rev-parse --show-toplevel` 自证，输出始终是这一条）。
- 设备：`127.0.0.1:5557`，hdc 实测 `const.product.devicetype=phone`、`const.ohos.apiversion=23`、`model=emulator`。
- 交付构建：`assembleHap --no-incremental` → `.dsh/logs/t18-assemble3.log`（`BUILD SUCCESSFUL` 1 次，`ERROR`/`ErrorCode`/`COMPILE RESULT` 各 0）；hap mtime 2026-09-13 18:04:56。
- 交付产物指纹：解包后 `ets/modules.abc` 的 SHA256 = `3399555710A864D0BCF4226230640F1A701AC29DEFFDDBD8C1DFD057BAE51C52`（**同树内**可比；hap 文件哈希不用）。
- **图片 / dump / hilog 只留本地**（`.dsh/logs/t18-frames/`、`.dsh/logs/t18-hilog-*.txt`，`.dsh/` 已 gitignore）。本文件只写文字论断 + 本地文件名。
- 下列帧一律来自**最终交付构建**（18:04:56 装机那一版）；17:53 那一版是同源码的中间构建，其帧只在 A/B 段引用。

## 论断 ↔ 证据（一条论断一个证据）

### 论断 1｜沉浸式设置页不再把 `immersive settings:` 当正文渲染（ticket 第 1 条前半）

- 证据：`.dsh/logs/t18-frames/21-final-immersive.png`（帧）+ `21-final-immersive.json`（layout dump）。
- dump 的全部文本节点：`沉浸式模式` / `沉浸式模式` / `隐藏导航栏和状态栏`；脚本判据 `hasImmersiveDiag=False`（搜 `immersive settings:`）。
- 帧：正文只有开关行 + 说明行，下方空白（原来的自证行位置没有任何文字）。

### 论断 2｜文件设置页不再把 `file settings:` 当正文渲染；「当前保存位置」保留（第 1 条后半）

- 证据：`.dsh/logs/t18-frames/20-final-filesettings.json`；判据 `hasDiagnostic=False`。
- dump 文本节点含 `当前保存位置：/data/storage/el2/base/haps/entry/cache/learnX-files`（**保留**，它是给用户的信息）；**不含** `file settings:`。
- 修前对照（原树 `63af17b`，见论断 7 的 A/B）：`t18-frames/AB-01-open.json` 在同一位置有 `file settings: useDocumentDir=false omitCourseName=false overrideUseDocumentDir=none …` ⇒ 这条残留确实在，且已消失。

### 论断 3｜成功拨动开关时**不显示**诊断串（判据里点名的 :76 / :87 / :91-93 三处）

- 证据：`t18-frames/08-fix-toggled-on.json`（拨到 ON 后的 dump）与 `09-fix-toggled-back.json`（拨回 OFF）。两者都只有 caption 与根目录变化，**没有**任何 `file settings:` 行。
- 修前对照：`t18-frames/AB-02-toggled.json`（原树）在拨动后正文出现**两行**同内容诊断串（`Text(effectiveSummary)` 与 `Text(message)` 各一行）。
- 失败分支未退化：`ui_export_failed` / `loh_clear_file_cache_failed + persist failed` 的赋值一字未改（见 `FileSettingsPage.ets` 的 diff）。

### 论断 4｜诊断串**照旧**写 hilog（界面没了 ≠ 日志里没了）

- 证据：`.dsh/logs/t18-hilog-final.txt`（`devecocli log --device 127.0.0.1:5557 --from 4m --tail 12000`，先全量拉再本地筛 —— 不按 `--keyword`，因为该过滤会丢 tag）。
  - `09-13 18:07:16.430 … [features.settings.immersive.page] immersive settings page appear: immersive settings: immersiveMode=false`
  - `09-13 18:06:17.829 … [features.files.settings] file settings page appear: file settings: useDocumentDir=false omitCourseName=false overrideUseDocumentDir=none overrideOmitCourseName=none source=stored-default root=/data/storage/el2/base/haps/entry/cache/learnX-files`
  - `… file settings changed: key=useDocumentDir value=false persisted=true file settings: …`（拨回时的消费点自证）
- 产物级：`ets/modules.abc` 里 `immersive settings: immersiveMode=` 与 `file settings: useDocumentDir=` 都仍在（两个 `describeX` 函数没被删）。

### 论断 5｜说明文字只剩前半句（ticket 第 2 条）

- 证据：`t18-frames/21-final-immersive.png` 帧里那一行只有 `隐藏导航栏和状态栏`；`21-final-immersive.json` 判据 `hasRestartCopy=False`（搜 `重启`）。
- 生成物：`entry/src/main/resources/{base,zh_CN}/element/string.json` 的 `loh_immersive_mode_description` = `隐藏导航栏和状态栏`，`en_US` = `Hide the navigation bar and status bar`（由生成器重跑而来，非手改）。
- 产物级负对照：`resources.index` 里 `需要重启应用` = **False**，`隐藏导航栏和状态栏` = **True**。

### 论断 6｜导出日志后用户能看到**确切路径**，且与 hilog 逐字一致（ticket 第 3 条）

- 证据 A（瞬时提示）：`t18-frames/22-final-export-toast.jpeg`（点击后立刻 `snapshot_display` 抓，3 秒窗口内命中）—— 两行：`已导出 90 条 / 15164 字节` / `保存位置：/data/storage/el2/base/haps/entry/files/logs/learnOH-1789294109474.log`。
- 证据 B（Toast 消失后仍在屏幕上）：`t18-frames/23-final-export-persistent.png` + `23-final-export-persistent.json`；dump 那一节点 `bounds=[0,2278,1320,2467]`，`text` 完整为上面两行。
- 证据 C（同一份文案的来源）：`.dsh/logs/t18-hilog-final.txt` 的 `09-13 18:08:29.477 … logs exported: path=/data/storage/el2/base/haps/entry/files/logs/learnOH-1789294109474.log records=90 bytes=15164`。
- **字符级比对**：dump 的路径（去掉 `保存位置：` 前缀）与 hilog 的 `path=` 值 `-ceq` = **True**，长度 70。同一份 `t()` 结果同时喂给 Toast 与常驻行，两者必然同源。
- 失败分支未退化：`ui_export_failed` 一字未改；且本轮 hilog 里 `log export failed` 计数 = 0。

### 论断 7｜开关行的说明文字现在**跟着开关原地刷新**（附带修复，见 ticket Comment 的修正 2）

- 修后（交付构建）：`08-fix-toggled-on.json` → caption 变成「文件保存在 App 的”文档”中，只会随 App 卸载而被删除。」；`09-fix-toggled-back.json` → 变回「…缓存…」。两次都**没有离开页面**。
- 修前（原树 `63af17b`，同树 A/B：`git stash` 后 `assembleHap` 装机）：`AB-02-toggled.json` 拨到 ON 后 caption **仍是**「…缓存…」，而 `file settings: useDocumentDir=true …` 与 `当前保存位置：…/files/learnX-files` 都已更新；退出再进（`AB-03`）才显示正确 ⇒ **既有缺陷**，不是本次改动引入。

## 门禁原始数字

| 门禁 | 数字 / 出处 |
| --- | --- |
| 单测 | `Tests run: 427, Failure: 0, Error: 0, Pass: 427, Ignore: 0`；`entry/.test/default/intermediates/test/coverage_data/test_result.txt` mtime **2026-09-13 18:01:16**（本轮）；`.dsh/logs/t18-test2.log` 里 `ERROR`=0 / `ErrorCode`=0 / `COMPILE RESULT`=0 / `BUILD SUCCESSFUL`=1。基线 427（`63af17b`） |
| 打包 | `.dsh/logs/t18-assemble3.log`：`BUILD SUCCESSFUL`=1，`ERROR`/`ErrorCode`/`COMPILE RESULT`=0 |
| `check-domain-purity.mjs` | PASS（25 个领域源文件） |
| `check-import-graph.mjs` | PASS；WARN 仍是 `entrybackupability/EntryBackupAbility.ets` 与 `pages/Index.ets`（入口文件，属正常） |
| `check-i18n-keys.mjs` | RESULT: OK；manifest 309 / reference 178 / 三语 missing=empty=extra=0；source 182 个键全部可解析 |
| `check-generated-fresh.mjs` | PASS（6 个生成物 × 2 个生成器） |

## 没做到 / 存疑

1. **导出文件是否真的落盘，没有独立核实**：`hdc -t 127.0.0.1:5557 shell ls /data/storage/el2/base/haps/entry/files/logs/` 与 `hdc file recv` 都返回 `No such file or directory`（应用私有沙箱，shell 用户看不到）。能核实的只有「调用无异常返回」（无 `log export failed`）与界面/日志路径一致。**不声称**文件内容正确。
2. `AB-02` 的「两行诊断串」只核了 dump，没有单独截图（它只是修前对照的旁证，不是判据）。
3. 英文界面下的文案与英文 Toast **没有取帧**；英文侧只核了生成物与 `resources.index`。设备语言属硬禁止项，未动。
4. 单测基线 427 引用的是已合并 ticket（14 / 16）的记录，**没有**在 `63af17b` 上单独跑基线；本轮没有增删任何 `it(`，只改了一条断言的期望值。
5. 第 2 条的英文新值把整句 `. App restart required.` 的后半句连同句末句点一起去掉（保留 `Hide the navigation bar and status bar`）；ticket 只写了「去掉那半句」，标点取舍是我定的。
