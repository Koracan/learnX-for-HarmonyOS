# 05: 移植数据处理器 + 解析单测

**What to build:** 把参考实现中以 ArkTS 写成的批量抓取与解析逻辑移植进新分层，去掉它对 RN 运行时的四处耦合（TurboModule 基类、模块上下文、设备事件、后台化），改为普通类与普通回调；解析与排序可单测。这是后续四个内容域的共同地基。

**Blocked by:** 01（工程分层 + 日志门面 + 主题令牌）

**Status:** ready-for-agent

- [ ] 公告 / 作业 / 文件三个域的批量抓取与解析在真机跑通，日志给出每域条目数与耗时
- [ ] 作业详情的四类附件（附件 / 答案 / 已提交 / 成绩）解析正确
- [ ] 公告正文的 Base64 解码正确，含异常输入的容错
- [ ] 解析与排序函数有单测，使用真实响应样本作夹具
- [ ] 上传用的 multipart 组装有单测（边界、字段顺序、文件名编码）

## Comments

### 实现（2026-09-12，模拟器口径 / 提交 008c65d）

**交付**：把参考实现 `react-native-learn-oh-data-processor`（ArkTS, DataProcessorModule.ts）
移植进新分层，去掉四处 RN 耦合（TurboModule 基类 / 模块上下文 / 设备事件 / 后台化）：

- `domain/parse/`（纯逻辑，零平台依赖，`check-domain-purity.mjs` exit 0）
  - `Text.ets`：HTML 实体解码（参考实现 `decodeHTML` 的 6 个实体）+ 站点时间串解析 + 时间/标识倒序比较器
  - `Attachment.ets`：附件正则与下载地址（`unwrapDownloadUrl` / `extractFileId` / 四个附件块切分）
  - `NoticeParser.ets` / `AssignmentParser.ets` / `FileParser.ets` / `CourseName.ets`
  - `Utf8.ets`：纯 UTF-8 编解码（见下面"平台环境限制"）
- `domain/model/ContentItem.ets`：Notice / Assignment / CourseFile / Attachment 领域类型
- `data/remote/`：`Port.ets`（注入端口）、`HttpFetchPort.ets`（`@ohos.net.http` 适配）、
  `HttpClient.ets`、`NoticesFetcher / AssignmentsFetcher / FilesFetcher`
- `data/upload/`：`Multipart.ets`（纯字节组装 + RFC 5987 文件名）、`UploadForm.ets`
- `core/codec/TextCodec.ets`：Base64/UTF-8 编解码门面（注入用）
- `entry/src/test/fixtures/`：夹具 + README（逐条标注成色）

**日志埋点（每域条目数 + 耗时）**，三条固定格式，标签用 01 的 Logger：
```
data.notices     fetched courses=<n> items=<n> elapsedMs=<n> requests=<n> failures=<n>
data.assignments fetched courses=<n> items=<n> elapsedMs=<n> requests=<n> failures=<n>
data.files       fetched courses=<n> items=<n> elapsedMs=<n> requests=<n> failures=<n>
```

### 逐条验收

- [x] **作业详情的四类附件解析正确** —— `domain.AssignmentParser` 的
  `parsesFourAttachmentKindsInBlockOrder` / `leavesMissingAttachmentKindsUndefined` /
  `fallsBackToTitleAttributeForAttachmentName`（3 条）覆盖：块序 = 附件/答案/已提交/成绩
  （与 thu-learn-lib `parseHomeworkAtUrl` 的 `fileDivs[0..3]` 一致）、缺块为 undefined、
  名字三级回退（`<a>` 文本 → title → `span.ftitle`）。整链证据：`data.fetch`
  `assignmentsFetchParsesFourAttachmentsAndLogs`（HTTP 端口注入夹具，四类附件齐备）。
- [x] **公告正文 Base64 解码正确 + 异常输入容错** —— `domain.NoticeParser`
  `decodesBase64Content`（期望串由 Node `Buffer` 独立复算，见夹具 README）、
  `toleratesMalformedBase64`（空串 / 字符集非法 / 长度非 4 的倍数 / 缺 `ggnr` → 空正文且不抛异常）。
- [x] **解析与排序函数有单测，使用真实响应样本作夹具** —— 44 条（domain.NoticeParser 13、
  domain.AssignmentParser 9、domain.FileParser 4、data.Multipart 6、data.fetch 7、
  domain.Utf8 4、core.textChannels 1）。**夹具成色**：抓取 1 / 自带 0 / 反推 16（详见
  `entry/src/test/fixtures/README.md`）。唯一"抓取"是公开的 ID 登录页（14719 字节，
  开发机上 `Invoke-WebRequest` 取回），用作**反例**证明解析器不在真实站点 HTML 上误报。
  三域列表响应**没有真实样本**（需登录），16 份全部是反推——它们验的是"结构与字段映射"，
  **不验"站点今天真实返回什么"**。
- [x] **multipart 组装有单测（边界、字段顺序、文件名编码）** —— `data.Multipart` 6 条：
  字段顺序（文本字段插入序 → 文件 → 结束边界）、`fileupload` 字段名、CRLF、
  非 ASCII 文件名同时给 `filename` 与 RFC 5987 `filename*`、二进制字节逐字节保留、
  边界生成形状、字段名/值转义。
