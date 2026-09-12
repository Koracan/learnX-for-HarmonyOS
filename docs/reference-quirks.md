# 参考实现的怪癖台账

**这是什么**：参考实现（`reference/learnOH-old/`）里那些**看起来像 bug、但已被确认为有意行为或历史约束**的点。它们的作用是**阻止未来的优化者"顺手修好"**它们。

**为什么需要单独一份文件**：这类点有两个反复出现的失败模式——
1. 有人读到它，判断"这写错了"，于是改掉；改了之后**行为偏离参考实现**，而移植的完成定义是"与参考实现的行为一致"（见 `spec.md` 第 1 节）。
2. 有人把它当成 bug 权宜而"清理"，结果丢掉的是**鸿蒙能力缺口下的必要补丁**（例如下面第 1 条）。

**这些文件的事实来源**：`reference/learnOH-old/`（只读）。编号条目都带**源文件与行号**，不是转述。

**两类条目，别混用判据**：
- **参考实现怪癖**（绝大多数编号条目）：定义"移植要与什么保持一致"。状态用 `锁定`／`已复审`／`待查`。
- **平台事实**（标题里注明【平台事实】的条目）：是本工程在**设备上实测**到的平台行为，**不是**参考实现的行为，因此**不构成保真约束**。它的作用是解释"为什么参考实现在平台上的写法不能照抄"，证据是设备 hilog 而非源文件。

## 怎么用

- **动手改任何一条之前**：把该条的状态从 `锁定` 改成 `已复审`，写清**为什么现在可以改**、以及**哪条验收标准随之改变**。只改代码不改这张表，等于隐式推翻决策。
- 若你在移植中发现**新的**怪癖：按下面的格式追加一条，**必须带源文件与行号**。不要写"据说/印象中"。
- 状态三档：`锁定`（必须照参考实现做）／`已复审`（已决定偏离，写明理由与替代验收）／`待查`（怀疑是怪癖但还没取证）。

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

## 2. 自动重登只在结果**恰好等于字符串** `'[]'` 时触发 —— 已复审（触发并集仍锁定；「重登后仍 `'[]'`」这一支在 ticket 08 收口）

**参考实现行为**（`src/data/source.ts:104`）：
```ts
let result = await task(cookieString, csrfToken);
if (result === '[]') {           // ← 精确字符串比较
  ...loginWithFingerPrint();     // 重新认证后重试一次
}
```
它**只看返回值是不是字面量 `'[]'`**，不看 HTTP 状态码、不看响应是否为登录页、也没有其它失败分支。

**这是有意的最小化处理，不是遗漏**：参考实现是把"会话失效"的判据**下放给被调用的 task**——task 内部解析失败时返回 `'[]'`。统一在这个出口判定，逻辑集中、不需要每个调用点各写一套。

**已知缺口（新实现必须补，但别改这条的语义）**：服务端**直接拒绝**时不会返回 `'[]'`（可能返回 HTML 登录页或带错误码的响应），于是**这条路径不触发重登**。ADR-0004 的 Consequences 已明确指出这一点，并要求新实现"任何非预期响应一律降级到 Enrollment"。

所以：**保留 `'[]'` 这条判据的语义**，同时**在它之外补上**服务端直接拒绝的分支（**注意：这条分支参考实现已经存在于另一条路径里，见下方更正——不是让我们自己发明**）。不要把它重写成"只判断状态码"——那会丢掉 task 内部解析失败这条路。

**取证**：`src/data/source.ts:104`（触发条件）、`:121-124`（重登后仅重试一次，无循环重试）。

**更正与补强（2026-09-12 查证）：参考实现里其实有【两条】重登路径、两个不同触发条件——"服务端直接拒绝"那条分支参考实现【已经有】，只是在另一个库里。**

| 路径 | 触发条件 | 取证 |
| --- | --- | --- |
| 原生处理器路径（本工程真正要移植的那条，用于三域抓取与上传） | 结果字符串**恰好等于** `'[]'` | `src/data/source.ts:104` |
| thu-learn-lib 路径（课程/学期/提交等库方法） | `noLogin(res)` = `res.url.includes('login_timeout') \|\| res.status == 403` | `node_modules/thu-learn-lib/lib/module/index.js:21`、`:46-71` |

