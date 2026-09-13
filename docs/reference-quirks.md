# 参考实现的怪癖台账（**历史记录 + 技术债登记**）

> ## ⚠️ 【更正 · 2026-09-13】本文件的定位已变
>
> 它**不再是"约束清单"**。原规则"移植的完成定义 = 与参考实现行为一致"**已作废**：
> 账号所有者 2026-09-13 裁定 `reference/learnOH-old/` 降级为**标尺**（只提供默认答案与回归比对），
> **不再阻止任何改动**。
>
> 现在本文件只有两种用途：
> 1. **历史记录** —— 解释"当初为什么这么写"，供改那处代码的人参考；
> 2. **技术债登记** —— 标题带 `技术债` 的条目是**待办**；仍然存在的限制见文件末尾的
>    「技术债」一节与各条目里标了 `【仍未定案】` 的段落。
>
> 下面原文里的"为什么别急着改"一类措辞，读作"当初的理由"，**不是禁令**。
> 改任何一处之前不再需要"先写理由、复审、迁移编号"那道门；但**改完应在 `docs/accepted-deviations.md`
> 追加一条带日期的说明**（变了什么 / 为什么 / 原证据还成立到哪一步）。

**这是什么**：参考实现（`reference/learnOH-old/`）里那些**看起来像 bug、但已被确认为有意行为或历史约束**的点。
它们的**原始**作用是阻止优化者"顺手修好"它们（**该作用已于 2026-09-13 作废，见上方更正**）。

**已复审的偏离不在本文件**：**原始**口径是本文件只放仍在生效的条目（`锁定` / `待查` / 【平台事实】/【站点事实】）；
现在本文件同时承担"技术债登记"（见文末），所以 `锁定` 与【平台事实】之外还会有标了 `技术债` / `【仍未定案】` 的条目。
已经复审并**批准偏离**的条目（连同替代验收标准）迁到 **`docs/accepted-deviations.md`** ——
那些条目**不再起"阻止改动"的作用**，只是变更记录与判据出处。两处**沿用同一套编号**，旧引用按号仍能找到（见文末索引）。

**为什么需要单独一份**：这类点有两个反复出现的失败模式 ——
1. 有人读到它，判断"这写错了"，于是改掉；改了之后**行为偏离参考实现** —— 这在移植阶段是问题（当时的完成定义见 `spec.md` 第 1 节），**现在不是**。
2. 有人把它当成 bug 权宜而"清理"，结果丢掉的是**鸿蒙能力缺口下的必要补丁**（例如下面第 1 条）。

**事实来源**：`reference/learnOH-old/`（只读）。编号条目都带**源文件与行号**，不是转述。

**两类条目，别混用判据**：
- **参考实现怪癖**（绝大多数编号条目）：定义"移植要与什么保持一致"。
- **平台事实 / 站点事实**（标题里注明的条目）：是本工程在**设备上实测**到的平台/站点行为，**不是**参考实现的行为，因此**不构成保真约束**；作用是解释"为什么参考实现在平台上的写法不能照抄"，证据是设备 hilog 而非源文件。

## 怎么用

- **动手改任何一条之前**：先确认它在本文件里（**在本文件 = 仍是约束**）。若状态是 `锁定` 而要偏离，先写清"为什么现在可以改 / 哪条验收标准随之改变"，
  并且**复审通过后把该条迁到 `docs/accepted-deviations.md`**（保持编号），本文件只留索引里的一行 ——
  不要把 `锁定` 就地改成 `已复审` 继续留在本文件（那会让"约束清单"重新混进历史记录）。
- 若你在移植中发现**新的**怪癖：按下面的格式追加一条，**必须带源文件与行号**。不要写"据说/印象中"。
- 本文件里只应出现 `锁定`／`待查`／【平台事实】／【站点事实】；`已复审` 一律在 `docs/accepted-deviations.md`。

## 已迁移条目索引（旧引用按编号查这里）

| 编号 | 标题 | 备注 |
| --- | --- | --- |
| 2 | 自动重登只在结果**恰好等于字符串** `'[]'` 时触发 | 迁移后**仍含一条生效约束**：重登触发的**并集**仍锁定（见该条顶部【仍锁定】） |
| 6 | 模板内联 `<script>` 与正文里的 `</script>` | 已复审（ticket 04 加固） |
| 10 | 提交报文里的 `fingerPrint` 取**页面值**而不是自造值 | 已复审（ticket 07） |
| 16 | 公告卡片的状态图标：参考实现用三色图标，新实现用同色 emoji | 原结论被账号所有者**改判**；**新约束**（图标必须与参考同形、不用 `SymbolGlyph`）在 **ticket 11.5** |
| 18 | 课程 / 学期这条线的四处有意偏离 | 已复审（ticket 12） |
| 22 | 文件详情的"预览 / 打开"：参考实现本来就有应用内预览 | 已复审（ticket 11） |
| 24 | 页头信息架构：左对齐自绘页头 + 相对更新时间（参考是居中 `HeaderTitle`，且没有更新时间元素） | 已复审（ticket 11.5，账号所有者点名） |
| 25 | 全应用底色去品红：底色族 + 中性族改中性灰（参考是 `rgb(255,251,255)` 那一套） | 已复审（ticket 11.5，账号所有者裁定） |
| 26 | 提交页不移植「之前分享的」（`pendingAssignmentData`） | 已复审（ticket 13；参考实现自己也没写过非 null 值） |
| 27 | 新选中附件那一行不可点（参考实现用上传前的本地 URI 进 FileDetail） | 已复审（ticket 13） |
| 28 | 分栏的详情路由迁移：整段迁移与参考一致；补上退出分栏的对称回迁 | 已复审（ticket 16；本条原来漏登记索引，ticket 15 补上） |
| 29 | 搜索的三处偏离：引擎换自写评分 / 结果排除被屏蔽课程 / 分栏下自成一左一右 | 已复审（ticket 15） |
| 30 | 设置与 Mock 模式的四处偏离 | 已复审（ticket 17）。**⚠️ 与下面正文里的第 30 条是两件不同的事，见 `docs/agents/porting.md` 的"已知缺陷"** |

> 流程（2026-09-13 起）：发现新怪癖/技术债 → 带源文件行号追加到本文件；
> 改掉某一处 → 在 `docs/accepted-deviations.md` **追加一条带日期的说明**（变了什么 / 为什么 / 原证据还成立到哪一步）。
> 移植阶段的"写理由→复审→迁移编号"那道门**已取消**（见文件头更正）。

---

## 1. `bytesWritten` 恒为 0 的下载补丁 —— 锁定

**参考实现行为**（`src/helpers/fs.ts:125-158`，代码注释原文即"HarmonyOS 库缺陷"）：
下载完成后**不信任** `result.bytesWritten`（鸿蒙下载库恒返回 0），改为：
1. `fs.stat(path)` 取磁盘真实大小；
2. 若 `statusCode !== 200 || stat.size === 0` → 删除文件并抛错；
3. 若 `stat.size < 5000` → 读文件内容，命中 `location.href` / `<!DOCTYPE html` / `<html` 任一 → **判定"下载到的是登录页/错误页"**，删除并抛错。

**为什么不能照抄也不能直接删**：这是一个**症状级补丁**——它靠"文件小且含 HTML"来猜测"会话失效"。但"会话失效时下载会静默得到 HTML"这个**事实**是真的，只是参考实现只能在文件落盘后才发现。

**新实现的做法**（`spec.md` 第 6 节）：在 **HTTP 层**解决——下载前检查响应 `Content-Type` 与状态码，命中 HTML 就不落盘。**不要把 `<5000 字节 + 含 <html>` 这条启发式搬过来**（那是把可判定的条件退化成猜测），也不要因为"新实现不需要它"就以为参考实现这里写错了。

**取证**：`src/helpers/fs.ts:125-158`（`bytesWritten`、`stat`、`5000`、`<html`、`location.href` 全部逐字可查）。

---

## 3. 学期排序是 `sort().reverse()`，不是自定义比较器 —— 锁定

**参考实现行为**（`src/data/actions/semesters.ts:27`）：
```ts
const sorted = semesters?.sort().reverse();
```
注意这**不是** `sort((a,b) => ...)`。它依赖学期 id 形如 `YYYY-YYYY-N` 这一事实，使得**默认字典序恰好等于时间序**，再 `reverse()` 得到"最新在前"。

**为什么容易被"修坏"**：字典序与时间序一致是**巧合级的依赖**。如果将来学期 id 格式变化（例如补零位数不同、或出现 `YYYY-YYYY-10`），字典序就会与时间序脱钩，而 `sort().reverse()` 会**静默给出错误结果**。

**新实现的做法**：`domain/model/Semester.ets` 用**显式的时间序比较**（ticket 01 已交付），并在单测里断言"与参考实现的 `sort().reverse()` 在合法 id 上结果一致"——既拿到了正确性，又保留了对参考实现的兼容证明。

**取证**：`src/data/actions/semesters.ts:27`；新实现的等价断言见 `entry/src/test/Semester.test.ets`。

---

## 4. 解析正则**不解码 HTML 实体**，`&amp;` 原样参与匹配 —— 锁定

**参考实现行为**：解析 HTML 属性的正则直接匹配**原始字节**，不做实体解码。因此属性值里出现 `&amp;` 时，取到的是 `&amp;` 本身（或按正则的字符类匹配不上而**取不到**该字段）。

