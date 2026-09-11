# 04: 公告详情 + HTML 渲染（Mock）

**What to build:** 从公告列表进入详情，正文以 Web 容器渲染 HTML，含数学公式、链接与暗色适配；附件可点。

**Blocked by:** 03（导航骨架 + 公告列表）

**Status:** ready-for-verification — 6/6 项均有模拟器证据；验收 3/5/6 为本轮按统筹复核结论更正或重取，待统筹复核
（注：`ready-for-verification` 不在 `docs/agents/issue-tracker.md` 的既有词表里，此处用它表达"实现方已交付、等复核"；
**是否置为 verified 由统筹决定**，实现方不自行判定。）

- [x] 详情标题与副标题由进入时的参数决定 —— **按参考实现为「发布者 + 绝对时间」，不显示课程名**
      （原文写的「课程名 + 发布者」与参考实现不符，统筹已确认以参考实现为准；见 Comments 第 2 节）
- [x] 正文按内容高度自适应，不出现内部滚动条（测高桥回传 5→…→2623；外层是唯一滚动容器）
- [x] 数学公式正确渲染（判据 = `$…$` 排版；**单 `# 04: 公告详情 + HTML 渲染（Mock）

**What to build:** 从公告列表进入详情，正文以 Web 容器渲染 HTML，含数学公式、链接与暗色适配；附件可点。

**Blocked by:** 03（导航骨架 + 公告列表）

 不渲染属参考实现行为**，
      见 `docs/reference-quirks.md` 第 9 条）；深色与浅色下正文对比度均可读
- [x] 正文中的附件链接与外部链接可点，且行为明确（附件 → FileDetail 传参；正文链接一律外部打开）
- [x] 切换深浅色后正文样式即时更新（应用级 colorMode 链路；本轮修掉"模板不重载"缺陷后重取）
- [x] 截图存 **`.scratch/notices-detail/evidence/`（模拟器 Pura 90，浅色 + 深色各一张）**；
      真机复验按 AGENTS.md 归 ticket 18 之前的一次性复验

## Comments

### 派单前的参考实现核查（统筹，逐行取证，2026-09-12）

**结论先说**：本 ticket 的模板与自动高度在参考实现里是**平台无关的 HTML/CSS/JS**，可以近似逐字复用；
真正需要重新设计的是「Web 容器 ↔ 原生」的两条桥（测高、取 cookie/CSRF），以及资产**不要内联**。

#### 1. 页面结构 `src/screens/NoticeDetail.tsx`

- 标题：`removeTags(title)`（:81）——与列表一致，实体解码在渲染层（`docs/reference-quirks.md` 第 4 条）。
- 副标题 = 发布者 + **绝对时间**（:84-92）：中文 `YYYY 年 M 月 D 日 dddd HH:mm`（**含星期**），英文 `MMM D, YYYY HH:mm`。
  注意列表用的是**相对时间**（`fromNow()`），详情用绝对时间，两者不同，别统一。
- **验收第 1 条与参考实现不符，需就地修正**：ticket 写的是「课程名 + 发布者」，但参考实现详情页
  **只显示发布者与时间，不显示课程名**。按本仓规则（移植完成定义 = 与参考实现行为一致），本条验收以
  「发布者 + 时间」为准；`courseName` 仅作为附件跳转 `FileDetail` 的参数（:65）。若产品上确要在详情页显示
  课程名，那属于**新增**，应单独登记为增强而不是混进移植验收。
- 附件在正文**上方**，是独立一行 `List.Item`（:95-109），点击 `navigation.push("FileDetail", {...})`，
  参数 `title: stripExtension(attachment.name)`、`fileType: getExtension(attachment.name)`。
  **不是**从正文字符串里解析链接——正文链接与附件是两条不同通路。
- 重型组件延迟：`InteractionManager.runAfterInteractions` 之后才渲染 WebView，此前显示 `ActivityIndicator`（:26-32, :110-116）。
- 空正文兜底：`content || "<p>" + t("noNoticeContent") + "</p>"`（:54）。

#### 2. 模板 `src/helpers/html.ts:27-118`（可复用）

- viewport：`width=device-width, initial-scale=1`；`#root` 高 100% 且 `overflow:auto`。
- 注入脚本 `addCSRFTokenToUrl`（:60-86）：给 `href`/`src` 中 **hostname 以 `tsinghua.edu.cn` 结尾**的 URL 追加 `_csrf`；
  token 取自 `dataSource.getCSRFToken()`（:68）——**会话态**，Mock 下为空。