所以新实现要做的**不是"自己发明一条补充分支"，而是把参考实现这两半的并集都覆盖**：`'[]'` **或** 响应 URL 含 `login_timeout` **或** 状态码 `403` → 重登，且**只重试一次**（两条路径都只重试一次，无循环）。这样 ADR-0004 要求的"任何非预期响应一律降级到 Enrollment"就落在参考实现既有语义上，而不是新增推测——论证强度完全不同，之前那种写法容易被当成"移植者擅自加戏"。

另一条路径重登后还会再判一次：仍 `noLogin` → `NOT_LOGGED_IN`；状态码非 200 → `UNEXPECTED_STATUS`（`index.js:49-68`）。这两个失败原因值得照搬成可诊断的错误分类。

**ticket 08 收口（2026-09-12，本条改判为「已复审」的那一半）**：触发条件与"只重试一次"两条**保持锁定**——并集照上表，`SessionGate`（06 交付）**一行语义都没改**。偏离的只有**重登之后仍然返回 `'[]'`** 这一支：

| 项 | 参考实现 | 新实现 | 替代验收标准 |
| --- | --- | --- | --- |
| 重登后仍 `'[]'` | 静默把 `'[]'` 交给调用方（界面表现为"空列表"，看不出会话其实没恢复） | `SessionGate` 仍原样返回（`sessionLostAfterReAuth=true`，06 已交付）；**调用方** `AuthedTaskRunner` 把它翻成 `requiresEnrollment=true`，值不往上传 | 单测 `degradesWhenTheListIsStillEmptyAfterReAuth`：任务两次都返回 `'[]'` 时结果 `requiresEnrollment === true`、`value === ''`；界面停回登录页并说明需要重新验证 |

**为什么这次可以偏离**：ADR-0004 的 Consequences 明文要求"任何非预期响应一律降级到 Enrollment"，而"重登成功但列表仍空"正是"非预期响应"；ticket 06 交付 `sessionLostAfterReAuth` 时就把这个口子留给了调用方（其 Comments 原话是"便于日后升级为 Enrollment 而不改行为"），本 ticket 就是那个"日后"。**触发条件那条没有动**，所以"移植是否与参考一致"仍有可比对的基准。

**取证**：`entry/src/main/ets/data/auth/SessionRestore.ets`（`AuthedRunResult.fromGate`）；
`entry/src/test/SessionRestore.test.ets`；`entry/src/main/ets/data/auth/ReAuth.ets`（未改）。

补充两条同源事实（都在 `source.ts`，ticket 06 要用）：`loginWithFingerPrint` **每次登录前先清空全部 cookie**（`:11-28,37`，注释写明"HarmonyOS cookies may persist unexpectedly"——又一处平台能力缺口补丁）；自定义 fetch **强制桌面 Chrome UA**（`:55-57`）。

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

**新实现的缺口**：`entry/src/main/ets/domain/parse/Text.ets` 的 `decodeHtmlEntities` 只覆盖参考实现 DataProcessor 的 **6 个命名实体**，而**渲染层的 `removeTags` 等价物目前没有实现**。真实公告的 `content` 含 `<p>` / `<span>` / `&nbsp;`（ticket 03 的 mock 逐字保留了这些），标题也可能含标签。

**后果与边界**：若在 UI 里直接渲染原始字段，界面上会出现字面量 `<p>`、`&nbsp;`、`&#39;`。这是**渲染层**的活——不要靠"让解析层解码"来解决，那正好违反本条上半。

**取证**：`src/helpers/html.ts:11-22`（`he.decode`、注释与标签正则、连续空白折叠、`trim`）；`src/components/NoticeCard.tsx:42,72`；`src/data/mock.ts:242-352`（7 条公告的原始 content 形状）。

---

## 5. 搜索的"手工精确匹配合并"是 CJK 下的必要行为 —— 锁定

参考实现里有一段看起来冗余的"手工精确/前缀匹配再合并"逻辑。**它不是权宜之计**：`fuse.js` 的 Bitap 与 `flexsearch` 的 `cjk` charset 对中文都**按码点逐字切分**，匹配不了拼音/同音字。这段合并层是 CJK 场景下的**必要补偿**，必须保留。拼音检索需独立拼音索引字段（后续增强，不在本次范围）。

