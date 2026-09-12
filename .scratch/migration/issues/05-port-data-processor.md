# 05: 移植数据处理器 + 解析单测

**What to build:** 把参考实现中以 ArkTS 写成的批量抓取与解析逻辑移植进新分层，去掉它对 RN 运行时的四处耦合（TurboModule 基类、模块上下文、设备事件、后台化），改为普通类与普通回调；解析与排序可单测。这是后续四个内容域的共同地基。

**Blocked by:** 01（工程分层 + 日志门面 + 主题令牌）

**Status:** verified-partial — 2 项凭据门控未关闭（见 Comments 末尾「未关闭项」）

- [ ] 公告 / 作业 / 文件三个域的批量抓取与解析在设备上跑通，日志给出每域条目数与耗时 —— **未关闭**：需真实会话（ticket 06）+ 触发入口，且需用户手动登记一次
- [x] 作业详情的四类附件（附件 / 答案 / 已提交 / 成绩）解析正确
- [x] 公告正文的 Base64 解码正确，含异常输入的容错 —— **含设备侧复验**（生产通道 `Base64Helper.decodeSync` 在模拟器上 `platform == expected`）
- [x] 解析与排序函数有单测
- [ ] 单测使用**真实响应样本**作夹具 —— **未关闭**：16 份夹具全为反推，三域无真实样本
- [x] 上传用的 multipart 组装有单测（边界、字段顺序、文件名编码）

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
- [x] **解析与排序函数有单测** —— 44 条（domain.NoticeParser 13、
  domain.AssignmentParser 9、domain.FileParser 4、data.Multipart 6、data.fetch 7、
  domain.Utf8 4、core.textChannels 1）。**夹具成色**：抓取 1 / 自带 0 / 反推 16（详见
  `entry/src/test/fixtures/README.md`）。唯一"抓取"是公开的 ID 登录页（14719 字节，
  开发机上 `Invoke-WebRequest` 取回），用作**反例**证明解析器不在真实站点 HTML 上误报。
  三域列表响应**没有真实样本**（需登录），16 份全部是反推——它们验的是"结构与字段映射"，
  **不验"站点今天真实返回什么"**。真实样本那半边由账号门控，见下面单独拆出的未关闭项。
- [ ] **单测使用真实响应样本作夹具（本条未满足，验收时改判）** —— 三域列表响应需登录，因此
  16 份夹具**全部为反推**、自带 0 份；唯一真实样本是公开的 ID 登录页（14719 字节），且只用作反例。
  这不只是"样本少一点"的问题：反推夹具能证明「实现与我们对参考实现的理解一致」，**不能证明
  「我们对参考实现的理解与站点今天真实返回的形状一致」**——后者只有验收第 1 条（带会话在设备上
  真跑）才能证。所以在拿到真实响应之前，本 ticket 的解析结论只覆盖到"结构契约"这一层。
  待用户手动登录后抓取真实响应回填夹具，再复核本条。
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

### 验收复核（统筹，2026-09-12，模拟器口径）

**我独立复跑了全量单测**：删掉 `entry/.test` 后强制全量重跑（`--no-incremental`），
避免命中 hvigor 的 up-to-date 缓存（第一次没删目录时 6 秒返回、其实没跑）。
`UnitTestArkTS` → `GenerateUnitTestResult`（`.dsh/logs/accept05-test2.log`），
`test_result.txt` 重新生成于 02:47:51：**15 个类，TOTAL=101 FAIL=0**，与申报一致。
`check-domain-purity.mjs` 我另跑一次 → PASS / EXIT=0。

**验收时改判一条**：原第 4 条申报为 `[x]`，但其区分性要求是「使用**真实响应样本**作夹具」——
本 ticket 实际是抓取 1 / 自带 0 / **反推 16**，三域均无真实样本。已在上方拆成两条，
「有单测」记 `[x]`、「真实响应样本」记 `[ ]` 并挂到手动登录之后。
这不是"样本少一点"的程度问题：反推夹具与实现同源同误解，**无法证伪**「我们对站点返回
形状的理解本身是否正确」，这一层只有验收第 1 条能覆盖。