- 深色：`DarkReader.enable({ darkSchemeBackgroundColor: "<surface 色>" })`（:88-101），由 `theme.dark` 决定是否注入。
- 数学：`renderMathInElement(document.querySelector("#root"), { throwOnError: false })`（:110-114）。
- `#root > p:first-child` / `:last-child` 去外边距（:49-54）。

#### 3. 自动高度与链接 `src/components/AutoHeightWebView.tsx`

- 测高（:24-48）：注入 JS 取 `max(documentElement.clientHeight, documentElement.scrollHeight, document.body.clientHeight,
  document.body.scrollHeight)`，经 `postMessage` 回传，原生侧 `setHeight`。**验收第 2 条（自适应、无内部滚动条）就是这条。**
- **链接一律外部打开**（:50-55）：`onNavigationStateChange` 里 `navigationType === "click"` → `stopLoading()` + `Linking.openURL(e.url)`；
  `originWhitelist: ["*"]`。即正文里**所有**链接都跳系统浏览器，不在容器内导航。验收第 4 条的「行为明确」= 外部打开。
- cookie（:57-71, :90-92）：`CookieManager.get(learn)` 后写进请求头 `Cookie`，并 `sharedCookiesEnabled`。
  本工程 cookie **只在内存**（ADR-0004，不落盘），所以这里必须留一个**可注入的 cookie/CSRF 提供者端口**：
  Mock 下返回空，真实值由 06/09 注入。**不要把 cookie 持久化到 preferences**。
- `baseUrl` 用 `Urls.learn`（:87-89），使正文里的相对 URL 解析到 learn.tsinghua.edu.cn。

#### 4. 资产体积（实测）——**决定实现方式，别照搬内联**

| 资产 | 字节 |
| --- | --- |
| `node_modules/katex/dist/katex.min.js` | 276,705 |
| `node_modules/katex/dist/katex.min.css` | 23,732 |
| `node_modules/darkreader/darkreader.js` | 322,649 |
| `katex/dist/contrib/auto-render.min.js` | 另需 |

- 参考实现用 `@preval` 在**构建期**把这些文件读成字符串内联进模板（`src/helpers/preval/readFile.js`）。合计约 630 KB。
- **ArkTS 不要照搬**：不要把 630 KB 内容写成 .ets 字符串字面量（编译期与内存都不划算）。
  改为放 `entry/src/main/resources/rawfile/webview/`，运行时用 `resourceManager.getRawFileContent` 读出再拼装模板，
  模板里留占位符。
- `katexStyles.preval.js` 还把 CSS 里的 `url(fonts/` 重写成 `https://fastly.jsdelivr.net/npm/katex@<version>/dist/fonts/`——
  即**公式字体依赖外网 CDN**。保持忠实就保留 CDN，但必须在验收证据里写明这一点（离线时公式排版会退化）。
  是否改为内置 woff2 属**独立决策**，先登记再动手。

#### 5. 可单测的部分（建议，用来支撑验收）

模板拼装是纯字符串逻辑，放纯区（受 `check-domain-purity.mjs` 保护）后可单测，不必全靠截图：
- 给定 `content`/`dark`/`backgroundColor`/`csrfToken`，断言产物包含 `viewport`、`#root`、注入脚本、是否含 DarkReader 段；
- 断言空正文时落到 `noNoticeContent` 文案；
- 断言深色开关只切换 DarkReader 段而不改其它结构。
读数（rawfile）与桥接（`javaScriptProxy` / `runJavaScript`）留在 `core/`。