**取证**：`.scratch/migration/search-package-eval.md`；`spec.md` 第 8 节「搜索的 CJK 注」。

---

## 6. 模板内联 <script> 与正文里的 </script> —— 已复审（ticket 04 加固）

**参考实现行为**：`helpers/html.ts:32-118` 的 `getWebViewTemplate` 把正文 `content` 直接拼进
模板（`:108`），而模板里有若干内联 `<script>`（CSRF 注入、DarkReader、KaTeX、数学调用）。
正文里若出现字面量 `</script>`，HTML 解析器会**提前结束**那个 script 元素，其后的正文被当成
裸 JS 执行。

**为什么别急着照抄**：这与本项目已经在登录页注入面上采取的加固原则冲突（`spec.md` 第 5 节
把 Enrollment 的注入面缩小而不是扩大）。危害面取决于上游正文——目前 Mock 是硬编码字面量
（无风险），但 ticket 09 会换成真实抓取的正文。

**新实现做法**：`domain/render/WebViewTemplate.ets` 的 `escapeScriptEndTags` 把正文里的
`</script` 转义成 `<\/script`（对渲染无影响：HTML 里 `<\/script` 不是有效标签，按文本显示）。
**只在正文含该字面量时才有差异**，单测 `escapes script end tags in the notice content` 守住。

**替代验收标准（本表"已复审"档要求写明的那一条）**：正文含字面量 `</script>` 时，
渲染结果**仍是文本**（既不被当作裸 JS 执行，也不提前结束模板里的内联 `<script>`）——
由单测 `escapes script end tags in the notice content` 断言"产物里只剩模板自己的 3 个 `</script>`"来承载。

**取证**：`reference/learnOH-old/src/helpers/html.ts:108`（`${content}` 直接插值）；
`entry/src/main/ets/domain/render/WebViewTemplate.ets` 的 `escapeScriptEndTags`；
`entry/src/test/NoticeDetail.test.ets`。

---

## 7. 模板注入脚本里的 new URL() —— 锁定（ticket 04 因平台约束换实现方式，行为等价）

**参考实现行为**：`helpers/html.ts:60-66` 的注入脚本用 `new URL(url)` 取 hostname，只对
**hostname 以 `tsinghua.edu.cn` 结尾**的 `href`/`src` 追加 `_csrf`。

**为什么别急着改**：这不是 bug，它依赖注入脚本跑在一个有来源的文档里。移植到 ArkWeb 时这个
前提变了（文档由 `loadData` 生成，是 opaque origin，`new URL()` 抛 TypeError），照抄会让全部链接
更新失败。但**改法必须是等价的手工解析**，不能把只对 tsinghua 追加这个条件去掉——那会变成对
所有链接都追加 `_csrf`，是行为偏离。

**为什么状态是"锁定"而不是"已复审"**：新实现**没有偏离**参考实现的行为——同一条件、同一追加方式、
同一跳过规则，只是把 `new URL()` 换成手工解析（等价的实现方式替换）。既然保真约束本身没变，按本表的词表
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

## 10. 提交报文里的 `fingerPrint` 取**页面值**而不是自造值 —— 已复审（ticket 07）
状态：**参考那套（自造 UUID）已在 2026-09-12 的真实登记上实测失败**；站点脚本带版本戳
`v=20260830062616`（2026-08-30 改版），晚于参考实现的最后修改，因此"参考能跑通"这一前提本身不再成立。

**参考实现行为（2026-09-12 补证，之前读漏了）**：它**自己生成随机 UUID**——
`SSO.tsx:33-39` 的 `useRef('xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(...))`（`Math.random`），
经 `SSO.tsx:51` 的 `replaceAll('${fingerPrint}', …)` 注入脚本；`sso.js:66` 把它写进 `#fingerPrint`、
`sso.js:24` 注入 `saveFinger` 的 XHR；`SSO.tsx:76` 再**回读表单实际提交的值**存为凭据。
⇒ 参考**在 fingerPrint 上同样偏离 stock（36 字符 UUID，形状与我们改造前一模一样）**，
而用户那次失败用的正是我们的 UUID。**所以本条不是"更忠实于参考"，而是"参考的取法在当前站点上已失败"。**

