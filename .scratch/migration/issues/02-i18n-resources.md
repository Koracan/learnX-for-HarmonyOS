# 02: i18n 资源化

**What to build:** 把参考实现的中英文案表迁进应用资源目录，界面文案全部从资源取；语言随系统切换，不再保留 TS 文案表。这是前置项（prefactor）。

**Blocked by:** None（可立即开始）

**Status:** verified

- [x] 参考实现中英两份文案的全部键都存在于资源中，中英各一份，无遗漏（实测 **180** 键，不是“约 400”；zh/en 键集一致）
- [x] 已存在的界面无硬编码文案（含提示、弹窗、Toast）——页面展示文案全部走资源；剩余中文字面量均为**日志/异常消息**，见 Comments 第 8 节
- [x] 系统语言为中文/英文时，界面分别为中文/英文，无需重启应用——**统筹已合并取证**：同进程切中↔英，PID 不变（见 Comments 第 5 节）
- [x] 日期与相对时间随语言本地化（`@ohos.intl` + 可注入 formatter 接缝，24 条单测；修复后中文布局未再复验，见 Comments 第 5 节）
- [x] 有一条检查能列出资源中缺失的键，供后续切片使用（`node scripts/check-i18n-keys.mjs`，负例套件全过）

## Comments

### 02 交付记录（i18n 资源化）

**状态**：代码与检查已落盘并通过编译/单测；**真机「中英切换无需重启」的最终取证已按统筹指令移交**（见第 5 节）。

#### 1. 交付物

| 交付 | 路径 |
| --- | --- |
| 资源（base/中文默认回退） | `entry/src/main/resources/base/element/string.json` |
| 资源（中文） | `entry/src/main/resources/zh_CN/element/string.json` |
| 资源（英文） | `entry/src/main/resources/en_US/element/string.json` |
| 键名映射表（183+24 行） | `.scratch/foundation/i18n-key-map.md` |
| 机器可读键清单 | `.scratch/foundation/i18n-keys.json` |
| 资源生成器 | `scripts/generate-i18n-resources.mjs`、`scripts/i18n-lib.mjs`、`scripts/i18n-ui-strings.mjs` |
| 键类型生成器 | `scripts/gen-i18n-keys.mjs` → `entry/src/main/ets/core/i18n/I18nKeys.ets` |
| 缺失键检查 | `scripts/check-i18n-keys.mjs`（+ `scripts/i18n-source-keys.mjs`） |
| 检查的负例验证 | `scripts/test-i18n-check-negative.mjs` |
| 计数取证 | `scripts/report-i18n-counts.mjs` |
| ohpm/dayjs 取证 | `scripts/investigate-dayjs-ohpm.mjs` |
| 门面 | `entry/src/main/ets/core/i18n/{I18n,I18nKeys,Locale,StringProvider,DateTimeUtil}.ets` |
| 单测 | `entry/src/test/I18n.test.ets`（已挂入 `entry/src/test/List.test.ets`） |
| 证据 | `.scratch/foundation/evidence/02-*` |

#### 2. 键总数核对（实测，非估计）

命令：`node scripts/report-i18n-counts.mjs`（输出同时写入 `.scratch/foundation/evidence/02-i18n-key-counts.txt`）

```
reference dictionaries (reference/learnOH-old/src/assets/translations):
  zh.ts keys : 180
  en.ts keys : 180
  key sets identical: true
  entries with a {N} placeholder: 0

generated resources:
  base   .../base/element/string.json   total=210 (loh_=183, ui_=24, template=3)
  zh_CN  .../zh_CN/element/string.json  total=207 (loh_=183, ui_=24, template=0)
  en_US  .../en_US/element/string.json  total=207 (loh_=183, ui_=24, template=0)

coverage: 180/180 reference keys migrated, 0 missing
```

- **ticket 里写的「约 400」与实际不符**：参考实现两本字典各只有 **180** 个键（`en`/`zh` 键集与顺序完全一致，脚本已断言）。所以迁移的参考键数是 **180**，不是约 400。
- 资源里除 180 个参考键外还有：**3** 个本工程新增的 `loh_*`（学期季节词 `秋季学期/春季学期/夏季学期`——参考实现把这三个词硬编码在 `reference/learnOH-old/src/helpers/parse.ts` 里，移植 `getSemesterTextFromId` 必须把它们变成资源）；**24** 个 `ui_*`（原生重写后的界面文案，参考实现没有对应键，单独命名空间，**不计入迁移数**）。
- 缺失 **0** 个。