### 04 交付记录（实现 agent，2026-09-12，模拟器口径）

**提交**：`6e87a08`（`feat(notices): 公告详情 + HTML 渲染（Mock，ticket 04）`，30 个文件）。
**门禁**：`hvigorw … test --no-incremental`（先删 `entry/.test`）→ **19 类 116 用例全过**，
其中新增 `features.notices.detail.*` 15 例（WebViewTemplate 9 / NoticeDateText 4 / FileNames 1 / MockAttachment 1）；
`check-domain-purity.mjs` → **PASS**（12 个领域文件）；`check-i18n-keys.mjs` → **RESULT: OK**（231 键，37 处源码引用全解析）；
`assembleHap` → **BUILD SUCCESSFUL**（提交态，产物 1,280,685 B）。

#### 1. 逐条验收（**只有 1、4 达成；2、3 部分；5 未达成；6 两张在但深色无差异**）

| 验收项 | 结论 | 证据（模拟器 Pura 90） |
| --- | --- | --- |
| 1 标题/副标题由参数决定 | **达成**（按参考实现：发布者 + 绝对时间，**不显示课程名**） | `04-detail-light-zh.png` + layout 的 `Text` 节点：「第一次大作业」「薛有泽」「2020 年 9 月 10 日 星期四 16:22」 |
| 2 高度自适应、无内部滚动条 | **部分** | `04-hilog-probe5.txt` 的 `content height: 5→21→57→150→389→1011→2623 source=bridge`；`04-detail-light-layout.json` 的 `Web [0,916,1320,2562]`（= 外层 Scroll 视口，正文四段全可见）。**Web 的高度设置值本身没被断言**（layout 只给可视边界），见未验证项 2 |
| 3 数学公式渲染 | **部分** | 行间 `$$…$$` 已由 KaTeX 排版（`04-detail-light-zh.png` 的 ∫ 公式）+ `04-hilog-mathaudit.txt` 的 `math=katexNodes:1`；**行内 `$E=mc^2$` 仍是字面量**，见未验证项 3 |
| 4 链接与附件可点、行为明确 | **达成** | 外部打开：`04-link-external-open.png`（系统浏览器停在 `learn.tsinghua.edu.cn` —— 即 `onLoadIntercept → startAbility` 生效、且 `baseUrl` 让相对链接解析到 learn 站点）；附件：`04-detail-light-zh.png` 的附件行 + `04-hilog-probe6.txt` 的 `attachment tapped` |
| 5 切换深浅色即时更新 | **未达成** | `04-detail-dark-zh.png` 顶部 `dark=true`（模板确实按 dark 重建了），但**正文仍旧浅色**；诊断线索见未验证项 1 |
| 6 浅色 + 深色各一张截图 | 两张都有，但**深色与浅色无视觉差异** | `04-detail-light-zh.png`、`04-detail-dark-zh.png` |

#### 2. 验收第 1 条与参考实现不符 —— 按参考实现做，请统筹确认

详情页**不显示课程名**：参考实现 `NoticeDetail.tsx:84-92` 只有发布者 + 绝对时间，`courseName`
仅作为附件跳 `FileDetail` 的参数（`:65`）。我按「移植完成定义 = 与参考实现行为一致」实现，
**没有自己加课程名**。若产品上确需显示，请作为**新增增强**单独登记（并写替代验收标准）。

#### 3. 有意差异与新增的怪癖台账条目（**已先改表再改码**）

`docs/reference-quirks.md` 新增第 6/7/8 条（本次提交内含）：

