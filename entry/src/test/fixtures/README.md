# 测试夹具（entry/src/test/fixtures）

本目录的字符串常量是公告 / 作业 / 文件三域解析用例的输入。**每一类都标注了成色**，
不要把它们统称为"真实响应样本"。

## 成色汇总（17 份夹具 + 1 个常量）

| 成色 | 份数 | 说明 |
| --- | --- | --- |
| **抓取** | **1** | `REAL_ID_LOGIN_HTML` |
| **自带** | **0** | `reference/learnOH-old/src/data/mock.ts` 只用于**核对取值形状**，没有复制任何字节 |
| **反推** | **16** | 由参考实现的正则 / 字段映射 + thu-learn-lib 的 cheerio 选择器反推构造，**非抓取** |

## 逐条

| 夹具 | 成色 | 依据 |
| --- | --- | --- |
| `REAL_ID_LOGIN_HTML` | **抓取** | 开发机上 `Invoke-WebRequest 'https://id.tsinghua.edu.cn/f/login' -UseBasicParsing` 取回 **14719 字节**后原样保存（仅换行规范化）。页面公开、无需登录，含 ticket 06 所需 `#sm2publicKey`。用例里当作**反例**：三域解析器在真实站点 HTML 上不得凭巧合命中。 |
| `NOTICE_DETAIL_ML10_HTML` | 反推 | 附件链接带 `class="ml-10"`、`href` 里是裸 `&`。形状取自参考实现 `fetchNotices` 的 ml-10 正则 + thu-learn-lib `result('.ml-10').attr('href')`。 |
| `NOTICE_DETAIL_ML10_AMP_HTML` | 反推 | 同上，但 `href` 里是 HTML 实体 `&amp;`：用于锁定参考实现"不解码实体但 `wjid` 仍能取到"的行为。 |
| `NOTICE_DETAIL_PREVIEW_HTML` | 反推 | `openNewWindow?...&downloadUrl=<percent-encoded>`，走参考实现的 `unwrapDownloadUrl`。 |
| `NOTICE_DETAIL_GENERIC_AMP_HTML` | 反推 | 无 ml-10、`href` 含 `&amp;`：锁定**通用回退分支**把 `&amp;` 原样留在 downloadUrl 且不推导 id。 |
| `NOTICE_LIST_RESPONSE_JSON` / `NOTICE_LIST_RESULTS_LIST_JSON` | 反推 | 字段名（ggid / bt / fbrxm / fbsj / fbsjStr / jzsj / sfqd / sfyd / fjmc / fjbt / ggnr）逐条取自参考实现 `fetchNotices` 的映射；取值形状参照 `mock.ts` 的公告条目。 |
| `ASSIGNMENT_DETAIL_FOUR_BLOCKS_HTML` / `ASSIGNMENT_DETAIL_ONE_BLOCK_HTML` | 反推 | 四个 `div.list.fujian.clearfix` 块的顺序依据 thu-learn-lib `parseHomeworkAtUrl`（`fileDivs[0..3]` → 附件/答案/已提交/成绩），与参考实现一致。 |
| `ASSIGNMENT_LIST_RESPONSE_JSON` / `ASSIGNMENT_DESCRIPTION_RESPONSE_JSON` / `ASSIGNMENT_DESCRIPTION_FAILURE_JSON` | 反推 | 字段名（xszyid / zyid / wlkcid / bt / jzsj / bjjzsj / sfbj / zywcfs / zytjfs / scsj / cj / jsm / pynr）取自参考实现 `fetchAssignments`。 |
| `FILE_LIST_RESPONSE_JSON` | 反推 | 字段名（kjxxid / wjid / bt / ms / fileSize / scsj / wjlx / isNew）取自参考实现 `fetchFiles`。 |
| `SESSION_EXPIRED_JSON` | 反推 | 三域列表接口的失败形态（`result != success`）。 |
| `RAW_NOTICE_WITH_BASE64` / `RAW_ASSIGNMENT` / `RAW_COURSE_FILE` | 反推 | 单条记录形式。 |

反推规则：**只用两个来源**——参考实现 `DataProcessorModule.ts` 的正则与字段映射，
以及 thu-learn-lib（cheerio 选择器）里对应的字段/块序。没有臆造第三种结构。

## 两个必须知道的约束

**1. HTML 实体不解码是参考实现的锁定行为**（`docs/reference-quirks.md` 第 4 条）。
所以夹具**不写"人眼期望"的形状**：`&amp;` 要么原样保留、要么按字符类匹配不上而取不到，
两种结果都是正确的移植行为；对应用例的断言写的就是这两种结果。
不要为了拿到 `&` 给实现加解码。

**2. Base64 期望值来自独立复算**：`RAW_NOTICE_WITH_BASE64.ggnr` 等字段的期望文本，是用
Node 的 `Buffer.from(s,'utf8').toString('base64')`（与 ArkTS 无关的独立实现）反向算出的；
曾经的期望串是手算的且算错了——单测的期望值必须来自可复算的来源。

## 为什么没有三域的真实响应

三域列表接口与详情页**需要登录会话**（开发机上匿名请求返回 403）。用户已同意
"稍后本人手动登录，其余由我们完成"，因此：

- 现在能证明的：解析、排序、Base64 容错、multipart 组装（本目录夹具 + 单测）；
- 尚不能证明的：三域在真实会话下的条目数与耗时（代码与 `data.* fetched ... items=.. elapsedMs=..`
  日志埋点已就绪，登录后只需看日志，见 ticket 05 Comments 的"待账号验证"一节）。

## 不用资源文件的原因

Hypium 用例在运行环境里读工程内文件要么走 `resourceManager` + rawfile 打包，要么走沙箱路径，
都会把"解析正确性"和资源管线耦合在一起。常量字符串让用例自足；代价是改 HTML 要同步改断言，
这一点在 `ContentItemFixtures.ets` 头部也写明了。

## 另一个环境限制

local 单测环境里 `@ohos.util` 的文本能力实测不可用（TextEncoder/TextDecoder/Base64Helper
返回空值，见 `Utf8.test.ets` 的 `core.textChannels` 探针日志）。因此解析用例注入的是
`TestHelpers` 里**纯 JS** 的 Base64 + UTF-8 实现；平台通道（`Base64Helper`）属于设备侧待复验项。
