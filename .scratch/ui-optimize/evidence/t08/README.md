# ticket 08（移除设置里"拨了没有任何效果"的开关）设备取证清单

设备：模拟器 **Mate X7**（串口 `127.0.0.1:5555`）。身份以 hdc 实测为准：
`hdc -t 127.0.0.1:5555 shell param get const.product.devicetype` → `phone`、`const.ohos.apiversion` → `23`
（`docs/agents/environment.md`：该实例复用 phone 镜像，故 devicetype 回 phone 属正常；`devecocli device list` 的串口列会张冠李戴，未采信）。
窗口 2210×2416 px（密度 2）。已安装包 `com.koracan.learnOH` versionName=`2.0.0` / versionCode=`2000000`。

> 这台机是**真实会话**：设置页显示账号 `han-wang23`，**没有** Mock 自证行。全程没有点「退出登录」、没有点任何提交入口、
> 没有改设备级永久设置（语言 / 分辨率 / 密度 / 系统深色模式）、没有清应用缓存。
> 5557（ticket 06）与 5559（ticket 03）全程未触碰。

## 溯源

| 项 | 值 |
| --- | --- |
| `git rev-parse HEAD`（取证时分支头 = main） | `626be964012e61d71fc7a79845c98b291e4136ac` |
| 工作区脏（本轮改动未提交） | `git status --porcelain` 14 行，其 UTF-8 SHA256 = `D2A97D6CC3A63DBA64C9DD12C68E6F98292FA96DD3C3960414A8762A533F5C6D` |
| 未提交改动的兜底副本 | `.dsh/logs/t08-wip.patch`（分支基线 94f39bd 时的快照，SHA256 前 16 = `8CE25407705D9672`） |
| 产物指纹 提交态（第一次构建，装机拍浅色帧） | `entry-default-signed.hap` **5,058,369 B @ 14:04:04**，SHA256 `800FFC591A3DC37B82BE66502DE88F851E9CC89AC70C2C6024CC64B7A23F8C60` |
| 产物指纹 深色取证态（`FORCE_DARK_FOR_EVIDENCE=true`） | **5,058,366 B @ 14:12:27**，SHA256 `296FDB3281B0B7D78E9CC794A3BB49BE54413CDAA713A24E48AAB07E70F020FF` |
| 产物指纹 提交态（复原后重刷） | **5,058,370 B @ 14:15:06**，SHA256 `8DC584E8807E06BC8D02B8EA6B06A3E8DF4F6D644A3FCFD271AEE9DDF544DCDB` |
| 解包后 `ets/modules.abc`（提交态） | 1,778,792 B，SHA256 `BAE4DFCCBAF1280B9D4A4C16CD4054DEC1BE0151AE1956AE484C3C6A8B992A1F` |

三份 hap 大小相差 1–3 B（提交态两次 5,058,369 / 5,058,370）—— 产物重生成的非字节可复现抖动，
与台账里既有的记录同源（例如 ticket 11.5 记过"差 6 B，属产物重生成的正常抖动"）。
**判"这是新产物"用的是时间戳 + 内容级检索两条**（见下面"产物内容级检查"），不是只看 `BUILD SUCCESSFUL`。

## 死开关的判据：字段 ↔ 消费点对照表

判据出处：**AGENTS.md / docs/agents/evidence.md 的"开关：自证要打在消费点"** —— 谁读它、读的人拿它做了什么。
原始 grep 输出：`grep-consumers-before.txt`（改动**前**的 main 树，逐条命令原样写在文件头）。

