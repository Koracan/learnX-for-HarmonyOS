# 已复审的偏离记录（原 `docs/reference-quirks.md` 的"已复审"条目）

**这是什么**：**已经复审并批准**对参考实现偏离的条目 —— 每条都写明"参考实现是什么 / 我们为什么偏离 / 替代验收标准是什么"。

**它不再起什么作用**：这些条目**不再是约束**。留着的用处只有两个：
1. **可追溯**：将来有人问"这里为什么和参考实现不一样"，答案在这里，不必靠记忆或考古提交历史；
2. **替代验收标准的出处**：编号与原 `docs/reference-quirks.md` **完全一致**，所以旧的"台账第 N 条"引用按号仍然找得到。

**仍然生效的约束在哪**：`docs/reference-quirks.md`（`锁定`／`待查`／【平台事实】／【站点事实】）。要新偏离一条锁定项时，
先在那里写清理由与替代验收，**复审通过后再把该条迁到本文件**（保持编号），并在那边的索引里留一行。

**注意**：第 2 条与第 16 条**迁移后仍含生效约束**（各自条目标了【仍锁定】/【改判·仍是约束】），别只看到"已复审"就当历史。

**格式**：与迁移前一致 —— 参考实现行为（带源文件行号）／为什么偏离／新实现做法／**替代验收标准**／取证。

---

## 2. 自动重登只在结果**恰好等于字符串** `'[]'` 时触发 —— 已复审（触发并集仍锁定；「重登后仍 `'[]'`」这一支在 ticket 08 收口）

> **【仍锁定】**本条**不是**纯历史记录：重登触发条件的**并集**仍锁定（不要改成只认字符串 `'[]'`）。已复审的只是"重登后仍返回 `'[]'`"那一支的处置。

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
收到的那一个字符串）。日志里以 `fingerprintSource=pageBody|pageDom|fallback` 自证取的是哪一个。

**2026-09-12 补正（D1）**：`saveFinger` 的 XHR patch **只在页面没给值时**才写 `fingerprint`，
**绝不覆盖非空值**——二次验证页（`doubleAuth.bundle.js`）自己已经在 body 里放了正确的指纹。
旧实现无条件覆盖，而那一页没有 `#fingerPrint` 字段（那是登录页的），于是每次回落成 36 字符兜底 UUID，
把页面 32 字符的值改掉（表单 32 / saveFinger 36）。**落盘的 `fingerPrint` 必须是 saveFinger 实际发出的
那个值（回读值）**：权威顺序 = `saveFingerXhr` > `formFieldDom` > `generatedFallback`
（`domain/auth/EnrollmentScript.ets` 的 `resolveEnrollmentFingerPrint`，唯一一处定义）。

**硬约束（2026-09-12 第 4 次真实登记后升级为硬约束）**：**登记值与出示值必须逐字一致**。落地为两条：
① `saveFinger` 的 XHR patch **绝不覆盖页面已给的非空 `fingerprint`**；② 落盘/重登回放用的是**同一处解析结果**
（`resolveEnrollmentFingerPrint`，权威顺序 `saveFingerXhr` > `formFieldDom` > `generatedFallback`）。
理由不是洁癖：服务端记录的是**它当时收到的那一个字符串**，而重登出示的是**凭据里那一个**——两者不一致就等于
"登记了一个永远不会被出示的值"。离线机制证据：单测 `neverOverwritesTheFingerprintThePageAlreadyPutInTheSaveFingerBody` /
`prefersTheSaveFingerValueOverTheDomValueAndTheFallback`；
设备侧的正验证：第 4 次登记 `enrollment fingerprint effective: value=8983…(32) source=formFieldDom pageDomSource=page usingFallback=false`
并且 `formFieldDom=746a15a2 persistedReadBack=746a15a2 formEqualsPersisted=true`。

**替代验收标准（本表"已复审"档要求写明的那一条）**：**提交报文里的 `fingerPrint` 必须等于页面
fingerprintjs2 的值；页面没给出值时才用我们生成的 UUID 兜底；且三处同值**（三点脱敏等式
`formFieldDom` = `saveFingerXhr` = `persistedReadBack`，判据本身不变），
不再要求它等于"我们生成的 UUID"。

**附注 1（2026-09-12 已推翻并更正；同日第 4 次真实登记后**升级为「已确证」**，见本节末）**：原文写"`/b/doubleAuth/personal/saveFinger` 在登录页加载的
任何脚本里都不存在 ⇒ 信任登记不走这个端点"——**这条推测是错的，已被 2026-09-12 10:57 那次真实登记的
设备日志推翻**（原文保留在此以免有人以为它从未出现过）：

- `10:57:08.553` `[xhr] req … path=/b/doubleAuth/personal/saveFinger n=4` →
  `10:57:08.600` `[xhr] res … status=200 chars=92 result=success … msgs=[msg=已增加]`；
  页面自己还打印了 `save local finger success`（`10:57:08.584/08.586`）。
  ⇒ **端点确实被调用，且服务端回了"已增加"**。
- **错的起因为什么值得记下来**：当时只把**登录页加载的脚本**搜了一遍就下了"不存在"的结论，
  而调用点在 `login/check` **之后**的二次验证页 bundle（`doubleAuth.bundle.js`）里——
  **"没搜到"不等于"不存在"**，尤其当搜索范围本身就是结论的一部分时。这是本表的一条方法论警告：
  范围受限的否定证据只能支持"在我搜过的范围内没有"，不能支持"不存在"。
- **取证**：`.scratch/enrollment/evidence/experiment-1057/experiment-1057-full.txt`（应用域 `A04c4f`）。
- **对本条实现的影响**：saveFinger 的 XHR patch 是**有效且必要**的注入点；随之而来的 D1 缺陷
  （我们覆盖了页面自己放好的指纹）见 `EnrollmentScript.ets` 的 `patchSaveFinger` 注释。

**升级为「已确证」（2026-09-12 第 4 次真实登记，免短信）**：本条不再只是"端点被调用过"。两个正向观测合起来足以把它定为
**站点的信任登记步**：

1. `saveFinger` 在**二次验证页**（就是渲染「信任该浏览器」单选项的那一页）上被调用，服务端回
   `result=success msgs=[msg=已增加]`——"**已增加**"是**新增登记**的语义（10:57:08.555 / 08.600，见上）。
2. 此后同一账号、同一浏览器再次登录时，`/login/check` **不再渲染二次验证页**（脚本集从 `doubleAuth.bundle.js` 换成
   `genprint.js`），表单提交到漫游**只用了 1.62 秒**；`doubleAuth/login` / `saveFingerRequest` / `radioVal` /
   `验证码` / `captcha` / `短信` **全部 0 命中** ⇒ 站点**直接信任、未要求任何短信**（12:01 那次
   `enrollment session established: via=browser-cookie-adopt`）。

⇒ **"`saveFinger` = 信任登记"：已确证。** 取证：`.scratch/enrollment/evidence/experiment-success/`（3 个 `.gz` 原件 + 应用域抽取）。

**边界（必须与上面那句分开读）**：第 4 次登记时 **`saveFinger` 根本没有被调用**（`saveFingerObserved=false`），
也就是说那次免短信**不是"这次登记成功"的结果**，而是"**站点在更早的某次已把该浏览器记为可信**"。更早那次（10:57）恰在
**D1 缺陷**下发出登记值 = **36 字符兜底 UUID**（`fingerprintChars=36 fingerprintSource=fallback`），而第 4 次出示的是
**32 字符页面值**（`source=formFieldDom`）。若服务端严格按"出示值 == 登记值"命中，那次登记**不应生效**。
⇒ **"信任以 `fingerPrint` 为键（严格逐字命中）"这一点仍未验证**：可能键不是它本身，也可能判据更宽松。
判定它只能靠 **ticket 08 的"无短信纯 HTTP 重登成功"**——而 2026-09-12 实测**失败**（`no ticket anchor in id login check response`），
所以这条**至今没有正面证据**。**不要**拿"免短信"去替代它（两个论断不能复用同一份证据）。


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

## 16. 公告卡片的状态图标：参考实现用三色图标，新实现用同色 emoji —— 已复审（ticket 09）→ **【改判】改用与参考实现一致的扁平矢量图标（ticket 11.5）**

> **【改判·仍是约束】**本条原评审结论（"用 emoji + 颜色/位置判据"）已被账号所有者**推翻**（2026-09-12）。
> 现在的约束是：**图标必须与参考实现同形**（扁平矢量）、单色、颜色走令牌；**不要用 `SymbolGlyph`**；
> 推荐内嵌参考实现那份 `MaterialCommunityIcons.ttf`。执行细节与验收在 **ticket 11.5**。

**参考实现行为**（`src/components/NoticeCard.tsx:45-69`）：卡片右上角最多三个图标，来自
`react-native-vector-icons/MaterialCommunityIcons`：