**为什么偏离**：2026-09-12 的真实登记（用户在模拟器上完成短信验证）被服务端拒绝授予信任，
原话"您的浏览器目前处于隐私或匿名模式，系统无法将该浏览器设置为信任浏览器"
（消息键 `double_sfjbsbbjwxrsb3`，见站点消息字典 `/common/public/all-messages.js`）。
把**提交报文**逐字段与"stock 浏览器"对比后，**唯一不同的一栏就是我们覆盖掉的 `fingerPrint`**：
`fingerGenPrint` / `fingerGenPrint3` 对未登录会话恒为空（设备实测
`POST /b/doubleAuth/personal/getFinger3` → `result=error`，匿名 HTTP 探针同样如此），
`deviceName` 我们没动（页面写 `other,Chrome/132`），`singleLogin` 是站点本意要勾上的。
`login.html:431-432` 又证明页面自己会给 `#fingerPrint` 赋值（fingerprintjs2，设备实测 `fpChars=32`）。
在只有证据没有猜测的前提下，**让报文与 stock 浏览器一致是唯一有依据的可控变量**。

**新实现做法**：生效指纹 = **页面自己算出的 fingerprintjs2 值**；只有页面没给出值时，才用我们生成的
UUID 兜底。同一个生效值用于三处：表单字段、`saveFinger` 的 XHR、凭据落盘与重登回放。
**store-and-replay**：登记值与重登出示值仍然**逐字相同**（不需要复算页面值——服务端记录的就是它
收到的那一个字符串）。日志里以 `fingerprintSource=page|fallback` 自证取的是哪一个。

**替代验收标准（本表"已复审"档要求写明的那一条）**：**提交报文里的 `fingerPrint` 必须等于页面
fingerprintjs2 的值；页面没给出值时才用我们生成的 UUID 兜底；且三处同值**（三点脱敏等式
`formFieldDom` = `saveFingerXhr` = `persistedReadBack`，判据本身不变），
不再要求它等于"我们生成的 UUID"。

**附注 1（事实，不是偏离）**：`/b/doubleAuth/personal/saveFinger` **在登录页加载的任何脚本里都不存在**
（把抓下来的全部站点脚本搜过；此前看到的 "saveFinger" 都是 `saveFinger3Local`/`saveFinger2Local` 的子串）。
⇒ 只能确定"登录页不调它"。用户看到的失败发生在「二次验证成功」**之后**的另一个页面，那个页面本工程
尚未抓到，所以**它仍可能在那里被调用**（参考实现专门为它打了补丁，作者多半见过它发出）。
实验里若诊断日志**没有** `saveFingerRequest`，那是**一条信息**（信任登记不走这个端点），
**不是 bug**，不要去"修"。

**附注 2（另一处已知偏离，本次实验**不动**）**：`deviceName` 参考是
`HarmonyOS,learnOH/{packageJson.version}`（`SSO.tsx:52`），本工程是
`HarmonyOS,learnOH/{versionName} ({productModel})`（`core/device/AppIdentity.ets:4`，
依据 spec 第 5 节）。**本次实验一次只动一个变量**：`deviceName` 不改，但两个值（页面 DOM 里的与
我们的）都会进日志，便于事后判断服务端看到的是哪一个。

**取证**：`reference/learnOH-old/src/screens/SSO.tsx:33-39,51-52,76`；
`reference/learnOH-old/src/helpers/preval/sso.js:24,66`；
ticket 07 Comments 的「方案 A」；`.scratch/enrollment/evidence/07-diag-prefix-finger3-empty.txt`
（`xhr res path=/b/doubleAuth/personal/getFinger3 … result=error`、`diag:idb roundTripOk=true`）；
`entry/src/main/ets/domain/auth/EnrollmentScript.ets` 的 `effectiveFingerPrint`；
`docs/adr/0004` 的正文仍需按本条修订（原文写"我们生成的设备指纹"）。

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

## 待查

（暂无。发现新的怪癖时追加，格式同上：参考实现行为／为什么别急着改／新实现做法／取证。）
