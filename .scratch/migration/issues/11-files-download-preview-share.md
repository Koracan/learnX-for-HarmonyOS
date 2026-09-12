# 11: 文件列表 + 详情 + 下载 + 预览 + 分享

**What to build:** 文件 tab 显示真实文件，详情可下载（进度可见）、在应用内预览 PDF 与图片、分享或交给其他应用打开；文件设置（使用文档目录、省略课程名、清理缓存）生效。

**Blocked by:** 09（公告切真实数据 + 快照）

**Status:** ready-for-agent

- [ ] 列表按上传时间倒序，显示大小与类型
- [ ] 下载显示进度，完成后可预览；PDF 与图片在应用内打开，无需跳转第三方
- [ ] 会话过期导致下载到登录页时能被识别并给出正确提示，不留下损坏文件
- [ ] 分享面板可调起；含中文与空格的路径可用
- [ ] 清理缓存后文件真正消失；使用文档目录与省略课程名两个设置均生效
- [ ] 真机截图

## Comments

### 统筹提示（2026-09-12，**用户提供的事实**）—— 本学期**文件非空**，可直接用真实数据验收

- 用户账号 **2026-2027 学年秋季学期**：**公告、文件、课程都有非空数据**；**只有作业为空**。
- ⇒ 本 ticket 的列表 / 下载 / 预览 / 分享**不需要学期切换**就能拿到真实数据；**空结果应视为失败信号**（端点 / 参数 / 会话 / 解析），**不要**解释成"本学期没文件"。
- 期望与网页端对照：条数、顺序（按上传时间倒序）、大小与类型。
- 与作业线（ticket 10/13）的区别记牢：那两条本学期为空，要真实数据必须切到 **2025-2026 学年春季学期**（见 ticket 12 的统筹提示）。

### 边界说明（2026-09-12，由 ticket 10 带入）—— "附件 → FileDetail" 的路由已接通，真身仍全是你的

ticket 10 的作业详情把**四类附件**（attachment / submittedAttachment / gradeAttachment / answerAttachment）
都接到 ticket 04 的 `ROUTE_FILE_DETAIL`（`features/notices/NoticeRoutes.ets`）与
`FileDetailPlaceholderPage` 上（照参考实现 `AssignmentDetail.tsx:132-145` 的 `handleFileOpen`）。
你实现真身时会碰到四件事：

1. **`FileDetailRouteParams.noticeId` 有两个来源**：公告详情传**公告 id**（`NoticeDetail.tsx:64`），
   作业详情传**附件 id**（`AssignmentDetail.tsx:134`）。参考实现里这个字段只用来拼下载目录名
   （`helpers/fs.ts:54`：`${dir}/${file.courseName}/${file.id}`），所以两种都能用。
   字段名保留 `noticeId` 是为了不动 ticket 04 已验收的导航契约（我**没有**改它的形状）。
2. **作业附件的 `id` 可能是空串**：真实数据里提交附件的下载地址是**路径形态** ——
   `/b/wlxt/kczy/zy/student/downloadFile/2025-2026-2151371080/2023011272_ZY_178014313120047eacdb87a-…` ——
   没有 `fileId=` / `wjid=` 查询参数，`domain/parse/Attachment` 取不到 id ⇒ `noticeId` 为空
   （实测 hilog：`assignment attachment tapped: kind=main … id=`）。
   真身若要"按文件缓存 / 去重"，**必须为这种情况兜底**（例如用 downloadUrl 的末段做键），
   别把空串直接当目录名。
3. **ticket 10 只做掉了"列表要全 + 可点 + 目标路由明确"**：下载（进度可见）、应用内预览 PDF 与图片、
   分享、三个文件设置（文档目录 / 省略课程名 / 清理缓存）、"会话过期导致下载到登录页"的识别——
   **全部还是你的**（本 ticket 的验收第 1-5 条一条未动）。本轮没有实现任何下载或落盘代码，
   也没有改 ticket 05 的 `helpers` 等价物。
4. 我改到的文件只有两处**注释**：`features/notices/NoticeRoutes.ets`、
   `features/notices/FileDetailPlaceholderPage.ets`；导航契约（字段名、参数形状、路由名）原样未动。

（工单里的"验收第 6 条 真机截图"同样按 AGENTS.md 转 ticket 18 的一次性复验。）
