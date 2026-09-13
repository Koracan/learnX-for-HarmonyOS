# 08: 移除没有效果的设置开关

**What to build:** 设置页里不再有「拨了没有任何效果」的开关。要么它真的生效，要么它消失——本 ticket 选消失。
顺便清掉那个开关的持久化字段与已成孤儿的文案键。

**Blocked by:** None（可立即开始）

**Status:** ready-for-agent

- [ ] 设置页不再出现无效果的开关；其余设置项（文件的两个设置、沉浸式设置）仍然生效
- [ ] 该开关的持久化字段与相关文案键一并清理；i18n 门禁仍然通过
- [ ] 已保存过该字段的旧数据不会导致读取异常
- [ ] 单测：设置持久化的读写不再包含该字段（沿用既有设置测试的写法）
- [ ] 证据：设置页截图（一屏一对文件：浅色 / 深色）

## Comments

### 2026-09-13 · 统筹者派单中的定位结论与裁定

**死开关是哪个（实现方先报后动，我复核过）**：**沉浸式设置子页的第二个开关「避让前置摄像头」（`immersiveAvoidFrontCamera`）**。
- 全仓 `Toggle(` / `ToggleType.Switch` / `TableCellType.SWITCH` 穷举后只有 4 个开关：文件设置 2 个（`useDocumentDir` / `omitCourseName`）、沉浸式页 2 个（`immersiveMode` / `immersiveAvoidFrontCamera`）；设置页主列表只有导航 cell，没有开关。
- **消费点判据**（AGENTS.md：开关必须自证生效且打在消费点）：前三个都有消费点（`FileDownloader.ets:172/194/196/203/206`、`ImmersiveSettingsProvider.ets:58` → `core/window/ImmersiveWindow.applyImmersiveMode`），而 `immersiveAvoidFrontCamera` 在 `entry/src/main` 下**除持久化与自身显示外零消费点**。
- **两条独立旁证**（我另外读到的）：`docs/accepted-deviations.md:696-699` 本仓自认"平台效果没有移植……只持久化与显示……不声称它改变了任何布局"；`docs/rn-app-inventory.md:33` 说明它**在参考实现里是有用的**（`header top-inset fallback disabled when immersiveMode && !immersiveAvoidFrontCamera`）⇒ "死"是移植时丢了能力，不是它本来无意义。

**裁定**：按工单的"要么生效、要么消失"，**移除开关 2**。spec 第 49 行的"文件的两个设置、沉浸式设置"按"**留下的开关都是真的生效的**"来读（留 3 个：文件 2 + `immersiveMode`），不作为"沉浸式页两个都留"的依据。

**附带四条必须一起收**：
1. **台账跟着改**：`docs/accepted-deviations.md` 有**两处**会因此变假 —— `:688` 的验证条款"关掉开关 1 时开关 2 自动置假且持久化"、以及 `:696-699` 那条边界。**不改历史记录**，就地**追加带日期的批注**（该条款不再适用 + 结论），参考实现出处保留。`docs/rn-app-inventory.md` **不动**（它描述 RN 应用本身，仍准确）；`.scratch/migration/**` 不许碰。
2. **连带逻辑**：`ImmersiveSettings.ets` 里"显示值 = `immersiveMode && immersiveAvoidFrontCamera`"与"开关 1 关掉时联动置假开关 2"**只为开关 2 存在**，一并处理（含单测），并保证 `immersiveMode` 自身行为一字未改（有单测钉住）。
3. **旧数据不炸 + i18n 收干净**：存过该字段的沙箱读取不得抛异常（给出策略）；两个孤儿键 `loh_avoid_front_camera` / `loh_avoid_front_camera_description` 一并删（先确认无其他引用），走生成器重跑并同步 `I18n.test.ets` 键数常量。
4. **设备帧拍对页面**：开关在**沉浸式子页**上，浅色/深色那一对要拍**该子页**的改动前后（开关消失、`immersiveMode` 仍在且可用），不是设置页首页；深色帧走 `FORCE_DARK_FOR_EVIDENCE`（提交态 `false`）并注明来源。