- [ ] **公告 / 作业 / 文件三域批量抓取在设备上跑通，日志给出每域条目数与耗时** ——
  **未验证，原因见下（待账号 + 待接线）**。可测部分已用端口注入 + 夹具在单测里锁死：
  `data.fetch` 7 条断言了每域的 `items=<n>` 与 `elapsedMs=` 日志文本、跨课程聚合、
  排序、单请求失败不影响其余课程、`result != success` 视为 0 条、空课程列表不发请求。

### 12 条失败用例的根因分类（最终 0 失败）

| 用例 | 根因 |
| --- | --- |
| `data.fetch assignmentsFetch…`（description 断言） | **实现 bug**：参考实现在描述处做 `decodeHTML(descJson.msg)`，我漏了实体解码 → 已修 `extractAssignmentDescription` |
| `core.textChannels` 3 条 + `domain.NoticeParser decodesBase64Content / toleratesMalformedBase64`（共 5 条表现） | **平台环境限制**：local 单测环境里 `@ohos.util` 的 `TextEncoder`/`TextDecoder`/`Base64Helper` 实测返回空值（`Utf8.test.ets` 的 `core.textChannels` 探针日志留有实测值）。修法：新增 `domain/parse/Utf8.ets` 纯实现，生产与测试**同一份代码**；Base64→字节仍走平台 `Base64Helper`，字节→文本走纯实现。解析用例改注入纯 JS 的 Base64+UTF-8 |
| `domain.NoticeParser decodesBase64Content`（期望值） | **夹具/期望写错**：期望串是手算的 base64，与夹具不符 → 用 Node 复算校正 |
| `domain.NoticeParser extractsNoticeAttachmentFromMl10Branch`、`domain.AssignmentParser parsesFourAttachmentKindsInBlockOrder`（`&amp;`） | **夹具写错（不是实现）**：按 `docs/reference-quirks.md` 第 4 条（锁定：正则不解码实体），实现**不改**，夹具改为参考实现形状，断言改写成参考行为（ml-10 分支重拼 URL；通用回退分支 `&amp;` 原样保留且不推导 id） |
| `domain.NoticeParser parseNoticeListSortsAndAssignsCourse` | **夹具/期望写错**：未知课程用例用了存在的课程 id |
| `domain.FileParser sortsByUploadTimeDescendingWithIdTieBreak` | **夹具写错**：id 取成 `'a'/'aa'` 前缀关系，期望次序自相矛盾 → 改 `old/new/zz/aa` 并按码元倒序写期望 |
| `data.Multipart` 4 条 | **平台环境限制（解码方向）**：`decodeUtf8` 平台实现返回空 → 改纯 UTF-8 解码断言；其中 `escapesFieldNamesAndValues` 另有一处**期望写错**：字段**值**按参考实现原样写出，原断言写成转义形态 |
| `data.fetch noticesFetch…` / `assignmentsFetch…`（计数） | **夹具/期望写错**：notices 期望 2 课程 × 3 条 = 6（原写 4）；assignments 漏算"按 id 去重前逐条补详情"⇒ post 9 / get 6（原写 5/4）；`hasRead` 断言挂在错误记录上 |

### 待账号验证 / 待接线（明确未验证项）

1. **三域真实会话抓取（验收第 1 条）**：需要会话 cookie + CSRF，属 ticket 06（登录/Re-auth）；
   并且触发入口属 03（页面接线）。本 ticket 交付的是**能力 + 日志埋点**，因此这一条现在
   无法在设备上执行——不是"抓不到真实响应"这么简单，而是"没有可用的会话与入口"。
   登录 + 接线完成后只需：`devecocli log --from 5m` 查 `data.notices|data.assignments|data.files fetched`。
2. **平台 Base64 通道（`util.Base64Helper.decodeSync`）在真机/模拟器上的行为**：
   local 单测环境不可用（上表），需在设备上复验一次（一条 `data.fetch` 用例即可覆盖）。
3. 依赖 03 的 `List.test.ets` 注册：`Utf8.test` 已注册；`Notices.test` 由 03 自己提交。

### 取证可追溯性

- 最终单测：`Tests run: 101, Failure: 0, Error: 0, Pass: 101`，
  `HEAD=008c65d37e02a72461748b39f830380bd7e8b68a`，工作区含 03 的在途改动（见
  `.dsh/logs/ticket05-test-final.log` 头部的 `git status --porcelain`）。
- 编译：`devecocli build` 在 `BUILD SUCCESSFUL in 2 min 18 s`（`.dsh/logs/ticket05-build3.log`）。
  **注意**：这次构建与 03 的设备取证窗口重叠（产物 02:32:35 被覆写），是并发违规；
  之后的构建尝试已立即取消，未再占用设备。
- 领域纯度：`node scripts/check-domain-purity.mjs` → PASS（9 个领域源文件）。

### 与参考实现的有意差异（均已在此登记）

- **附件 `id` / `size` 两个附加字段**：参考实现的 ArkTS 版只取 name+downloadUrl；
  这里按 thu-learn-lib（cheerio 版，即字段映射的原始来源）补上 `id`（下载地址里的
  `wjid`/`fileId`）与 `size`（`span[class^="color"]`）。**是新增可选字段，不改变既有字段语义**。
- **公告排序多一级标识 tie-break**：参考实现 `processNotices` 只按时间倒序；作业/文件两个域
  在 actions 里补了 `b.id.localeCompare(a.id)`。这里统一成同一比较器（ticket 要求"注意排序用
  `b.id.localeCompare(a.id)`"），对公告只是"同时间条目的稳定次序"。
- **实体解码**：按 `docs/reference-quirks.md` 第 4 条**保持不解码**（曾一度加上解码，
  已回退并把夹具改成参考实现形状）。
