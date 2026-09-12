# 01: 工程分层 + 日志门面 + 主题令牌

**What to build:** 建立 core / domain / data / ui / features 分层与依赖方向（domain 不依赖任何上层与平台）；提供带模块标签的分级日志，可落盘并从应用内导出；把参考实现的颜色、排版、尺寸常量迁为主题令牌；首屏改为使用主题令牌渲染并接入日志。这是前置项（prefactor），后续每个切片都依赖它。

**Blocked by:** None（可立即开始）

**Status:** verified

- [x] 目录分层就位，并有一条自动检查（lint 规则或单测）证明 domain 不依赖平台与应用层
- [x] 日志分 debug/info/warn/error 四级，带模块标签；可在应用内导出为文本文件
- [x] 颜色、排版、尺寸令牌取自参考实现；深浅两套都经令牌取色，界面无硬编码色值
- [x] 首屏以主题令牌渲染，切换系统深浅色时即时生效（同进程热切换，无重启）
- [x] 截图存入证据目录 `.scratch/foundation/evidence/`（真机 `3FYBB25407201890` 未连接，实为模拟器 Pura 90；见 Comments）

## Comments

### 结论：5 条验收全部达成（证据路径均为仓库内相对路径）

**1) 分层就位 + domain 纯度自动检查 —— 达成**
- 分层目录：`entry/src/main/ets/` 下 `core/`（log、i18n、theme…）、`domain/`（model）、`data/`、`ui/`（theme）、`features/` 就位。本 ticket 落地 `core/log/*`、`ui/theme/Tokens.ets`、`domain/model/Semester.ets`、`pages/Index.ets`；HTTP/SM2/asset/导航壳/列表页留给后续切片。
- 自动检查：`scripts/check-domain-purity.mjs`（node 直跑，退出码 0=通过 / 1=违规 / 2=空跑）。
  - 正例（真实输出）：`node scripts/check-domain-purity.mjs` →
    `[domain-purity] 扫描 1 个领域源文件（entry/src/main/ets/domain）` / `[domain-purity] PASS domain 不依赖平台与应用层`，exit 0。
  - **负例（故意违规 → 失败，已跑并复原）**：临时在 `domain/model/Semester.ets` 顶部插入两行
    `import { hilog } from '@kit.PerformanceAnalysisKit';` 与 `import { Logger } from '../../core/log/Logger';`，重跑 → **exit 1**，stdout：
    ```
    [domain-purity] FAIL 发现 2 处违规：
      - entry/src/main/ets/domain/model/Semester.ets:1  平台依赖被禁止：@kit.PerformanceAnalysisKit ('import { hilog } from "@kit.PerformanceAnalysisKit";')
      - entry/src/main/ets/domain/model/Semester.ets:2  越出 domain 的引用：../../core/log/Logger ('import { Logger } from "../../core/log/Logger";')
    ```
    删除两行后重跑 → exit 0（文件按字节备份/恢复，已核对无残留）。
  - 真实领域纯逻辑：`domain/model/Semester.ets`（`YYYY-YYYY-N` 解析、校验、比较、排序、取最新；排序语义显式对齐参考实现 `data/actions/semesters.ts` 的 `sort().reverse()`）。9 条 Hypium 用例覆盖。

**2) 四级日志 + 模块标签 + 应用内导出 —— 达成**
- `core/log/LogFormat.ets`（纯逻辑）、`core/log/LogBuffer.ets`（固定容量环形缓冲 500 + 导出）、`core/log/Logger.ets`（hilog + 缓冲，`new Logger('ui.index')`）。
- 统一格式（hilog 原始片段）：`A04c4f/ui.index: 2026-09-12 00:33:16.379 INFO  [ui.index] 首屏渲染…`（时间戳 + 级别 + 标签 + 消息）。
- 应用内导出：首屏「导出日志为文本文件」按钮 → `exportLogs(context)`；沙箱实文件
  `/data/app/el2/100/base/com.koracan.learnOH/haps/entry/files/logs/learnOH-1789144464540.log`（663 B），
  `hdc file recv` 取回为 `.scratch/foundation/evidence/01-exported-log.txt`（首屏含"导出时间/记录数 + 6 条带标签记录"）。
  导出函数签名 `exportLogs(context, buffer?)`，settings 切片（17）可直接调用。