**为什么容易"修坏"**：任何有 Web 常识的人都会觉得"应该先解码实体再取属性"。但——
- 参考实现**没有**这么做，这是**当前的行为契约**；
- 一旦新实现自己加上解码，遇到 `&amp;` 的用例会得到**与参考实现不同**的结果，于是"移植是否正确"就失去了可比对的基准；
- 登录页等场景下 `finger3.js` 那类脚本也是按原始 DOM 取值，**整条链上都假定不解码**。

**新实现的做法**：**照参考实现不解码**。若将来确实需要解码，作为**独立增强**提出并**单独定义验收标准**（因为参考实现没有这个行为，无法用它证明"移植正确"）。

**取证**：ticket 05 的失败用例里 `&amp;` 相关的三条（夹具与期望按参考实现行为校正）；参考实现的解析正则见 `src` 下各 parser 与 `thu-learn-lib`。

**这条也是 ticket 05 那批失败用例的判据**：夹具必须**服从参考实现的行为**，而不是服从人眼期望——否则夹具本身就成了"要求新实现比参考实现更正确"，那不是移植。

**同一件事的另一半（别只读上面半条）：渲染层是「解码」的。** 参考实现把实体解码**推迟到渲染**，而不是不做。`src/helpers/html.ts:11-22` 的 `removeTags()` 依次做四件事：去 HTML 注释 → 去标签 → **`he.decode()`（全实体集）** → 折叠连续空白并 trim；`src/components/NoticeCard.tsx:42,72` 用它渲染标题与正文摘要。

所以实体这件事的契约是**两层**，必须同时成立：

| 层 | 行为 | 依据 |
| --- | --- | --- |
| 解析层 | **不解码**，`&amp;` 原样参与正则 | 本条上半（锁定） |
| 渲染层 | **解码**，且是 `he` 的完整实体集（含 `&#39;` / `&#x27;` 数字实体），并去标签 | `helpers/html.ts:11-22` |

**【已更正 · 2026-09-13】这段"新实现的缺口"已经补上（下文保留原样作为历史）：**
渲染层的 `removeTags` 等价物**已实现** —— `entry/src/main/ets/domain/render/WebViewTemplate.ets` 的 `removeTags()`
（去注释 → 去标签 → 全实体解码 → 折叠空白），实体补全在 `domain/parse/Text.ets` 的 `entityByName`，
生产调用点 20+ 处，单测 `entry/src/test/NoticeDetail.test.ets`。
**本条现在唯一还有效的只有上面"解析层不解码"那半。**真实公告的 `content` 含 `<p>` / `<span>` / `&nbsp;`（ticket 03 的 mock 逐字保留了这些），标题也可能含标签。

**后果与边界**：若在 UI 里直接渲染原始字段，界面上会出现字面量 `<p>`、`&nbsp;`、`&#39;`。这是**渲染层**的活——不要靠"让解析层解码"来解决，那正好违反本条上半。

**取证**：`src/helpers/html.ts:11-22`（`he.decode`、注释与标签正则、连续空白折叠、`trim`）；`src/components/NoticeCard.tsx:42,72`；`src/data/mock.ts:242-352`（7 条公告的原始 content 形状）。

---

## 5. 搜索的"手工精确匹配合并"是 CJK 下的必要行为 —— 锁定

参考实现里有一段看起来冗余的"手工精确/前缀匹配再合并"逻辑。**它不是权宜之计**：`fuse.js` 的 Bitap 与 `flexsearch` 的 `cjk` charset 对中文都**按码点逐字切分**，匹配不了拼音/同音字。这段合并层是 CJK 场景下的**必要补偿**，必须保留。拼音检索需独立拼音索引字段（后续增强，不在本次范围）。

**取证**：`.scratch/migration/search-package-eval.md`；`spec.md` 第 8 节「搜索的 CJK 注」。

---

## 7. 模板注入脚本里的 new URL() —— 锁定（ticket 04 因平台约束换实现方式，行为等价）

**参考实现行为**：`helpers/html.ts:60-66` 的注入脚本用 `new URL(url)` 取 hostname，只对
**hostname 以 `tsinghua.edu.cn` 结尾**的 `href`/`src` 追加 `_csrf`。

**为什么别急着改**：这不是 bug，它依赖注入脚本跑在一个有来源的文档里。移植到 ArkWeb 时这个
前提变了（文档由 `loadData` 生成，是 opaque origin，`new URL()` 抛 TypeError），照抄会让全部链接
更新失败。但**改法必须是等价的手工解析**，不能把只对 tsinghua 追加这个条件去掉——那会变成对
所有链接都追加 `_csrf`，是行为偏离。

**为什么状态是"锁定"而不是"已复审"**：新实现**没有偏离**参考实现的行为——同一条件、同一追加方式、
同一跳过规则，只是把 `new URL()` 换成手工解析（等价的实现方式替换）。既然行为契约本身没变，按本表的词表
就该记 `锁定`：它约束的正是"别去掉只对 tsinghua.edu.cn 追加这个条件"。

**新实现做法（逐条对齐，只有解析方式不同）**：

| 条件 | 参考实现 | 新实现 |
| --- | --- | --- |
| hostname 以 `tsinghua.edu.cn` 结尾（含其子域） | `hostname.endsWith(...)` | 手工切出 hostname 后做同一判断 |
| 追加方式 | `searchParams.set('_csrf', token)` | 有 `?` 用 `&`、无则 `?` 拼上 |
| 空 token | 追加 `_csrf=`（`set` 的语义） | 同样追加 `_csrf=` |
| 非 http(s) 的 href（`mailto:` / `#anchor`） | `new URL()` 抛异常 → 跳过该链接 | 同样跳过 |
| 末尾 `#fragment` | `toString()` 保留 | 手工拼回（与参考实现一致） |
| 端口 | `hostname` 不含端口 | 手工剥离 `:port` 后再比较 |

**取证**：`reference/learnOH-old/src/helpers/html.ts:60-66`；
`entry/src/main/ets/domain/render/WebViewTemplate.ets` 的 `buildCsrfScript`；
`entry/src/test/NoticeDetail.test.ets`（`injects the csrf token into the link rewriter`、
`escapes a hostile csrf token instead of breaking out of the literal`）。

---

## 8. 【平台事实】ArkWeb 的两条行为（不是参考实现的怪癖，故**不构成保真约束**）—— ticket 04 新增

设备实测（模拟器 Pura 90，HarmonyOS 6.1.0(23)），两条都写进了
`entry/src/main/ets/ui/components/HtmlWebView.ets` 的注释与 ticket 04 的取证记录：

1. **`WebviewController.runJavaScript` 的返回值恒为 `null`**（即使脚本里写了显式 `return`）。
   所以用返回值把高度量回原生这条路走不通——参考实现的 `postMessage` 端口在 ArkWeb 上
   的等价物只能是 `javaScriptProxy` 注入的桥。
2. **`javaScriptProxy` 只注入对象，不会执行任何脚本**。测高脚本必须另外经
   `javaScriptOnDocumentStart`（等价于参考实现的 `injectedJavaScriptBeforeContentLoaded`，
   `AutoHeightWebView.tsx:76`）放进页面；否则出现桥是好的、但没人调用它的静默失败。
   另：`file://` 指向应用沙箱（`cacheDir`）会被 ArkWeb 以 `ERR_ACCESS_DENIED` 拒绝，
   所以正文只能走 `loadData(html, 'text/html', 'UTF-8', baseUrl, baseUrl)`。

**取证**：`.scratch/notices-detail/evidence/04-hilog-probe4.txt`（`ERR_ACCESS_DENIED`）、
`04-hilog-probe5.txt`（`page log: bridge=object keys=log,onExternalLink,onHeight`）、
`04-hilog-detail.txt`（`loadData issued` + `no content height`）。

---

## 9. 行内单 `$…$` 公式**不渲染**（只有 `$$…$$` 与 `\(…\)`）—— 锁定

**参考实现行为**：`src/helpers/html.ts:110-114` 调用 `renderMathInElement(document.querySelector("#root"), { throwOnError: false })`，**没有传 `delimiters`**。KaTeX auto-render 的默认分隔符集（从 `katex/dist/contrib/auto-render.min.js` 的 `n.delimiters=n.delimiters||[...]` 读出）是：

| 左 | 右 | display |
| --- | --- | --- |
| `$$` | `$$` | true（行间） |
| `\(` | `\)` | false（行内） |
| `\begin{equation}` / `\begin{align}` / `\begin{gather}` 等环境 | 对应 `\end{…}` | true |

**单 `$` 不在其中。** 所以正文里写 `$E = mc^2$`，参考实现会把它**当字面量显示**（页面上直接看到 `$E = mc^2$` 这串字符）；`$$…$$` 正常排版。

**为什么别急着"修好"**：这是本表里最容易被误判为 bug 的一条——用 `$x$` 试一下发现没渲染，几乎必然会想给 `delimiters` 补上单 `$`。但参考实现没这么做，补上就**行为偏离**：真实公告里出现的单个 `$`（价格、变量名等）会被突然当成公式吞掉，变成新的错误来源。KaTeX 上游默认不给单 `$` 也正是这个原因。

**新实现做法**：照参考实现**不传 `delimiters`**（`domain/render/WebViewTemplate.ets` 的数学调用保持 `{ throwOnError: false }`）。

**背景**：ticket 04 曾把"行内 `$…$` 未渲染"记为"部分达成／根因未定论"。经查证它属**参考实现行为**，故验收第 3 条以"`$$…$$` 正常排版"为达成判据。若将来确实要支持单 `$`，那是**新增**，需单独定义验收标准并评估与真实正文的冲突。

