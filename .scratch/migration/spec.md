# learnOH 移植总纲

**状态**: 待确认（确认后逐功能开 spec）
**范围**: 把参考实现（`reference/learnOH-old/`，React Native for OpenHarmony）已实现的全部功能，以 HarmonyOS 原生 ArkTS / ArkUI 重写。

事实附录（本总纲的依据，不含于此文档）：
- `docs/rn-app-inventory.md` —— 参考实现的导航 / 状态 / 持久化 / 组件 / 外部接口清单 + 十大风险
- `.scratch/migration/dependency-inventory.md` —— 依赖 → 调用点 → 替代方案映射
- `.scratch/migration/capability-map.md` —— 鸿蒙能力地图与缺口
- `.scratch/migration/idp-login-flow.md` —— ID 登录页取证、信任生命周期、简化设计
- `.scratch/migration/search-package-eval.md` —— 模糊搜索包评估

## 1. 范围

**做**：参考实现 1.1.0 实际交付的全部行为——登录/保持登录、公告、作业（含提交）、文件（下载/预览/分享）、课程、学期选择、设置及其子页、搜索、收藏、归档、隐藏课程、Mock 模式、暗色模式、沉浸式、断点分栏。

**不做**（参考实现从未实现，没有验收标准，属于新开发而非移植）：CourseX、后台抓取与通知、推送、日历/提醒同步。
_要重新纳入需单独立项；"移植正确"对一个从未存在过的行为无法证明。_

**完成定义**：每个功能 = 一份 `spec.md`（含逐条验收清单）+ 真机截图证据 + 纯逻辑单测。

## 2. 分层

```
entry/src/main/ets/
├── core/       平台封装：HTTP+cookie jar、SM2/密码学、asset、preferences、文件路径、
│               设备信息、日志、Web 桥、i18n 访问
├── domain/     实体与纯规则：Credential/Session/Semester/Course/Notice/Assignment/File/
│               收藏/归档/隐藏/Snapshot。零平台依赖，可单测
├── data/       Repository：抓取 + 解析 + 快照 + 自动重登。每域一个
├── ui/         通用组件：列表外壳、卡片、Filter、Toast、Skeleton、WebView 容器
└── features/   逐功能页面：auth/ notices/ assignments/ files/ courses/ search/ settings/
```

依赖方向：`features → data → domain`；`core` 被 `data`/`features` 使用；**`domain` 不依赖任何上层**。单 `entry` 模块，暂不拆 HAR（体量不值得，见 ADR-0001 相关讨论）。

## 3. 状态层

- 领域 store 用 `@ObservedV2`/`@Trace` 建模，视图直接读，获得细粒度刷新。
- 取数、缓存、重登放在 Repository —— 它**无 UI 依赖**，用来补上"丢掉 reducer 纯函数后失去的可测性"。
- 不引入 redux 系任何东西（ADR-0002）。

## 4. 持久化

| 数据 | 位置 | 时机 |
| --- | --- | --- |
| 凭据（账号/密码/设备指纹） | asset store，`DEVICE_UNLOCKED`，**无额外开关** | 登记成功时写入 |
| 设置、收藏、归档、隐藏课程、当前学期 | preferences | 变更即写 |
| 内容快照（含 `fetchedAt`、`schemaVersion`） | preferences（JSON） | 抓取成功后写；启动时先展示旧快照再后台刷新 |
| 会话 cookie / CSRF | 内存，**不落盘** | 自动重登时重建 |
| 下载的文件 | `learnX-files/{courseName}/{fileId}`，根目录由"使用文档目录"设置决定 | 下载时 |

**升级清理**：首次启动检测参考实现遗留（`persist:*` 前缀键、`learnX-files` 旧目录）并清理，然后要求重新登录一次。不做数据迁移。

## 5. 认证

两个阶段，边界清晰：

**设备登记 Enrollment**（仅首次安装、信任过期后）
ArkWeb 加载 ID 登录页 → 注入脚本做三件事：预填账号密码（readonly）、把**我们生成的**设备指纹写入表单、把 localStorage 里的 `fingerGenPrint` 写进 DOM → 用户完成短信验证 → `onLoadIntercept` 检测到 roaming URL 即成功 → 提取 cookie 同步给 HTTP jar → 持久化凭据。
_注入面已缩小_：页面自己会在加载时写好 `fingerPrint`/`fingerGenPrint3`/`singleLogin`（默认勾选"信任浏览器"），`fingerPrint` 与 `fingerGenPrint3` 直接读 DOM 即可；仅 `saveFinger` 的 XHR 需要注入我们自己的指纹与 `deviceName`。