| 图标名 | 颜色 | 令牌 | 条件 |
| --- | --- | --- | --- |
| `attachment` | 橙 | `Colors.orange500` = `#ff9800` | `attachment` 存在 |
| `flag` | 红 | `Colors.red500` = `#f44336` | `markedImportant` |
| `checkbox-blank-circle` | 蓝 | `Colors.blue500` = `#2196f3` | `!hasRead` |

**为什么不能照抄**：MaterialCommunityIcons 是 RN 生态的字体图标包，ArkUI 没有对应物。
候选有两个：`SymbolGlyph`（系统符号库）与 emoji 文本。前者的问题不是"做不到"，而是
**符号 id 不可移植**——符号集随系统字体版本变化，拿 `attachment` 这样的名字猜 id 会得到
"编译通过、运行时空格"的失败模式，而且它无法保证"橙/红/蓝"三种语义色（`SymbolGlyph` 的
着色是单色渲染层的事）。emoji 在**本模拟器（Pura 90 / HarmonyOS 6.1.0(23)）上逐帧可验**，
且颜色由 `PLAIN_PALETTE` 令牌给出，与参考实现同源。

**新实现做法**：三个标记都用文本渲染，颜色取**同一批令牌**（`PLAIN_PALETTE.orange500` /
`red500` / `blue500`），顺序与参考实现一致（附件 → 重要 → 未读）。因为 emoji 本身不带
语义文字，两个图标各挂一条 `accessibilityText`（`ui_attachment_label` /
`ui_marked_important_label`）——参考实现的图标名对读屏就是名称，这里用 i18n 键补上。
未读**改回纯圆点**（参考实现就是纯圆点；ticket 03 曾额外加"未读"文字，本 ticket 移除）。

**替代验收标准（本表"已复审"档要求写明的那一条）**：公告卡片右上角在
`attachment` 存在时出现橙色标记、在 `markedImportant` 时出现红色标记、在
`hasRead === false` 时出现蓝色圆点；三者可同时出现，顺序为附件 → 重要 → 未读；
**判据是设备截图上的颜色与位置，而不是"用了名为 attachment 的图标"**。
**改判（2026-09-12，账号所有者裁定，见 ticket 11.5）**：上面那条"emoji + 颜色/位置判据"的降级验收**被推翻**。
账号所有者明确要求**与旧实现一致的扁平图标风格**（我们当前是拟物/emoji，旧实现是扁平矢量）。

- **新的替代验收标准**：图标与参考实现**同形**（同一图标名对应的字形），单色矢量、颜色仍由 `PLAIN_PALETTE` / 主题令牌给出；
  判据从"颜色与位置对得上"升级为"**形状也对得上**"（逐屏与旧实现截图对照，一屏一对文件）。
- **实施条件已查明**：参考实现用的那份字体就在本地仓库里 ——
  `reference/learnOH-old/node_modules/react-native-vector-icons/Fonts/MaterialCommunityIcons.ttf`（1,147,844 B）与 `MaterialIcons.ttf`（356,840 B）；
  名称 → codepoint 可照 `react-native-vector-icons` 的 glyph map 抄。**推荐内嵌同一份字体**（保真度最高），
  备选 SVG 资源；**仍然不要用 `SymbolGlyph`**（理由见上：符号 id 不可移植）。
- **影响面**：本条的三个标记**只是其中一处**；作业卡片 5 枚、课程卡片 3 类计数、底部 tab 栏、页面顶栏、设置项都要一起换。
  清单表、逐屏对照证据、许可证与 hap 体积代价都由 **ticket 11.5** 负责。
- **原证据还成立到哪一步**：ticket 09/10/12 那些"颜色/位置对得上"的截图**仍然成立**（它们证明的是同一件事的颜色与顺序），
  只是验收判据升级；ticket 11.5 会在这三个 ticket 里各写一句边界说明。

**取证**：`reference/learnOH-old/src/components/NoticeCard.tsx:45-69`、
`reference/learnOH-old/src/constants/Colors.ts`；
`entry/src/main/ets/features/notices/NoticesPage.ets` 的 `statusIcons`；
ticket 09 的模拟器截图（`.scratch/notices/evidence/`）。

**执行结果（2026-09-12，ticket 11.5 交付）**：约束落地为**内嵌同一份字体**——
`reference/learnOH-old/node_modules/react-native-vector-icons/Fonts/MaterialCommunityIcons.ttf`（1,147,844 B）
与 `MaterialIcons.ttf`（356,840 B）拷进 `entry/src/main/resources/rawfile/fonts/`，
运行时用 `font.registerFont` 注册（`ui/icons/IconFont.ets`），字形码位照 `react-native-vector-icons@10.2.0`
的 glyphmap 抄成**闭集枚举**（`ui/icons/IconCatalog.ets`），渲染走**唯一的** `IconGlyph` 组件
（`ui/icons/IconGlyph.ets`）。**没有用 `SymbolGlyph`**。
- 代价：hap 体积 **+1,504,684 B ≈ +1.44 MiB**（两个 TTF 的字节和；单 MCI 是 +1,147,844 B ≈ +1.09 MiB），
  加上许可证文本；逐屏对照证据、码位表与 hap 体积实测都在 ticket 11.5 的交付节。
- **许可证口径的一处更正**：本 ticket 的原话是"Material Design Icons 为 OFL-1.1"。
  实测：`react-native-vector-icons@10.2.0` 打包的那份字体来自 `@mdi/font ^6.5.95`，
  而该版本仓库（`Templarian/MaterialDesign-Webfont@v6.5.95`）的 LICENSE 写的是
  **"Fonts: Apache 2.0"**（Pictogrammers Free License）；`MaterialIcons.ttf` 是 Google 的 Apache-2.0。
  ⇒ 仓库里**两份许可证都随附**（Apache-2.0 为主、OFL-1.1 一并留存），出处与字节数写在文件头，
  不擅自把口径改成其中一种（见 ticket 11.5 的"未验证/更正"一节）。
- 回退口径：注册失败（`font.registerFont` 抛错或 `getFontByName` 取不到 path）时，
  `IconFont.markNotReady` 落一条 `error` hilog，界面渲染**可读文本**（无障碍文案 / 短名）而不是空白——
  设备实证（故意把 rawfile 改名）见 ticket 11.5 的回退证据。

---

## 18. 课程 / 学期这条线的四处有意偏离 —— 已复审（ticket 12）

**参考实现行为**（参考工程 reference/learnOH-old/）：

| # | 参考实现 | 出处 |
| --- | --- | --- |
| A | 学期切换页挂在**设置栈**（SettingsStackParams.SemesterSelection），不在课程栈 | src/screens/SemesterSelection.tsx、src/screens/types.ts |
| B | 课程详情页每个标签页各自 dispatch(getXxxForCourse(courseId))，**按课程二次取数** | src/screens/CourseDetail.tsx:36-40,72-76,108-112 |
| C | 当前学期**只能**由界面点选写入 redux（setCurrentSemester） | src/screens/SemesterSelection.tsx:38-40 |
| D | 三类计数从**已加载的全局 state** 算（selectCoursesWithCounts），而不是课程页自己抓 | src/data/selectors/filteredData.ts:24-49 |

**为什么偏离（逐条）**：

- **A**：ticket 12 的交付物把"学期选择"与课程放在一起（课程 tab 头部点学期名进入）。
  位置属导航结构，行为（列出可选学期、切换、列表随之更新）一字未变。
- **B / D**：本工程的一次刷新**已经取回三域**（课程 + 公告 + 作业 + 文件），再按课程各发一次会重复请求
  （3 × N 门课）。参考实现之所以要各发一次，是因为它可以**直接**进入课程详情而全局 state 里可能还没有
  该课程的内容；本工程把三域放在**同一次抓取**里，进详情时数据已在手上。D 是同一原因的正向结果：
  计数与列表**同源**，不会出现"列表是新的、计数是旧的"。
- **C**：这是本表里**唯一影响取数能力**的偏离。统筹给的事实：本账号 **2026-2027 学年秋季学期没有作业**，
  而 ticket 10（作业）/ 13（提交）的验收必须拿到 **2025-2026 学年春季学期**的真实作业。
  若只能靠界面点选，验收脚本就必须做 UI 交互，证据容易退化成"人肉截图"。
  实测还确认了两条通道的可行性：hdc file send 到应用沙箱**被拒**（permission denied，
  反向的 hdc file recv 可以），而 aa start --ps 可用。

**替代验收标准（本表"已复审"档要求写明的那一条）**：

1. 学期切换在界面上可用，切换后课程列表随之更新（课程名集合/条数变化可截图、可与站点原始响应对照）；
2. 存在一条**不经界面交互**的切学期入口，且**实际生效值**进 hilog：

       hdc shell aa start -a EntryAbility -b com.koracan.learnOH --ps lohSemester 2025-2026-2

   ⇒ hilog 出现
   data.courses semester override: constant="" runtime="2025-2026-2" effective="2025-2026-2" source=runtime-want-param
   以及 data.courses snapshot semester=2025-2026-2 source=override courses=⟨n⟩ ...；