**取证**：`reference/learnOH-old/src/helpers/html.ts:110-114`（未传 delimiters）；`reference/learnOH-old/node_modules/katex/dist/contrib/auto-render.min.js`（默认分隔符数组）；`entry/src/main/ets/domain/render/WebViewTemplate.ets`。

---

## 11. 【平台事实】ArkWeb 的 IndexedDB 与 `databaseAccess`（不是参考实现的怪癖，**不构成保真约束**）—— ticket 07 新增

设备实测（模拟器 Pura 90，HarmonyOS 6.1.0(23)），两条都来自 ticket 07 的诊断构建：

1. **`databaseAccess` 默认 false，但 IndexedDB 照样可用。** `EnrollmentWebView` 没有设置
   `databaseAccess`，实测 `indexedDB=object`，且原生往返探针（`indexedDB.open` → `put` → `get`）
   `roundTripOk=true`；`domStorageAccess(true)` 下的 localStorage 也正常（`localStorageOk=true`）。
   ⇒ `databaseAccess` 对应的是**老的 Web SQL Database**，**不是 IndexedDB**。
   排查"站点认为这个浏览器存不住东西"时，**不要先去动这个开关**（ticket 07 曾把它当第一嫌疑，
   被这一条判死）。
2. **`javaScriptOnDocumentStart` 注入的脚本跑在文档最开始**：那时 `<head>` 里的第三方脚本
   （例如站点的 `localstorageUtil.js`）**还没有定义全局**。ticket 07 的第一版探针在那一刻读到
   `localstorageUtil=absent`，一度被误读成"站点对象不存在"——同一轮 load 期的调用是正常的
   （`finger3 source=localstorage chars=0`）。⇒ 探针必须能区分"此刻还没定义"与"根本不存在"，
   否则它会生产假结论。

**取证**：`.scratch/enrollment/evidence/07-diag-prefix-finger3-empty.txt`
（`diag:env origin=[https://id.tsinghua.edu.cn] … localStorageOk=true indexedDB=object`、
`diag:idb roundTripOk=true`、`diag:lf localstorageUtil=absent` 与随后 load 期的
`[finger3] source=localstorage chars=0` 并存）。

---

## 12. 【平台事实】站点自带的 detectIncognito@1.5.1 在 ArkWeb 上会**误判隐私模式**（不是参考实现的怪癖，**不构成保真约束**）—— ticket 07 新增

**这是什么**：ID 登录页提交成功后的**二次验证页**（`id.tsinghua.edu.cn/do/off/ui/auth/login/check`）
内置 `detectIncognito@1.5.1`（`doubleAuth.bundle.js`，bundle 里 `e.VERSION="1.5.1"`）。Chromium 分支的判据是
（bundle 原文）：

```js
navigator.webkitTemporaryStorage.queryUsageAndQuota(function (usage, quota) {
  isPrivate = Math.round(quota / 1048576) < 2 * Math.round((performance.memory?.jsHeapSizeLimit ?? 1073741824) / 1048576);
}, err);
```

即 **"临时存储配额 < 2 × JS 堆上限" 就算隐私模式**。而该页 `render` 的分支是
`this.state.isPrivate ? messages.double_sfjbsbbjwxrsb3 : messages.double_sfjbsbbjwxrsb`，
且 `isPrivate` 时**只渲染 `<Input type="hidden" name="type" value="否">`——「信任该浏览器」选项根本不出现**。
出现 rsb3 那句文案 ⇔ `isPrivate === true`（演绎，不是推测）。

**设备实测（模拟器 Pura 90，HarmonyOS 6.1.0(23)，2026-09-12）**：

| 环境 | heapMb | thresholdMb | quotaMb | `isPrivateByChromeRule` |
| --- | --- | --- | --- | --- |
| 数据分区 6 GiB（可用 4.4 GiB）——**用户那次失败时的配置** | 2089 | 4178 | **3504** | **true** |
| 数据分区 16 GB（可用 15 GiB）——本轮把 `hw.dataPartitionSize` 6144→16384 后 | 2089 | 4178 | **9347** | **false** |

⇒ 用户 2026-09-12 那次"您的浏览器目前处于隐私或匿名模式…"**不是被服务端拒绝，也不是我们注入的错**：
该判据只用到引擎上报的**两个数**（临时配额、JS 堆上限），我们的注入（fingerPrint / fingerGenPrint /
saveFinger / singleLogin）**在它之外**。**参考实现在这台模拟器上今天同样会失败。**

**是否影响真实设备**：**未验证**——真机（MatePad Air，API 24）数据分区通常几十 GB，`quota` 预计远大于
`2 × jsHeapSizeLimit`（约 4.2 GB），即**自然通过**；但这是**预测**。该问题已并入 **ticket 18 之前的真机
一次性复验**：真机上若同样出现"隐私/匿名模式"，带着证据重新决策。

**明确不做的"修法"（决策留档）**：**不**把 `navigator.webkitTemporaryStorage.queryUsageAndQuota` /
`navigator.storage.estimate` 包一层去上报一个更大的配额。那是**欺骗站点的一个反欺诈/隐私启发式**，
而且只对"小数据分区"这类测试环境有意义（真实设备天然满足），收益为负、风险为正。参考实现也没有这东西。

**新实现做法**：**不动代码**。这是取证环境的属性；要复现用户那次现象，把模拟器的
`hw.dataPartitionSize` / `disk.dataPartition.size` 调小即可（6 GB 就会踩中）。

**取证**：`.scratch/enrollment/evidence/experiment-0918/` 的 `07-incognito-probe.txt`（改前，`isPrivateByChromeRule=TRUE`）、
`07-incognito-probe-after-resize.txt`（改后，`isPrivateByChromeRule=false`，quota 9801080832 / 9347 MB）、
`doubleAuth.bundle.js`（`e.VERSION="1.5.1"` 与该判据、该 render 分支）、
`experiment-0918-full.txt`（用户会话：三次 `/b/doubleAuth/login` 全部 `result=success`、无 `saveFingerRequest`、无 roaming）。

---

---

## 13. 【仍未定案 · 见文末技术债】已信任分支的 `/login/check` 可能是 JS 驱动页 —— 票据锚点可能不在 HTTP 响应里（ticket 07/08，**未定案**）

**观察到的事实**（2026-09-12 第 4 次真实登记 + 同日冷启动复验）：
- 已信任（免短信）那次，`/do/off/ui/auth/login/check` 之后加载的是**一张 genprint 页**：
  `scriptCount=3 inlineScripts=1 formAction=none scripts=[/res/ui/jquery.min.js /v2/dist/doubleauth/localstorageUtil.js /res/selfservice/genprint.js]`，
  接着 `POST /b/doubleAuth/personal/getFinger3`（`result=error`），再跳 `j_spring_security_thauth_roaming_entry`。
  未信任那次（10:57）同一路径加载的是 **`doubleAuth.bundle.js`**（二次验证页），并多一跳 `redirect2Jsp`。
- 纯 HTTP 重登拿到的那张页是 `status=200 bytes=1280 idLoginPage=false doubleAuthMentions=0`，**没有 `<a>` 锚点**
  ⇒ 我们那套**与参考实现逐字一致**的取票据方式（首个 `<a href>` → 最后一个 `=` 之后；
  `data/auth/LoginParsers.ets:41-61` ↔ `reference/learnOH-old/tmp/bundle.harmony.js` @2044751 的 `getRoamingTicket`）
  取不到票据 ⇒ `NO_TICKET_IN_RESPONSE`（冷启动因此没能重建会话，降级到登录页——降级本身是正确的）。

**已排除的静态候选**（2026-09-12 直接抓站点静态资源读，**不需要登录、不需要用户动手机**）：
- `/res/selfservice/genprint.js`（106 B，5 行）：只调 `localstorageUtil.getFinger3FromRemoteAndSave()`，**无任何跳转**；
- `/v2/dist/doubleauth/localstorageUtil.js`（35 KB bundle）：`roaming` / `redirect2Jsp` / `location.href` / `ticket` **0 命中**；
  `getFinger3FromRemoteAndSave` = `$.post("/b/doubleAuth/personal/getFinger3", {}, cb)`，**不做跳转**；
- `/res/selfservice/finger3.js`（登录**表单**页的辅助脚本）：管 `#fingerGenPrint3` 与 `singleLogin` 复选框，**不跳转**
  （顺带独立确认了第 7 节那条"页面会显式把 `singleLogin` 置为未勾选"）。
⇒ 跳转指令**只可能在那张 1280 字节页自身的 inline script / meta refresh 里**（该页 `inlineScripts=1`）。**这是排除法，不是直接证据。**

**两种世界（**先判别再改码**）**：
- **W1**：票据/漫游 URL **就在 HTTP 响应正文里**（只是不再是 `<a href>`）⇒ 纯 HTTP 路线成立，我们只差一步解析（或一步跳转）；
- **W2**：票据由站点 JS 在执行期生成 ⇒ 纯 HTTP 做不到 ⇒ **要改 ADR-0004**（它第 7 行否决过"隐藏 WebView 静默重登"），
  属**决策变更**（需用户签字），不是改代码。

**判别计划（只读探针；明确：不需用户动手机、不走登记、不发短信）**：把那张 1280 字节页的**正文**（或结构：所有 `<script src>`、
inline script 正文、form action、`location.href` 赋值、`ticket` / `getFinger3` / `redirect2Jsp` / `roaming` 的出现处）打出来。
**计数不足以判 W1/W2**；探针开关的**实际生效值**要打进 hilog；**一轮只打一次登录**（`singleLogin='on'` 可能踢掉既有会话，
连续重试还可能触发风控）。