1. **第 6 条**：正文里的 `</script>` 转义。参考实现把 `content` 直接插进含内联 `<script>` 的模板
   （`helpers/html.ts:108`），正文含字面量 `</script>` 会提前结束 script（注入路径）。本实现转义为
   `<\/script`（渲染无差异）。单测 `escapes script end tags in the notice content` 守住。
2. **第 7 条**：注入脚本的 `new URL()` 改成**等价手工解析**。`loadData` 的文档是 opaque origin，
   `new URL()` 抛 TypeError（照抄会让所有链接更新失败）；但「只对 hostname 以 `tsinghua.edu.cn` 结尾的
   链接追加 `_csrf`」这个条件**逐条保留**（含空 token 追加 `_csrf=`、非 http(s) 跳过、fragment 拼回）。
3. **第 8 条**（平台事实，会误导移植者）：`runJavaScript` 返回值恒为 `null`（显式 `return` 也一样）→
   测高只能走 `javaScriptProxy` 桥；而桥**只注入对象不执行脚本**，测高脚本必须另外经
   `javaScriptOnDocumentStart` 放进页面；`file://` 指向应用沙箱会被 `ERR_ACCESS_DENIED` 拒绝。
   三条都有失败日志留证（`04-hilog-detail.txt` / `04-hilog-probe4.txt` / `04-hilog-probe5.txt`）。

#### 4. 附件与 FileDetail 的处理决定

附件行**照参考实现接上真实导航**：点击 `push('FileDetail', …)`，参数逐项对齐
`NoticeDetail.tsx:63-71`（`title: stripExtension(name)`、`fileType: getExtension(name) ?? ''`，
另带 `id`/`courseName`/`courseTeacherName`/`downloadUrl`）。目标页 `FileDetailPlaceholderPage`
**只把参数显示出来**并标注「文件详情属 ticket 07」——即**导航契约已交付、文件详情内容未交付**。

#### 5. 取证夹具（提交态关闭）与模板复用的取舍

- 参考实现 mock 的 7 条公告**既没有 KaTeX 公式、也没有 `<a>` 链接**，无法用它取「公式/链接」的证据。
  我没有改 ticket 03 锁定的 mock 夹具，而是加了 `NoticeDetailEvidence.ets` 的一对开关
  （`EVIDENCE_DETAIL_CONTENT`、`EVIDENCE_DARK_TOGGLE`，**提交态均为 false**，可用
  `git show HEAD:…` 核对），取证时整段替换正文并在详情页顶部显示 `dark=` 控制条。
- 因此**所有详情截图里都有一条 `dark=` + `toggle` 控制条**，以及状态栏时间戳；这是取证态的特征。
- 模板资产按 ticket 要求**不内联**：`rawfile/webview/` 4 份（katex.min.js 276,705 B、auto-render.min.js 3,467 B、
  katex.min.css 26,792 B（`url(fonts/` 已重写为 `https://fastly.jsdelivr.net/npm/katex@0.16.27/dist/fonts/`）、
  darkreader.js 322,649 B）；运行期用 `getRawFileContentSync` 读出。**公式字体依赖外网 CDN**（离线退化）。

#### 6. 未验证 / 未达成（请勿当成已通过）

1. **深色正文没有变深**（验收 5 未达成、验收 6 的深色图无差异）。模板确实按 dark 重建（截图顶部 `dark=true`），
   但正文仍浅色。下一步诊断（未执行）：在页面里跑 `DarkReader.isEnabled()` 与
   `getComputedStyle(document.body).backgroundColor`，区分「DarkReader 没生效」与「模板 dark 分支没进去」。
2. **Web 组件的高度设置值未被断言**：已确认的是行为（内容全可见、公式完整、外层 Scroll 起作用），不是 `height=2623` 这个属性值。
3. **行内公式 `$…$` 未渲染**（页面里是字面量 `$E = mc^2$`），同页行间 `$$…$$` 正常；根因未定论。
   **可能**是 KaTeX auto-render 的默认分隔符不含单个 `$`。