#### 3. 资源体系的选择与依据

选择：`resources/{base,zh_CN,en_US}/element/string.json` + 资源名 `loh_*` / `ui_*`。

依据（都自己查证过）：
1. `$r('app.string.<name>')` 是官方静态资源访问方式，语言限定词由 `resources/<locale>/element` 目录承担，是本工程模板（`module.json5` 用 `$string:EntryAbility_label`）已在用的机制；
2. 逻辑层（`data/`、`domain/`、纯函数）拿不到 `$r`——`$r` 只在组件 build 上下文合法。等价入口是 `ResourceManager.getStringByNameSync(name)` / `getStringSync(resource.id, ...args)`，SDK 里 `@ohos.resourceManager.d.ts:2454/2486/2301/2333` 有明确定义；
3. `resources/` 下另放 i18n JSON 的方案（spec 提到的备选）需要自己写读取与语言匹配，等于放弃系统限定词与资源 id 机制，没有收益。

语言限定词命名：`zh_CN` / `en_US`（HarmonyOS 标准限定词），模拟器实测中文界面文案正确取自资源（见 `evidence/02-zh.png`）。

取串边界（B 项）：
- UI：`this.s($r('app.string.xxx'))`，其中 `s()` → `i18nService.tKey(resource)`；`tKey` 用 `resource.id` + `ResourceManager.getStringSync` 取同一个资源。之所以包一层而不是直接把 `$r` 塞给 `Text()`：页面需要在**同一进程内**因语言变化重取串，`tKey` 是这条刷新链路的显式入口，同时给后续纯逻辑切片复用。
- 纯逻辑：`i18nService.t('loh_xxx')`；键是生成的联合类型 `I18nKey`（207 个字面量），写错键名编译期就失败。

插值：参考字典里 **0 个** `{N}` 占位符（脚本断言）。本工程新增的 4 处占位符用 HarmonyOS 位置占位符 `%1$s` 表达，并在 `t()` 里由 `formatMessage()` 做位置替换：

| 资源 | 中文 | 英文 |
| --- | --- | --- |
| `ui_semester_later` | `较晚 = %1$s` | `later = %1$s` |
| `ui_exported` | `已导出 %1$s 条 / %2$s 字节` | `Exported %1$s records / %2$s bytes` |
| `ui_export_failed` | `导出失败：%1$s` | `Export failed: %1$s` |

#### 4. 日期与相对时间（含 spec §11 #6 dayjs/ohpm 查证）

**结论：不采用 dayjs。** 完整取证见 `.scratch/foundation/evidence/02-ohpm-dayjs-info.txt`（用 `node scripts/investigate-dayjs-ohpm.mjs` 可复现）：

- 本机 `ohpm` **没有 `search` 子命令**（`ohpm search dayjs` → `ohpm ERROR: unknown command 'search'`，ohpm 6.1.2.285）；
- `ohpm info dayjs` **能解析**：`dayjs@1.11.13 | MIT | deps: none | versions: 3`，仓库是 `https://ohpm.openharmony.cn/ohpm/`；
- 但把 tarball 拉下来解开看，它是**原样镜像的 npm 包**，不是 OpenHarmony 包：
  - 顶层只有 `dayjs.min.js` / `package.json` / `index.d.ts` / `locale.json`，**没有 `oh-package.json5`**；
  - `package.json` 的 `main` = `dayjs.min.js`，**没有 `module` / `exports`**；`dayjs.min.js` 是 UMD 包装（`module.exports=e()`，否则挂 `globalThis.dayjs`），没有 ESM 导出，ArkTS 无法 `import dayjs from 'dayjs'`；
  - locale 是独立脚本（`locale/zh-cn.js` 走 `module.exports=_(require("dayjs"))`，否则挂 `globalThis.dayjs_locale_zh_cn`），dayjs 按运行时名字挑 locale —— ArkTS 禁止动态 `require`。

因此改用平台实现：`@ohos.intl` 的 `Intl.DateTimeFormat` / `Intl.RelativeTimeFormat`，并把「策略」与「措辞」拆开：