**为什么别急着改**：放宽 `extractTicket`（例如也认 `location.href=`）在 W2 下**不会**让它工作，却会让"取不到票据"这个
**正确的失败信号**消失。**先取证再改。**

**取证**：`.scratch/enrollment/evidence/experiment-success/`；ticket 07 Comments「第 4 次真实登记」第 8 节；ticket 08 Comments 末节；
静态资源副本 `.dsh/logs/genprint.js.txt` / `.dsh/logs/static-1.js` / `.dsh/logs/static-2.js`。

**后续（ticket 08 第二轮，2026-09-12）—— 本条的前提被推翻，W1/W2 退回"待重新定义"**：

带着 W12 探针的 armed 构建实测（模拟器 Pura 90，HEAD `66a06e3`）证明：**纯 HTTP 的
`POST /do/off/ui/auth/login/check` 拿回来的那张 1280 字节页，根本不是上面那张 genprint 页。** 它的
`counts` 是 `anchorTag=0 metaTag=1 httpEquiv=1 refresh=0 location.href=0 location.replace=0
location.assign=0 scriptTag=0 formTag=0 actionEq=0`、`inlineScriptCount=0`、`candidateUrlCount=0`
⇒ 全正文里**没有任何 `<script>`、没有 `<a>`、没有 `<form>`、没有任何 URL**；形态是**一张 GBK 通用报错页**
（`<meta … charset=gb2312>` + 一句红字 + 一个 `window.close()` 按钮）。

⇒ 上面那条"跳转指令**只可能**在那张 1280 字节页自身的 inline script / meta refresh 里"的**排除法没有对象**：
它建立在"两张页是同一张"这个未经检验的假设上。**已确证**的只是"**这张**响应里没有跳转目标"；
"纯 HTTP 拿不到票据"**未确证**。真正的下一步不是解析页面，而是先证明**我们发出去的请求是完备的**
（见第 15 条：cookie 吸收从来没成功过）。

**取证**：`.scratch/enrollment/evidence/experiment-w12/` 的 `E2-w12-raw-lines.txt`（counts 原文）、
`E7-response-body.txt`（整张正文还原）、`README.md`（判定与未验证项）。

---

## 14. 【仍未定案 · 见文末技术债】`adopt()` 在 10:57 失败于"收割时机偏早"（ticket 07）

**事实**：10:57 那次登记漫游到了、也收割到了（`entries=2 names=[JSESSIONID,XSRF-TOKEN] chars=102`），但随后的纯 HTTP 会话采纳
（`EnrollmentSession.adopt()`）拿到 `status=200 bytes=1657`、CSRF 抽取为空 ⇒ `NOT_LOGGED_IN`。
**armed 探针（2026-09-12 第 4 次登记，5 行全在）排除了四个候选里的三个**：四个变体
（`stage=body` / `stage=jsessionidRetry`（URL 重写）/ `stage=uaRetry ua=webview(Chrome/132…)` / `stage=uaRetry ua=pinned(Chrome/120…)`）
返回**字节级相同**的 `status=200 bytes=116093 csrfEqOccurrences=3 csrfParsedChars=36 loginTimeoutInBody=false idLoginPage=false`
⇒ **不是 CSRF 正则失配、不是 UA 绑定、不是 `;jsessionid` URL 重写**。
**剩下的差别**：本轮收割集合是 `entries=3 names=[JSESSIONID,XSRF-TOKEN,!Proxy!PHPSESSID] chars=147`（多了 `!Proxy!PHPSESSID`），
且收割发生在页面走完 `roam.php` / `zhjw…j_acegi_login.do` **之后**（12:01:10.318）；10:57 则是在课程页刚 load 完就收割。
⇒ **强线索：10:57 的失败是"收割时机偏早"**——会话就位所需的那颗 cookie 还没下发。

**为什么是未证**：两轮之间还差一个变量（免短信 vs 二次验证成功后的跳转链不同），现有日志分不开"收割时机"与"跳转链差异"；
要分开需要"逐次 `enrollment cookies` 记录 + 收割时刻的 cookie 全集"。
**为什么别急着改**：`adopt` 本身就是我们对 ADR-0004 的偏离（ADR 要的是纯 HTTP 重登），所以"修 `adopt` 的时机"
**不是** ticket 08 的解法，最多算 ticket 07 的稳健性改进；在 W1/W2 判清之前动它属于改错地方。

---

## 15. 【平台事实】`HttpResponse.cookies` 给的是 **Netscape 制表符行**，不是 `Set-Cookie`（不是参考实现的怪癖，**不构成保真约束**）—— ticket 08 新增

**这是什么**：`@ohos.net.http` 的 `HttpResponse.cookies`（`HttpClient.ets:163` 直接把它当 `setCookie` 往上传）
在**模拟器 Pura 90 / HarmonyOS 6.1.0(23)** 上返回的不是 `name=value; attrs`，而是 **Netscape cookie-file 的一整行**：
**制表符分隔的 7 个字段** —— `domain / includeSubdomains / path / secure / expiry / name / value`：

```
#HttpOnly_id.tsinghua.edu.cn<TAB>FALSE<TAB>/<TAB>FALSE<TAB>0<TAB>JSESSIONID<TAB>FB9C…authweb1
```

- `#HttpOnly_` 前缀表示 httpOnly，**域要剥掉这个前缀**；以 `#` 开头的行通常是注释，但**这一种不是注释，不能跳过**；
- `expiry=0` ⇒ 会话 cookie；域可能带前导点；**值里可能有 `=`**（只切第 6 个制表符，其余并回值）；
- 多条 cookie ⇒ **多行**（`\n` 分隔），不是逗号拼接。

**官方文档不给格式**：本地 SDK 的 `@ohos.net.http.d.ts` 里 `HttpResponse.cookies` 只有一句
`Cookies returned by the server. @type {string}`。**没有格式说明**，只能实测。

**为什么这条值钱**：只认 `name=value` 的解析器（`parseSetCookie` 的 `first.indexOf('=') <= 0 ⇒ undefined`）
在这行上**静默落空**——一条 cookie 都不入库。于是后续所有请求都带着**空 JSESSIONID**（空值又被
`cookieHeaderFor` 丢掉 ⇒ 连 `Cookie` 头都没有）打到服务端，服务端按"会话失效"回一张通用报错页。
ticket 08 曾把这张页误读成"站点改了登录页 / 需要改 ADR-0004"，真因却在我们自己的解析器。

**规矩（比这条事实本身更重要）**：**看到 `name=value` 之外的形态时，先怀疑平台/我们自己的解析，而不是站点。**
把"我们发出去的请求"（请求头、cookie 名与长度、表单字段）变成可观察量，再谈服务端行为。

**新实现做法**：`core/http/CookieJar.ets` 新增 `looksLikeNetscapeCookieLine()` /
`parseNetscapeCookieLine()` / `parseSetCookieResponse()`——**逐行**判定形态，**标准 `Set-Cookie` 与
Netscape 行两条入口都保留**（`response.header['set-cookie']` 那边给的是标准形态）。吸收时按来源
（`netscape` / `standard` / `mixed` / `empty`）+ 吸收数 + 跳过行数落一行自证。
**注意**：这条不属于"参考实现的怪癖"，因此**不构成保真约束**——参考实现依赖
`@react-native-cookies/cookies`（平台 WebView 的 cookie 存储），根本没有等价物可比。

**取证**：`.scratch/enrollment/evidence/experiment-w12/E5-page-cookie-format.txt`（设备原文，逐字）、
`E3-cookie-parse-failure.txt`（离线复刻两段纯函数：`splitSetCookieHeader`→1 段、`parseSetCookie`→undefined）、
`E4-known-url-probe.txt`（`cookieNamesSent=[]`、`jarAfterProbe … valueChars=0`、已知漫游 URL 两个都 401）。

---

---

## 17. 【站点事实】部分接口的**裸请求一律 403**（站点自己的报错页），带 `?_csrf=` 才 200 —— ticket 09 实测

**观察到的事实**（模拟器 Pura 90 / HarmonyOS 6.1.0(23)，2026-09-12）：
- `GET /b/kc/zhjw_v_code_xnxq/getCurrentAndNextSemester` **不带参数** → `status=403 bytes=2628 text/html`；带 `?_csrf=<36>` → `status=200 bytes=153 application/json`。
- `GET /b/kc/v_wlkc_xs_xktjb_coassb/queryxnxq` → **带不带 `_csrf` 都 403**（它还要别的参数）⇒ 不能一概而论成"带 csrf 就行"。
- 403 的正文是**站点自己的报错页**：`<p class="infoo">服务器内部错误 </p> <p>错误码为：403</p>`——**不是**登录页，正文里**没有** `login_timeout`。

**为什么这条值钱（也为什么别急着把它当"会话失效"）**：`data/auth/LoginParsers.isNoLoginResponse` 的并集判据里**包含 `status === 403`**（照参考实现 `thu-learn-lib` 抄的，属锁定行为）。于是**任何漏带 `_csrf` 的请求都会被判成"会话丢了"** → 触发一次重登 → 重试仍 403 → 按 `SessionGate` 降级为 `NOT_LOGGED_IN` / `UNEXPECTED_STATUS`，最终把用户踢回登录页——**而根因只是我们自己少了一个查询参数**。这与第 15 条是同一类教训：**先把"我们发出去的请求"变成可观察量，再谈服务端行为。**