### 待办（验收发现，与设备复验一并处理，不必现在动手）

1. `entry/src/test/TestHelpers.ets` 两处注释互相矛盾：文件头说「Base64 → 字节仍走平台
   `util.Base64Helper`（这部分在本环境工作正常）」，第 74 行附近却说「本环境里 `@ohos.util`
   不可用」。而本 ticket 的结论是 Base64Helper **也**返回空值。请按**实测到的具体 API** 分别写清
   （哪个正常、哪个返回空/undefined、怎么观测的）——该文件会被当证据引用，含糊说法会误导后来人。
2. `TestHelpers.deviceBase64Decoder` 已**无任何调用点**（全仓 grep 只在定义处出现），且其注释
   声称「与生产一致」会误导。要么删除，要么改名为设备专用探针并注明只在设备上有效。
3. `domain/parse/Utf8.ets` 属于 `spec.md` 第 2 节新增的「纯叶子工具」例外（默认 `core` 不得依赖
   `domain`，纯叶子工具例外、放在 `domain/` 下以受纯度检查保护）。请在文件头注明它属于该例外，
   并确认它无平台 import、无领域实体 import。
4. **设备窗口可用时**：用一条 `data.fetch` 用例复验平台 `util.Base64Helper.decodeSync` 通道
   （本地单测环境不可用）。这一条需要独占设备，先向统筹申请窗口。

### D4 设备复验：平台 Base64 通道（2026-09-12，模拟器 Pura 90 / 127.0.0.1:5555）

**结论：平台上该通道工作正常**——local 单测环境里解不出字节，纯粹是该环境对 `@ohos.util` 的桩实现所致，
不是生产代码的问题。生产路径（`core/codec/TextCodec.decodeBase64Text` → 平台 `Base64Helper.decodeSync`
→ 纯 UTF-8 解码）与预期一致。

走法（临时探针，一轮；遵守 AGENTS「取证要点」的自证生效要求）：

1. 临时文件 `core/codec/TextCodecProbe.ets`（`TEXT_CODEC_EVIDENCE=true`）+ `EntryAbility.onCreate`
   一行调用；探针**无论开关取值都先打一行 `PROBE-SWITCH`**，因此"没有 PROBE 行"才可判定为
   "探针没跑到"，而不会被误读成"现象不存在"。
2. `devecocli run --device 127.0.0.1:5555`（BUILD SUCCESSFUL → App installed successfully →
   start ability successfully）→ `devecocli log --from 10m --bundle-name com.koracan.learnOH`。
3. 原始 hilog（`.dsh/logs/ticket05-evidence-hilog.log`，域 A04c4f = 0x4C4F）：
```
09-12 03:45:48.486  7658  7658 I A04c4f/evidence.textcodec: ... PROBE-SWITCH switch=on
09-12 03:45:48.487  7658  7658 I A04c4f/evidence.textcodec: ... PROBE base64 input=PHA+5Yqh platform="<p>务" expected="<p>务" match=true threw=false
```
   - `switch=on`：开关生效值自证（排除"改了但没生效"）。
   - `platform="<p>务"` = `expected`（expected 由 Node `Buffer` 独立算出）⇒ **match=true**。
4. 复原并核对：`git checkout -- entryability/EntryAbility.ets`、删除探针文件；
   `git status --porcelain -- entry/src/main/ets/entryability` 为空、探针文件不存在；
   全量重跑（删 `entry/.test`）`Tests run: 101, Failure: 0, Pass: 101`。

**仍未单独测出**：平台 `util.TextDecoder.decodeWithStream/decodeToString` 在设备上的行为。
这一项**已不再重要**：生产路径的"字节 → 文本"改用 `domain/parse/Utf8.ets` 的纯实现，
`TextDecoder` 不在任何生产路径上（只有探针会碰它）。因此不再为它排取证窗口。

### D 前三件的收尾（同一轮）