**3) 令牌取自参考实现、深浅两套、界面无硬编码色值 —— 达成**
- `ui/theme/Tokens.ets`：`PLAIN_PALETTE` 7 色逐字取自 `reference/learnOH-old/src/constants/Colors.ts`；`LIGHT_COLORS`/`DARK_COLORS` 34 键逐值取自 `App.tsx` 的 `lightThemeColors`/`darkThemeColors`（`rgb()/rgba()` → `#RRGGBB`/`#AARRGGBB`，由脚本从 App.tsx 解析生成，非手抄）；`TYPOGRAPHY` 取自 react-native-paper 5.15.0 的 MD3 typescale；`SIZES` 基准 4vp 取自 `Styles.ts`。
- Hypium 覆盖：33 个颜色键 × 深浅两套「有值且是合法字面色值」、深浅同名同序、主要角色深浅有别、`Colors.ts` 7 个字面量逐条断言、typescale 15 条、尺寸 16 条。
- 无硬编码色值：`entry/src/main/ets` 全量扫描，`#RRGGBB` 只出现在 `Tokens.ets`；`pages/Index.ets` 取色一律走 `resolveTheme()`。（统筹已独立复核此条。）

**4) 首屏令牌渲染 + 系统深浅色即时生效 —— 达成（同进程、无重启）**
- 浅色：`01:32:04` PID **16244** 冷启动，系统浅色 → `Ability onCreate: colorMode=1`、`ui.index first-screen: theme=light primary=#9A25AE`；无障碍树 `系统配色=浅色 / 颜色令牌=LIGHT_COLORS`。
- 切深色：在**不杀进程**的前提下把系统切到深色（设置 → 显示和亮度 → 深色模式 → 全天开启），`01:40:24` 把应用前台化 → hilog `configuration updated: colorMode=0` + `Ability onForeground`，**PID 仍为 16244，全程没有新的 `Ability onCreate`/`onWindowStageCreate`**（即同进程热切换，非重启）。全文见 `01-hilog-live-switch.txt`。
- 同一次前台化后的无障碍树：`系统配色=深色 / 颜色令牌=DARK_COLORS`；截图 `01-index-dark-final.png`：整页外层底色为深（`#1E1A1D`），卡片 `#4D444C`，按钮 `#F9ABFF`/`#570066` —— 最外层 `backgroundColor(this.theme().colors.background)` 确实生效。
- 浅色截图 `01-index-light.png` 与深色截图 `01-index-dark-final.png` 出自**同一版代码**、同一台模拟器。

**5) 截图落证据目录 —— 达成**：`.scratch/foundation/evidence/`，清单与 SHA256 见该目录 `README.md`。

### 本轮发现并修掉的两个真实"实时刷新"缺陷（都在系统深浅色热切换时复现）
1. **@Builder 按值传参**：原 `infoCard(theme, title, rows)` 三个按值参数 → 切主题后卡片整块保持旧主题（早期截图：页面外层变浅、卡片仍深、文案仍 `DARK_COLORS`）。改为单对象按引用参数 `infoCard(spec: CardSpec)`（调用点传对象字面量）。
2. **ForEach 键不含会变的值**：键取 `row.label`（如"系统配色"，切主题时不变）→ ArkUI 复用旧子节点，于是卡片配色已更新、行文案仍停在 `DARK_COLORS`。键改为 `row.label + '|' + row.value`。
   两个缺陷都已用「同一进程内浅↔深切换」复测通过（即上面第 4 条的证据）。

### 一次已按要求回退的插曲
用户曾要求"主题下三个选项：跟随系统/浅色/深色"，我实现后（`core/theme/ThemeMode.ets` + `ThemeStore.ets` + 首屏选择器 + 3 个语言包各 2 个新键 + 4 条单测）用户澄清"误以为是应用内功能，请回退"。已**完整回退**：删除新增文件、还原 `Index.ets`/`EntryAbility.ets`/`List.test.ets`，并从 `string.json`（base/zh_CN/en_US）移除新增键 —— 三个资源文件键数回到 210/207/207，`entry/src/main/ets` 与 `entry/src/test` 中 `ThemeMode|themeMode|ui_theme` 零命中。**未触碰 02 的资源键。**

