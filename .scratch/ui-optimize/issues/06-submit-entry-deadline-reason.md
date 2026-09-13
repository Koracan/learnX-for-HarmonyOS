# 06: 已截止时提交入口给出原因

**What to build:** 作业已截止时点提交入口，界面明确告诉用户「已截止、不能提交」，而不是毫无反应。
拦截行为本身一字不改（已截止就是不能提交）；改的只是「静默」变成「有说明」。

**Blocked by:** None（可立即开始）

**Status:** verified（合并 `400c952`：前提证伪 + 夹具构建下提交页给出原因，负对照齐全）

- [x] 点提交入口在已截止时给出可读提示，文案里出现「截止」这类明确词
- [x] 判定扩展为**带原因**，至少区分：已截止 / 未选附件 / 正在提交中；三种情形文案不同
- [x] 未截止且附件就绪时，提交入口的行为与改动前一致
- [x] 单测：纯判定函数对三种情形分别返回预期原因（沿用既有提交状态机测试的写法）
- [x] 提示文案进入 i18n 资源，i18n 门禁通过
- [x] ⚠️ 本账号所有作业均已截止 ⇒ **只验到「提示出现」为止，绝不发出真实提交请求**

## Comments

### 2026-09-13 · 统筹者派单中的现场情报与裁定（阶段 1 实现方读码后的回报 + 我的裁定）

**现场情报（实现方读码所得，我复核过关键处）**：提交入口有**两个**，判定函数不是同一个 ——
1. **作业详情页页头的上传图标** → `AssignmentFilter.isPastDeadline`（`AssignmentFilter.ets:34`）→ `AssignmentDetailPage.openSubmission()`：
   **源码里已经会提示**（`loh_assignment_past_deadline`）+ 日志 `submission entry blocked:`。⇒ 工单前提（"毫无反应"）在**这一支**与源码对不上。
2. **提交页页头「提交」按钮** → `domain/assignments/SubmissionState.canSubmit()` → 改动前 `.enabled(...)`：**这才是源码里真正静默的地方** ——
   判假时既无请求也无说明，而判假有 `uploading` / 没有可提交的内容两种原因。

参考实现（标尺）：`AssignmentSubmission.tsx:274-276` 只置灰、不给文字、**完全不看截止**；`AssignmentDetail.tsx:82-86` 已截止时有 `Toast(assignmentPastDeadline)`。

**待定性（阶段 2 设备取证的第一件事）**：真机登记（`migration/issues/18:256`）说"点上传图标无反应"，而源码有 toast；ticket 13 自己的取证又写"toast 未抓到"。⇒ 必须**先定性**：
真实会话进已截止作业详情 → 点上传图标 → 截图 + layout dump + hilog 搜 `submission entry blocked` / `toast failed` / `submission blocked`。
- 若 toast 出现 ⇒ 工单前提在这一支**被证伪**，如实记录（真正静默的是提交页）；
- 若抓不到且 hilog 有 `toast failed:` ⇒ 那是 **toast 传递层**的缺陷，**不在本 ticket 里顺手修**，交统筹者决定是否另立 ticket。

**裁定**：
- **提交页不消费截止判定**（那一支的 `pastDeadline` 传常量 `false`，函数签名保留，详情页入口照旧传真实值）。三条理由：① 工单写死"拦截行为本身一字不改"；② 参考实现也不看，改了就是**无验收条款背书**的偏离；③ 它在本账号**不可达**（详情页入口本来就拒绝已截止进入）⇒ 拿不到证据的行为不该加。另外，LMS 有 `bjjzsj`（补交截止，夹具 `AssignmentEvidence.ets:85` 就有这一支）⇒ **站点才是逾期裁判**，本地在别处再加一道闸可能挡住合法补交；"提交页要不要拦、拦的是 `deadline` 还是补交截止"是**独立问题**，另案再议。
- **`past_deadline` 复用** `loh_assignment_past_deadline`（参考实现已有、三语已有译文、含「截止」字样），不新造近义键。
- **提交页那一支的设备证据走夹具通道**：真实会话进不去提交页（546 条全已截止）时，用本仓既有的 `MOCK_ASSIGNMENTS_FOR_EVIDENCE`（提交态 `false`）—— 夹具 `夹具·未到期（含公式）`（`deadline = now + 2 天`）未截止、进得去；证据里必须注明**夹具构建**，且只拍"被拦下"的那一支，不触发任何真实提交。