- `TestHelpers.ets`：注释改为**逐 API 实测表**（TextEncoder 返回空数组 / Base64Helper 解不出字节 /
  TextDecoder 未单独测出），删除了原先那句把推断写成实测的描述；死代码 `deviceBase64Decoder`
  改名 `platformProbeBase64Decoder` 并注明"只在设备上有效、不参与断言"。
- `domain/parse/Utf8.ets`：文件头注明属 spec 第 2 节「纯叶子工具」唯一例外（core 允许引用它），
  自查写明**零 import**。
- `Utf8.test.ets`：探针用例名改为 `platformTextChannelProbe`，避免"名字像断言、实际不断言"。

**最终单测取证**：`HEAD=3dc63b8473a681029645f51f01d8e64d7d56168d` + 本次三个未提交文件的改动，
全量 `Tests run: 101, Failure: 0, Error: 0, Pass: 101`（`.dsh/logs/ticket05-test5.log`，
先删 `entry/.test` 再跑，非缓存命中）。per-class：
domain.Semester 9 / ui.theme.Tokens 5 / core.LogFormat 4 / core.i18n 10 / core.i18n.DateTimeUtil 14 /
domain.NoticeParser 13 / domain.AssignmentParser 9 / domain.FileParser 4 / data.Multipart 6 /
data.fetch 7 / features.notices.NoticeOrder 8 / NoticeRepository 3 / NoticeListStore 4 /
domain.Utf8 4 / core.textChannels 1。

### 统筹验收（2026-09-12，模拟器口径）→ Status: verified-partial

**结论：实现与本地证据部分通过；2 项凭据门控未关闭，因此【不】标 `verified`。**

#### 我独立重跑的（在 `558bdca` 上）

| 检查 | 命令 | 结果 |
| --- | --- | --- |
| 全量单测 | 删 `entry/.test` 后 `hvigorw … test --no-incremental` | 15 类 **TOTAL=101 FAIL=0**（`test_result.txt` 03:49:08 重新生成） |
| 探针残留 | `git ls-files` / `git grep TEMP-EVIDENCE HEAD` / `git show HEAD:EntryAbility.ets` | 三项均无命中；`deviceBase64Decoder` 在 `entry/` 下零出现 |
| 提交范围 | `git show --stat 558bdca` | 4 个文件（3 源文件 + ticket），无探针、无 EntryAbility |
| 工作区 | `git status --porcelain` | 空 |
| 领域纯度 | `check-domain-purity.mjs` | PASS / exit 0 |

#### D4 设备复验：我核对了**原始 hilog**，不采信转述

我自己读 `.dsh/logs/ticket05-evidence-hilog.log`，两行原文：
```
09-12 03:45:48.486 … A04c4f/evidence.textcodec: … PROBE-SWITCH switch=on
09-12 03:45:48.487 … A04c4f/evidence.textcodec: … PROBE base64 input=PHA+5Yqh platform="<p>务" expected="<p>务" match=true threw=false
```
- `switch=on` 是**自证生效**，排除"改了但没生效"（该要求源自 03 那轮踩到的坑，见 AGENTS.md「取证要点」）。
- `platform == expected`，expected 由 Node `Buffer` 独立算出 ⇒ **平台 Base64 通道在设备上正常**；local 解不出字节确系该环境对 `@ohos.util` 的桩实现。
- 这条**关闭**了原待办 4，并把"生产路径依赖平台 `Base64Helper`"这个设计决策从**未验证假设**变成**已验证**——这是本轮最实质的收获。

#### 我另外核了 `TextDecoder` 是否还需占窗口：**不需要**，同意 05 判断

`entry/src/main/ets` 全量搜索：生产代码里的平台编解码只剩 `TextCodec.ets:21` 的 `util.Base64Helper`；**`util.TextDecoder` 与 `util.TextEncoder` 已不在任何生产路径上**（`TextEncoderFn` 只是注入式编码器的类型别名，实现是纯函数）。所以平台 `TextDecoder` 的行为不再影响生产，为它再占一次设备窗口不值得。**此判定记录在案**：若将来有人把"字节 → 文本"改回平台实现，必须重新打开这一项。