3. 覆盖优先级 = override > 界面选择 > 站点当前学期，且**界面显示的 semester 就是实际生效值**
   （课程 tab 头部那句"当前学期：getSemesterTextFromId(effective)"）。

---

## 22. 文件详情的"预览 / 打开"：参考实现**本来就有应用内预览**，外跳的只有"打开"动作 —— 已复审（ticket 11）

**先把参考实现的行为摆准**（`screens/FileDetail.tsx`）——工单里"参考实现是 `FileViewer.open`"只描述了**那个按钮**，不是全部：

| 位置 | 参考实现行为 | 出处 |
| --- | --- | --- |
| 进入详情 | 自动下载（`handleDownload(false)`） | `:152-154` |
| 渲染判定 | `canRender = path && (fileType === 'pdf' \|\| canRenderInWebview(fileType))`；图片扩展名集合 = `jpg/jpeg/png/gif/svg/bmp/webp` | `:61-62`；`helpers/html.ts:123-127` |
| PDF | **应用内** `<Pdf source={{uri: path}}/>`（react-native-pdf） | `:170-175` |
| 图片 | **应用内** `<WebView source={{uri: 'file://'+path}}/>` | `:176-188` |
| 其他类型 | 信息面板（标题/类型/体积/描述）+ 分享 + 打开 | `:189-258` |
| "打开"动作 | `FileViewer.open(path, {showOpenWithDialog:true})` —— **这一条才是跳系统"打开方式"** | `helpers/fs.ts:171-179`，工具栏 `:120-124` |

⇒ 所以"PDF 与图片在应用内打开"**不是**对参考实现的偏离（参考实现就是应用内预览）；偏离的是**渲染器**与**那个"打开"动作**。

**偏离（两条，逐条写清）**：

| # | 项 | 参考实现 | 新实现 | 为什么 |
| --- | --- | --- | --- | --- |
| B1 | 渲染器 | react-native-pdf / WebView | PDF：HMS PDFKit 的 **`pdfService.PdfDocument` + `PdfPage.getPagePixelMap()`**（渲染成 `PixelMap` 交给 ArkUI `Image`，单页翻页）；图片：ArkUI `Image` + `image.createPixelMap` | 平台替换（RN 库在 ArkTS 里不存在），**且 `PdfView` 组件在本模拟器上运行期不可用**——见下面的【平台事实】。**可观察量（在应用内看到内容）不变** |
| B2 | "打开"动作 | `FileViewer` 跳系统"打开方式" | **不提供外跳**：pdf/图片一律应用内预览，其余类型给信息面板 + 分享 | 验收第 2 条要求"无需跳转第三方"；验收第 4 条的分享仍在（`systemShare`） |

**替代验收标准（本表"已复审"档要求写明的那一条）**：

1. 点开一个 pdf / 图片文件后，**设备截图里能看到内容本身**（既不是空容器，也不是系统"打开方式"弹窗，也不是跳到了另一个应用）；
2. 服务端返回 HTML 登录页时**不进入预览**（不落盘 + `loh_session_expired`，见下单测与设备证据）；
3. 分享面板仍可调起（系统分享面板截图），且**含中文与空格的路径**可用（URI 由 `fileUri.getUriFromPath` 生成）。

**【平台事实】`PdfView` 组件在本模拟器上运行期不可用（ticket 11 实测）**：

- 编译期：`@hms.officeservice.PdfView.d.ets` 里确实写着 `export { pdfViewManager, PdfView }`，`devecocli build` 也 BUILD SUCCESSFUL；
- 运行期（模拟器 Pura 90 / HarmonyOS 6.1.0(23) / `127.0.0.1:5555`，2026-09-12）：点开一个 pdf 文件的瞬间，
  组件构造直接失败并**崩溃重启**：
  `the requested module '@hms:officeservice.PdfView' does not provide an export name 'pdfViewManager'`
  （`FIX THIS APPLICATION ERROR: @Component 'FilesPage'[119] has error in update func`）。
  ⇒ 这是**编译通过、运行期炸**的典型（与本表第 8 条那条"平台能力缺口"同一类：d.ts 与真实实现不一致）。
- 处置：改用**同一套 PDFKit** 的 `pdfService` 命名空间（`@hms.officeservice.pdfservice`）：
  `new pdfService.PdfDocument()` → `loadDocument(path)`（**同步**返回 `ParseResult`）→
  `getPageCount()` / `getPage(i)` → `PdfPage.getPagePixelMap()` → ArkUI `Image`。
  **仍然是应用内渲染**，且只渲染当前页（内存有界），配"上一页 / 下一页"。

**未验证项的处置**：若平台连 `pdfService` 都不可用（应用内渲染不了 PDF），
**如实记为未达成**并把证据附在 ticket 11（试了什么、看到什么），而不是用"跳第三方"顶替。
ticket 11 的设备证据里保留了两段：`PdfView` 崩溃的 hilog（上文原文）与 `pdfService` 渲染成功的截图。

**取证**：`reference/learnOH-old/src/screens/FileDetail.tsx:61-62,120-124,152-154,169-188`；
`reference/learnOH-old/src/helpers/fs.ts:171-179`；`reference/learnOH-old/src/helpers/html.ts:123-127`；
`entry/src/main/ets/features/files/FileDetailPage.ets` 的 `loadPreview` / `previewBody`；
入口单测 `entry/src/test/FileDownload.test.ets`（`classifiesPreviewableTypesAndMetaLine`）；ticket 11 的模拟器截图与 hilog。


---

## 24. 页头信息架构：**左对齐自绘页头 + 相对更新时间**（参考是居中 `HeaderTitle(title, subtitle)`，且没有"更新时间"元素）—— 已复审（ticket 11.5，账号所有者点名）

**参考实现行为**：

| 项 | 参考实现 | 出处 |
| --- | --- | --- |
| 页头版式 | **居中** `HeaderTitle(title, subtitle)`：20px 粗体标题 + 12px / 行高 0.6 / 半透明副标题 | `src/App.tsx:118-135`（`getTitleOptions`，`headerTitleAlign:'center'`）、`src/components/HeaderTitle.tsx` |
| 副标题槽位 | **选了筛选时**显示筛选名（`FilterList.tsx:191-201` 把它交给 `headerTitle`）；列表页默认只给课程页传学期 | `src/components/FilterList.tsx:185-201` |
| 学期出现的位置 | **只有 Courses** 传 `defaultSubtitle = getSemesterTextFromId(currentSemesterId)` | `src/screens/Courses.tsx:48-50` |
| "更新时间" | **不存在这个元素**（任何页面都没有"更新于 / 刚刚更新"） | 全仓 grep 无对应 UI |
| 页头背景 | 走导航主题的 `card` 色（浅色 = `rgb(255,251,255)`，即品红偏色） | `App.tsx:220-222,244` |

**为什么偏离**（账号所有者 2026-09-12 点名，原话见 ticket 11.5 的 Part B）：

> "当前学期我希望只在'课程'页面显示，'取证覆盖生效'对用户无意义，更新实现应该写相对时间（刚刚更新、1 分钟前更新等），'未完成n'是多余的。背景我希望不继续使用微品红色，用白色即可。总的来说这四项应该只保留更新时间，并和标题压缩到同一行……课程页则把标题、学期、更新时间压缩在同一行"

本工程的页头是**自绘**的（`hideTitleBar(true)`，左对齐、无系统导航栏），所以"居中 + 副标题槽位"这套版式在移植后本来就不存在；
本 ticket 要做的是**信息架构**：把参考实现"只有课程页显示学期"这一条**明确保留**，同时把"更新时间"这个**参考实现没有的元素**加进来。

**新实现做法**：

1. **作业页**：页头只剩「标题 + 相对更新时间」**同一行**。移除 `当前学期 <学期>`、`取证覆盖生效` 徽标、`未完成 n`
   （未完成数在筛选片里已有，不重复）。
2. **课程页**：页头 = 「课程 + 学期 + 相对更新时间」，学期与更新时间排在标题**右侧同一行区域内**、彼此上下两行
   （学期在上、相对时间在下）；**学期文本仍可点** → 学期切换页（ticket 12 的行为一字未改）。
3. **公告 / 文件页**：同一原则（标题 + 相对更新时间同一行），**保留**有信息量的计数
   （公告 `未读 n`、文件 `文件条数`）——不为了统一而删信息。
4. **相对时间**：数据源 = 快照的 `fetchedAtMillis`（`snapshot.fetchedAt`）。措辞四档：
   `<60s → 刚刚更新` / `N 分钟前更新` / `N 小时前更新` / `N 天前更新`（英文同义）；
   **不每秒重算**（只在进入页面 / 刷新后取一次），实现见 `ui/components/UpdatedTime.ets`。
5. **学期不再出现在作业 / 文件页头**（`当前学期：…` 那一行删掉；文件列表每行本来就有课程名，学期冗余）。