| # | 开关（设置页 → 页面） | 持久化字段 | 文案键 | 消费点（谁读它 → 拿它做了什么） | 判定 |
| --- | --- | --- | --- | --- | --- |
| 1 | 文件设置 → "保存打开的文件到文档" | `useDocumentDir`（preferences `learnoh_file_settings`） | `loh_file_use_document_dir` | `data/files/FileDownloader.ets:172,194,203` → `domain/files/FilePath.learnXFilesRoot()`（`FilePath.ets:130-131` 选 filesDir / cacheDir，改变**落盘根目录**） | **生效** |
| 2 | 文件设置 → "文件名不包含课程名" | `omitCourseName`（同一 preferences） | `loh_file_omit_course_name` | `FileDownloader.ets:196,206` → `FilePath.localFileName()`（`FilePath.ets:152-153` 决定 `课程名-文件名` / `文件名`） | **生效** |
| 3 | 沉浸式设置 → "沉浸式模式" | `immersiveMode`（preferences `learnoh_immersive_settings`） | `loh_immersive_mode`（+ `loh_immersive_mode_description`） | `features/settings/repository/ImmersiveSettingsProvider.ets:58` → `core/window/ImmersiveWindow.applyImmersiveMode()`（`setWindowLayoutFullScreen` + `setWindowSystemBarEnable`，隐藏/恢复状态栏与导航栏）；界面切换时也立刻调一次（`ImmersiveSettingsPage.onImmersiveToggle`） | **生效** |
| 4 | 沉浸式设置 → "避让前置摄像头" | `immersiveAvoidFrontCamera`（同一 preferences 文件） | `loh_avoid_front_camera` / `loh_avoid_front_camera_description` | **无**：`entry/src/main` 下只有（a）`data/settings/PreferencesImmersiveSettings.ets` 把它读出来、`put` 回去，（b）`ImmersiveSettingsPage` 把它显示出来 —— **没有任何读取方把它用于任何行为** | **死开关 → 移除** |

第 4 行"零消费点"的原始输出（`git grep -n -E 'immersiveAvoidFrontCamera' -- entry/src/main`，全文见 `grep-consumers-before.txt`）——
命中的每一行都落在这三类里：**注释 / 持久化读写 / 自身显示**：

```
entry/src/main/ets/data/settings/ImmersiveSettings.ets:40:  immersiveAvoidFrontCamera: boolean;          <- 值定义
entry/src/main/ets/data/settings/ImmersiveSettings.ets:46:  immersiveAvoidFrontCamera: false             <- 默认值
entry/src/main/ets/data/settings/ImmersiveSettings.ets:53:    immersiveAvoidFrontCamera: value.immersiveAvoidFrontCamera   <- 拷贝
entry/src/main/ets/data/settings/ImmersiveSettings.ets:62:  return value.immersiveMode && value.immersiveAvoidFrontCamera <- 显示值（只为第二个开关服务）
entry/src/main/ets/data/settings/ImmersiveSettings.ets:79-80: 联动置假（同上）
entry/src/main/ets/data/settings/ImmersiveSettings.ets:166:  next.immersiveAvoidFrontCamera = value   <- 写回
entry/src/main/ets/data/settings/PreferencesImmersiveSettings.ets:26: AVOID_FRONT_CAMERA_KEY   <- preferences 键名
entry/src/main/ets/data/settings/PreferencesImmersiveSettings.ets:43,50,68: get/组装/put     <- 持久化读写
entry/src/main/ets/features/settings/ImmersiveSettingsPage.ets:84,94,112,177: this.avoidFrontCamera = ... / switchValue <- 自身显示
```

**开关渲染点穷举**（`git grep -n -E 'Toggle\(|ToggleType\.Switch|TableCellType\.SWITCH' -- entry/src/main`，同一份原始输出文件）：
全仓只有 4 个开关 —— `FileSettingsPage.ets:132` 一个 `Toggle` 用于两行、`ImmersiveSettingsPage.ets:161,174` 两个 `TableCellType.SWITCH`，
渲染组件在 `ui/components/TableCell.ets:126`。**设置页主列表（`SettingsPage.ets`）里一个开关都没有**（只有导航 cell）。

**两条独立旁证**（不是本 ticket 的推断，是仓里已有的记录）：