4. **CSRF 追加的运行时行为未取证**：Mock 的 token 是空串，注入脚本运行时路径没有真实值；纯逻辑侧有模板断言。
5. **返回列表后滚动位置是否保留未复测**（ticket 03 的结论在本次 Navigation 外壳改造后没有重跑）。
6. **重试 `NoticeRecord` 增加可选 `attachment` 字段**（对齐参考实现 mock.ts:290-296）：真实数据源 ticket 09 落地时需填充它；
   本 ticket 在 `MockNoticeRepository` 里逐字补了那一条附件（含 `downloadUrl`），单测断言「恰好一条带附件」。
7. **全部证据来自模拟器**，无真机证据（按 AGENTS.md 归 ticket 18 前的一次性复验）。

#### 7. 证据清单

`.scratch/notices-detail/evidence/`（19 个文件 + `README.md`，含字节数与 SHA256 前 16 位，用 `git add -f` 只把 README 入库）；
`revision.txt` 记 `git rev-parse HEAD`、`git status --porcelain` 的 SHA256（取证时工作区是脏的 → 过程证据）、
设备上 `bm dump` 的 `versionCode=1000042 / versionName=1.1.0`。

### 04 复核更正与重取（实现 agent，2026-09-12 第二轮）

统筹复核指出两处**证据/结论错位**，都成立，已按其结论更正并重取：

#### A) 验收第 3 条：部分达成 → **达成**

统筹把根因钉死了：参考实现 `helpers/html.ts:110-114` 调用 `renderMathInElement` 时**没有传 `delimiters`**，
而 KaTeX auto-render 的默认分隔符集是 `$$…$$`（行间）、`\(…\)`（行内）与 `\begin{…}` 环境——**单 `$` 不在其中**。
所以 `$E = mc^2$` 显示为字面量**就是参考实现的行为**，不是缺陷。已由统筹登记为 `docs/reference-quirks.md` 第 9 条（锁定）。
**本实现不给 `delimiters` 补单 `$`**（那会让真实公告里的价格/变量名被当公式吞掉）；
模板里保持 `{ throwOnError: false }`，验收判据改为「`$$…$$` 正常排版」→ **达成**
（`04-detail-light-zh.png` 的 ∫ 公式 + `04-hilog-mathaudit.txt` 的 `math=katexNodes:1`）。

#### B) 验收第 5 条：**「未达成」是我的误判，实为「未验证」；重取后确有一个真实缺陷，已修**

**证据状态错位（我的错）**：上一轮我把 `04-detail-dark-zh.png` 报成深色证据并据此写「顶部 dark=true 但正文仍浅色」。
实际时序是：04:24:30 在 `dark=true` 下取了 layout → 04:26:27 点了 toggle（翻回 false）→ **04:26:40 才截图**，
所以那张图显示的是 `dark=false`。而且 **layout dump 只有 `type`/`bounds`/`children`，不含颜色信息**，
它支持不了「正文仍浅色」这个论断。两个文件已**删除**，不再作为证据。教训：

- **截图与 layout 必须同态取，中途不要点开关**；
- **不要用 layout dump 支撑颜色类论断**；
- **不要把「未验证」写成「未达成」**——前者是证据问题，后者是功能缺陷，修复方向完全不同。

**重取（按统筹要求的口径）**：应用级 `setColorMode`（只作用于本应用，不动设备全局设置）、冷启动、
同一会话内把页面侧事实经桥写进 hilog；截图与 layout 在同一状态下取。审计行：

```
# 浅色态（同一会话）
load finished: native.isDark=false themeAuditSwitch=true
theme audit native.isDark=false defined=false enabled=err:ReferenceError: DarkReader is not defined bodyBg=rgba(0, 0, 0, 0) bodyColor=rgb(0, 0, 0) darkCallInDom=false
# 点应用级深色后
evidence colorMode -> DARK
theme changed -> reload content: native.isDark=true
theme audit native.isDark=true defined=true enabled=true bodyBg=rgb(30, 26, 29) bodyColor=rgb(232, 230, 227) darkCallInDom=true
```