**【"同一行"的语义 —— 账号所有者 2026-09-12 复看实现后补充澄清，同日记入】**

账号所有者原话"和标题压缩到同一行 / 课程页则把标题、学期、更新时间压缩在同一行"，指的是**学期与相对时间都落在标题那一段文字所占的行区域内**
（即参考实现 `HeaderTitle` 那种"标题 + 副标题并排"的版式），**不是"必须严格排成一行文字"**：
标题字号更大（`headlineSmall`），它占的高度足以让学期与相对时间在标题右侧**竖排**放下，
所以课程页「标题 + 右侧学期/时间两行」**符合原意**（账号所有者已确认其示例图就是这个排法）。
统筹曾按字面读成"必须单行"并据此打回一次，账号所有者复看实现截图后否定了那次打回——**以本条澄清为准**。

**替代验收标准（本表"已复审"档要求写明的那一条）**：

1. 作业页头截图里**不出现**学期文本、`取证覆盖生效`、`未完成 n`（一屏一对文件）；只剩「作业 + 刚刚更新」这一类两段文字；
2. 课程页头截图里有「课程 + 学期 + 相对更新时间」三项，**三项都落在标题所在的那一行区域内**（学期与相对时间在标题右侧、允许竖排两行；
   不得掉出页头区域或挤进正文），且学期文本仍可点进学期切换（点击后截图/日志与 ticket 12 一致）；
3. 相对时间四档**边界**由单测钉住（`updatedTimeParts`：59s → `JUST_NOW`、60s → 1 分钟、59min → 59 分钟、60min → 1 小时、23h → 23 小时、24h → 1 天），
   设备侧用**注入快照时间戳**（改 `fetchedAtMillis`，不靠手速）拍 `刚刚更新` 与 `N 分钟前更新` 两帧；
4. ~~公告页头仍有 `未读 n`~~ **（ticket 14 起改判，见本条末的追记）**、文件页头仍有条数
   （信息量计数未被"统一"删掉），两者与相对更新时间同行；
5. **学期只出现在课程页头**（可复现的口径）：`grep -rn "getSemesterTextFromId(" entry/src/main/ets` 只有 3 处 ——
   `core/i18n/DateTimeUtil.ets:248`（**定义**）、`features/courses/CoursesPage.ets:110`（**课程页头**，经 `semesterText()` 渲染
   "实际生效学期"）、`features/courses/SemesterSelectionPage.ets:62`（**学期选择列表的每一行**，不是页头）。
   作业页 / 文件页 / 公告页**没有任何调用点**，所以"学期不在它们的页头里"是可 grep 证的。
   > 更正（ticket 11.5 复验）：这条判据原来写的是 `grep -n "ui_courses_semester_label" entry/src/main/ets/features`，
   > 但该键在 features 下**唯一**的引用是 `features/courses/SemesterSelectionPage.ets:141` —— 学期选择页那枚勾的
   > **无障碍文案**，与页头无关。原判据指向另一屏、且证明不了这件事，已换成上面的枚举口径。

**【追记 · ticket 14，2026-09-13】公告页头的 `未读 n` 已移除（本条第 4 项对公告不再适用）**

- **变了什么**：公告页头从「标题 + 相对更新时间 + `未读 n`」变成「标题 + 相对更新时间」；
  未读数改由**过滤条上的"未读"片**承担（`未读 2` 与其余四片同排）。
- **为什么**：本条第 4 项写它时就与参考实现不一致 —— 参考实现的公告未读数是**筛选条上的角标**
  （`components/FilterList.tsx:246` 的 `unreadCount`、`components/Filter.tsx:181-187` 的 Badge），
  页头（`HeaderTitle`）里**没有**这个元素；ticket 03 当初把它自造在页头，是为了在筛选条落地前
  有个可见的未读信号。ticket 14 落地筛选条后，同一信息会**两处重复**，工单第 9 行要求二选一。
- **保留的那一半**：文件页头的条数**仍在**（它不是筛选条上某一组的重复，见本条第 4 项后半）；
  相对更新时间（本条主体）一字未动。
- **原证据还成立到哪一步**：ticket 11.5 关于"作业页头无学期/无徽标/无未完成计数"的证伪截图不受影响；
  `未读 n` 的那一类截图（若有）不再是提交态基准 —— 同一数字现在看过滤条的"未读"片。
  可观察量转移到 **ticket 14 的公告页截图**（页头两段文字 + 过滤条五片）。
- **取证**：`entry/src/main/ets/features/notices/NoticesPage.ets` 的 `header()` / `filterRow()`；
  ticket 14 交付节第 1 条（与 ticket 03 自造页头的对账）。

**与 ticket 12 的关系**：ticket 12 替代验收第 3 条"界面显示的 semester 就是实际生效值（课程 tab 头部那句）"**仍然成立**
（学期文本还在，只是位置/版式变了）；**但"取证覆盖生效"这枚徽标被移除** ⇒ 覆盖生效的界面信号从此只有
"课程页头的学期文本"，其余靠 hilog 的消费点行（`data.courses effective semester=… source=override`）。
本 ticket **没有**用构建期开关把它加回取证构建（默认界面不许出现；需要时按 ticket 11.5 的说明重开）。

**取证**：`reference/learnOH-old/src/App.tsx:118-135`、`src/components/HeaderTitle.tsx`、`src/components/FilterList.tsx:185-201`、
`src/screens/Courses.tsx:48-50`；`entry/src/main/ets/features/{assignments/AssignmentsPage,courses/CoursesPage,notices/NoticesPage,files/FilesPage}.ets` 的 `header()`；
`entry/src/main/ets/ui/components/UpdatedTime.ets`；`entry/src/test/UpdatedTime.test.ets`；ticket 11.5 的逐屏截图。

**【追记 · ticket 03（界面优化轮），2026-09-13】相对时间的"重算时机"改了：从"构建那一刻算一次"变成"每次页面被显示时重算"**

- **变了什么**：页头那一行的时间**基准**从"求值那一刻的 `Date.now()`"改成"**本页最近一次被显示的时刻**"
  （AppStorage 键 `lohPageShownAtMillis`；动作 `markPageShown()` **只有一处实现**，在
  `entry/src/main/ets/features/shell/PageShown.ets`）。两个触发源都汇进它：切 tab（底栏点击 + `Tabs.onChange`）
  与**回到前台**（`EntryAbility.onForeground`），另加壳层首次显示。**没有**定时器 —— 仍是"被显示时算一次"，
  不是"每秒刷新"（本条第 4 项后半那句"不每秒重算"继续成立）。
- **为什么**：本条第 4 项写的意图是"**只在进入页面** / 刷新后取一次"，但实现只在页面**构建那一刻**算过一次：
  `TabContent` 的子组件实例是持久的、`build()` 不因切 tab 重跑（`onPageShow` 又是 `@Entry` 级生命周期，
  这四个页面是 shell 里的子组件，拿不到）。⇒ 隔夜切回来页头还写着"刚刚更新"。所以这次不是推翻本条，
  而是让实现在"重新进入页面"这件事上**对得上本条的措辞**。数据源（快照 `fetchedAtMillis`）、四档措辞、
  边界单测**一字未改**（`ui/components/UpdatedTime.ets` 与 `UpdatedTime.test.ets` 都不在本次 diff 里）。
- **原证据还成立到哪一步**：本条第 4 项与替代验收第 3 条前一半（四档边界由单测钉住）**全部仍然成立**；
  第 3 条后一半"设备侧用**注入快照时间戳**拍两帧"不再是**唯一**路径 —— 本轮改用**不碰设备存储**的做法
  （等真实两分钟 + 切走切回 / 回前台）取到两帧，原方法仍可用。
  各行"节点构成"类证据（ticket 11.5 的逐屏截图、ticket 01 的页头 layout dump）也不受影响：那一行**仍然在**；
  但它的取值现在会在页面被重新显示时变新 ⇒ **新拍的 dump 里那一行的文本可能不再是"刚刚更新"**，
  按"节点存在 / 措辞属于哪一档"读，不要按"文本恒为刚刚更新"读。本次改动**新增**了一处页头语言之外的
  全局状态（AppStorage 键），不含任何设备级设置、不含持久化。
- **取证**：`.scratch/ui-optimize/evidence/03-relative-time-refresh.md`（同一台 MatePad Pro 13 / `127.0.0.1:5559`：
  `刚刚更新` → `3 分钟前更新` → `6 分钟前更新`，两帧间隔均 ≥2 分钟且未改设备时钟）；
  实现见 `entry/src/main/ets/features/shell/PageShown.ets` 与四个列表页的 `updatedText()`。

---

## 25. 全应用底色去品红：M3 紫种子的**底色族 + 中性族**改中性灰（参考实现是 `rgb(255,251,255)` 那一套）—— 已复审（ticket 11.5，账号所有者裁定）

**参考实现行为**（我们的 `ui/theme/Tokens.ets` 是**一比一**抄过来的）：