- 纯策略（可单测）：`pickRelativeUnit` / `relativeAmount` / `relativeTimeParts` / `describeRelativeTime`，阶梯与大单位优先同 dayjs 阈值；
- 措辞与日期布局（平台）：`PlatformRelativeTimeFormatter` / `PlatformDateTimeFormatter`，通过 `RelativeTimeFormatter` / `DateTimeFormatter` 两个接口注入，测试用假实现，真实措辞在设备上取证；
- 新增 `formatRelativeTo(target, now, locale)`：**这是踩坑后的修正**。最初我在页面里写 `formatRelativeTime(now - 3*24*3600*1000, locale)`，把绝对时间戳当成 delta 传，界面上出现了 **“in 56 years”**（56 年正好是 Unix 起点到现在的距离）——截图 `evidence/02-zh.png` 就是这次现场。现在 delta 转换由 `formatRelativeTo` 承担并有单测。

注意：本机 **local 单测环境不加载 ICU**（实测 `formatRelativeTime(...)` 在 host 返回空串），所以单测只锁策略层与中英措辞表；真实 ICU 输出以设备取证为准（见第 5 节，我已拿到 ICU 在设备上确实生效的证据）。

#### 5. 语言切换「无需重启」：机制 + 已取证 / 未取证

机制（三层）：
1. `EntryAbility.onCreate` / `onConfigurationUpdate` 调 `i18nService.bindResourceManager(this.context.resourceManager, this.context.config.language)`——语言以 ability 的 `config.language` 为准；
2. `ApplicationContext.on('environment', EnvironmentCallback)` 与 `UIAbility.onConfigurationUpdate` 两条通知路径都接上，回调里 `i18nService.refresh()` 并 `AppStorage.setOrCreate(LOCALE_VERSION_KEY, Date.now())`；
3. 页面 `@StorageLink(LOCALE_VERSION_KEY) localeVersion` 订阅该版本号，变化即重建并重新取串；应用内切换按钮走 `context.getApplicationContext().setLanguage(lang)` + 立即重建，同进程生效。

**已取证**：
- 应用可构建、安装、启动（`devecocli build` exit 0；`devecocli run --device 127.0.0.1:5555` 安装并 `start ability successfully`）；
- 截图 `evidence/02-zh.png`：模拟器中文界面下，**所有界面文案都来自资源**（自检 / 系统配色 / 颜色令牌 / 最近日志条数 / 语言 / 当前语言 / 相对时间示例 / 日期时间示例 / 学期文案示例 / 语言切换（无需重启）/ 切到中文 / 切到英文 / 参考实现调色板 / 导出日志为文本文件）；
- 该截图同时证明设备上 **ICU 确实生效且按传入 locale 输出**：修 bug 前 `locale()` 误报 `en-US`，界面就出现了英文措辞 `in 56 years` 与 `09/12/2026, 00:43`（en-US 日期布局），而资源文案仍是中文——即「资源跟随系统语言」与「ICU 跟随传入 locale」两条链路都在工作。

**未取证（如实说明）**：
- 修复后 `locale()` 改为 `config.language`（模拟器为 `zh-Hans`），因此日期/相对时间应变回中文布局；**这一步没有重新部署复验**——统筹已下令冻结我继续写 `Index.ets` / `EntryAbility.ets` 并禁止 `devecocli run`（避免与 ticket 01 互相顶掉 app 实例）；
- 因此**「系统语言中/英切换、界面跟随、无需重启」这一条的最终双截图由统筹 + 01 合并取证**，我这边不再声称通过。上面那台设备上 `persist.global.language` 是 `zh-Hans`，且 shell 身份（uid=2000）**无权 `param set persist.global.language`**（`Set parameter ... fail! errNum is:1001!`），所以系统级语言切换在模拟器上只能走「设置」应用；我采用的应用内 `setLanguage()` 走的是同一条配置更新链路。

#### 6. 缺失键检查 + 负例验证

`node scripts/check-i18n-keys.mjs`（退出码 0/1）同时做 6 件事：每个 locale 的 MISSING / EMPTY / EXTRA、参考字典漂移（独立重解析 `reference/.../{zh,en}.ts`）、**ArkTS 源码引用的键是否都存在**（`$r('app.string.x')` / `t('x')` / `tName('x')`，并校验占位符实参个数）、以及 en==zh 的信息性提示。

这条「源码引用」检查不是装饰：它在开发中真的抓到了我把 20 处 `loh_ui_*` 写成而资源名是 `ui_*` 的错误（当时输出 25 条 problem），否则界面上会是一排空白。

