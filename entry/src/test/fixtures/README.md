# 测试夹具（entry/src/test/fixtures）

本目录的字符串常量是公告 / 作业 / 文件三域解析用例的输入。**每一类都标注了成色**，
不要把它们统称为"真实响应样本"。

## 成色分类

| 夹具 | 成色 | 依据 |
| --- | --- | --- |
| `REAL_ID_LOGIN_HTML` | **抓取**（1 份） | 开发机上 `Invoke-WebRequest 'https://id.tsinghua.edu.cn/f/login' -UseBasicParsing` 取回 14719 字节后原样保存（仅做换行规范化）。页面公开、无需登录。它同时含 ticket 06 所需 `#sm2publicKey`。 |
| `NOTICE_DETAIL_ML10_HTML` / `NOTICE_DETAIL_PREVIEW_HTML` | **反推** | 由参考实现 `extractAttachment` / 公告附件正则，加上 thu-learn-lib `parseNotificationDetail` 的 `result('.ml-10').attr('href')` + `wjid` 选择器反推构造。 |
| `NOTICE_LIST_RESPONSE_JSON` / `NOTICE_LIST_RESULTS_LIST_JSON` | **反推** | 字段名（ggid / bt / fbrxm / fbsj / fbsjStr / jzsj / sfqd / sfyd / fjmc / fjbt / ggnr）逐条取自参考实现 `fetchNotices` 的映射；取值形状参照 `reference/learnOH-old/src/data/mock.ts` 的公告条目。 |
| `ASSIGNMENT_DETAIL_FOUR_BLOCKS_HTML` / `ASSIGNMENT_DETAIL_ONE_BLOCK_HTML` | **反推** | 四个 `div.list.fujian.clearfix` 块的顺序依据 thu-learn-lib `parseHomeworkAtUrl`（`fileDivs[0..3]` → 附件/答案/已提交/成绩），与参考实现一致。 |
| `ASSIGNMENT_LIST_RESPONSE_JSON` / `ASSIGNMENT_DESCRIPTION_RESPONSE_JSON` | **反推** | 字段名（xszyid / zyid / wlkcid / bt / jzsj / bjjzsj / sfbj / zywcfs / zytjfs / scsj / cj / jsm / pynr）取自参考实现 `fetchAssignments`；取值形状参照 `mock.ts` 的作业条目。 |
| `FILE_LIST_RESPONSE_JSON` | **反推** | 字段名（kjxxid / wjid / bt / ms / fileSize / scsj / wjlx / isNew）取自参考实现 `fetchFiles`；取值参照 `mock.ts` 的文件条目。 |
| `RAW_*` | **反推** | 同上，单条记录形式。 |

反推的规则：**只用两个来源**——参考实现 `DataProcessorModule.ts` 的正则与字段映射，
以及 thu-learn-lib（cheerio 选择器）里对应的字段/块序。没有臆造第三种结构。
反推夹具的断言只覆盖"解析器对这些结构的判定"，不覆盖"站点今天是否真的这样返回"。

## 为什么没有三域的真实响应

三域列表接口与详情页**需要登录会话**（开发机上匿名请求返回 403）。用户已同意
"稍后本人手动登录，其余由我们完成"，因此：

- 现在能证明的：解析、排序、Base64 容错、multipart 组装（本目录夹具 + 单测）；
- 尚不能证明的：三域在真实会话下的条目数与耗时（代码与 `data.* fetched ... items=.. elapsedMs=..`
  日志埋点已就绪，登录后只需看日志，见 ticket 05 Comments 的"待账号验证"一节）。

## 不用资源文件的原因

Hypium 用例在设备进程里跑，读工程内文件要么走 `resourceManager` + rawfile 打包，
要么走沙箱路径，都会把"解析正确性"和资源管线耦合在一起。常量字符串让用例自足；
代价是改 HTML 要同步改断言，这一点在 `ContentItemFixtures.ets` 头部也写明了。
