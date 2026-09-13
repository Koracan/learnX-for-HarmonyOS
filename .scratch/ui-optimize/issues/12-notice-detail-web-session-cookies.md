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

**Status:** ready-for-agent

- [ ] 那条含二维码的公告，**设备截图上图片可见**（同状态 before/after；before 是破图，见 `.scratch/ui-optimize/evidence/t05/before-notice-detail-broken-qr.png`）
- [ ] 只写内存态：给出"进程重启后 ArkWeb 里不残留可用会话 cookie"的可复核判据（例如 `fetchCookieSync(url, incognito=true)` 为空）
- [ ] `HttpOnly` 的 JSESSIONID 确实被写入（否则仍是 `login_timeout`）；写入失败要有可读日志，不静默
- [ ] 会话变化跟着变：重登后 Web 容器读到新会话；**登出后 Web 容器不再持有可用会话**
- [ ] 影响面受控：公告详情、作业详情这些走 `HtmlWebView` 的页面行为不回归；**不要破坏登记页**（`EnrollmentWebView` 现有的 `clearAllCookiesSync` / `fetchCookieSync` 收割逻辑）
- [ ] 只对 learn 源生效，外部 CDN（katex/darkreader）不受影响
- [ ] 单测：cookie 串拆分与写入参数构造做成**纯函数**，钉住输入 → 输出；`cookieHeader()` 为空时不写任何 cookie
- [ ] 硬约束：`domain/` 必须保持零平台依赖（`check-domain-purity` 绿）
- [ ] 证据：设备截图（二维码可见）+ 重启后不可用的判据 + 同状态 before/after
