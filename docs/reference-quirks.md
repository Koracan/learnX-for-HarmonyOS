# 参考实现的怪癖台账

**这是什么**：参考实现（`reference/learnOH-old/`）里那些**看起来像 bug、但已被确认为有意行为或历史约束**的点。它们的作用是**阻止未来的优化者"顺手修好"**它们。

**为什么需要单独一份文件**：这类点有两个反复出现的失败模式——
1. 有人读到它，判断"这写错了"，于是改掉；改了之后**行为偏离参考实现**，而移植的完成定义是"与参考实现的行为一致"（见 `spec.md` 第 1 节）。
2. 有人把它当成 bug 权宜而"清理"，结果丢掉的是**鸿蒙能力缺口下的必要补丁**（例如下面第 1 条）。

**这些文件的事实来源**：`reference/learnOH-old/`（只读）。每条都带**源文件与行号**，不是转述。

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

## 2. 自动重登只在结果**恰好等于字符串** `'[]'` 时触发 —— 锁定（并已知其缺口）

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

## 6. 模板内联 <script> 与正文里的 </script> —— ticket 04 新增（已加固）

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

**取证**：`reference/learnOH-old/src/helpers/html.ts:108`（`${content}` 直接插值）；
`entry/src/main/ets/domain/render/WebViewTemplate.ets` 的 `escapeScriptEndTags`；
`entry/src/test/NoticeDetail.test.ets`。

---

## 7. 模板注入脚本里的 new URL() —— ticket 04 新增（改成等价的手工解析）

**参考实现行为**：`helpers/html.ts:60-66` 的注入脚本用 `new URL(url)` 取 hostname，只对
**hostname 以 `tsinghua.edu.cn` 结尾**的 `href`/`src` 追加 `_csrf`。

**为什么别急着改**：这不是 bug，它依赖注入脚本跑在一个有来源的文档里。移植到 ArkWeb 时这个
前提变了（文档由 `loadData` 生成，是 opaque origin，`new URL()` 抛 TypeError），照抄会让全部链接
更新失败。但**改法必须是等价的手工解析**，不能把只对 tsinghua 追加这个条件去掉——那会变成对
所有链接都追加 `_csrf`，是行为偏离。

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

## 8. ArkWeb 的两条平台事实（不是参考实现的怪癖，但会误导移植者）—— ticket 04 新增

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

## 待查

（暂无。发现新的怪癖时追加，格式同上：参考实现行为／为什么别急着改／新实现做法／取证。）