### 2026-09-13 · 实现方交付（分支 `wt/t08`，基线 `94f39bd` → 已 merge main 至 `626be96`）

**结论**：死开关（沉浸式子页第二个开关"避让前置摄像头"）已**消失**；字段 `immersiveAvoidFrontCamera`、两条只为它存在的语义
（显示值 = `immersiveMode && …`、关掉开关 1 时联动置假）与两条文案键一并清理；`immersiveMode` 行为一字未改。

| 项 | 结果 |
| --- | --- |
| 改动文件 | 14 个（3 个 main 源文件 / 2 个单测 / 2 个脚本 / 3+1+2 个生成物 / 1 个台账文档）—— 清单与理由见交付回报 |
| 台账 | `docs/accepted-deviations.md` **两处就地追加带日期批注**（:687-693 验证条款第 5 条、:701-710 边界条目），**原句一字未删**；`docs/rn-app-inventory.md` 与 `.scratch/migration/**` 未动 |
| i18n | 键数 **311 → 309**（参考迁入 180 → 178；local 8 与 ui 123 不变）；退役清单唯一出处 `scripts/i18n-lib.mjs` 的 `RETIRED_REFERENCE_KEYS`，6 个生成物由生成器重跑、与输入同一次提交 |
| 单测 | `Tests run: 421, Failure: 0, Error: 0, Pass: 421, Ignore: 0`（`test_result.txt` 时间戳 `2026/09/13 14:02:05`，本轮）；基线 **423 由 diff 推得**（唯一改动的测试文件 `Settings.test.ets` 的 `it(` 12 → 10），未单独跑基线 |
| 打包 | 提交态 `BUILD SUCCESSFUL`（26s659ms / hap @14:04:04）、深色取证态 `BUILD SUCCESSFUL`（6s528ms / @14:12:27）、复原后提交态 `BUILD SUCCESSFUL`（5s293ms / @14:15:06）；三次日志搜 `ERROR`/`ErrorCode`/`COMPILE RESULT` **零命中**；提交态 hap 解包后 `ets/modules.abc` 里 `voidFrontCamera` = 0 次、`setImmersiveMode` = 2 次（正向对照） |
| 四个脚本 | `check-domain-purity` PASS、`check-import-graph` PASS、`check-i18n-keys` `RESULT: OK`、`check-generated-fresh` PASS |
| 旧数据 | 设备上真造出 `prefs = {immersiveAvoidFrontCamera:true, immersiveMode:true}`，覆盖安装后 `load: immersiveMode=true` 正常、无 error；拨回 OFF 后陈旧键**仍在**（不读不删） |
| 证据 | `.scratch/ui-optimize/evidence/t08/README.md`（逐文件论断表）+ 浅色/深色各一组沉浸式子页帧 + 改动前对照 + 4 份 px 清单；图片只留本地，文字证据已 `git add -f` |

**未做到 / 存疑**：① 单测绝对基线 423 未实测（按"砍一次构建"的指令，只给了 delta 的实测 + 静态计数口径）；
② `FORCE_DARK_FOR_EVIDENCE` 的"提交态复原"是**产物级 + 视觉级 + hilog** 三重自证（重刷产物 + 浅色帧 + `evidence switches: …=false`），不是重跑一次基线单测；
③ `immersiveAvoidFrontCamera` 在参考实现里本来的平台效果（RN 安全区回退）**仍未移植** —— 本 ticket 只做"消失"，不做"补一套 inset 回退"。
④ 改动前的那一帧来自**改动生效前已装在设备上的版本**（源码版本没有记录，只能确认它的沉浸式页是旧的两开关形态 + 旧自证串），
不是本分支自己构建的基线产物；本 ticket 没有为它单独构建（按指令砍掉了那次构建）。