**新实现做法**：生产代码的 `authedGet` **一律**带 `?_csrf=`（`data/remote/AuthedRequest.ets`）——这是必须项不是可选项；判读失败时先核对"这次请求带没带 `_csrf`"，再看状态码。

**取证**：`.scratch/notices/evidence/README.md` 第 1 节（A1/A2/A3/A4 四行原始输出）、`09-probe3-hilog-simulator.txt` 的 `[probe] …-bare status=403` 系列。

**更正（2026-09-12，ticket 12 复测）——上表 A3/A4 那条 `queryxnxq` 子结论【未能复现】，不要再据此认定该接口坏掉。**

- 同一台模拟器、同一个 account、**同一个** `authedGet`（带 `?_csrf=`）实测：
  `data.courses GET status=200 bytes=127 ok=true`、`semesters resolved current=2026-2027-1 list=9 listOk=true`，
  学期切换页因此列出了 9 个学期（截图见 `.scratch/courses/evidence/A3-semester-picker-final.png`）。
- 本轮**没有**解释"为什么 ticket 09 的 A4 是 403"（可能是当次探针自身的请求完备性问题——第 15/17 条反复强调的那类），
  只记录"带 `_csrf` 的 `queryxnxq` 现在返回 200 + JSON 数组"。
- **本条其余部分不变**：裸请求（不带 `_csrf`）确实会拿到站点自己的 403 报错页，而 `isNoLoginResponse` 把 403
  当会话失效 ⇒ 生产代码的 `authedGet` 一律带 `_csrf` 这条**必须遵守**。
- 取证：`.scratch/courses/evidence/A5b-hilog-final-current-datacourses.txt`、`A4-layout-semester-picker-final.json`；
  ticket 12 Comments 的"修正台账第 17 条的一条子结论"。

---

## 19. 作业的最终次序是**两步**：processor 按截止时间倒序 + JS 侧切"未到期 / 已过期" —— 锁定

**参考实现行为**：作业 tab 用的那条全局列表，次序由两处接起来：

1. **原生 processor 先按截止时间倒序**：`DataProcessorModule.processAssignments`
   （`reference/learnOH-old/node_modules/react-native-learn-oh-data-processor/harmony/learn_oh_data_processor/src/main/ets/DataProcessorModule.ts:72-76`
   的 `.sort((a, b) => timeB - timeA)`）；
2. **JS 侧再切分**：`src/data/actions/assignments.ts:123-128`

   ```ts
   const sorted = [
     ...assignments.filter(a => dayjs(a.deadline).isAfter(dayjs())).reverse(),  // 未到期 → 由近及远
     ...assignments.filter(a => !dayjs(a.deadline).isAfter(dayjs())),           // 已过期 → 保持第 1 步的降序
   ];
   ```

**为什么容易被漏掉**：那句 `[...]` 读起来像一个完整的排序实现（它的名字也叫 `sorted`），
于是只搬它、不搬 processor 的 sort。后果是**已过期段变成接口返回顺序**。

**真实数据实测（2026-09-12，模拟器 Pura 90 / HarmonyOS 6.1.0(23)，2025-2026 春季 57 条）**：
漏掉第一步时列表前三条的截止时间是 `2026-05-31 23:59` / `2026-06-20 23:59` / `2026-04-30 23:59`
（截图 `.scratch/assignments/evidence/pre-fix/B1-assignments-spring-list-top-final.png`）。
ticket 05 的移植正是这样，而它的单测 `ordersUpcomingFirstLikeTheReferenceFinalSort`
（`entry/src/test/AssignmentParser.test.ets`）**只钉了"未到期在前"**、入参又是排好序的，
所以这一步在真实数据之前从未被任何断言发现。

**新实现做法（ticket 10 补第一步）**：两步都在 `data/remote/AssignmentsFetcher.fetch` 里做完 ——
`compareAssignmentsByUpcoming(sortAssignments(collected), Date.now())`；
`compareAssignmentsByUpcoming` 的语义**一行未改**（它对应的就是参考实现第 2 步），
所以"与参考实现一致"这一基准仍然成立。

**替代/补充验收标准**：单测 `assignmentsFetchSortsByDeadlineBeforeSplittingUpcomingAndPast`
（`data.fetch`）用**故意乱序**的夹具（旧 → 未到期 → 新）断言
`未到期（由近及远）→ 已过期（按时间倒序）`；界面侧见 ticket 10 的
`B1/B3-assignments-spring-list-*-final.png`。

**取证**：`DataProcessorModule.ts:72-76`；`src/data/actions/assignments.ts:123-128`；
`entry/src/main/ets/data/remote/AssignmentsFetcher.ets`；`entry/src/test/DataFetch.test.ets`。

---

## 20. 完成方式 / 提交方式：参考实现比较**数字枚举**，站点下发的也是数字 —— 锁定（ticket 10 补证）

**参考实现行为**（`src/screens/AssignmentDetail.tsx:153,158`）：
`completionType === HomeworkCompletionType.GROUP`（= `2`）、
`submissionType !== HomeworkSubmissionType.OFFLINE`（= `0`）；
两个枚举在 thu-learn-lib `lib/module/types.js:65-73`，而 `completionType/submissionType`
原样取列表接口的 `zywcfs` / `zytjfs`（`lib/module/index.js:874-875`）。

**设备实测（2026-09-12，模拟器 Pura 90，2025-2026 春季真实作业）**：站点下发的是**数字代码** ——
`assignment detail appear: … completionType=1 submissionType=2` ——
所以参考实现那两个比较在真实数据上**是对的**（1 = 独立完成，2 = 在线提交）。

**为什么值得单独登记**：ticket 05 的反推夹具里这两个字段是**中文标签**（`'个人'` / `'网络学堂'`，
见 `entry/src/test/fixtures/ContentItemFixtures.ets`），真实形状却是数字。
若按夹具的形状写映射（只认中文标签），两枚 Chip 会在真实数据上全部落进"else"分支 ——
而单测仍会全绿（夹具就是这么写的）。**真实形状与反推夹具不一致时，以真实数据为准并登记。**

**新实现做法**：`features/assignments/AssignmentText` 的 `isGroupCompletion` /
`isOfflineSubmission` **两种形状都认**（数字代码 `'2'`/`'0'` 与站点标签 `'小组'`/`'线下'`），
语义仍落在参考实现的同一分支；单测 `completionAndSubmissionAcceptCodesAndSiteLabels` 同时钉住两种形状。
详情页把**原始值**打进 hilog，于是"映射判错"与"取数没取到"能区分。

**取证**：`AssignmentDetail.tsx:153,158`；thu-learn-lib `lib/module/types.js:65-73`、`lib/module/index.js:874-875`；
`entry/src/main/ets/features/assignments/AssignmentText.ets`；
`.scratch/assignments/evidence/B7-hilog-spring-assignments-full.txt`（`completionType=1 submissionType=2`）。

---

## 21. 优秀作业是**另一条接口**（`yxzylist`）、失败被吞、卡片与详情各显示一处 —— 锁定（ticket 10 补做）

**参考实现行为**：一个取数 + 两处消费，三者的语义都要一起照做。

| 位置 | 行为 | 出处 |
| --- | --- | --- |
| 取数 | 拿完作业列表后，**对同一门课再 POST 一次** `LEARN_HOMEWORK_LIST_EXCELLENT` = `/b/wlxt/kczy/zy/student/yxzylist`，body 与作业列表**同一个** `LEARN_PAGE_LIST_FORM_DATA(courseID)`；取 `json.object.aaData`，按每条 `h.zyid` 归到作业；**整段在 try/catch 里被吞掉**（源码注释 `// Don't block the whole process if excellent homework list cannot be fetched`） | thu-learn-lib `lib/module/index.js:859-864, 894-928`、`urls.js:50` |
| 卡片 | `excellentHomeworkList.length > 0` → 右上角一枚**黄色 medal**（`Colors.yellow500`） | `components/AssignmentCard.tsx:84-91` |
| 详情 | 每条一段：medal 图标 + 附件（**`gradeAttachment \|\| submittedAttachment`**）+ `author.anonymous ? t('anonymous') : author.name` + "X的优秀作业"；附件点击走**同一条** `FileDetail` | `screens/AssignmentDetail.tsx:327-363` |
| 每条记录的附件 | 来自**优秀作业详情页** `/f/wlxt/kczy/zy/student/viewYxzy?wlkcid=&xszyid=`（`urls.js:71`）的**四类附件块**（与作业详情同一套解析） | `index.js:906-920` |

**为什么值得单独登记**：这条接口与作业列表**长得像、语义不同** ——
它**按 `zyid` 分组后可以一条作业多条记录**（不是 1:1）；而且"失败被吞"是**有意行为**：
拿不到优秀作业不该让整页作业失败。**别把这条 catch 当成遗漏去掉**，也别把它改成"取不到就把该作业标成失败"。

**设备实测（2026-09-12，模拟器 Pura 90 / HarmonyOS 6.1.0(23)）**：

| 学期 | 课程数 | 非空课程 | 原始条数 | 备注 |
| --- | --- | --- | --- | --- |
| 2025-2026 春季 | 7 | 2（`…719` 18 条 / `…1080` 6 条） | **24** | 落在 **15 个 `zyid`** 上（6 个 `zyid` 各 2 条）；**24/24 全部匿名**（`sfzm='是'`、`cy=''`） |
| 2026-2027 秋季 | 2 | 0 | 0 | 与"秋季没有作业"一致 |