负例验证：`node scripts/test-i18n-check-negative.mjs`（输出写入 `evidence/02-check-i18n-negative.txt`）

```
=== baseline (no mutation)                          exit=0 -> PASS
=== delete loh_back from en_US -> MISSING           exit=1 -> PASS   MISSING: loh_back
=== append ui_bogus_key to zh_CN -> EXTRA           exit=1 -> PASS   EXTRA  : ui_bogus_key
=== drop reference key back from the manifest       exit=1 -> PASS   !! reference keys MISSING from the manifest: back
=== blank out loh_ok in zh_CN -> EMPTY              exit=1 -> PASS   EMPTY  : loh_ok
=== restored (no mutation)                          exit=0 -> PASS
NEGATIVE SUITE: ALL PASS
```

当前基线：`manifest keys 207 / reference keys declared 180 / reference dictionary keys 180`，三个 locale 的 missing=empty=extra=0，`source key references: 28 distinct keys, all resolved`，`RESULT: OK`。

#### 7. 单测

`hvigorw test -p module=entry@default -p buildMode=debug`（本地单测，不装设备）→ `BUILD SUCCESSFUL`，`entry:test` 通过，**0 条断言失败**（失败会打印 `hvigor ERROR: Error in <用例名>`；此前确实打印过，见 `.dsh/logs/02-unit-test*.log` 的历史）。日志摘录：`evidence/02-unit-test.txt`。

`entry/src/test/I18n.test.ets` 共 24 个用例，覆盖：键总量与命名空间合法性、未知键拒绝、未绑定 provider 时回显键名、绑定后按类型取串、缺失资源返回空串、语言变化监听、位置/普通占位符替换、带占位符的 `t()`；相对时间阶梯与取整、`now` 判定、把正确 `(amount, unit)` 交给措辞层、中英相对措辞（`3天前` / `3 days ago` / `昨天` / `yesterday` / `刚刚` / `just now`）、`formatRelativeTo` 的 delta 转换、中英日期布局、`isChineseLocale`、`getSemesterTextFromId` 中英与畸形输入、`formatFileSize`。

#### 8. 界面无硬编码文案（E 项）

`Index.ets` 内所有 `Text(...)` / `Button(...)` 文案均已改为资源取串；页面上不再有硬编码展示文案。仍保留的中文只在**日志**里（`logger.info/error` 的诊断文本，不是界面文案；logger 属 ticket 01 区域，未动）。

`entry/src/main/ets` 全量扫描后剩余中文字面量分布：`pages/Index.ets` 6 处（全是 logger）、`entryability/EntryAbility.ets` 4 处（logger）、`core/log/LogBuffer.ets` 3 处（导出文件头）、`domain/model/Semester.ets` 3 处（异常消息）、`core/log/Logger.ets` 1 处（注释）、`__sm2probe/Sm2ProbeAbility.ets` 1 处（探针常量）。**均非界面展示文案**；若要连日志一起资源化，建议单开切片。

#### 9. 与 ticket 01 的边界（按统筹指令）

`entry/src/main/ets/pages/Index.ets` 与 `entry/src/main/ets/entryability/EntryAbility.ets` 自收到统筹冻结指令起**已停止写入**，此前叠入的 i18n 集成代码（`bindResourceManager` 两处调用、`environment` 回调 + `LOCALE_VERSION_KEY`、`s()`/`tKey` 取串、`switchLanguage`）保留，供 01 增量修复。`core/i18n/*` 五个文件归本 ticket。

#### 10. 移交 / 后续切片需要注意的坑

1. **不要用 `ResourceManager.getLocales()` 当语言**：模拟器上它返回 `en-US`，而资源解析实际用 `zh-Hans`，会得到「中文标签 + 英文日期」的混合界面。以 ability `config.language` 为准（`common.Context` 上没有 `config`，页面里取不到，只能在 ability 里拿）。
2. **本机 local 单测不加载 ICU**：任何断言真实 ICU 文案的单测都会失败（返回空串），措辞类断言请走注入的 formatter 假实现。
3. **`arkts-no-structural-typing`**：ArkTS 形状类型不兼容，类必须显式 `implements` 接口（本 ticket 在测试与 `I18nService implements SemesterTextSource` 上踩过）。
4. **生成文件不要手改**：`I18nKeys.ets`、三份 `string.json`、`i18n-key-map.md`、`i18n-keys.json` 都由脚本生成；改文案请改 `scripts/i18n-ui-strings.mjs`（UI 文案）或资源生成器后重跑：`node scripts/generate-i18n-resources.mjs && node scripts/gen-i18n-keys.mjs`。
5. **加键后必跑** `node scripts/check-i18n-keys.mjs`；新增键会同时改变 `I18N_KEY_COUNT`，`I18n.test.ets` 里的常量断言会失败并提醒同步。
6. **顺手发现的 ticket 01 缺陷（未处理，留给他们）**：截图 `evidence/02-zh.png` 里系统为深色、卡片是深色，但页面最外层底色是白的——深色 `theme.colors.background` 没有作用到最外层容器；另外 `@Builder` 按值传参导致切主题时卡片不刷新（01 已自述在修）。

