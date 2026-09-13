# 12: 公告详情内嵌图片破图 —— 把会话同步进 Web 容器（内存态 cookie）

**What to build:** 公告详情里内嵌的图片（课程微信群二维码之类）能**真正**显示出来。

根因（ticket 05 已实测钉死，不是地址解析问题）：
- 那条公告的 `<img src>` 本来就是**绝对 https**，解析后的地址与站点都正确，但 `complete=true naturalWidth=0`；
- 页面内 XHR 同一图片 URL → `status=200 type=text/html bytes=69 finalUrl=…/f/login_timeout`（站点自己的登录超时跳转页）；
- 同一条 URL 走**应用自己的 HTTP 客户端** → `type=image/jpeg`；
- ArkWeb 里的 `JSESSIONID` 与应用内存会话**摘要不同**（名字与长度完全一样：102 B / 42+36，只比名字长度会误判成"同一会话"）；
- 生产代码里 `SessionHeaderProvider.cookieHeader()` **只有日志消费者**，`WebCookieManager` 只在登记页出现过 ⇒ **Web 容器里的 cookie 只可能是登记那一次留下的，纯 HTTP 重登不会更新它**。
⇒ 根因是 **Web 容器的网络上下文没有当前会话**，子资源（img）请求因此未鉴权。

**修法（账号所有者 2026-09-13 裁定：走 A′）**：把承载公告正文的 Web 组件置 **`incognitoMode(true)`**，
并在控制器挂载后把应用内存会话的 cookie 逐条写进 **incognito（内存态、不落盘）** 的 cookie 存储：
`WebCookieManager.configCookieSync(url, value, /*incognito*/ true, /*includeHttpOnly*/ true)`。
SDK 文档明写 incognito 下 "cookies, records of websites, geolocation permissions will not save in persistent files"
⇒ 会话不进持久化存储，**不与 ADR-0004「不持久化会话 cookie」冲突**。
（`includeHttpOnly=true` 是必需的：JSESSIONID 很可能是 HttpOnly。）

**Blocked by:** None（ticket 05 的地址解析修复是前提，已在 main）

**Status:** verified-partial（合并 `c3340a2`：破图修复与"不落盘"两条设备实证达成；"会话变化/登出"一条受禁令限制只能代码+单测）

- [x] 那条含二维码的公告，**设备截图上图片可见**（同状态 before/after；before 是破图，见 `.scratch/ui-optimize/evidence/t05/before-notice-detail-broken-qr.png`）
- [x] 只写内存态：给出"进程重启后 ArkWeb 里不残留可用会话 cookie"的可复核判据（例如 `fetchCookieSync(url, incognito=true)` 为空）
- [x] `HttpOnly` 的 JSESSIONID 确实被写入（否则仍是 `login_timeout`）；写入失败要有可读日志，不静默
- [ ] 会话变化跟着变：重登后 Web 容器读到新会话；**登出后 Web 容器不再持有可用会话**
      （**未设备验证**：不许点「退出登录」、重登需短信；仅代码 + 单测覆盖，见 Comments 第 4 条）
- [x] 影响面受控：公告详情、作业详情这些走 `HtmlWebView` 的页面行为不回归；**不要破坏登记页**（`EnrollmentWebView` 现有的 `clearAllCookiesSync` / `fetchCookieSync` 收割逻辑）
- [x] 只对 learn 源生效，外部 CDN（katex/darkreader）不受影响
- [x] 单测：cookie 串拆分与写入参数构造做成**纯函数**，钉住输入 → 输出；`cookieHeader()` 为空时不写任何 cookie
- [x] 硬约束：`domain/` 必须保持零平台依赖（`check-domain-purity` 绿）
- [x] 证据：设备截图（二维码可见）+ 重启后不可用的判据 + 同状态 before/after

## Comments

### 2026-09-13 · 统筹者验收：verified-partial（合并 `c3340a2`）

**我独立复核过的东西**：
- **两帧截图我亲眼看过**（不是只看哈希表）：`before-notice-detail-broken-qr.png` 里该出二维码的位置是**破图占位**（一个小裂图图标 + 空框），正文其余部分正常；
  `after-notice-detail-qr-visible.png` 里**真实图片渲染出来了**（微信群二维码清晰可见）。⇒ A′ 成立。
- **顺带自己看到了开放项 (a) 是真的**：那张图的原始尺寸比视口宽（视口约 440 CSS px，站点 HTML 写死 `width="820" height="1200"`），所以一屏只能看到二维码的一部分，要横向拖动。**这不是本 ticket 引入的**（模板里本来就没有 `img` 尺寸规则，与参考实现一致）⇒ 记为候选，不在本 ticket 改。
- **单测**：`entry/.test/.../test_result.txt` 时间戳 `2026/9/13 13:39:21`、`Tests run: 398, Failure: 0, Error: 0, Pass: 398`（分支基线 392 ⇒ +6）。核对的是文件本身。
- **改动面**：4 个文件（`core/web/WebSessionCookie.ets` 新增、`ui/components/HtmlWebView.ets`、`WebSessionCookie.test.ets` 新增、`List.test.ets` 注册），与工单对应；**无探测代码残留、无 PNG 入库**（`git grep` 过 `t12/probe`）。
- **接线复核**：`loadHtmlFromCache()` 先 `syncSessionCookies()`；写入前 `clearAllCookiesSync(true)`（先清后写，避免旧会话独有的名字残留）；逐条 `configCookieSync(url, value, incognito=true, includeHttpOnly=true)`；容器侧 `Web({ ..., incognitoMode: true })`；**日志只打条数/名字/值的长度，值本身（会话凭证）绝不进日志** —— 这条很重要，做对了。
- **ADR-0004 实证**：新进程首次挂载 `incognitoBefore=none`，两轮独立复现（含提交态产物）⇒ 会话不跨进程、不落盘。

**未达成（如实）**：
1. **"会话变化 / 登出"那一条没有设备证据**：不许点「退出登录」、重登需要短信 ⇒ 只能代码 + 单测覆盖（每次挂载现取会话、先清后写、`cookieHeader()` 为空时写 0 条并清空容器存储）。这是**受禁令限制**，不是实现方偷懒，故记 verified-partial。
2. **作业详情只有编译级覆盖**：`HtmlWebView` 是公告详情与作业详情共用组件，公告详情设备复核通过，作业详情未单独跑设备（同一组件、同一路径）。

**记录下来的既有现象（本 ticket 未动，供账号所有者决定）**：
- **登记页在非 incognito（持久）存储里留了 `[XSRF-TOKEN,JSESSIONID]`**（日志 `persistentBefore=entries=2 names=[…]`）。这正是修复前容器误用的那一份、也是 `login_timeout` 的来源之一。**修复后容器不再读它**，但那份残留仍在盘上；ADR-0004 的措辞是"会话 cookie 不落盘"，登记页的收割/清理时机**是既有行为**，本 ticket 明确未改。⇒ 作为技术债登记：*要不要在登出/重登记时清掉非 incognito 存储，需要单独一次决定*。
- `HtmlWebView.ets` 里还有**既存**的「验收第 N 条 / ticket NN」注释（非本次新增）—— 由注释清理那张 ticket 统一处理。
- `check-generated-fresh` 在**新建的 Windows worktree** 里首次跑会假红（CRLF/LF）：main 上已由 `.gitattributes` 根治（`af16874`）；该分支的 worktree 早于那次修复，所以它遇到的是同一个已修问题，提交内容与 HEAD 一致（`git diff` 为空）。