### 实际跑过的命令与结果（关键项）
| 命令 | 结果 |
| --- | --- |
| `node scripts/check-domain-purity.mjs` | exit 0，PASS；负例 exit 1（2 处违规）后复原再 exit 0 |
| `hvigorw --mode module -p module=entry@default -p product=default test` | exit 0；Hypium **42 run / 0 failure / 0 error / 42 pass**（含 02 的 i18n 24 条） |
| `devecocli run --device 127.0.0.1:5555` | 构建 `BUILD SUCCESSFUL in 1 min 54 s`，安装并启动成功（`.dsh/logs/run-5.log` → `01-build-arkts.log`） |
| `devecocli ui screenshot/click/layout --device 127.0.0.1:5555` | 取证与导航；深浅两套截图 + 无障碍树 |
| `hdc -t 127.0.0.1:5555 shell hilog -x` | 日志导出与热切换证据 |
| `hdc -t 127.0.0.1:5555 file recv <沙箱日志> ` | 取回导出文件 663 B |
| `devecocli check lint` | 本机返回 `Files checked: 0`（同时统筹侧报 `spawn EPERM`），**该检查器在本版本不可用**；编译反馈改用 `devecocli build`（`check arkts` 在 1.3.2 不存在） |

### 未做到 / 未验证（如实说明）
- **编译期警告未清零**：`LogBuffer.ets` 的 `fs.*` 与 `Semester.ets:145` 有 `Function may throw exceptions` 的 ArkTS WARN（非 ERROR，构建通过）；未逐条 try/catch 包裹。
- `devecocli check lint` 在本机扫不到文件（`Files checked: 0`），所以"静态 lint 门禁"这一路证据是空的，只有编译 + 单测 + 脚本检查三项。
- 真机 `3FYBB25407201890`（MatePad Air，API 24）**未连接**，全部证据来自模拟器 `127.0.0.1:5555`（Pura 90，HarmonyOS 6.1.0(23)）。ticket 里写的"真机截图"实际是模拟器截图。
- 系统深色模式没有 CLI 开关（`hdc shell param set persist.global.colorMode` 被 shell 身份拒绝，errNum 1001），只能走「设置」应用 UI 点击，故切换过程依赖 UI 自动化，非脚本化的一键复现。
- 同仓库曾有 02 号 subagent 并发写 `Index.ets`/`EntryAbility.ets`（现已冻结）；过程中一度出现编译错误（`common.Context` 无 `config`），由 02 自行修掉，非本 ticket 改动。

### 验收（统筹复核，2026-09-12）—— **通过**

结论：5/5 验收项达成。以下每条都是统筹**自己重跑/自己看图**得出的，不采信报告转述。

| 验收项 | 统筹的独立动作 | 结果 |
| --- | --- | --- |
| domain 纯度自动检查 | 自己跑 `node scripts/check-domain-purity.mjs` | `PASS` / exit 0，重跑一致 |
| 四级日志 + 导出 | 核对 `LogFormat`/`LogBuffer`/`Logger` 三级分工；导出实文件 663 B 已 recv | 达成 |
| 令牌取自参考实现 | 逐条比对 `Colors.ts`（7 plain 色）与 `App.tsx:202-289`（MD3 30+ 令牌），抽查 `rgb(255,214,254)`→`#FFD6FE`、`rgb(123,0,143)`→`#7B008F`、`rgb(250,240,251)`→`#FAF0FB` 三次换算 | 逐条相符，**非手写** |
| 无硬编码色值 | 全 `entry/src/main/ets` 扫描 `#RRGGBB` | 仅 `Tokens.ets` 命中；`pages/` 剩余中文只在 `logger.*` 调用里 |
| 深浅色即时生效 | 看图 `01-index-dark-final.png` + 读 `01-hilog-live-switch.txt` | 见下 |

**深色渲染（此前唯一的缺口）已闭合**：`01-index-dark-final.png` 里**最外层底色**呈深色（不只卡片），状态栏深色，页面自报 `系统配色=深色 / DARK_COLORS`。
**热切换是协议级铁证**（不是"看起来变了"）：
```
09-12 01:32:04.687  16244 16244  Ability onCreate: colorMode=1 ...      ← 冷启动浅色
09-12 01:32:05.236  16244 16244  Ability onWindowStageCreate
09-12 01:40:24.445  16244 16244  configuration updated: colorMode=0      ← 切深色
09-12 01:40:24.548  16244 16244  Ability onForeground
```
同一 PID `16244` 跨越两个时刻，且**没有第二次 `onCreate`/`onWindowStageCreate`** ⇒ 确实同进程热切换。