#### 12. 验收（统筹复核，2026-09-12）—— **通过**

结论：5/5 验收项达成。第 3 项由统筹补取证，其余为统筹**自己重跑**的结果。

**① 键完整性——独立重数，不采信脚本自报**
我自己解析参考实现两份字典：`zh.ts` 180 键 / `en.ts` 180 键。再自己跑检查器：
```
manifest keys : 207   reference declared : 180   reference dictionary : 180
[base ] entries=210 missing=0 empty=0 extra=0 untranslated=0
[zh_CN] entries=207 missing=0 empty=0 extra=0 untranslated=0
[en_US] entries=207 missing=0 empty=0 extra=0 untranslated=1   (ui_app_name, 品牌名中英一致，属预期)
source key references : 28 distinct keys, all resolved
RESULT: OK
```
⇒ **180/180 迁移，0 缺失**。ticket 原文"约 400 键"确系笔误，已按实测改为 180。

**② 界面无硬编码文案**：`Index.ets`/页面文案全走资源；残留中文字面量仅在 `logger.*` 与异常消息中（非界面展示）。

**③ 中英切换无需重启——统筹实测（这是本 ticket 移交前唯一未取证项）**
在模拟器上点页面内的「切到英文」按钮，**不冷启动**，然后 dump 无障碍树：
```
系统配色=浅色 / 颜色令牌=LIGHT_COLORS
Native HarmonyOS rewrite · foundation / 01 layering + logging + theme tokens
Self-check / Relative time sample: 3 days ago / 09/12/2026, 01:03 / Fall 2025-2026
PID before: 29654   PID after: 29654   PID UNCHANGED: True
```
再点「切到中文」→ 全部回到中文，`相对时间示例 = 3天前`、`日期时间示例 = 2026/09/12 01:03`。
**PID 跨切换不变** ⇒ 同进程重建，无重启。截图 `.scratch/foundation/evidence/01-index-en.png`，layout dump `.dsh/logs/lang-{en3,zh3}.json`。
注：`ResourceManager.getLocales()` 在模拟器返回 `en-US` 而系统实际 `zh-Hans`，当时由此产生的 `in 56 years` / 英文日期布局缺陷已修；上表的中文 `3天前` 即修复后的复验结果（原先"修复后未复验"的缺口闭合）。

**④ 日期与相对时间本地化**：`3天前` / `3 days ago`、中文 `2026/09/12 01:03` / 英文 `09/12/2026, 01:03`，两种语言均实测。

**⑤ 缺失键检查可复用**：`node scripts/check-i18n-keys.mjs` exit 0；负例套件注入 4 类缺陷全部检出。

**局限**：证据来自**模拟器** Pura 90（HarmonyOS 6.1.0(23)），非真机 API 24。系统级语言切换（改系统设置）在模拟器上受 shell 身份限制（`param set persist.global.language` → errNum 1001），故实际验证走的是应用内 `setLanguage()` 这条同样触发 configuration 更新的链路。

#### 11. 本 ticket 明确**未完成 / 未验证**的项

- 「真机系统语言中/英切换、界面跟随、无需重启」的**双截图最终取证**：按统筹指令移交合并取证（原因与已有证据见第 5 节）。
- 修复后中文日期/相对时间布局的**复验**：需要一次重新部署，被冻结令挡住。
- `check lint`：`devecocli check lint` 报 `Issues: 0 | Errors: 0 ... Files checked: 0`——该版本对 ArkTS 目录没有实际产出条目，**不能算作 lint 通过**，真正的编译证据是 `devecocli build`（exit 0）。