- `docs/accepted-deviations.md:696-699`（ticket 17 交付节）："`immersiveAvoidFrontCamera` 的平台效果没有移植……所以这个开关**只持久化与显示**……**不声称**它改变了任何布局"。
- `docs/rn-app-inventory.md:33`：参考实现里它**有用**（`header top-inset fallback disabled when immersiveMode && !immersiveAvoidFrontCamera`）
  ⇒ "死"是移植时丢了那个能力，不是它本来无意义；因此处置是"不提供"，而不是"补一套 inset 回退兜住它"。

## 改了哪些行（台账批注：追加、不改写历史）

`docs/accepted-deviations.md` 的**两处**（父级点名），都是**就地追加带日期的批注**，原句一字未删：

| 位置（当前行号） | 原文（保留） | 追加的批注（摘要） |
| --- | --- | --- |
| 替代验收标准 第 5 条（:687-693） | "关掉开关 1 时开关 2 自动置假且持久化" | 【2026-09-13 追加】该末句**已不再适用**：开关 2 与其持久化字段、两条只为它存在的语义、两条文案键均已移除；原文保留因为它记录了当时真验证过的东西；本条其余部分（立刻生效 / 重启保持）仍有效，`immersiveMode` 行为未改。 |
| 未验证 / 边界（:701-710） | "`immersiveAvoidFrontCamera` 的平台效果没有移植……只持久化与显示……不声称它改变了任何布局" | 【2026-09-13 追加 · 处置已定】选择不是补 inset 回退，而是**不提供**；字段与文案键移除（退役清单唯一出处 `scripts/i18n-lib.mjs`）；旧沙箱残留键**既不读也不删**及理由；参考实现出处保留。 |

`docs/rn-app-inventory.md` **未改动**（它描述 RN 应用本身，仍然准确）；`.scratch/migration/**` **未触碰**。

## i18n：键数变化与退役机制

| 项 | 改动前（main） | 改动后 |
| --- | --- | --- |
| 参考实现迁入 | 180 | **178**（退役 2：`avoidFrontCamera` / `avoidFrontCameraDescription`） |
| 本工程新增（学期季节词等） | 8 | 8 |
| 原生重写 UI 文案（`ui_`） | 123 | 123 |
| **合计（= `I18N_KEY_COUNT`）** | **311** | **309** |

- 参考实现字典是**只读输入**，所以退役不是去改 `reference/`，而是把清单放在 `scripts/i18n-lib.mjs` 的 `RETIRED_REFERENCE_KEYS`，
  在 `buildRows()` 里过滤。**资源生成器与 `check-i18n-keys.mjs` 都走 `buildRows`** ⇒ 生成物、manifest 与"reference drift"检查天然一致（无需在 checker 里再写一份例外）。
- 6 个生成物由 `node scripts/generate-i18n-resources.mjs && node scripts/gen-i18n-keys.mjs` 重跑而来（与输入同一次提交），`check-generated-fresh` PASS。
- `entry/src/test/I18n.test.ets`：`REFERENCE_KEY_COUNT` 180 → **178**、`TOTAL_KEY_COUNT` 311 → **309**、`UI_STRING_COUNT` 保持 123（178+8+123=309）。
- 删掉的资源名：`loh_avoid_front_camera`、`loh_avoid_front_camera_description`（三份 `string.json` 各 8 行、`I18nKeys.ets` 4 行、`i18n-keys.json`、`i18n-key-map.md`）。

## 旧数据（沙箱里存过被删字段）

**处理策略：不读、也不删（忽略未知/陈旧字段）。** 理由：① 读路径只看 `immersiveMode`，`preferences.get` 取不到的键返回默认值，
不可能因此抛异常；② preferences 按键存取，多出来的键是惰性的；③ 为了纯清理去 `delete` + `flush` 会在每次启动写同一个
preferences 文件（一个只为观感的写操作，还可能失败）。

设备上**真的复现了**"旧数据"这一状态（不是推理）：