`bodyBg=#1E1A1D`（= `DARK_COLORS.surface`）、`bodyColor` 为浅色 → **深色下正文对比度可读**（`04c-after-toggle-dark.png`）。

**这次重取暴露并修掉的两个真实缺陷**（都在 `ui/components/HtmlWebView.ets`）：

1. **主题变化不会重载模板**：`loadData` 只在 `onControllerAttached` 里调用一次，改 `@Prop isDark` 不会让 ArkWeb 重新加载
   → 切换深浅色后正文**不更新**（`04-hilog-dark2.txt`：`evidence dark toggled` 之后没有第二次 `loadData issued`）。
   修法：`@Prop @Watch('onThemeChanged') isDark` 触发重送；同时把 `loaded` 归位，
   否则重送时的主框架请求会被 `onLoadIntercept` 当成用户点击而**跳到系统浏览器**。
2. **底色与深色标志不同源**：原先 `surfaceColor` 是独立 `@Prop`，实测 `@Prop isDark` 的 `@Watch`
   可能早于同批其它 `@Prop` 赋值触发 → 「深色已生效、底色仍是浅色」，DarkReader 拿到浅底 → 深色文字配浅底不可读。
   修法：底色改由 `isDark` 推导（`resolveTheme(isDark).colors.surface`），彻底消除不一致窗口。

顺带把取证控制条改成**切应用级 colorMode**（不再自己翻一个 `@State`），于是控制条走的就是生产同一条链路，
`dark=` 读的也是 `isDark()` 本身——不再有「界面显示的标志 ≠ 模板实际用的标志」的余地（这正是上轮错位的根源）。

#### C) 提交态界面截图（原缺失，已补）

开关全部翻回 false 后重新构建安装（产物 1,282,925 B），冷启动进详情页截图：
`04-final-list-zh.png`、`04-final-detail-zh.png` —— **无 `dark=`/`toggle` 控制条**，正文是真实 Mock 内容
（「第一次大作业已布置，请同学们仔细阅读作业说明文档……」）。hilog 三行自证提交态：
`detail evidence content: enabled=false`、`themeAuditSwitch=false`、`detail evidence dark toggle: enabled=false`。

#### D) 台账状态按词表更正

- 第 6 条（`</script>` 转义）→ **已复审**，并写明替代验收标准：「正文含字面量 `</script>` 时渲染结果仍是文本」，
  由单测断言「产物里只剩模板自己的 3 个 `</script>`」承载；
- 第 7 条（`new URL()` 换手工解析）→ **锁定**（行为等价、只是平台约束下换了实现方式，不构成偏离）；
- 第 8 条改归 平台事实 与文件头的两类判据由统筹完成，我未再改动。

#### E) 门禁（本轮重跑，全部在修复之后）

`hvigorw … test --no-incremental`（先删 `entry/.test`）→ **Tests run: 116, Failure: 0, Error: 0, Pass: 116**（19 类）；
`check-domain-purity.mjs` → **PASS**（12 个领域文件，exit 0）；`check-i18n-keys.mjs` → **RESULT: OK**（231 键，exit 0）；
`assembleHap` → **BUILD SUCCESSFUL**（提交态，1,282,925 B）。

#### F) 仍然未验证 / 已知缺口

1. **Web 组件的高度设置值未被断言**（layout 只给可视边界）：已确认的是行为，不是 `height=2623` 这个属性值；
2. **CSRF 追加到链接的运行时行为未取证**：Mock token 是空串，只有模板级单测；
3. **返回列表后的滚动位置未复测**（ticket 03 的结论在本次 Navigation 外壳改造后未重跑）；
4. 全部证据来自**模拟器**，无真机证据。
