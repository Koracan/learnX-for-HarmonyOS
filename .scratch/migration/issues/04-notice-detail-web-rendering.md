# 04: 公告详情 + HTML 渲染（Mock）

**What to build:** 从公告列表进入详情，正文以 Web 容器渲染 HTML，含数学公式、链接与暗色适配；附件可点。

**Blocked by:** 03（导航骨架 + 公告列表）

**Status:** ready-for-agent

- [ ] 详情标题与副标题由进入时的参数决定（课程名 + 发布者）
- [ ] 正文按内容高度自适应，不出现内部滚动条
- [ ] 数学公式正确渲染；深色与浅色下正文对比度均可读
- [ ] 正文中的附件链接与外部链接可点，且行为明确（下载 / 外部打开）
- [ ] 切换深浅色后正文样式即时更新
- [ ] 真机截图（浅色 + 深色各一张）

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