```
# 改动生效前装机的那一版（沉浸式页两个开关），把开关 1、开关 2 都拨到 ON 之后：
hdc -t 127.0.0.1:5555 file recv /data/app/el2/100/base/com.koracan.learnOH/haps/entry/preferences/learnoh_immersive_settings prefs-immersive-before.txt
<?xml version="1.0" encoding="UTF-8"?>
<preferences version="1.0"><bool key="immersiveAvoidFrontCamera" value="true"/><bool key="immersiveMode" value="true"/></preferences>
```

随后 `hdc install -r` **覆盖安装**本轮提交态产物（`-r` 保留数据），冷启动后 hilog：

```
14:08:22.166  I A04c4f/data.settings.immersive: [data.settings.immersive] immersive settings load: immersiveMode=true
14:08:22.255  I A04c4f/features.settings.immersive: [features.settings.immersive] immersive restored on startup: persisted=true applied=true
14:08:23.006  I A04c4f/features.notices.provider: [features.notices.provider] evidence switches: FORCE_DARK_FOR_EVIDENCE=false FORCE_ENGLISH_FOR_EVIDENCE=false
```

⇒ ① 读路径正常返回（没有异常、没有 `immersive settings load failed`）；② `immersiveMode` 的旧值**照旧生效**
（启动即隐藏状态栏 / 导航栏 —— 见 `t08-after-immersive-restored-bars-hidden.png`：那一帧顶部没有系统状态栏）；
③ 从该页把开关拨回 OFF，状态栏立刻回来（`t08-after-immersive-light.png`）——**开关 1 的"即时生效"未变**。

之后再一次读 preferences，**陈旧键仍在**（既没被读也没被删），而 `immersiveMode` 已被新代码更新：

```
<?xml version="1.0" encoding="UTF-8"?>
<preferences version="1.0"><bool key="immersiveMode" value="false"/><bool key="immersiveAvoidFrontCamera" value="true"/></preferences>
```

## 逐文件论断表（**一个文件一条主论断**）

图片只留本地（`.scratch/.gitignore` 忽略 `**/evidence/**`）；本 README 与 `grep-consumers-before.txt` 是文字证据，显式 `git add -f`。

