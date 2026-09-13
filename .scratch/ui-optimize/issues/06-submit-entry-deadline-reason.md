# 06: 已截止时提交入口给出原因

**What to build:** 作业已截止时点提交入口，界面明确告诉用户「已截止、不能提交」，而不是毫无反应。
拦截行为本身一字不改（已截止就是不能提交）；改的只是「静默」变成「有说明」。

**Blocked by:** None（可立即开始）

**Status:** ready-for-agent

- [ ] 点提交入口在已截止时给出可读提示，文案里出现「截止」这类明确词
- [ ] 判定扩展为**带原因**，至少区分：已截止 / 未选附件 / 正在提交中；三种情形文案不同
- [ ] 未截止且附件就绪时，提交入口的行为与改动前一致
- [ ] 单测：纯判定函数对三种情形分别返回预期原因（沿用既有提交状态机测试的写法）
- [ ] 提示文案进入 i18n 资源，i18n 门禁通过
- [ ] ⚠️ 本账号所有作业均已截止 ⇒ **只验到「提示出现」为止，绝不发出真实提交请求**

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
