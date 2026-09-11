# ticket 04 取证（公告详情 + HTML 渲染，Mock）

**设备口径**：全部证据来自**模拟器** Pura 90（`127.0.0.1:5555`，HarmonyOS 6.1.0(23)）。
真机 `3FBYB25407201890`（MatePad Air，API 24）**未连接**，按 AGENTS.md 归 ticket 18 之前的一次性复验。

**源码版本**：见 `revision.txt`。本目录跨越四个构建（开关矩阵见下），因此是**过程证据**。

## 开关矩阵（每一批都自证生效，hilog 里有对应行）

| 构建 | EVIDENCE_DETAIL_CONTENT | EVIDENCE_DARK_TOGGLE | EVIDENCE_THEME_AUDIT | FORCE_DARK | 产出 |
| --- | --- | --- | --- | --- | --- |
| ① 浅色夹具 | true | false | true | false | `04-detail-light-*`（公式/链接/附件同屏） |
| ② 深色（应用级 setColorMode） | true | false | true | true | `04b-dark-*` |
| ③ 切换对照 | true | true | true | false | `04c-before-*`（浅）↔ `04c-after-*`（深） |
| ④ **提交态** | false | false | false | false | `04-final-*`（真实交付界面，无控制条） |

④ 是提交态产物：hilog 里 `detail evidence content: enabled=false`、`themeAuditSwitch=false`、
`detail evidence dark toggle: enabled=false` 三行自证。

## 逐条验收 → 证据（两个论断不复用同一份文件）

| 验收项 | 结论 | 证据 |
| --- | --- | --- |
| 1 标题/副标题由进入时的参数决定 | **达成**（按参考实现：发布者 + 绝对时间，**不显示课程名**） | `04-final-detail-zh.png` + `04-final-detail-layout.json`（Text：「第一次大作业」/「薛有泽」/「2020 年 9 月 10 日 星期四 16:22」） |
| 2 正文高度自适应、无内部滚动条 | **达成** | `04-hilog-probe5.txt`：`content height: 5→21→57→150→389→1011→2623 source=bridge`；`04-detail-light-layout.json`：`Web` 节点边界 = 外层 Scroll 视口，正文四段全可见、公式完整 |
| 3 数学公式渲染 | **达成**（判据 = `$$…$$` 排版；单 `$` 不渲染属参考实现行为，见 quirks 第 9 条） | `04-detail-light-zh.png`（∫ 公式已排版）、`04b-dark-detail-zh.png`（深色下同样排版）、`04-hilog-mathaudit.txt`（`math=katexNodes:1`） |
| 4 链接与附件可点、行为明确 | **达成** | 外部打开：`04-link-external-open.png`（系统浏览器停在 `learn.tsinghua.edu.cn`，证明外部打开 + `baseUrl` 解析）；附件跳 FileDetail：`04-final-detail-zh.png` 的附件行 + `04-final-hilog.txt` 的 `attachment tapped` |
| 5 切换深浅色正文即时更新 | **达成**（本轮修复后重取） | `04c-before-toggle-light.png`（`dark=false`，浅底）↔ `04c-after-toggle-dark.png`（`dark=true`，深底）+ `04c-toggle-hilog.txt` 的两次审计：浅色 `darkCallInDom=false bodyBg=rgba(0,0,0,0)`；切换后 `theme changed -> reload content: native.isDark=true`、`enabled=true bodyBg=rgb(30, 26, 29) bodyColor=rgb(232, 230, 227)` |
| 6 浅色 + 深色截图各一张 | **达成** | 浅：`04c-before-toggle-light.png`（夹具正文）与 `04-final-detail-zh.png`（真实正文）；深：`04c-after-toggle-dark.png`、`04b-dark-detail-zh.png` |

## 关于上一轮报告的一处**证据状态错位**（已更正）

上一轮我把 `04-detail-dark-zh.png` 当成深色证据，并据此写「顶部 dark=true 但正文仍浅色」。
统筹复核指出：该 PNG 实际显示 `dark=false`（截图与 layout 不是同一状态取的），而 layout dump 不含颜色信息，
**支持不了**「正文仍浅色」这个论断。结论：

