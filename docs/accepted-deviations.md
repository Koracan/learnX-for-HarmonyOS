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

---

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