**对统筹此前误判的更正（值得留档）**：我先前把那张混合态截图（系统深色 + 卡片深色 + 外层白）判为"新旧截图时机问题"。01 指出真实原因是两个代码缺陷，且都修了：
1. `@Builder infoCard(theme, title, rows)` **按值传参** → 切主题后卡片整块保持旧主题；
2. `ForEach` 键取 `row.label`①，而 `label` 在切主题时**不变** → ArkUI 复用旧子节点，表现为"卡片底色变了、行文案仍写 `DARK_COLORS`"。键改为 `label|value`。
我的时机解释是错的；对方的解释可复现且已修。

**我另行复核的两项**：
- Hypium **我自己重跑**：`hvigorw ... test` → `Tests run: 42, Failure: 0, Error: 0, Pass: 42`（读 `entry/.test/.../test_result.txt`，逐条 42 个 `result=Success`）。
- 插曲回退**零残留**：`ThemeMode|ui_theme|theme_mode` 全仓源码 **0 命中**；资源键数 `base=210 / zh_CN=207 / en_US=207`；工作树干净。

**保留的两点局限（不构成验收阻碍，但后续切片需知）**：
- 证据全部来自**模拟器** Pura 90（HarmonyOS 6.1.0(23)），真机 API 24 未连接 ⇒ 见 spec §11 #7。
- ArkTS 编译 **WARN 未清零**（`LogBuffer.ets` 的 fs 调用、`Semester.ets:145` may-throw），非 ERROR；本版本 `check lint`/`check arkts` 均不可用，静态门禁这一路无证据。

### 主要交付文件
`entry/src/main/ets/core/log/{Logger,LogBuffer,LogFormat}.ets`、`entry/src/main/ets/ui/theme/Tokens.ets`、`entry/src/main/ets/domain/model/Semester.ets`、`entry/src/main/ets/pages/Index.ets`、`entry/src/main/ets/entryability/EntryAbility.ets`、`scripts/check-domain-purity.mjs`、

### 边界说明（2026-09-12，由 ticket 11.5 带入）—— 底色类令牌不再与参考实现一致

- **变了什么**：`LIGHT_COLORS` / `DARK_COLORS` 里的**底色家族**（`background` / `surface` / `card` / `elevation.level1..5`）
  与**中性家族**（`onBackground` / `onSurface` / `surfaceVariant` / `onSurfaceVariant` / `outline` / `outlineVariant` /
  `inverseSurface` / `inverseOnSurface` / `backdrop` / `surfaceDisabled` / `onSurfaceDisabled`）改成 `R=G=B` 中性色
  （浅色底色 = `#FFFFFF`，深色底色 = `#1C1C1C`）。逐令牌"改前 → 改后"见 ticket 11.5 交付节，
  理由与替代验收标准见 `docs/accepted-deviations.md` 第 25 条（账号所有者 2026-09-12 裁定）。
- **哪些仍然一致**：`primary` / `onPrimary` / `primaryContainer` / `onPrimaryContainer` / `secondary` / `onSecondary` /
  `secondaryContainer` / `onSecondaryContainer` / `tertiary*` / `error*` / `inversePrimary` / `shadow` / `scrim`
  **一字未动**；`PLAIN_PALETTE`（`Colors.ts` 那一份 500 系）一字未动；`TYPOGRAPHY` 与 `SIZES` 一字未动。
- **你的证据还成立到哪一步**：ticket 01 的令牌单测（值存在、字面量形状、深浅两套同键名、"未定义即失败"）
  **全部仍然成立**；被推翻的只有"**逐值取自参考实现**"这一句在底色/中性族上的适用
  （`Tokens.test.ets` 里那条断言已按新值更新，并新增"中性族 R=G=B"与"品牌色与 `PLAIN_PALETTE` 逐值相等"两条）。
- **可观察量转移到哪里**：ticket 11.5 —— 设备截图**取色**（浅色 `R=G=B` 且 `≥254`；深色 `R=G=B` 且 `<60`）
  与"源码令牌字面量 = `#FFFFFF`"的 grep；旧截图里的浅底色 `254,250,254` 不再是基准。