| 文件 | 字节 | SHA256(前16) | 用途（主论断） |
| --- | ---: | --- | --- |
| t08-after-immersive-light.png | 175827 | 0A75EF10D860A933 | **提交态**产物：沉浸式子页**只剩一个开关**（"沉浸式模式"，OFF），"避让前置摄像头"整行与其说明文字都不在；页内自证行 = `immersive settings: immersiveMode=false`；系统状态栏可见（= 开关 1 的 OFF 生效） |
| t08-after-immersive-dark.png | 176760 | 5549C00D5D2733CC | **深色取证产物**（`FORCE_DARK_FOR_EVIDENCE=true`，注明来源）：同一页面的深色帧，同样只剩一个开关，自证行同上 |
| t08-after-settings-list-light.png | 216093 | B9CC45846A5E0375 | 提交态：设置页主列表 9 行照旧（用户信息 / 退出登录 / 沉浸式模式 / 学期切换 / 文件 / 隐私政策 / 帮助与反馈 / 关于 / 导出日志为文本文件），本次改动没有动它们 |
| t08-after-settings-list-dark.png | 217582 | CC62C77ADA247F16 | 深色取证产物：同上列表的深色帧（同一状态、只换主题） |
| t08-before-immersive-light.png | 223027 | F0534D92A036D3C8 | **改动生效前**装机版本的同页浅色帧：**两个开关**（沉浸式模式 / 避让前置摄像头）都在，自证行是旧的四段式 `immersiveMode=false immersiveAvoidFrontCamera=false effectiveAvoidFrontCamera=false avoidSwitchEnabled=false` |
| t08-before-immersive-both-on.png | 213842 | 970DEC3DE1B8A363 | 改动前版本把两个开关都拨到 ON（这一步**造出了"沙箱里存过该字段"的状态**，prefs XML 见上节）；开关 2 从"禁用"变为可用，说明它不是没渲染，只是真的没有任何效果 |
| t08-after-immersive-restored-bars-hidden.png | 313058 | 73765EC26147EE6B | 覆盖安装后冷启动：旧数据 `immersiveMode=true` **照旧生效**（顶部没有系统状态栏），且这是改动后只剩一个开关的页面 |
| t08-after-immersive-switch-on.png | 166958 | 3CA5F9F91865ED04 | 改动后页面上把唯一那个开关拨到 ON 的瞬间（页面自证行 `immersiveMode=true`） |
| t08-dark-evidence-build-boot.png | 324882 | 285AFE17BF167239 | **深色取证构建确实生效**：冷启动整屏深色（对应 hilog `force dark for evidence: setColorMode(DARK)`）—— 深色帧的来源自证 |
| t08-final-committed-light.png | 323188 | 9E7F5228534C4AAA | 复原后重装的**提交态**产物冷启动：浅色、真实会话、公告照常；对应 hilog `evidence switches: FORCE_DARK_FOR_EVIDENCE=false` |
| grep-consumers-before.txt | 20111 | 757A7C0C86C8D923 | 上节"字段 ↔ 消费点"的**原始 grep 输出**（改动前的 main 树；含四条字段的逐条命中与开关渲染点穷举） |
| logs/layout-after-immersive-light.json | 28812 | BC8B0B4C99E561DF | 提交态沉浸式子页的元素清单：**只有 1 个 `Toggle`** `bounds=[2042,1134,2155,1197]`；无"避让前置摄像头"、无其说明文字；自证行 `immersive settings: immersiveMode=false` |
| logs/layout-after-immersive-dark.json | 28812 | BC8B0B4C99E561DF | 深色帧的同一份清单，与浅色那份**逐字节相同** ⇒ 两帧之间唯一的变量是主题（同一状态的正向证据） |
| logs/layout-after-settings-list-light.json | 66147 | 2B2E6199017AE268 | 提交态设置页列表的 px 清单（9 行 + 五行底栏） |
| logs/layout-after-settings-list-dark.json | 66147 | 2B2E6199017AE268 | 同上，深色帧的清单，逐字节相同 |
| logs/probe-current-screen.png / logs/probe-settings-tab.png | 322300 / 216607 | 8E1FAFFC6A4384E0 / C2B54E3CD934A254 | 过程帧（开机落在公告 tab、点设置 tab 前），**不作为论断证据** |

## 产物内容级检查（`docs/agents/gates.md` 的"陈旧产物"判据）

把提交态 hap 当 zip 解开（`Copy-Item x.hap x.zip; Expand-Archive`），逐字节检索：

```
=== ets/modules.abc (1,778,792 B) ===
effectiveAvoidFrontCamera            -> 0
applyImmersiveToggle                 -> 0
avoidFrontCameraEnabled              -> 0
voidFrontCamera                      -> 0     <- 整个标识符族都不在（含旧自证串 ' immersiveAvoidFrontCamera='）
setImmersiveMode                     -> 2     <- 正向对照：新写入口在
immersive settings: immersiveMode=   -> 1     <- 正向对照：新自证串在
loh_immersive_mode                   -> 2     <- 正向对照
=== resources.index (49,541 B) ===
loh_avoid_front_camera               -> 0     <- 退役的两个文案键已从资源索引消失
avoidFrontCamera                     -> 0
loh_immersive_mode                   -> 2     <- 正向对照：还存在的键找得到（NOT FOUND 不是假阴性）
loh_immersive_mode_description       -> 1
```

## 门禁原始输出