| 令牌 | 参考实现值（浅色） | 出处 |
| --- | --- | --- |
| `background` / `surface` | `rgb(255,251,255)` | `src/App.tsx:220-222` |
| `card` | `rgb(255,251,255)` | `src/App.tsx:244` |
| `elevation.level1..5` | 品红偏色逐级加深（我们逐值抄成 `#FAF0FB / #F7EAF9 / #F4E4F6 / #F3E1F5 / #F1DDF4`） | `src/App.tsx:235-239` |
| 深色 `background/surface/card` | `rgb(30,26,29)` = `#1E1A1D`（紫调中性） | `src/App.tsx:206-230` |

**为什么偏离**：账号所有者 2026-09-12 用取色器测得**整个 APP 界面底色**是 `254,250,254`
（即 `#FFFBFF` 经截图色彩配置转换后每通道 −1），明确要求"用白色即可"；深色一并去紫调。
这条**推翻了 ticket 01 验收里"主题令牌与参考实现一致"**对底色类令牌的适用（语义色不受影响）。

**新实现做法**（三段式，逐令牌"改前 → 改后"见 ticket 11.5 交付）：

1. **底色家族（必须改）**：`background` / `surface` / `card` → `#FFFFFF`；
   `elevation.level1..5` → 中性阶梯 `#FAFAFA / #F5F5F5 / #F0F0F0 / #EDEDED / #EAEAEA`（**保持 level1 最浅、level5 最深**的方向）。
2. **中性家族（一并去紫调）**：`onBackground` / `onSurface` / `surfaceVariant` / `onSurfaceVariant` /
   `outline` / `outlineVariant` / `inverseSurface` / `inverseOnSurface` / `backdrop` /
   `surfaceDisabled` / `onSurfaceDisabled` → 全部 `R=G=B`。
3. **绝对不动（品牌与语义强调色）**：`primary` / `onPrimary` / `primaryContainer` / `onPrimaryContainer` /
   `secondary` / `onSecondary` / `secondaryContainer` / `onSecondaryContainer` / `tertiary*` / `error*` / `inversePrimary`。
   tab 选中态与筛选片的粉底（`primaryContainer`）因此**一字未动**。

**页面级不需要各改各的**：真正画出界面底色的只有 `colors.background`（`ShellTabs.ets:266` 与各页面
`*.backgroundColor(this.theme().colors.background)`），所以改令牌即全应用生效；
排查结果：仓库内**没有**硬编码的底色（`grep "#FFFBFF"` 只剩令牌表与文档）。

**替代验收标准（本表"已复审"档要求写明的那一条）**：

1. **浅色**：设备截图里多屏（作业 / 课程 / 公告 / 文件 / 详情）的**空白底色**像素满足 `R=G=B` 且每通道 `≥254`
   （判据**不写死** `==255`：截图色彩配置会把纯白量成 254）；源码侧另有 `LIGHT_COLORS.background === '#FFFFFF'` 的单测；
2. **深色**：同一批屏（切到深色后）空白底色满足 `R=G=B` 且每通道 `<60`，并保留 elevation 明度阶梯（源码断言 level1 与 level5 的明度差）；
3. 令牌单测钉住：深浅两套的**中性族全为 `R=G=B`**、`primary` 家族与 `PLAIN_PALETTE` **逐值不变**、
   两套的 `background` 仍然不同（深浅仍是两套）。

**为什么这次可以偏离**：这是**账号所有者点名的**改动（原话："背景不仅仅是页头，我用取色器测得**整个 APP 界面底色**都是 254,250,254"），
且偏离面被限定在**中性色**：所有承载语义的颜色（品牌紫、成功/错误/警告）一字未动，
所以"哪些颜色代表什么"这一层与参考实现仍然可比。

**取证**：`reference/learnOH-old/src/App.tsx:206-244`；`entry/src/main/ets/ui/theme/Tokens.ets` 的 `LIGHT_COLORS` / `DARK_COLORS`；
`entry/src/test/Tokens.test.ets`；ticket 11.5 的设备取色（模拟器 Pura 90）。

---

## 26. 提交页不移植「之前分享的」（`pendingAssignmentData`）—— 已复审（ticket 13）

**参考实现行为**：`screens/AssignmentSubmission.tsx` 从 redux 读 `assignments.pendingAssignmentData`
（:79-80），非空时把它变成「即将上传的附件」（:294-302），并在附件行尾显示 `（之前分享的）` /
`(previously shared)`（:376-380）。写入者是 action `setPendingAssignmentData`
（`data/actions/assignments.ts:169-172`）。

**为什么偏离（两条，第一条是决定性的）**：

1. **参考实现自己也从来没有给它写过非 null 值。** 对 `reference/learnOH-old/` 全仓检索
   （`Select-String -Pattern pendingAssignmentData`，见 `docs/accepted-deviations.md` 本条的取证一行）：
   `setPendingAssignmentData` 只出现在**定义**（actions / types / reducer）与提交页里那 4 处
   `dispatch(setPendingAssignmentData(null))`（:117, :136, :166, :228）——**没有任何一处** dispatch 一个真实对象。
   ⇒ 参考实现里这条 UI 是**死支路**（系统分享入口从未接上），不构成可比对的行为。
2. 本工程**没有**系统分享入口（spec 未涵盖「从其他应用分享文件到 learnOH」），也没有对应的数据层动作。

**替代验收标准**：

1. 提交页只有「文件 / 照片」两个入口能产生待上传附件，且附件行尾**没有**任何「之前分享的」字样；
2. `grep -rn pendingAssignmentData entry/src` 无命中（键、状态、文案都不存在）；
3. 被删掉的那条 UI 的不可达性由第 1 条的检索结果承担：参考实现里它不可达，所以「移植它」没有可观察量。

**取证**：`reference/learnOH-old/src/screens/AssignmentSubmission.tsx:79-80,294-302,376-380`；
`reference/learnOH-old/src/data/actions/assignments.ts:169-172`；`reference/learnOH-old/src/data/reducers/assignments.ts:21,100`；
全仓检索输出见 ticket 13 的交付节（写入者只有 `null`）。

---

## 27. 新选中附件那一行不可点（参考实现点它进 FileDetail，用**上传前的本地 URI** 预览）—— 已复审（ticket 13）

**参考实现行为**：`AssignmentSubmission.tsx:358-374` 把「即将上传的附件」渲染成 `TextButton`，
`onPress` 调 `handleFileOpen({ id:'0000', name, downloadUrl: attachmentResult.uri,
previewUrl: attachmentResult.uri, size, type })` —— 即用**本地 URI**（`file://…`，尚未上传）进 `FileDetail`。

**为什么偏离**：本工程 `FileDetail` 的契约是「给一个 `downloadUrl`，**先下载再预览**」（ticket 11 验收：
服务端返回 HTML / 非 200 时**不进入预览**、落到错误态）。把本地 `file://` URI 塞进这条路由不会预览，
只会得到一次必然失败的下载。要真正支持「预览还没上传的本地文件」需要**另开一条**本地文件预览路径
（超出 ticket 13 的范围；且本轮没有可提交的真实作业，无法判断该入口的实际价值）。

**替代验收标准**：

1. 新附件那一行**可读地**显示图标 + 文件名（含中文 / 空格的文件名不被吞掉）；
2. 同一行的「移除已选择的附件」按钮可用；移除后该行消失、页头提交按钮按 `canSubmit` 规则变灰；
3. 页面**不声称**提供预览：点击该行不发请求、不跳转、不弹错误；
4. **已提交附件**行仍然可点进 `FileDetail`（与参考实现一致，且走的是真正的下载契约）。

**取证**：`reference/learnOH-old/src/screens/AssignmentSubmission.tsx:358-374`（`handleFileOpen` 见 :147-163）；
`entry/src/main/ets/features/assignments/AssignmentSubmissionPage.ets` 的 `pickedAttachmentRow` /
`submittedAttachmentRow`；`entry/src/main/ets/features/files/FileDetailPage.ets`（下载契约）。




---

## 28. 分栏的详情路由迁移：**整段迁移与参考实现一致**；仅额外补上**退出分栏时的对称回迁**（且不移植右栏空屏栈底）—— 已复审（ticket 16；2026-09-13 统筹更正定性）

**参考实现行为**（`reference/learnOH-old/`）：