#### 未关闭项（**不要把本 ticket 当成全绿**）

1. 验收第 1 条「三域批量抓取在设备上跑通 + 每域条目数与耗时日志」——需 ticket 06 的真实会话与触发入口，且需用户手动登记一次。能力与日志埋点已就绪（`data.fetch` 7 条断言了 `items=`/`elapsedMs=` 日志文本）。
2. 「使用**真实响应样本**作夹具」——抓取 1（公开 ID 登录页，仅作反例）/ 自带 0 / **反推 16**。反推夹具与实现同源同误解，只能证"结构契约"，**不能证**站点今天真实返回的形状。

> 这两项都由**账号**门控，不是实现缺陷。用户手动登录后回填即可关闭。

#### 一处遗留的误导性注释（已请 05 修）

`core/codec/TextCodec.ets:6-8` 仍写着「Base64 → 字节仍走平台 `util.Base64Helper`（**这部分在本环境工作正常**）」，并称「平台 `decodeWithStream` 在单测环境里返回 undefined」。
前者与本次设备复验结论**相反**（设备正常、local 不正常），后者是 05 自己已撤回的**推断**。同一类错误我已要求在 `TestHelpers.ets` 修过，这里漏了——**同源错误要一次修干净**，否则下一个读这份文件的人会得出相反结论。

### 边界说明（2026-09-12，由 ticket 12 带入）—— 你已验收的两个资产被改了，但你的证据仍然成立

ticket 12 在**真实数据**上发现：站点把作业的 `jzsj`（截止时间）下发成 **epoch 毫秒数字**（2025-2026 春季学期实测 57/57 条，
例 `1780243140000` = 2026-05-31 23:59 本地时间），而 `parseTimestamp` 直接对入参调 `raw.trim()` ⇒
`undefined is not callable` ⇒ 整页课程/作业失败。参考实现在**渲染层**用 `dayjs(deadline)` 处理（dayjs 对数字按毫秒解释，
`AssignmentCard.tsx:103-108`），所以这是**我们的移植在真实数据上缺了一格**，不是站点异常。

**变了什么**（提交 `2a776d2`）：

- `domain/parse/Text.ets`：`parseTimestamp` / `compareTimeDesc` / `compareByTimeThenIdDesc` 的入参放宽为 `string | number | undefined`；
  **有限数字按 epoch 毫秒返回**，其它非字符串 = 不可解析（等价 dayjs 的 Invalid Date）。
- `domain/parse/AssignmentParser.ets`：新增 `normalizeDeadline`，`deadline` 由 `text(raw.jzsj)` 改成 `normalizeDeadline(text(raw.jzsj))`
  （非字符串 → 本地 `YYYY-MM-DD HH:mm`；**字符串一律原样保留**）。
- 诊断侧：`data/remote/AssignmentsFetcher` 的汇总行多一个 `nonStringDeadlines=<n>`，并只对第一条打一行 warn。

**你的证据还成立到哪一步**：**全部成立**。字符串入参的行为一字未改（`AssignmentParser.test.ets` 里"字符串截止时间一律原样保留"
那条断言就是为它钉的）；本 ticket 验收第 1 条的三域抓取与 D4 的 Base64 设备复验都**不经过**数字分支。
**可观察量转移到哪里**：`data.assignments` 的 `nonStringDeadlines` 字段（真实数据上应等于条目总数）；
界面上截止时间的正确显示见 ticket 12 的 E3 截图与 `Assignment.deadline` 的既定形状。
**本 ticket 的 `verified-partial` 不变**（两项仍由账号门控）。

**给 ticket 10 读者的一句话**：作业卡片要显示截止时间时**直接读 `Assignment.deadline`**（已是 `YYYY-MM-DD HH:mm` 字符串），
不要再自己 `Number(...)` 或假设它是字符串。