| 项 | 结果 |
| --- | --- |
| 单测（先删 `entry/.test` + `test --no-incremental`） | `entry/.test/default/intermediates/test/coverage_data/test_result.txt` 时间戳 **2026/09/13 14:02:05**（本轮；作业 14:01:13→14:02:09），末行 `Tests run: 421, Failure: 0, Error: 0, Pass: 421, Ignore: 0`；日志里有 `Finished :entry:default@GenerateUnitTestResult`，无 `ERROR`/`ErrorCode`/`COMPILE RESULT` |
| `assembleHap --no-incremental`（提交态） | `BUILD SUCCESSFUL in 26 s 659 ms`；日志搜 `ERROR`/`ErrorCode`/`COMPILE RESULT` **零命中**；hap 时间戳 14:04:04 |
| `assembleHap --no-incremental`（深色取证态） | `BUILD SUCCESSFUL in 6 s 528 ms`；零命中；hap 时间戳 14:12:27（+ 内容是深色，见 `t08-dark-evidence-build-boot.png`） |
| `assembleHap --no-incremental`（复原后提交态） | `BUILD SUCCESSFUL in 5 s 293 ms`；零命中；hap 时间戳 14:15:06 + 上面的内容级检索 |
| 四个脚本 | `check-domain-purity` PASS / `check-import-graph` PASS（仅入口文件 WARN）/ `check-i18n-keys` `RESULT: OK`（manifest 309、reference declared 178）/ `check-generated-fresh` PASS |

**单测基线的口径（如实登记）**：本轮 `Tests run: 421`。按统筹者"砍掉一次构建"的指令，我**没有**单独跑 main 的基线；
基线由 **diff 推得 = 423**：本轮唯一改动的测试文件是 `Settings.test.ets`（`it(` 12 → 10，删掉的两条都是普通 `it`，
不是循环里生成的），`I18n.test.ets` 只改常量（`it(` 24 → 24），其余测试文件零改动 ⇒ 执行条数净减 2。
绝对数 423 没有实测，只有这个 delta 是实测 + 静态计数双口径的。

## 逐条验收

1. **设置页不再出现无效果的开关；其余设置项仍生效** —— 沉浸式子页浅色帧 + px 清单只剩 1 个 `Toggle`（`t08-after-immersive-light.png` / `layout-after-immersive-light.json`），
   "避让前置摄像头"整行与其说明文字都不在；对照帧 `t08-before-immersive-light.png` 里两个开关都在。
   其余三个开关：文件设置两个没被改动（`git diff` 里没有 `FileSettingsPage.ets` / `FileSettings.ets` / `FileDownloader.ets` / `FilePath.ets`），
   `immersiveMode` 当场可证 —— 拨 ON 状态栏消失、拨 OFF 立刻回来、覆盖安装后按旧值恢复（三段都有帧 + hilog）。
2. **持久化字段与孤儿文案键一并清理；i18n 门禁仍过** —— 字段与两条文案键的引用全仓归零（只余注释、退役清单与"断言其不存在"的单测）；
   `check-i18n-keys` `RESULT: OK`；键数 311 → 309；产物级检索证明退役键不在 `resources.index` 里。
3. **旧数据不炸** —— 见"旧数据"一节：设备上真造出过 `immersiveAvoidFrontCamera=true` 的沙箱，覆盖安装后读路径正常（hilog 有 `immersive settings load: immersiveMode=true`，无 error），
   且陈旧键**保持原样**（既不读也不删）。
4. **单测：设置持久化的读写不再包含该字段** —— `Settings.test.ets` 的新用例把写出的载荷 `JSON.stringify` 后断言含 `immersiveMode`、**不含** `immersiveAvoidFrontCamera`（沿用既有 `InMemoryImmersiveSettingsPort` 写法与文件位置）；`List.test.ets` 无需改（没有新文件）。
5. **证据：沉浸式子页截图，浅色 / 深色** —— `t08-after-immersive-light.png` 与 `t08-after-immersive-dark.png`（后者来自 `FORCE_DARK_FOR_EVIDENCE=true` 的**取证构建**，其"真的变深色"由 `t08-dark-evidence-build-boot.png` + hilog `force dark for evidence` 自证；
   复原后重装的提交态由 `t08-final-committed-light.png` + hilog `FORCE_DARK_FOR_EVIDENCE=false` 自证）。