| 项 | 参考实现 | 出处 |
| --- | --- | --- |
| 迁移在分栏态下**每次详情入栈都会触发** | 原判据是 `splitEnabled && !lastSplitEnabled.current && showDetail && …`；但 `showMain` **恒为 true**（全仓只有定义与引用、**无 setter**）⇒ 分栏后 `showDetail` 恒真。触发面因此比`只在进分栏那一次`大得多 | `src/App.tsx:720,873,904`（`grep -n showMain App.tsx` 只这三处）；`SplitView.tsx:43-50` |
| 迁移的**粒度 = 栈顶连续详情段**（**与本工程一致，不是偏离**） | `do { goBack() } while (白名单里)` 是**循环**：剥掉整个顶部详情链；而 `navigate` 一次只送**栈顶**那条进右栏，其余几级在**后续详情入栈**时被继续迁走 ⇒ 累积起来右栏拿到的就是**整段** | `SplitView.tsx:66-85` 的 `do…while` + `:43` 的恒真判据 |
| 退出分栏时**不回迁** | `splitEnabled` 为假时只渲染 `masterChild`（详情容器整段不渲染），而左栏此刻已回到列表根 | `SplitView.tsx:109,136-138`、`App.tsx:873,885-896` |
| 右栏迁移前的栈底 | 详情容器自带一个 `EmptyDetail` 根屏（`Empty` 组件），所以迁过去的那条详情"返回"落到**空白页** | `App.tsx:570-577,927-934` |

**更正与真正的偏离范围（2026-09-13 统筹复验时改写；初版定性有误）**

初版本条把“只迁栈顶一条”写成偏离理由、并称“中间几级详情会被丢掉”。**逐行复核后该定性是错的**：
上表第 2 行已给出——`do…while` 剥掉整段，且判据因 `showMain` 恒真而在每次详情入栈时触发，
所以“**整段迁移与参考实现一致，不构成偏离**”。

**真正的偏离只有一处：退出分栏时的对称回迁。** 参考实现那句“退出时详情容器整段卸载”是隐式的，
并没有把右栏内容搬回主栈的动作。为什么仍要补：“验收第 3 条要求旋转/缩放时正在浏览的详情不丢失”，
而参考实现那套在竖屏回退时会让左栏停在列表、右栏整段卸载 ⇒ 正在看的详情消失。补回迁后窄窗下详情仍在屏上
（从“右栏”变成“整屏”），**更接近验收第 3 条**；代价是页面组件被重建（其可观察后果由替代验收第 2/3 条钉住）。

**另一处不属于偏离、而是“修复漏移植”**：参考实现右栏栈底是 `EmptyDetail` 空屏（`App.tsx:570-577`），
本工程**不移植**它，而是把整段详情搬过去 ⇒ 右栏“返回”回到**上一级详情**而非空白（替代验收第 4 条）。
按移植完成定义这一条本应照抄，本工程选择不照抄（理由：手机形态下不存在空屏的对应物，且它会让“返回”产生一个不可解释的空白页），故一并登记。

**新实现做法**（`entry/src/main/ets/features/shell/SplitView.ets`）：

1. `splitMigrationPlan(pathNames)` 取**栈顶连续详情段**（按参考实现同一份 9 条白名单判定），
   `migrateDetailRoutesInto` 把这一段**自底向顶**整段搬到右栏，左栏用 `clear/popToIndex` 逐级回到列表根；
   右栏的 `push` 延后 `SPLIT_VIEW_MIGRATION_DELAY_MS`（100ms，与参考实现 `SplitView.tsx:69-76` 同值同因）。
2. `migrateDetailRoutesBack` 在**退出分栏**时把右栏那一段同步搬回主栈 —— 于是竖屏/窄窗下详情仍在屏上，
   只是从"右栏"变成"整屏"；页面组件被重建，但三个详情页都是**参数驱动**（详情内容随 `NavPathStack` 的
   `param` 走），文件详情还会走下载缓存（`fromCache=true`，不发第二次网络请求）。
3. 两个 tab 栈的其余行为与参考实现一致：单栏时详情照旧压**主栈**（ticket 03/04 的行为一字未改），
   分栏时列表项点击进**右栏**、同名路由替换（对齐参考实现的 `navigate` 语义，`screens/Notices.tsx:33-45`）。

**替代验收标准**：

1. 双栏（≥750vp 且横向）下点列表项：详情出现在**右栏**，左栏仍在列表页且该行保留高亮；
2. 旋转/缩放窗口（平板 1440×960 ↔ 960×1440）后**正在浏览的详情仍在屏上**（竖屏变成整屏），
   且 hilog 里有 `split view exit/enter: moved=N masterRoutes=… detailRoutes=…` 给出来回迁移的条数；
3. **不重复请求**：迁移后不出现第二次取数 —— 文件详情走缓存（`file detail ready … fromCache=true`），
   公告详情只重放同一份 `param` 生成的 HTML（不发起应用侧 HTTP）；
4. 多级详情（课程详情 → 附件文件详情）迁移到右栏后，右栏的"返回"回到**上一级详情**（不是空白）；
5. 电话形态（<750vp）版式与 ticket 03/04 完全一致：详情整屏、返回回到列表、切 tab 保留浏览位置。

**取证**：`reference/learnOH-old/src/components/SplitView.tsx:41-98,109-138`、`src/App.tsx:570-577,864-896,927-934`、
`src/screens/Notices.tsx:33-45`；`entry/src/main/ets/features/shell/SplitView.ets`；
`entry/src/test/SplitView.test.ets`；ticket 16 交付节与 `.scratch/splitview/evidence/README.md`。

---

## 29. 搜索的三处偏离：**引擎换成自写加权评分** / 结果**排除被屏蔽课程** / 分栏下搜索页自成一左一右 —— 已复审（ticket 15）

**参考实现行为**（`reference/learnOH-old/`）：

| 项 | 参考实现 | 出处 |
| --- | --- | --- |
| 检索引擎 | **fuse.js@7.1.0**（npm 包）：Bitap 模糊 + `keys` 权重 | `src/hooks/useSearch.ts:2,69-74` |
| 手工合并层 | 标题/课程名 `toUpperCase().includes(query.trim().toUpperCase())` 的结果与 fuse 结果**手工合并**（手工在前、`Set` 按 id 去重） | `:44-61,107-116` |
| 喂进检索的条目 | `state.X.items`（**原始 items**，不是列表用的 `all`）⇒ **归档项仍会被搜到** | `src/screens/Search.tsx:35-37` |
| 被屏蔽课程 | **不排除**：没有任何按 `hidden` 过滤的动作 ⇒ 屏蔽课程的内容**仍会出现在搜索结果里** | 同上（`items` 是原始集合） |
| 进详情 | 有右栏引用 → `navigate` 进**根分栏的右栏**并补 `disableAnimation:true`；否则 `navigation.push` | `Search.tsx:54-63`、`src/hooks/useDetailNavigator.ts` |
| 分栏下右栏内容 | 搜索页挂在根容器的**主栏**里（`SplitView.tsx:109-135` 把 masterChild 收成 393vp），右栏仍是"进搜索页之前那个详情容器" | `src/App.tsx:885-896` |

**三处偏离**：

| # | 项 | 参考实现 | 新实现 | 为什么 |
| --- | --- | --- | --- | --- |
| D1 | 引擎 | fuse.js@7.1.0 | **自写加权评分**（`features/search/SearchCore.ets`）：字段表与权重逐字照抄；分档 = 精确 > 前缀 > 子串 > ASCII 词编辑距离 | 平台没有 fuse.js 的 ArkTS 移植。评估文档的首选 `@ohos/flexsearch@2.0.1` **实测不可用**（`index.d.ts` 声明具名导出 `Document`，真实入口 `src/flexsearch.js` 只有 `export default` ⇒ 编译期 `00507015 … does not provide an export name 'Document'`）。改用兜底方案后**没有新增任何 ohpm 依赖**（`entry/oh-package.json5` 与 HEAD 一致） |
| D2 | 屏蔽课程 | 不排除 | **排除**（复用 `features/marks/FilteredContent` 的 hidden 判据） | 工单 15 验收第 5 条「隐藏课程的内容不出现」+ ticket 14 转来的那半。**归档项仍照参考实现保留可搜** |
| D3 | 分栏右栏 | 复用根分栏的右栏（进搜索页前那个详情容器） | 搜索页内部自成一左一右（左栏 = 结果、右栏 = 详情），右栏**起始为空态** | 本工程的搜索页是盖在 ShellTabs 之上的根级 NavDestination，没有"外面那个右栏"可用（ShellTabs 的分栏在**每个 tab 内部**，见台账第 28 条） |

**替代验收标准**：

1. **大小写不敏感；标题或课程名的精确与前缀匹配必定命中** —— 由手工合并层独立保证（与参考实现同一判据、
   同一 `includes('')` 空查询语义）；单测 `matches titles and course names case-insensitively…` /
   `puts manual title/course hits first and deduplicates by id` 钉住；设备证据 `E3-phone-search-prefix-cjk-query.png`；
2. 其余字段（发布人 / 正文 / 描述 / 成绩与答案正文 / 文件类型）**大小写不敏感子串**命中
   （单测 `searches the extra reference fields of all three domains`；设备证据 `E4-phone-search-content-only-cjk-query.png`、
   `E4b-phone-search-case-insensitive-ascii.png`）。**不声称与 fuse 的召回等价**：② 层的边界是
   "子串 + ASCII 词的 ≤1/≤2 编辑距离"，CJK 只有子串/前缀（与 `.scratch/migration/search-package-eval.md` 第 3 条一致）；
