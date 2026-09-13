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