- 那两个文件（`04-detail-dark-zh.png`、`04-detail-dark-layout.json`）**已删除**，不再作为证据；
- 教训写进 ticket Comments：**截图与 layout 必须同态取，中途不要点开关**；
- 也不再把「未验证」写成「未达成」——两者修复方向完全不同。

## 由此暴露并修掉的一个真实缺陷

重取深色证据时发现：`loadData` 只在 `onControllerAttached` 里调用一次，改 `@Prop isDark`
**不会**让 ArkWeb 重新加载 → 切换深浅色后正文不更新（`04-hilog-dark2.txt` 就是那条轨迹：
`evidence dark toggled: effectiveDark=true` 之后没有第二次 `loadData issued`）。

修法两处（见 `entry/src/main/ets/ui/components/HtmlWebView.ets`）：
1. `@Prop @Watch('onThemeChanged') isDark` —— 标志变化时重送模板，并把 `loaded` 归位
   （否则重送时的主框架请求会被 `onLoadIntercept` 当成点击而外部打开）；
2. 容器底色不再作为独立 `@Prop` 传入，改由 `isDark` 推导 —— 实测 `@Prop isDark` 的 `@Watch`
   可能早于同批其它 `@Prop` 赋值触发，导致「深色已生效、底色还是浅色」，DarkReader 拿到浅底 → 文字不可读。

## 失败的尝试也留证（解释实现里的两处平台适配）

- `04-hilog-detail.txt`：脚本**没有被注入**时的状态（`loadData issued` 之后只有 `no content height`）。
- `04-hilog-probe4.txt`：`loadUrl('file://<sandbox>/…')` 被 ArkWeb 以 `ERR_ACCESS_DENIED` 拒绝。
- `04-hilog-probe5.txt`：改用 `javaScriptOnDocumentStart` 注入后桥活过来。
- `04-hilog-probe*.txt` 里的 `content height probe: null`：`runJavaScript` 返回值恒为 `null`（显式 `return` 也一样）。

## 仍未验证 / 已知缺口

1. **Web 组件的高度设置值未被断言**：layout dump 只给可视边界，看不到 `height=2623`。已确认的是**行为**
   （内容可见、公式完整、外层 Scroll 起作用），不是属性值。
2. **CSRF 追加到链接的运行时行为未取证**：Mock 的 token 是空串，注入脚本没有真实值可测；纯逻辑侧有模板断言。
3. **返回列表后滚动位置是否保留未复测**（ticket 03 的结论在 Navigation 外壳改造后未重跑）。
4. 全部证据来自模拟器，无真机证据。

## 文件清单（28 个，含字节数与 SHA256 前 16 位）

| 文件 | 字节 | SHA256(前16) |
| --- | --- | --- |
| `04-detail-light-layout.json` | 26309 | `47ff14195049c5b6` |
| `04-detail-light-zh.png` | 262894 | `4134cb8dc4a2b875` |
| `04-final-detail-layout.json` | 26005 | `4d147df0a125c15e` |
| `04-final-detail-zh.png` | 192725 | `c60f9bdaa612f7db` |
| `04-final-hilog.txt` | 12131 | `8c507fcc24311512` |
| `04-final-list-zh.png` | 337991 | `b2cf3da0e78ac4c1` |
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
| `04b-dark-detail-layout.json` | 59983 | `2d5cbbd87725a377` |
| `04b-dark-detail-zh.png` | 261253 | `cf2f7a05b01a96fc` |
| `04b-dark-hilog.txt` | 13362 | `80994b25880d77d2` |
| `04c-after-toggle-dark.png` | 272415 | `23105186e4faa751` |
| `04c-after-toggle-layout.json` | 62107 | `6a8bb62e1223feed` |
| `04c-before-toggle-layout.json` | 62124 | `838fa2830ac14dd1` |
| `04c-before-toggle-light.png` | 262511 | `b4aada5eafc1216b` |
| `04c-toggle-hilog.txt` | 15689 | `b6e8996835d2755a` |
| `revision.txt` | 1912 | `59d82fe4d794404a` |