3. 手工结果在前、按 id 去重、**手工组内保持输入顺序**（单测 `ranks higher-weight fields first…` 的后半段）；
4. **空查询 = 三个域的全量**（参考实现 `includes('')` 的后果；单测 `lists everything… for an empty query`）；
5. 搜索结果里**看不到被屏蔽课程**的条目（`E10-phone-search-hidden-course-empty.png`）而**取消屏蔽后同一查询立刻命中**
   （`E11-phone-search-after-unhide-hit.png`）；**归档项仍搜得到**（单测 `keeps archived items searchable` +
   `E9-phone-notices-archived-view.png` 与 `E3-…png` 这一对）；
6. 分栏（≥750vp 且横向，平板模拟器）下点搜索结果：详情出现在**右栏**、左栏保留查询与结果高亮（`T1/T2/T3-tablet-*.png`）。

**未验证 / 降级边界（如实登记）**：

- D1：`@ohos/flexsearch` 的 **default 导入**这条路**没有试**（按工单"不在这上面耗超过一轮构建"的约定停在第一轮）；
  已实测的只有"具名导入在该包上失败"这一条 —— 见工单 15 交付节的未验证项；
- 参考实现 fuse 的**排序细节**（score 降序、`ignoreLocation` / 阈值等默认项）没有被逐值复刻：
  ② 层的排序是"加权分降序 + 同分保持输入顺序"；
- D3 的右栏起始空态：参考实现里右栏会**保留**进搜索页之前的那个详情，本工程不会（见上表）。

**取证**：`reference/learnOH-old/src/hooks/useSearch.ts:2,5-116`、`src/screens/Search.tsx:35-63`、
`src/hooks/useDetailNavigator.ts`、`src/components/SplitView.tsx:109-135`、`src/App.tsx:885-896`；
`entry/src/main/ets/features/search/SearchCore.ets`；`entry/src/test/Search.test.ets`；
`.scratch/search/evidence/README.md`、`.scratch/search/evidence/15-flexsearch-smoke-failure.txt`；
`.scratch/migration/search-package-eval.md`。
---

## 30. 设置与 Mock 模式的四处偏离 + 两处增补：分栏详情白名单补一条 / **不移植服务端登出** / Mock 落在**仓储层**（不是整棵 state）/ 「导出日志」与「Mock 自证行」 —— 已复审（ticket 17）

**参考实现行为**（`reference/learnOH-old/`）：

| 项 | 参考实现 | 出处 |
| --- | --- | --- |
| 设置页条目 | 8 条：用户信息 / 退出登录 / 沉浸式 / 学期选择 / 文件设置 / 隐私政策（外链）/ 帮助 / 关于 | `src/screens/Settings.tsx:62-118` |
| 退出登录 | `dataSource.logout()`（**服务端**注销）→ `clearLoginCookies()`（清平台 cookie）→ `dispatch(clearStore())` | `Settings.tsx:37-57` |
| Mock 模式 | 登录页判定 `username===DUMMY_USERNAME && password===DUMMY_PASSWORD` ⇒ `dispatch(setMockStore())`，**整棵 redux state** 换成 `data/mock.ts`（723 行）；mock 状态由 redux-persist 写进 SecureStorage（白名单含 `username/password/fingerPrint`） | `Login.tsx:43-46`、`reducers/root.ts:46-56,138-139` |
| Mock 用户不显示沉浸式 | `!isMockUser ? <TableCell …immersiveMode/> : null` | `Settings.tsx:74-82` |
| 分栏详情路由白名单 | **9 条**，含其余四个设置子页，**没有** `ImmersiveSettings` | `components/SplitView.tsx:55-65` |
| 沉浸式设置的说明文字 | `immersiveModeDescription` = "隐藏导航栏和状态栏，**需要重启应用**"；另有一个**从未被引用**的 `pleaseRestartAppToApplyImmersive` | `assets/translations/zh.ts:206-210`（全仓 grep 无 UI 引用） |
| 关于页构建号 | `DeviceInfo.buildNo()`（react-native-device-info 的 `getBuildNumber()`） | `screens/About.tsx:27`、`constants/DeviceInfo.ts:9` |
| 开源依赖一节 | `Object.keys(packageJson.dependencies)` 动态列 | `About.tsx:79-84` |

**四处偏离**：

| # | 项 | 参考实现 | 新实现 | 为什么 |
| --- | --- | --- | --- | --- |
| D1 | 分栏详情白名单 | 9 条（漏 `ImmersiveSettings`） | **10 条**（补上 `ImmersiveSettings`） | **参考实现自身不一致**：`App.tsx:512-538` 把五个设置子页都注册进 Settings 栈（`ImmersiveSettings:515` / `SemesterSelection:520` / `FileSettings:525` / `About:530` / `Help:535`），而白名单只收了后四个 —— 于是参考实现下"从设置页点沉浸式"在平板分栏时会被推进**左栏**，其余四个进右栏。补齐的理由：① 与同栈其余四个子页一致；② 沉浸式是**全屏式**设置页，塞进 393vp 左栏比进右栏更差。⇒ 这是**有意识的偏离，不是没看出区别**。见 `features/shell/SplitView.ets` 与 `entry/src/test/SplitView.test.ets`（断言跟随事实改成 10 条） |
| D2 | 退出登录 | 还调 `dataSource.logout()`（服务端注销会话） | **只清本地**：`session.clear()`（内存 cookie jar + Session + 凭据缓存）+ `credentials.clear()`（asset store） | 本工程的数据层没有"服务端登出"这个用例，也没有对应端口；工单验收第 4 条要的可观察量是"凭据被清除并回到登录页"，两步合起来就是它。**不新造一个没有验收判据的网络调用**（另见"未验证"一节） |
| D3 | Mock 的落点 | 替换**整棵 redux state** | 落在**仓储层**：mock 模式下四个 provider 返回 `data/mock/Mock*Repository` | 本工程没有 redux / 全局 state（数据源是四个注入式仓储，界面各持一份 store）；工单验收第 5 条要的是"界面可用 + 数据是样例 + 不发请求"，仓储层替换即达成，且**界面与 store 一行都不用改** |
| D4 | Mock 的持久化 | mock 状态会被 redux-persist 写进 SecureStorage | **只活在进程内**（不写任何凭据 / 偏好） | 会话与凭据都不落盘是既有口径（ADR-0004 / spec 第 4 节）；把 guest/guest 写进凭据库会让"重启后自动登录 mock 账号"成为一条新的、没人验收的路径 |

**两处增补**（参考实现没有、本工程主动加）：

| # | 项 | 依据 | 代价 |
| --- | --- | --- | --- |
| A1 | 设置页多一行「**导出日志**」（图标 `description`，就地动作 + Toast） | ticket 01 的 `core/log/LogBuffer.ets` 文件头**明确**把 `exportLogs()` 的调用方留给"settings 切片（ticket 17「导出日志」）"；本 ticket 的 What to build 也列了它 | 参考实现里这一项不存在 ⇒ 逐条比对截图时多一行；位置在**最后**（前 8 行与参考实现逐字同序同图标） |
| A2 | 设置页在 **mock 用户**下多一条自证行（`ui_mock_mode_active`，含实时请求计数） | 验收第 5 条要求"不发起真实网络请求"**可证明**；计数打在**消费点**（`data/remote/NetworkAudit`，两个真实 http 出口共用） | 只在 mock 用户下出现，正常账号界面与参考实现逐条一致 |

**一处"文案与行为不完全一致"（如实登记，未偏离）**：说明文字仍按参考实现原样显示"需要重启应用"（**迁移键**，改它会让 `check-generated-fresh` 失败），而本 ticket 的验收第 3 条要求**即时生效** —— 行为按验收（切换后立刻调 `setWindowLayoutFullScreen` / `setWindowSystemBarEnable`），文字保持原样。参考实现自己也是"文字说重启、代码里 `useEffect` 立刻生效"（`App.tsx:682-690`），本工程与它的行为一致。

**替代验收标准**：

1. **设置页条目**：前 8 条的顺序、图标、分组间距与参考实现逐条一致（一屏一对文件：浅色 / 深色各一张）；
   「退出登录」弹确认框（标题 `logout` / 正文 `logoutConfirmation` / 按钮 `cancel`+`ok`），确认后**回到登录页**且凭据被清（重启后仍在登录页）；
2. **D1**：平板模拟器（≥750vp 横向）上从设置页点进**沉浸式**子页 → 该页在**右栏**；在该页上旋转 / 缩放窗口
   → 该页仍留在屏上（hilog 有 `split view enter/exit: tab=settings moved=N`）；
3. **D2**：退出登录后 `credentials.load()` 返回 undefined（"没有持久化凭据"一行）、cookie jar 已清空、
   界面回到登录页；**不声称**服务端会话被注销；