**自动重登 Re-auth**（信任期内的每次冷启动）
纯 HTTP，零 WebView：GET 登录页取 `#sm2publicKey` → `cryptoFramework` SM2 加密密码 → POST 取 ticket → 走 roaming → 抓 `_csrf` → 建立会话内存。

**信任生命周期**：服务端授予 180 天；过期后 Re-auth 必然失败并触发短信。
**失败处理**：任何非预期响应（含服务端拒绝）一律**降级到 Enrollment**，不做静默重试循环，也**不做**过期主动提醒（与站点行为一致，Q25 决策）。

**`deviceName`** = `HarmonyOS,learnOH/{versionName} ({productModel})`，仅登记时上报（重登不发它，故不影响信任绑定）。

## 6. 依赖映射总表

工作量：S ≈ 1 天内，M ≈ 数天，L ≈ 一周以上。

| 参考实现依赖 | 新实现 | 量 | 风险 |
| --- | --- | --- | --- |
| `react-native-learn-oh-data-processor` (ArkTS, 548 行) | **直接移植**，仅 4 行耦合（基类/上下文/设备事件） | S | 低 |
| `thu-learn-lib` (1353 行, cheerio+cookie jar+sm-crypto) | 自写 Client：登录/CSRF/学期/课程/用户/单课程列表；HTML 用正则 | M | 中（SM2 变换字符串待验证） |
| `@react-navigation/*` (12 个 navigator) | ArkUI `Navigation` + `NavPathStack` + `Tabs` | M | 中 |
| `react-native-paper` (MD3) | ArkUI 原生组件 + 自写 Card/Snackbar/Dialog | M | 低 |
| `redux` + `react-redux` + `redux-persist` + `redux-thunk` + `typesafe-actions` | 领域 store + Repository | L | 中（ADR-0002） |
| `@react-native-async-storage/async-storage` | `@ohos.data.preferences` | S | 低 |
| `react-native-secure-key-store` | `@ohos.security.asset` | S | 低 |
| `react-native-cookies` | 自建 cookie jar（内存 + 手工 Cookie 头） | M | 中 |
| `react-native-fs` | `@ohos.file.fs`（无下载 API，配 http/rcp） | M | 中 |
| `react-native-webview` | ArkWeb Web + `WebviewController`（无 onMeasure，需 JS 回传高度） | M | 中 |
| `react-native-pdf` | HMS PDF Kit `@hms.officeservice.PdfView` | S | 低（HMS Core 依赖待验证） |
| `react-native-document-picker` | `picker.DocumentViewPicker` + `@ohos.fileshare` 持久化授权 | M | 中（易漏持久化） |
| `react-native-image-picker` | `picker.PhotoViewPicker` | S | 低 |
| `react-native-file-viewer` | HMS `filePreview.openPreview` | S | 低 |
| `react-native-share` | HMS systemShare `ShareController` | S | 低 |
| `react-native-device-info` | `@ohos.deviceInfo` | S | 低 |
| `react-native-immersive` | `@ohos.window` | S | 低（setter 签名待验证） |
| `react-native-localize` | `@ohos.i18n` + 资源目录 | S | 低 |
| `react-native-vector-icons` | 打包 MCI TTF + 旧名映射 | S | 低 |
| `react-native-gesture-handler`（Swipeable/RectButton） | ArkUI 列表 `swipeAction` + 手势 | M | 中（旧版正因鸿蒙手势冲突才改用 RectButton） |
| `react-native-reanimated` | `@State`/`@Observed` + `animateTo` | S | 低 |
| `react-native-tab-view` | ArkUI `Tabs` | S | 低 |
| `react-native-securerandom` | `cryptoFramework.createRandom`（旧版是死代码，可能不需要） | S | 低 |
| `fuse.js` | `@ohos/flexsearch` + **保留精确/前缀合并层** | M | 中（见第 8 节注） |
| `dayjs`（48 处） | 优先查 ohpm；否则自写 parse/format/relativeTime + 中英 locale | M | 中 |
| `he` | 自写实体解码（6 个实体） | S | 低 |
| `katex` / `darkreader` | 打包进 rawfile 注入 Web（ArkTS 无 preval） | M | 中 |
| `cheerio` | 正则解析（旧 ArkTS 模块已验证） | M | 中 |
| `mime-types` | 自写扩展名→MIME 表 | S | 低 |
| `axios` / `memfs` / `buffer` / `url-polyfill` / `path` / `preval` | **删除**（0 引用或纯构建期） | — | — |