原始响应（逐字节）落盘后取回：`.scratch/assignments/evidence/P1-excellent-probe-spring.txt`、`P2-excellent-probe-autumn.txt`；
逐课 hilog（含 raw 分块）：`P3-hilog-spring-probe-full.txt`、`P4-hilog-autumn-probe-full.txt`。

**新实现做法（与参考实现的三点差异，逐条写清）**：

1. **请求数如实进汇总行**：`AssignmentsFetcher.fetch` 每门课 +1 POST、每条优秀作业 +1 GET，
   汇总行多一个 `excellent=<n>`（实测春季 `requests=166` = 135 + 7 + 24、`excellent=24`、`failures=0`），
   另有消费点自证行 `data.assignments excellent: course=… zyid=… items=… anonymous=… named=…`。
2. **不取 `getHomeworkDetail(baseId)`**（参考实现对每条优秀作业还会再 POST 一次作业描述接口）：
   该 `baseId` 的作业**本来就在同一次 fetch 里取过描述**，优秀作业段也不显示它。
   这是**请求数减少**，不改变任何界面可观察量；要逐字照抄参考实现的请求集合，就把这一条改回并同步 ticket 05 的计数。
3. **失败粒度比参考实现细一档**：参考实现的 `Promise.all` 一旦某条详情页抛错，**整门课**的优秀作业一起丢；
   这里改成"单条取不到 ⇒ 保留该条（只是没有附件）+ warn 一行"。
   替代验收标准：**整条列表请求失败 ⇒ warn 一行，作业列表与次序完全不受影响**；
   **单条详情页失败 ⇒ 该条保留且无附件**。两条都由 `AssignmentsFetcher.fetchExcellent` 的 warn 分支承载，
   并有单测（`assignmentsFetchParsesFourAttachmentsAndLogs` 里那次 404 就是第一条路径）。

**取证**：上述 thu-learn-lib 行号；`entry/src/main/ets/data/remote/AssignmentsFetcher.ets`（`fetchExcellent`）；
`entry/src/main/ets/domain/parse/AssignmentParser.ets`（文件末尾"优秀作业"一节）；
`entry/src/test/ExcellentHomework.test.ets`；
ticket 10 补做轮的 `G1/G1b/G5b/G8`（真实）、`H1/H3/H7`（夹具）、`G4/I2`（hilog）、`E2`（产物检索）。

---

## 23. 【平台事实】PDFKit 的 `PdfView` **组件**在本模拟器上运行期没有 `pdfViewManager`——应用内 PDF 预览必须走 `pdfService`（ticket 11 新增）

**这是什么**（不是参考实现的怪癖，**不构成保真约束**；是"d.ts 与真实实现不一致"的平台缺口）：

- **编译期**：`@hms.officeservice.PdfView.d.ets` 写的是 `export { pdfViewManager, PdfView }`，`devecocli build` **BUILD SUCCESSFUL**；
- **运行期**（模拟器 Pura 90 / HarmonyOS 6.1.0(23) / `127.0.0.1:5555`，2026-09-12）：点开任意 pdf 文件的瞬间，
  组件构造失败并**崩溃重启**：

      FIX THIS APPLICATION ERROR: @Component 'FilesPage'[119] has error in update func:
      the requested module '@hms:officeservice.PdfView' does not provide an export name 'pdfViewManager'
      which imported by '&entry/src/main/ets/features/files/FileDetailPage&'

  ⇒ 典型的"编译通过、运行期炸"：**门禁全绿也不能证明这条链路可用**。

**新实现做法**：改用**同一套 PDFKit** 的 `pdfService` 命名空间（`@hms.officeservice.pdfservice`），
同步 API、不依赖组件：

    new pdfService.PdfDocument() → loadDocument(path): ParseResult
      → getPageCount() / getPage(i) → PdfPage.getPagePixelMap(): image.PixelMap → ArkUI Image

只渲染当前页（内存有界），界面配"上一页 / 下一页"（`ui_file_prev_page` / `ui_file_next_page` / `ui_file_page_of`）。
**行为仍是"应用内渲染 PDF"**，与参考实现的 `<Pdf>`（react-native-pdf）等价；偏离登记在
`docs/accepted-deviations.md` 第 22 条（渲染器替换 + 不再外跳）。

**为什么别急着改回去**：不要因为 d.ts 里有 `PdfView` 就再把组件装回来——它在**这台模拟器**上会让详情页直接崩。
若将来在别的设备/版本上要复验，先**点开一个 pdf** 看是否崩，而不是只看编译结果。

**取证**：`.scratch/files/evidence/B2-pdfview-crash-hilog.txt`（崩溃原文，模拟器）；
`entry/src/main/ets/features/files/FileDetailPage.ets` 的 `pdfDocument` 字段与 `renderPdfPage`；
`.scratch/files/evidence/` 里 `pdfService` 渲染成功的截图。

---

## 28. 【平台事实】模拟器**实例 ≠ 已部署镜像**；`emulator start` 不负责部署（ticket 16 侦察，2026-09-13）

**这是什么**（不是参考实现的怪癖，**不构成保真约束**；是"模拟器实例 ≠ 已下载镜像"这一层工具行为）：

`devecocli emulator list` 列出四个**实例**，但实例不等于能跑：

| 实例 | 形态 | `config.ini` 的 `imageSubPath` | 该镜像在磁盘上 | 实例目录是否已铺开 |
| --- | --- | --- | --- | --- |
| Pura 90 | phone | `HarmonyOS-6.0.31/phone_all_x86/` | ✅ 有 | ✅ 5 个 `.img/.qcow2` |
| Mate X7 | foldable | `HarmonyOS-6.0.31/phone_all_x86/` | ✅ 有（与 Pura 90 **同一个**） | ✅ 有（userdata 789 MB） |
| MateBook Pro | 2in1 | `HarmonyOS-6.0.31/pc_all_x86/` | ❌ 无 | ❌ 只有 `config.ini` |
| MatePad Pro 13 | tablet | `HarmonyOS-6.0.31/tablet_x86/` | ✅ **有**（账号所有者当日下载） | ✅ **已铺开**（userdata 773 MB） |

