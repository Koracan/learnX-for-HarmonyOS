# 05: 公告详情内嵌图片不再破图

**What to build:** 公告详情里内嵌的图片（正文里的课程微信群二维码之类）能正常显示，不再出现破图占位。
相对路径的图片地址要被正确解析到站点地址；基础地址来自这次请求的响应地址，不是一个写死的合成路径。

**Blocked by:** None（可立即开始）

**Status:** verified-partial（地址解析与单测达成；设备项「图片可见」未达成，真因转 ticket 12）

- [x] 相对路径的图片地址与链接被解析到正确的站点地址；绝对 http(s) 地址的行为不变
- [x] 基础地址从响应地址推导；同一个公告在不同的请求地址下都能解析正确
- [x] 既有的 `_csrf` 重写条件与追加方式一字未改（两件事在同一段注入脚本里，条件彼此独立）
- [x] 单测：用真实形状的公告正文夹具断言重写结果（沿用既有公告详情测试的写法）
- [ ] 证据：设备上打开那条含二维码的公告，截图里图片可见
## Comments

### 2026-09-13 · 统筹者验收：verified-partial（地址解析修复达成；设备项未达成，真因转 ticket 12）

- 验收清单 1–4 **达成**：相对地址/链接按「这次请求的响应地址」解析到站点；基址从响应地址推导（合成路径已消失，设备 hilog 可见 `loadData issued … baseUrl=https://learn.tsinghua.edu.cn/f/wlxt/kcgg/wlkc_ggb/student/beforeViewXs?…`）；
  `_csrf` 重写条件与追加方式有「逐字节相同」的冻结断言；单测夹具取真机快照那条公告的真实形状。
  单测 `Tests run: 397, Failure: 0, Error: 0`（本轮），四门禁脚本 PASS/OK。
- 验收清单 5（**设备上截图里图片可见**）**未达成**，且 ticket 的**疑因被证伪**（这一步是有价值的证伪，不是失败）：
  - 那条公告的 `img src` 本来就是**绝对 https**；解析后地址与站点都正确，但 `complete=true naturalWidth=0`；
  - 页面内 XHR 同一 URL → `status=200 type=text/html bytes=69 finalUrl=…/f/login_timeout`；同一条 URL 走**应用自己的 HTTP 客户端** → `type=image/jpeg`；
  - ArkWeb 里的 JSESSIONID 与应用内存会话**摘要不同**（名字与长度完全一样，只比名字长度会误判成「同一会话」）；`cookieHeader()` 在生产代码里只有日志消费者。
  ⇒ 真因是 **Web 容器的网络上下文没有当前会话**（子资源请求未鉴权），与地址解析无关。
- **处置**（账号所有者 2026-09-13 裁定）：本 ticket 的地址解析修复**照常入库**（它是真实存在的缺陷修复：相对地址此前会落到写死的合成路径 `/learnoh/notice-detail.html` 下）；破图真因**另立 ticket 12**（走 A′：`incognitoMode(true)` + `configCookieSync(url, value, incognito=true, includeHttpOnly=true)`，会话只进内存态，不违反 ADR-0004）。