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

**`core` 与 `domain` 之间的边界（ticket 03/05 期明确）**：默认 `core` **不得**依赖 `domain`——`core` 是平台封装层，`domain` 是策略层，基础设施依赖策略属于反向依赖。唯一的例外是**纯叶子工具**（无平台依赖、无领域实体、无业务规则，例如 `domain/parse/Utf8.ets` 的 UTF-8 编解码）：这类工具放在 `domain/` 下可获得 `scripts/check-domain-purity.mjs` 的**自动纯度保护**，而 `core` 允许引用它。这样定的理由是实测教训——平台 `util.TextDecoder.decodeWithStream` 在单测环境里返回 `undefined`，把「解析是否正确」与「平台 API 在这个环境是否可用」绑在了一起；把这类工具放进受保护的纯区，能让 host 与设备共用同一份实现。

**这条边界检查器覆盖不到**：`check-domain-purity.mjs` 只扫描 `domain/**` 自身的 import，对 `core → domain` 这种反向引用**不会报错**。因此新增 `core` 文件若引用了 `domain`，必须自问是否属于上面的「纯叶子工具」例外；不属于就应当把纯的部分下沉到 `domain`，或让 `core` 自行实现。

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
_注入面已缩小_：旧实现必须用**猴补丁**（`jQuery.fn.submit` + XHR 拦截）才拿得到这些值；新实现不需要猴补丁——页面会在加载时自己写好它们，用有限次轮询读/写 DOM 即可。**但"手段简化"不等于"语义改变"**：三个指纹字段的归属必须按下表分清，否则会踩到 2026-09-12 那次歧义（曾把"不需要猴补丁"误读成"表单别动"）。

| 字段 | 谁的值 | 处理 |
| --- | --- | --- |
| `fingerPrint` | **我们生成的**（应用侧 UUID） | **必须权威**：页面写完之后**盖掉表单字段**，并在 `saveFinger` 的 XHR 里注入同一个值；两处都要，缺一即不一致 |
| `fingerGenPrint` | 页面的（`localstorageUtil.getFinger3FromLocal()`） | 读 DOM 后写进 `#fingerGenPrint`，**持久化**，重登原样回放 |
| `fingerGenPrint3` | **服务端下发**、缓存在 localStorage（`getFinger3FromRemoteAndSave`） | 读 DOM 并持久化，重登原样回放 |
| `singleLogin` | 页面的（默认勾选"信任浏览器"） | 不动 |

**为什么 `fingerPrint` 必须是我们的值**：纯 HTTP 重登（下一节）会把 `fingerPrint`/`fingerGenPrint`/`fingerGenPrint3` 一起作为表单字段发给 ID 侧（`thu-learn-lib/lib/module/index.js:119-125`），而服务端判定"同一浏览器"就建立在设备指纹上。因此**服务端登记的必须是将来重登要出示的同一个值**。页面那个值是 fingerprintjs2 的 canvas/webgl 指纹（17 项），我们**无法复算**，只能当不透明串存下来回放——那样凭据有效性就取决于服务端页面脚本保持不变，不受我们控制。我们自己的 UUID 是唯一**确定可复现**的值，所以它在**表单与 `saveFinger` 两处都必须权威**；只覆盖一处会导致两处不一致，服务端绑哪个变未知，验收第 2 条（服务端登记值 == 保存的凭据指纹）无法成立。这条同时是参考实现的行为：`sso.js` 的 `jQuery.fn.submit` 猴补丁在提交时把 `fingerPrint` 写进表单，`saveFinger` 的 XHR 也被注入同一个值（见 `idp-login-flow.md` 第 2 节）。

**取证要求（验收第 2 条的可判定形式）**：登记时在**三个点**各打一行**脱敏**指纹（例如 SHA256 前 8 位十六进制，**绝不打原始值**）——① 写进表单字段的值、② `saveFinger` 实际携带的值、③ 最终落盘的值。三点相同才算本条成立。只声明"我们注入的是同一个变量"只能证明代码意图，证明不了**实际发出的报文**。

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

- 每功能 `spec.md` 附**逐条验收清单**（我起草，你可改），你在设备截图后逐条判。
- 证据存 `.scratch/<feature>/evidence/`。**口径（2026-09-12 定）**：日常验收用**模拟器 `Pura 90`**（`127.0.0.1:5555`，HarmonyOS **6.1.0(23)**）——它与工程声明的 `compatibleSdkVersion` 同版本，因此 API 语义层证据比真机更贴目标；证据一律按实标注"模拟器"。
- **真机 `3FYBB25407201890`（MatePad Air，API 24）做最终一次性复验**，时点卡在 ticket 18 之前，专门覆盖"在更高 API 上的向后兼容"这一层（与 §11 #7 同一笔账）。真机未接入期间，凡验收项字面写着"真机"的，按模拟器取证并在 ticket 内注明**该条真机复验仍欠**。
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
| 1 | ✅ **已验证**（2026-09-12）：变换串 = `SM2_256|SM3`（`SM2|SM3` 亦可；`SM2_256`/`SM2` → 401，`SM2_256|SM3|C1C2C3` → 801）；`doFinal` 出 ASN.1 DER，用 `SM2CryptoUtil.getCipherTextSpec(der,'C1C3C2')` 取出后在左侧补零拼 `04 + C1x + C1y + C3 + C2`，与 `sm-crypto@0.3.14` 默认 C1C3C2 **双向互解通过** ⇒ Re-auth 可纯 ArkTS，ADR-0004 不变。证据：`.scratch/migration/sm2-verify/`（`device-sm2probe-hilog.log`、`sm2-probe.log`、`arkts-verify.log`、`analyze-sha256-der.log`）；详见 issue 06 Comments | `auth` 的 Re-auth |
| 2 | `@ohos/flexsearch` 的 `.js` 入口能否在 API 23 工程中导入 | `search` |
| 3 | 目标设备（MatePad Air）上 HMS Core 是否满足 PDF Kit / Preview Kit / ShareKit 要求 | `files` |
| 4 | `@ohos.window` 沉浸式/全屏 setter 的确切签名 | `shell` |
| 5 | ArkWeb 的 `onLoadIntercept` / cookie 读取 API 在 API 23 的确切形态 | `auth` 的 Enrollment |
| 6 | ✅ **已验证**（2026-09-12）：**不采用 dayjs**。本机 ohpm 6.1.2.285 无 `search` 子命令；`ohpm info dayjs` 能解析（dayjs@1.11.13），但 tarball 是**原样镜像的 npm UMD 包**——无 `oh-package.json5`、`package.json` 无 `module`/`exports`、locale 靠运行时动态 `require`，ArkTS 无法 import。改用 `@ohos.intl` + 可注入 formatter 接缝（纯阶梯策略可单测）。查证脚本 `scripts/investigate-dayjs-ohpm.mjs`，详见 issue 02 Comments | `foundation` |
| 7 | **部分解决**（2026-09-12）：工程声明 `compatibleSdkVersion 6.1.0(23)`，本机 SDK 与模拟器 `Pura 90` 运行时**均为 HarmonyOS 6.1.0(23)**，故 API 23 语义下的构建与运行已在模拟器上持续验证通过（见 issue 01/02 证据）。**欠账**：真机 `3FYBB25407201890` 是 **API 24**，"更高 API 上的向后兼容"未验证 —— 已并入 ticket 18 前的真机一次性复验（见第 8 节） | 全程 |