镜像库实况（`C:\Users\korac\AppData\Local\Huawei\Sdk\system-image\`）：`phone_all_x86\`（`system.img` 3.67 GB / `sys_prod.img` 838 MB）与 **`tablet_x86\`**（`system.img` 3.67 GB / `sys_prod.img` 629 MB）
（磁盘上还各有约 69 MB 的 `cache.img`，实例目录各约 773–790 MB）。**仍没有 `pc_all_x86`**（2in1）⇒ `MateBook Pro` 起不来（见上表）。

**两个会骗人的地方**：

1. **`devecocli emulator image list` 不加 `--all` 时，列出的是"本地已下载"这一档**，表头里那个 `Downloaded` 列**并不区分本地/远端**——
   在 API 23 这一档它把 phone / foldable / triplefold / widefold 四行都报成 `Downloaded = true`，
   但磁盘上只有 phone 一个镜像，且这四个形态**共用**同一个 `phone_all_x86`（见上表 Mate X7 行）。
   判据：`--device-type tablet` 会直接回 `No matching system images found`，而 `image list --all` 给出的
   API 23 `tablet` 行是 `downloaded: false`。**要把 `Downloaded` 当真，先加 `--all` 并只看与你 API 版本相符的那一行。**
   另注：镜像目录名 `HarmonyOS-6.0.31` 与它实际承载的 API 23 / `6.1.0.115` 对不上，**别按目录名判断 API**。
2. **`devecocli emulator start` 只启动已部署实例，不会替你部署。** 对未铺开的实例它会给出一句
   `was launched but did not appear in hdc list targets within the timeout`，**看起来像超时，其实是启动即失败**；
   真因在 `...\Emulator\deployed\<实例>\Log\Emulator.log` 逐字可见：

       [Critical] [SnUtil.cpp(CheckPublic:229)]can not open image_signature file
       [Critical] [SnUtil.cpp(ShowErrorMessage:138)]can not read uuid file
       [Critical] [SnUtil.cpp(ReadSn:49)]"can not read sn"

   **别把这句话当"等久一点就好"**，也别在超时后盲目重试。

**对本工程的影响（ticket 16 的取证设备选择）**：

- 唯一能直接启动的**大屏**实例是 **Mate X7（foldable，API 23，复用已下载的 phone 镜像）**。
  其 `config.ini`：折叠态 `hw.lcd.single.width=1080`/`density=500` ⇒ 1080/(500/160) = **345.6 vp**；
  `hw.lcd.number=2` ⇒ 展开态第二块屏（近方形），约 **1008 vp** ⇒ **高于 `spec.md` 第 149 行定的 750vp 断点**。
  折叠↔展开切换本身就是"窗口尺寸变化"的真实触发，可用于 ticket 16 的双栏与状态稳定判定。
- **tablet 形态（`MatePad Pro 13`）在镜像铺开后是能用的**（2026-09-13 实测）：启动成功并进 hdc 列表，
  串口 `127.0.0.1:5557` —— **与 Pura 90 的 `5555` 同时在线**，即本机可并行两台模拟器。
  横向 `hw.lcd.single.width=2880`/`density=320` ⇒ **1440 vp × 960 vp**，比 750vp 断点高近一倍。
  代价：每台约占 4 GB 内存与 4 核（本机 31.5 GB / 14 核，容纳两台没问题），且**构建锁与设备锁仍各只有一把**。
- **平板上跑登录前必须先放大数据分区**：其默认 6 GiB 会正好踩中第 12 条那个 `detectIncognito` 误判
  （配额 < 2×堆上限 ⇒ 判成隐私模式 ⇒ 二次验证页**不渲染「信任该浏览器」**，页面显示
  `二次验证成功` + 「您的浏览器目前处于隐私或匿名模式…无法将该浏览器设置为信任浏览器」）。
  **改哪里（2026-09-13 实测，第一次改错了）**：真正被 qemu 读的是**同一目录下 `hardware-qemu.ini` 的 `disk.dataPartition.size`
  （默认 `6g`）**，而 `config.ini` 里的 `hw.dataPartitionSize` **只是记录，改它不生效**——
  只改 `config.ini` 时设备上 `df` 显示 `/data` 仍是 5.7G、used 788M/avail 4.6G，配额也就没上去。
  正确步骤：① 停实例；② 把 `hardware-qemu.ini` 的 `disk.dataPartition.size` 改成 `16g`
  （与 Pura 90 一致，它本来就是 `16g`）；③ **删掉 `userdata.img.qcow2`**（不删就继续按旧的 6g 续用，
  `config.ini` 改了也没用）；④ 启动（会重建 userdata ⇒ **应用要重装、凭据要重来**）。
  判据：启动后 `hdc -t <serial> shell df /data` 应显示约 15G。`config.ini` 那一项顺手也改成 `16384` 以免被 DevEco 覆盖回去。
- **真机复验已完成**（2026-09-13，ticket 18）：真机 MatePad Air / API 24 上跑过一次整体复验。
  真机与模拟器（API 23）的证据**不能互相冒充**，每张图/每份日志按实标注设备；判据与设备清单见 `docs/agents/evidence.md` 与 `docs/agents/environment.md`。

**取证**：`devecocli emulator list` / `device list` / `emulator image list [--all] [--device-type tablet]` 的原始输出；
`...\Emulator\deployed\{Pura 90,Mate X7,MateBook Pro,MatePad Pro 13}\config.ini`；
`...\deployed\MatePad Pro 13\Log\Emulator.log`（2026-09-13 00:02:20 起，783 字节，崩溃原因逐字）；
`...\Sdk\system-image\HarmonyOS-6.0.31\` 的目录列举。

---

## 29. 【平台事实】鸿蒙侧两个「选取附件」picker 的行为（ticket 13 实测；**不构成保真约束**）

**这是什么**：参考实现用 RN 的两个库选附件（`AssignmentSubmission.tsx:120-170`：`DocumentPicker.pick` 与
`launchImageLibrary({mediaType:'mixed', selectionLimit:1})`）；平台替换为 `picker.DocumentViewPicker` 与
`photoAccessHelper.PhotoViewPicker`。以下四条是**设备实测**（模拟器 Pura 90 / `127.0.0.1:5555` /
HarmonyOS 6.1.0(23)，2026-09-13），**不是**参考实现的行为，因此不作为保真判据：

1. **两个 picker 都能在模拟器上打开**（都可重复打开；文件选择器本轮开了两次）。
   文件选择器：最近 / 浏览两个页签、位置（我的手机 13.79 GB 可用 / 32 GB、我的云盘）、
   媒体库（图库）、来源（下载与接收、浏览器）、`已选 (0)`、`完成` 禁用、「仅可访问所选项目」。
   相册选择器：图片和视频 / 所有相册、安全访问图库横幅、拍照磁贴。
   取证：`.scratch/submission/evidence/B4-*.png`、`B5-*.png`、`B8-*.png`。
2. **取消 ⇒ `select` 正常 resolve 成空数组，不是抛异常**（这条决定了代码里不需要参考实现的
   `DocumentPicker.isCancel(err)` 分支）：系统侧 `PickerSheetPage: onThirdSelectCancel` 紧接应用侧
   `document/photo pick cancelled (empty uri list)`。取证：`B-log-pickers-full.txt`。
3. **`photoAccessHelper.PhotoViewPicker` 在本 SDK 上只有无参构造**：带 context 的重载属于
   `@ohos.file.picker` 的旧 `PhotoViewPicker`。写 `new photoAccessHelper.PhotoViewPicker(context)` 会得到
   编译错误 `Expected 0 arguments, but got 1`（本轮实测，构建日志 `t13-build-1.log`）。
   `picker.DocumentViewPicker` 仍是带 context 的推荐重载。
4. **「选到文件」在本模拟器上取不到证据**（不是 picker 的问题，是环境里没有可选内容）：
   用户区为空（「最近」= 没有文件）；`hdc file send` 推入 `…/Docs/Documents/` 的文件**不被「最近」收录**；
   「浏览 → 我的手机」这一行对 `hdc` 级点击**无响应**（两次点击前后截图**字节完全相同**，
   sha256 `4fd49f27c5385bcf603b4b59e74ed1884b6ee58aa3281a75995ab15a22e2a504`）；相册 `itemCount: 0`。
   取证：`B6-*.png` / `B6b-*.png` / `B7-*.png` / `B8-*.png`。
   ⇒ 复现「选到文件 → 附件进入状态机」这一跳，需要**用户区里真的有文件**（或图库里有照片）；
   见 ticket 13 交付的未验证项第 3 条。

**为什么值钱**：第 2 条把「取消要不要按失败处理」这个只能靠实测定的问题关掉了；
第 3 条是「d.ts 与真实构造不一致」的又一例（同第 8、23 条的性质）；第 4 条划清了
「平台能力不可用」与「本机环境没有内容」的界线 —— **别把 B6/B6b/B7 读成 picker 坏了**。

**取证**：`.scratch/submission/evidence/README.md` 与其中的 `B4/B5/B6/B6b/B7/B8/B9-*.png`、
`B-log-pickers-full.txt`；`entry/src/main/ets/features/assignments/AttachmentPickers.ets`。

---

## 30. 收藏 / 归档 / 屏蔽的**三个视图口径不对称**（fav ⊆ all；archived / hidden 用原始 items；置真 append 不去重）—— 锁定

**参考实现行为**（全部逐字可查，行号是 `reference/learnOH-old/`）：

| # | 行为 | 出处 |
| --- | --- | --- |
| A | `all = items.filter(i => !archived.includes(i.id) && !hidden.includes(i.courseId))` | `src/data/selectors/filteredData.ts:77-79`（公告）、`:111-113`（作业）、`:147-149`（文件） |
| B | `fav = all.filter(i => fav.includes(i.id))` —— **在 all 之上再筛**，所以**已归档的条目不出现在收藏夹**、被屏蔽课程的条目同理 | `:83`、`:118`、`:153` |
| C | `archived = items.filter(i => archived.includes(i.id))` 与 `hidden = items.filter(i => hidden.includes(i.courseId))` —— **用原始 `items`**，不套 A 的两条排除：归档视图里能看到被屏蔽课程的条目，屏蔽视图里也能看到已归档的条目 | `:84-85`、`:119-120`、`:154-155` |
| D | **屏蔽（hidden）视图四个列表都有**，不只是课程页：`components/Filter.tsx:211-218` 无条件渲染该项，四个屏幕都传 `hidden`（`screens/Notices.tsx:58`、`Assignments.tsx:60`、`Files.tsx:59`、`Courses.tsx:52`）。**"隐藏课程的内容从列表里消失"指的是从 `all` 里消失**，不是"没有这个视图" | 同上 |
| E | 收藏按钮的状态取的是**过滤后的 fav 分组**（`fav?.some(f => f.id === item.id)`），不是原始 `favorites` 数组 | `src/components/FilterList.tsx:210-215` |
| F | reducer 置真一律 **append、不去重**（`[...state.favorites, id]` / `[...state.archived, ...ids]` / `[...state.hidden, courseId]`） | `src/data/reducers/notices.ts:59-72`、`assignments.ts:69-96`、`files.ts:67-94`、`courses.ts:65-70` |

**E + F 合起来有一个可复现的后果**：先收藏一条公告 → 再到课程页屏蔽它所属的课程 → 打开公告页的"屏蔽"视图 → 该行显示为**未收藏**（因为它在 `all` 之外、不在 fav 分组里）→ 再点一次收藏，`favorites` 里就出现**重复 id**。代码路径逐行可推（不需要设备），本工程的单测 `favoriteAndArchiveTogglingFollowsTheReferenceReducers` 把"append 不去重"钉住。

**为什么别急着"修好"**：这三条（统一三组口径、给 append 加去重、把 hidden 视图从内容三域删掉）都会让可观察行为偏离参考实现，而"移植是否正确"正是拿参考实现当基准的。曾经有一次口头转述把 D 说成"只有课程页有 hidden 视图、三域直接剔除不显示分组"，与源码不符——**以本条的 C/D 为准**（ticket 14 交付里也记了这次更正）。

**新实现做法**：`entry/src/main/ets/features/marks/FilteredContent.ets`（三域分组与计数，逐行对齐 A-F）与 `entry/src/main/ets/domain/marks/CollectionFlags.ets`（迁移规则，含 append 不去重）照抄；隐藏课程的内容从 `all` 里剔除、并提供"屏蔽"视图，与参考实现一致。

**取证**：上表的源文件行号；`entry/src/test/Favorites.test.ets`（`allExcludesArchivedItemsAndItemsOfHiddenCourses`、`favoriteIsASubsetOfAllSoArchivedItemsNeverShowUpInFavorites`、`archivedAndHiddenGroupsKeepTheOtherFilterOut`、`favoriteAndArchiveTogglingFollowsTheReferenceReducers`）；ticket 14 的交付节与 `.scratch/favorites/evidence/README.md`。


---

## 31. 【平台事实】本环境的模拟器**不能旋转、也不能缩放窗口**（Emulator 6.1.1.300 的 scene 命令要 ≥ 7.0）—— ticket 16 新增

**这是什么**（不是参考实现的怪癖，**不构成保真约束**；是"本机模拟器工具链能做什么"这一层事实）：

ticket 16 的验收第 3 条要的是"**旋转或缩放窗口**时正在浏览的详情不丢、不重复请求"。本机两台模拟器
（Pura 90 / MatePad Pro 13）上**没有任何可用的触发手段**，逐条实测如下（原始输出见
`.scratch/splitview/evidence/D-log-rotate-resize-unavailable.txt`）：

| 试过的办法 | 原始结果 | 结论 |
| --- | --- | --- |
| `devecocli emulator rotate --target 127.0.0.1:5557 left` | `Emulator scene control commands require Emulator 7.0 or later. Current Emulator version is 6.1.1.300.` | 整组 scene 命令（rotate / fold / power / volume / battery / sensor / scene / geolocation / shake）都不可用 |
| `devecocli emulator fold --target 127.0.0.1:5557 close` | 同一句版本错误 | 折叠机切换展开/折叠态也不可用（Mate X7 那条路同样走不通） |
| `hdc … shell aa start -a EntryAbility -b … --ww 1200 --wh 1600 --wl 200 --wt 100` | `start ability successfully.`，但随后的 layout dump 仍是 `[0,0,2880,1920]` | 全屏 stage 应用忽略窗口尺寸参数，窗口没被缩放 |
| `hdc … shell wm size` / `wm --help` | `/bin/sh: wm: inaccessible or not found` | 设备上没有 `wm` |
| `hdc … shell hidumper -s WindowManagerService -a '-h'` | `Usage: -h \| -a \| -w {window id} [ArkUI Option]` | WMS 只提供只读 dump，没有设置方向/尺寸的子命令 |
| `hdc … shell param get \| Select-String density\|orient\|rotation` | 没有任何可写的 display density / orientation 参数 | 也没有"改密度换 vp 尺寸"这条后门 |
| `devecocli ui swipe --speed 200 1440 1900 1440 1100`（想开多任务再进分屏） | 应用仍在前台，画面与操作前同态 | 手势进不了多任务/分屏 |
| `devecocli emulator power` 等 | 同版本错误 | 连"灭屏/亮屏"都不可编程 |

**还有一个会骗人的地方**：设备锁屏时 `devecocli ui screenshot` 可能返回**竖屏尺寸**的黑帧
（实测一次：`1920×2880` 全黑，而同时刻的 layout dump 明明是 `[0,0,2880,1920]`）。
**别把那张黑帧当"设备转到竖屏了"** ——它只是锁屏/息屏；先 `hdc … shell power-shell wakeup` 再上滑解锁，
然后重新截图。

**对本工程的影响**：

- ticket 16 验收第 3 条的**运行期**那一半在本环境取不到证据（见该 ticket 交付节的未验证项第 1 条）；
  可迁移的判据只有单测（`entry/src/test/SplitView.test.ets` 的 `splitMigrationPlan` 边界）。
- **真机不受影响**：真实平板/2in1 的旋转与窗口缩放是系统能力（ticket 18 的最终一次性复验正好可以补这一格）。
- 将来要在这类模拟器上做旋转类验收，先确认 Emulator ≥ 7.0（或改用 DevEco 模拟器窗口上的旋转按钮，
  那是 GUI 操作、不在 CLI 可达范围内）。

**取证**：`.scratch/splitview/evidence/D-log-rotate-resize-unavailable.txt`（逐条原始输出）、
`D1-tablet-aa-start-window-params-ignored-layout.json`（`aa start --ww/--wh` 后仍是 2880×1920）、
`D2-tablet-recents-swipe-left-app-foreground.png`（上滑后应用仍在前台）；ticket 16 的交付节。

---

## 32. 搜索字段表里有 **4 个恒不命中的键**（`*AttachmentName` 系列）—— 锁定

**参考实现行为**：`src/hooks/useSearch.ts:5-42` 交给 fuse 的键表里，公告与作业各含若干
`*AttachmentName` 字段，但参考实现的类型里**根本没有这些属性**：

| 域 | 键 | 参考实现里有这个字段吗 |
| --- | --- | --- |
| 公告 | `attachmentName` | ❌ `Notice.attachment` 是**对象**（文件名在 `attachment.name`），没有扁平的 `attachmentName`（`src/data/types/state.ts:104-118`；`thu-learn-lib` 的 `Notification` 同） |
| 作业 | `attachmentName` / `submittedAttachmentName` / `gradeAttachmentName` / `answerAttachmentName` | ❌ 同上：`Assignment` 只有 `attachment` / `submittedAttachment` / `gradeAttachment` / `answerAttachment` 四个**对象**字段（`state.ts:135-166`） |

fuse 按路径取到 `undefined` ⇒ 这 5 个键（公告 1 + 作业 4）**恒不命中**，是字段表里的死权重。
**文件的 `category.title` 不是死键**：参考实现的 `File.category` 是对象（`state.ts:177-190`、`components/FileCard.tsx:72`），那一格是活的。

**为什么别急着「修好」**：把 `attachment.name` 接进检索看起来是「白捡的召回」，
但参考实现**没有**这个行为（附件名从来搜不到），补上就是**行为增强**：
同一个查询会多返回一批参考实现不会返回的条目，「移植是否与参考实现一致」因此失去可比对的基准。
要加就走「新增验收标准」（例如「附件名可检索」）并单独记一笔，不要混进移植。

**新实现做法**：`entry/src/main/ets/features/search/SearchCore.ets` 的字段表**逐字抄权重、
但不含这四个死键**（列在 `REFERENCE_INERT_KEYS`，单测断言它们不在索引字段里）。
另记一条**本工程的数据模型缺口**（不是有意口径）：`MODEL_MISSING_KEYS = ['category.title']` ——
`CourseFile` 没有 `category`（ticket 11/12 的文件模型没取它），所以那一格在本工程里也取不到值。

**取证**：`reference/learnOH-old/src/hooks/useSearch.ts:10,20,22,25,27,40`；
`reference/learnOH-old/src/data/types/state.ts:104-118,135-166,177-190`；
`entry/src/main/ets/features/search/SearchCore.ets`；`entry/src/test/Search.test.ets`（`keeps the reference field tables and weights verbatim`）。





---

## 技术债（**待办清单** · 2026-09-13 起）

> 本节是**唯一**的"待办"口径：这里列的东西**不需要**再走移植期那道门，直接可以做。
> 每条都带**能自己复核**的判据；本轮的完整审计过程与更长的候选清单**不在本文件内**（那属于工作区）。

### A. 代码里仍然存在的限制

| 条目 | 限制 | 判据（可复核） | 后果 |
| --- | --- | --- | --- |
| 32 | 搜索字段表缺 `category.title`（数据模型 `CourseFile` 没有 `category` 字段） | `features/search/SearchCore.ets` 的 `MODEL_MISSING_KEYS = ['category.title']`；`domain/model/ContentItem.ets` 的 `CourseFile` 无该字段 | 文件搜索无法按分类文本召回（`fileType` 权重 2 仍在，故影响小） |
| 30 | 收藏/归档/屏蔽三视图口径不对称；置真 **append 不去重** ⇒ 被屏蔽课程的行显示为"未收藏"，再点一次会写**重复收藏 id** | `domain/marks/CollectionFlags.ets`（`concat([id])` 不去重）；`features/marks/FilteredContent.ets`；单测 `entry/src/test/Favorites.test.ets` | 收藏状态显示错 + 重复 id 记账 |

### B. 仍未定案（需要新的证据，不是改代码）

| 条目 | 为什么还开着 | 下一步（只读探针，不需要账号以外的资源） |
| --- | --- | --- |
| 13 | 纯 HTTP 的 `/login/check` 到底拿不拿得到票据（W1/W2 未判） | 先把**我们发出去的请求**变成可观察量（请求头 / cookie 名与长度 / 表单字段），再谈服务端行为 |
| 14 | `adopt()` 那次失败是"收割时机偏早"还是"跳转链差异"分不开 | 逐次记录 `enrollment cookies` + 收割时刻的 cookie 全集 |
| 17 附注 | `NoticesFetcher` 的**公告详情**请求 `beforeViewXs` 没带 `?_csrf=`，但**参考实现在这里带不带未核** | 读参考实现对这一跳的请求构造，再决定要不要补 |

### C. 已解决但仍留在正文里（读到时不必再研究）

`#1`（HTTP 层内容类型判定，启发式未搬）· `#3`（显式时间序比较器 + 等价断言）· `#7`（手工解析替代 `new URL()`，条件等价）·
`#15`（Netscape 制表符行 + 标准 `Set-Cookie` 双入口解析器）· `#19`（两步排序已补齐）· `#20`（数字码与站点标签都认）·
`#5`（CJK 匹配合并层仍在，但融合引擎已换成自写评分）· `#23`（`PdfView` 组件已弃用，改走 `pdfService`）

### D. 平台/站点事实（无待办）

`#8` · `#11` · `#12` · `#23` · `#28` · `#29` · `#31` · `#17`（正文本身）

### E. 已知的编号冲突（清理本节时一并修）

`#30` 在两份台账里指**两件不同的事**（本文件 = 三视图口径；`accepted-deviations.md` = 设置与 Mock 模式的四处偏离）。
`docs/agents/porting.md` 的"已知缺陷"一节记了这件事；**代码注释里凡是写"第 30 条"的地方都要连台账名一起看**。