### 2026-09-13 · 统筹者验收：**verified**（合并 `400c952`）

**最重要的一条：工单的前提在"详情页入口"这一支被设备证伪了**
真实会话（Pura 90 / `127.0.0.1:5557`）进已截止作业（第十二次作业，截止 2026-06-15 23:59，页面标「已截止」）→ 点页头提交图标 → **提示出现了**：
- hilog：`submission entry blocked: reason=past_deadline deadline=2026-06-15 23:59` + `AceOverlay: Toast node mount to root node` / `toast remove from root`；
- layout dump（`uitest dumpLayout -m true`）：`"text":"作业已截止" "type":"Toast" "visible":"true" "bounds":"[481,2352][839,2478]"`；
- **对照**：同页**不点击**时 `"type":"Toast"` 出现 **0** 次，点击那一次恰好 **1** 次；**`toast failed` 0 次** ⇒ toast 传递层没有缺陷，**不需要另立 ticket**。
- **这一帧我亲眼看过**：页面底部确实是「作业已截止」，页面头部那枚紫色上传图标清晰可见。
⇒ 真机登记（`migration/issues/18:256`）"点上传图标无反应、无任何提示"在这台设备+这份产物上**不成立**；本 ticket 真正补的是**提交页那支的静默**。

**提交页的"有说明"（夹具构建，已注明）**：`MOCK_ASSIGNMENTS_FOR_EVIDENCE=true` 单独构建取证产物（`assignments evidence: mock=true count=4`），进「夹具·未到期（含公式）」→ 提交页 → 不填正文不选附件 → 点「提交」：
- hilog ×14（14 次点击）：`submission blocked: reason=nothing_to_submit xszyid=mock-upcoming-1 …`；
- layout dump：`"text":"请先填写正文或选择附件，再提交" "type":"Toast" "visible":"true"`；**这一帧我也亲眼看过**（按钮是灰的但仍可点，底部是那句提示）；
- **"没有请求"负对照**：`data.assignments.submit` / `sending` / `fileupload` / `tjzy` / `toast failed` **全 0**，二次确认弹窗的「确定 / 取消」在 dump 里**不存在**。⇒ 工单第 6 条"绝不发出真实提交请求"有计数器背书，不是口头保证。

**"已搜索、不存在"（含一次判据纠正）**：9 个学期逐一遍历（每次 `aa force-stop` + `aa start --ps lohSemester <学期>` + 自证 `effective=… source=runtime-want-param`），读 `assignments applied: … items=N … pastDue=M`：合计 **items 546 / pastDue 546**，每个学期都 `pastDue == items` ⇒ **提交页在真实会话下不可达**（与我那份 18 号扫描的 546 逐个相同）。
- **判据纠正（值得记）**：列表上的「未完成」= `!i.submitted`（`features/marks/FilteredContent.ets:15`），**不含截止项** —— 2025-2026-1 显示「未完成 26」而那一学期 **108 条全部已截止**。用"未完成数"推"有没有未截止作业"会读反；实现方自己发现并改用 `pastDue`，这一点写进了证据。

**其余我复核的**：`test_result.txt` 时间戳 `2026/9/13 13:42:42`、`Tests run: 409, Failure: 0, Error: 0`；合并后主树四门禁绿；提交态产物与"阶段 2a 已验产物" **`ets/modules.abc` 逐字节相同**（`E7914006…996C0E`）⇒ 设备上留的是已验产物；夹具开关已还原 `false`、运行期学期覆盖已消失（`source=none`）。

**如实记录的限制**：
1. `uploading`（正在提交中）这一支**没有设备证据**（要抓"上传中"的窗口），只有单测 + `submissionBlockedKey` 的三键映射钉住。
2. 「未截止且附件就绪 ⇒ 能走到二次确认」这条**设备上也验不到**（那要求真的发起提交）。改动的等价性由单测钉住：**8 个状态下 `blocked === !canSubmit`**，即拦截集一个字没变。
3. 提交页那一帧来自**夹具构建**（`MOCK_ASSIGNMENTS_FOR_EVIDENCE=true`），不是提交态产物；提交态产物只用于"详情页提示"那一帧与最终留机。

**我这一轮下的两条裁定都已落地**：提交页**不**消费截止判定（`pastDeadline` 传常量 `false`，签名保留）；`past_deadline` **复用** `loh_assignment_past_deadline`，未新造键。
