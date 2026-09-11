# ticket 04 取证（公告详情 + HTML 渲染，Mock）

**设备口径**：全部证据来自**模拟器** Pura 90（`127.0.0.1:5555`，HarmonyOS 6.1.0(23)）。
真机 `3FBYB25407201890`（MatePad Air，API 24）**未连接**，按 AGENTS.md 归 ticket 18 之前的一次性复验。

**源码版本**：见 `revision.txt`（HEAD + 脏工作区哈希 + 设备上装包版本）。工作区取证时是脏的，
所以这批文件是**过程证据**，不对应任何单个提交。

**取证期的两个开关**（提交态 false，见 `revision.txt`）：`EVIDENCE_DETAIL_CONTENT`、
`EVIDENCE_DARK_TOGGLE`。开启后详情页顶部会多一个 `dark=` + `toggle` 控制条，所有详情截图里都能看到它。

## 逐条验收 → 证据文件（两个论断不复用同一份文件）

| 验收项 | 结论 | 证据文件 |
| --- | --- | --- |
| 1 标题/副标题由进入时的参数决定 | 达成（按参考实现：**发布者 + 绝对时间，不显示课程名**） | `04-detail-light-zh.png` + `04-detail-light-layout.json`（`Text` 节点：「第一次大作业」/「薛有泽」/「2020 年 9 月 10 日 星期四 16:22」） |
| 2 正文高度自适应、无内部滚动条 | 部分（行为达成，属性值未断言） | `04-hilog-probe5.txt`：`content height: …` 递增到 2623、`source=bridge`；`04-detail-light-layout.json`：`Web [0,916,1320,2562]` = 外层 Scroll 视口，正文四段全部可见 |
| 3 数学公式渲染 | 部分（行间达成，行内未达成） | 行间：`04-detail-light-zh.png`（∫ 公式已排版）；`04-hilog-mathaudit.txt`：`math=katexNodes:1`。行内 `$E=mc^2$` 仍是字面量 → 未验证项 3 |
| 4 链接与附件可点、行为明确 | 达成 | 外部打开：`04-link-external-open.png`（系统浏览器停在 `learn.tsinghua.edu.cn`，说明 `baseUrl` 生效、链接被外部打开而非容器内导航）；附件跳 FileDetail：`04-detail-light-zh.png` 的附件行 + `04-hilog-probe6.txt` 的 `attachment tapped` / `notice detail appear` |
| 5 切换深浅色后正文即时更新 | **未达成** | `04-detail-dark-zh.png`（顶部 `dark=true`，但正文仍是浅色）；`04-hilog-dark2.txt` 是**另一次**切换（切回 false）的日志。诊断线索见未验证项 1 |
| 6 浅色 + 深色各一张截图 | 两张都在，但深色那张与浅色**无视觉差异** | `04-detail-light-zh.png`（浅色，含公式）、`04-detail-dark-zh.png`（`dark=true` 帧） |

## 失败的尝试也留证（解释实现里的两处平台适配）

- `04-hilog-detail.txt`：脚本**没有被注入**时的状态——`loadData issued` 之后只有 `no content height`，
  高度恒为 1（正文完全不可见）。
- `04-hilog-probe4.txt`：`loadUrl('file://<sandbox>/…')` 被 ArkWeb 以 `ERR_ACCESS_DENIED` 拒绝。
- `04-hilog-probe5.txt`：改用 `javaScriptOnDocumentStart` 注入后桥活过来：
  `page log: bridge=object keys=log,onExternalLink,onHeight` 与递增的 `content height`。
- `04-hilog-probe*.txt` / `04-hilog-mathaudit.txt` 里还有 `content height probe: null`：
  `runJavaScript` 的返回值在设备上恒为 `null`（显式 `return` 也一样），这就是实现里改用桥回传的原因。

## 未验证项（不要把没验证的当已验证）

1. **深色正文没有变深**：模板确实带 `dark=true` 重建了（`04-detail-dark-zh.png` 顶部可读），但正文仍浅色。
   下一步诊断（未执行）：在页面里跑 `DarkReader.isEnabled()` 与 `getComputedStyle(document.body).backgroundColor`，
   确认是 DarkReader 没生效还是模板的 dark 分支没进去。
2. **Web 组件的高度设置值未断言**：layout dump 只给可视边界，看不到设成 2623。已确认的是行为
   （内容可见、公式完整、外层 Scroll 起作用），不是属性值。
3. **行内公式 `$…$` 未渲染**（页面里是字面量），同页行间 `$$…$$` 正常；根因未定论。
4. **CSRF 追加到链接的运行时行为未取证**：Mock 的 token 是空串，注入脚本的运行时路径没有真实值可测；
   纯逻辑侧由 `NoticeDetail.test.ets` 的模板断言覆盖。
5. **返回列表后滚动位置是否保留未复测**（ticket 03 的结论在 Navigation 外壳改造后没有重测）。

## 文件清单（19 个，含字节数与 SHA256 前 16 位）

| 文件 | 字节 | SHA256(前16) |
| --- | --- | --- |
| `04-detail-dark-layout.json` | 62123 | `d25884fee6afccc3` |
| `04-detail-dark-zh.png` | 263975 | `e75fe95e5e9d174c` |
| `04-detail-light-layout.json` | 26309 | `47ff14195049c5b6` |
| `04-detail-light-zh.png` | 262894 | `4134cb8dc4a2b875` |
| `04-hilog-all.txt` | 7250 | `2badaec30ab4f371` |
| `04-hilog-dark2.txt` | 323 | `f45042c6793f4a8c` |
| `04-hilog-detail.txt` | 7392 | `747a447f87989bda` |
| `04-hilog-mathaudit.txt` | 13501 | `52199193a93f9a59` |
| `04-hilog-probe.txt` | 8464 | `3082f6773186ecc4` |
| `04-hilog-probe2.txt` | 7357 | `69e95d7f7ead14a1` |
| `04-hilog-probe3.txt` | 4578 | `667a8b164d971bac` |
| `04-hilog-probe4.txt` | 5703 | `b90979197b89fec4` |
| `04-hilog-probe5.txt` | 6277 | `2869a8a5567c3720` |
| `04-hilog-probe6.txt` | 13206 | `8c1927d8c1326538` |
| `04-link-external-open.png` | 136232 | `11310957281c9109` |
| `04-list-layout.json` | 63367 | `9d1d78f219628c5d` |
| `04-list-zh.png` | 338823 | `b4a35c81dcb7d67c` |
| `probe.png` | 338996 | `82cd3056de7bbfdb` |
| `revision.txt` | 1353 | `81e4ff97dbe9e3f5` |