4. **D3/D4**：以 guest/guest 登录后三个 tab + 课程详情都有样例数据可浏览，**且** `data/remote/NetworkAudit` 的计数
   在这些浏览动作之后仍为 **0**（设置页那一行把它显示在屏幕上；另有一条**独立**证据证明这个计数器本身会涨 —— 真实账号下同一个计数器 > 0）；重启后回到登录页（mock 不持久化）；
5. **沉浸式**：切换开关后**立刻**生效（状态栏 / 导航栏消失与恢复各一张截图）；重启后仍是上次的值
   （preferences `learnoh_immersive_settings`）；关掉开关 1 时开关 2 自动置假且持久化；
   【2026-09-13 追加】本条末句"关掉开关 1 时开关 2 自动置假且持久化"**已不再适用**：开关 2
   （`immersiveAvoidFrontCamera`）已从沉浸式设置页移除，连带它的持久化字段、两条只为它存在的语义
   （显示值 = `immersiveMode && immersiveAvoidFrontCamera`、关掉开关 1 时的联动）与两条文案键
   （`loh_avoid_front_camera` / `loh_avoid_front_camera_description`）。原文保留是因为它记录了当时真的验证过的东西；
   本条其余部分（**立刻生效 / 重启保持**）仍然有效，且 `immersiveMode` 的行为未改。
6. **A1/A2**：见上表"代价"一列；两处都**只在对应场景**出现。

**未验证 / 边界**：

- **D2 的"服务端会话仍有效"这条路没有验证**：本工程不发"服务端登出"请求，所以被注销的只是本机凭据；
  服务端那一侧是否仍有会话（直到超时）**未测**。若将来要补，判据应是"下一次登录是否还需要短信 / 二次验证"，
  而那属于 ticket 07/08 的信任链，不在本 ticket。
- **`immersiveAvoidFrontCamera` 的平台效果没有移植**：参考实现里它唯一的用途是 RN 安全区回退
  （`App.tsx:727` 的 `disableHeaderTopInsetFallback`）；本工程的自绘页头没有那套 inset 回退，
  所以这个开关**只持久化与显示**（显示值 = `immersiveMode && immersiveAvoidFrontCamera`，联动与禁用照抄），
  **不声称**它改变了任何布局。
  【2026-09-13 追加 · **处置已定**】上面这条"边界"就是它成为"拨了没有任何效果"的开关的原因；选择不是补一套
  inset 回退去兜住它，而是**不提供**：开关 2 与持久化字段 `immersiveAvoidFrontCamera` 已移除，两条文案键
  一并退役（退役清单的唯一出处是 `scripts/i18n-lib.mjs`，生成物由生成器重跑而来）。旧沙箱里残留的
  `immersiveAvoidFrontCamera` 键**既不读也不删** —— 读路径只看 `immersiveMode`，缺键时 `get` 返回默认值，
  不可能因此抛异常；preferences 按键存取，多出来的键是惰性的。
  参考实现侧的出处仍是 `App.tsx:727` 与 `docs/rn-app-inventory.md:33`（后者描述的是 RN 应用本身，未改动）。
- **学期选择子页的 store 是设置页自己的一份**：参考实现的学期是全局 redux state，从设置页切学期会**全局**生效；
  本工程的课程数据按 tab 各持一份 store（ticket 12/15 的既有结构），所以从**设置页**切学期只影响该子页自身，
  **课程 tab 不会跟着变**。这是本 ticket 的已知缺口（登记为未验证项）；要修需要把课程 store 收敛成进程内单例
  ——那会动 ticket 12/15 已验收的结构，超出本 ticket 范围。

**取证**：`reference/learnOH-old/src/screens/{Settings,ImmersiveSettings,About,Help}.tsx`、`src/components/{TableCell,SplitView}.tsx`、
`src/data/{mock.ts,reducers/root.ts,reducers/settings.ts}`、`src/App.tsx:682-690,727`、`src/helpers/env.ts` 与 `.env`；
`entry/src/main/ets/features/settings/`（SettingsPage / ImmersiveSettingsPage / AboutPage / HelpPage）、
`entry/src/main/ets/features/mock/MockMode.ets`、`entry/src/main/ets/data/mock/`、`entry/src/main/ets/data/remote/NetworkAudit.ets`、
`entry/src/main/ets/data/settings/ImmersiveSettings.ets`；`entry/src/test/Settings.test.ets`；
`.scratch/settings/evidence/README.md`。

---

## 30. 收藏 / 归档 / 屏蔽：**置真改为去重**、行级收藏状态改用**原始收藏集合**（三视图口径收敛）—— 已复审（2026-09-13）

> **⚠️ 同号两义**：本条与上面的「设置与 Mock 模式的四处偏离」都是第 30 条（历史编号冲突，见 `docs/reference-quirks.md` 的「已知的编号冲突」一节）。
> 本条是 `docs/reference-quirks.md` 第 30 条（三视图口径）收敛后迁来的记录。

**参考实现行为**（`reference/learnOH-old/`，逐字可查）：

| # | 行为 | 出处 |
| --- | --- | --- |
| A | `all = items.filter(i => !archived.includes(i.id) && !hidden.includes(i.courseId))` | `src/data/selectors/filteredData.ts:77-79`（公告）、`:111-113`（作业）、`:147-149`（文件） |
| B | `fav = all.filter(i => fav.includes(i.id))` —— 在 all 之上再筛 | `:83`、`:118`、`:153` |
| C | `archived` / `hidden` 两个分组用**原始 items**（不套 A 的两条排除） | `:84-85`、`:119-120`、`:154-155` |
| D | 行级收藏状态取**过滤后的 fav 分组**（`fav?.some(f => f.id === item.id)`） | `src/components/FilterList.tsx:210-215` |
| E | reducer 置真一律 **append、不去重** | `src/data/reducers/notices.ts:59-72`、`assignments.ts:69-96`、`files.ts:67-94`、`courses.ts:65-70` |

**可复现的后果**（D + E）：先收藏一条公告 → 再到课程页屏蔽它所属的课程 → 打开公告页的"屏蔽"视图 → 该行显示为**未收藏**（条目在 all 之外、不在 fav 分组里）→ 再点一次收藏，favorites 里写下**重复 id**。

**变了什么**（2026-09-13）：

| 项 | 参考实现 | 新实现 |
| --- | --- | --- |
| 置真 | append、不去重（收藏 / 归档 / 屏蔽三处） | **集合语义**：已在集合里就不再加入（`domain/marks/CollectionFlags.ets` 的 `mergeId` / `mergeIds`） |
| 行级收藏状态 | 取过滤后的 fav 分组 | 取**原始收藏集合**（`flags.noticeFavorites` / `assignmentFavorites` / `fileFavorites`），三个列表页的滑动操作、长按菜单与 ForEach key 同一判据 |

**没变的**：三个分组的构造口径（A / B / C）与计数算式、`filteredData.ts` 的四个 tab 默认值、`all` 排除已归档与被屏蔽课程、收藏视图仍是 all 的子集（不在其中重复出现已归档 / 被屏蔽课程的条目）、归档与屏蔽两个分组仍用原始 items。行级**归档**状态也仍取归档分组（该分组就是"归档"视图的列表）。

**为什么可以偏离**："与参考实现一致"自 2026-09-13 起不再是完成定义（`reference/learnOH-old/` 只是标尺）；重复 id 是记账缺陷，屏蔽视图里的收藏状态显示错是界面缺陷，两者都在本轮 spec 的范围内（技术债 #30：置真去重 + 口径统一）。

**替代验收标准**：

1. 单测 `favoriteAndArchiveTogglingFollowsTheReferenceReducers`：同一内容项连续两次置真后 `favorites` 仍只有一份 id（该断言由"append 不去重"**反转为去重语义**，是有意的行为变更）；归档与屏蔽的置真同样只有一份。
2. 单测 `aFavoritedItemStaysFavoritedAfterItsCourseIsHidden`：收藏后屏蔽该课程，条目不在 fav 分组里（收藏视图口径不变），但原始收藏集合仍含它 ⇒ 屏蔽视图里该行显示为已收藏；此时再点一次收藏是**取消收藏**（置假），不会又写一条。
3. 设备侧：真机上一次「收藏 → 屏蔽该课程 → 看屏蔽视图」的截图，行上的收藏图标呈"已收藏"态（由统筹者采集）。

**原证据还成立到哪一步**：`reference-quirks.md` 第 30 条的 A–C（分组口径）与表格里的源文件行号仍然成立；只有 D / E 两项不再成立（正文条目已标【已收敛】）。ticket 14 交付节里"append 不去重是照抄参考实现"的结论按本条更正。

**取证**：`entry/src/main/ets/domain/marks/CollectionFlags.ets`、`entry/src/main/ets/features/marks/FilteredContent.ets`、`entry/src/main/ets/features/{notices/NoticesPage,assignments/AssignmentsPage,files/FilesPage}.ets`、`entry/src/test/Favorites.test.ets`；单测输出见本轮交付回报。