## 7. 实现顺序（feature slug）

| # | slug | 内容 |
| --- | --- | --- |
| 1 | `foundation` | 分层骨架、日志（可导出）、HTTP+cookie jar、SM2、asset、preferences、路径、设备信息、i18n 资源迁移、Hypium 单测骨架 |
| 2 | `shell` | `Navigation`/`NavPathStack`/`Tabs` 骨架、主题与暗色、断点分栏（≥750vp 横向）、沉浸式 |
| 3 | `auth` | Enrollment 注入、Re-auth、保持登录、会话失效降级、Mock 数据源策略 |
| 4 | `notices` | 列表 + 详情（ArkWeb HTML 渲染、KaTeX、暗色） |
| 5 | `assignments` | 列表 + 详情（描述/附件/成绩/优秀作业） |
| 6 | `files` | 列表 + 详情 + 下载 + 预览（PDF/图片）+ 分享 |
| 7 | `courses` | 列表 + 详情（tab）+ 学期选择 |
| 8 | `submission` | 作业提交（multipart + 进度） |
| 9 | `marks` | 收藏 / 归档 / 隐藏课程及其跨列表过滤 |
| 10 | `search` | flexsearch + 精确合并层 |
| 11 | `settings` | 设置与子页（文件设置/关于/帮助）+ 日志导出 |

顺序依据参考实现 `skills/skills.md` 的演进序（认证 → 五大页 → 精细化 → 生态）。`foundation` 与 `shell` 是新增的前置项，因为参考实现的对应能力寄生在 RN 生态里。

## 8. 验收

- 每功能 `spec.md` 附**逐条验收清单**（我起草，你可改），你在真机截图后逐条判。
- 真机证据存 `.scratch/<feature>/evidence/`。唯一真机：`3FYBB25407201890`（MatePad Air，API 24）。
- **纯逻辑写 Hypium 单测**：解析正则、排序、cookie jar、CSRF/URL 组装、路径规范化、搜索评分、快照 schema 迁移。这些"最容易悄悄错、又最难肉眼发现"。
- 真机诊断靠可导出日志（`foundation` 交付）。
- **搜索的 CJK 注**：fuse 的 Bitap 与 flexsearch 的 `cjk` charset 都按码点逐字切分，匹配不了拼音/同音字。参考实现里那段"手工精确匹配合并"是 CJK 下的**必要行为**而非 bug 权宜，必须保留。拼音检索需独立拼音索引字段（后续增强，不在本次范围）。

## 9. 版本与发布

`versionName 2.0.0`、`versionCode 2000000`（旧版 `1000042`；应用市场要求严格递增）、`bundleName com.koracan.learnOH` 不变、`compatibleSdkVersion/targetSdkVersion 6.1.0(23)`。见 ADR-0003。

## 10. 工作流

- 计划与 issue：`.scratch/<feature-slug>/spec.md` + `issues/NN-<slug>.md`（顶部 `Status:` 行）——见 `docs/agents/issue-tracker.md`。
- 不可逆决策进 `docs/adr/`；术语进 `CONTEXT.md`。
- 构建/部署：见 `AGENTS.md`（多设备必须 `--device`；`devecocli run` 必须后台作业；构建耗分钟级，输出重定向到 `.dsh/logs/`）。

## 11. 待验证（阻断前先查明）

| # | 事项 | 阻断 |
| --- | --- | --- |
| 1 | `cryptoFramework.createCipher` 接受的确切 SM2 变换字符串，及其密文排列是否与 `sm-crypto` 的 `04` 前缀格式一致（决定 Re-auth 能否纯 ArkTS 实现） | `auth` 的 Re-auth |
| 2 | `@ohos/flexsearch` 的 `.js` 入口能否在 API 23 工程中导入 | `search` |
| 3 | 目标设备（MatePad Air）上 HMS Core 是否满足 PDF Kit / Preview Kit / ShareKit 要求 | `files` |
| 4 | `@ohos.window` 沉浸式/全屏 setter 的确切签名 | `shell` |
| 5 | ArkWeb 的 `onLoadIntercept` / cookie 读取 API 在 API 23 的确切形态 | `auth` 的 Enrollment |
| 6 | `dayjs` 是否有可用 ohpm 包（48 处使用） | `foundation` |
| 7 | 本机仅装 API 24 SDK，工程声明 23 —— 需确认 API 23 语义下的构建与 API 可用性边界 | 全程 |
