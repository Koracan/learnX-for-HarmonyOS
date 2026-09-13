// i18n-ui-strings.mjs
//
// UI copy introduced by the native rewrite. These strings do not exist in the
// reference dictionaries (the reference UI was replaced wholesale), so they
// live in their own `ui_` namespace and are NOT counted as migrated reference
// keys. Placeholders use {N} and are rewritten to %(N+1)$s.

export const UI_STRINGS = [
  ['ui_app_name', 'learnOH', 'learnOH'],
  ['ui_app_tagline',
    'HarmonyOS 原生重写 · foundation / 01 分层 + 日志 + 主题令牌',
    'Native HarmonyOS rewrite · foundation / 01 layering + logging + theme tokens'],
  ['ui_self_check_card_title', '自检', 'Self-check'],
  ['ui_system_color_mode', '系统配色', 'System color mode'],
  ['ui_dark', '深色', 'Dark'],
  ['ui_light', '浅色', 'Light'],
  ['ui_color_tokens', '颜色令牌', 'Color tokens'],
  ['ui_recent_log_count', '最近日志条数', 'Recent log records'],
  ['ui_semester_parse_failed', '解析失败', 'Parse failed'],
  ['ui_semester_parse', 'domain.Semester 解析', 'domain.Semester parse'],
  ['ui_semester_compare', 'domain.Semester 比较', 'domain.Semester compare'],
  ['ui_semester_later', '较晚 = {0}', 'later = {0}'],
  ['ui_reference_palette', '参考实现调色板（Colors.ts）', 'Reference palette (Colors.ts)'],
  ['ui_export_logs', '导出日志为文本文件', 'Export logs to a text file'],
  ['ui_exported', '已导出 {0} 条 / {1} 字节\n保存位置：{2}', 'Exported {0} records / {1} bytes\nSaved to: {2}'],
  ['ui_export_failed', '导出失败：{0}', 'Export failed: {0}'],
  ['ui_locale_live_demo', '语言切换（无需重启）', 'Language switch (no restart)'],
  ['ui_switch_chinese', '切到中文', 'Switch to Chinese'],
  ['ui_switch_english', '切到英文', 'Switch to English'],
  ['ui_current_locale', '当前语言', 'Current locale'],
  ['ui_relative_time_sample', '相对时间示例', 'Relative time sample'],
  ['ui_date_time_sample', '日期时间示例', 'Date/time sample'],
  ['ui_semester_sample', '学期文案示例', 'Semester text sample'],
  ['ui_language', '语言', 'Language'],
  // --- 公告列表（导航骨架）新增 ---
  ['ui_tab_notices', '公告', 'Notices'],
  ['ui_tab_placeholder', '该页面将在后续迭代中实现', 'This page will be implemented in a later iteration'],
  ['ui_empty_notices', '暂无公告', 'No notices'],
  ['ui_refreshed_at', '更新于 {0}', 'Updated {0}'],
  // --- 公告详情（HTML 渲染）新增 ---
  // 详情页的绝对时间由 domain/render/NoticeDateText 按下面的模式渲染；dayjs 的记号
  // （YYYY/M/D/H/m）与 ICU 的针名不同，故模式作为资源进 i18n，而不是写死在渲染代码里。
  // 中文模式含 dddd（星期）；英文模式是 MMM D, YYYY HH:mm。两者逐字取自
  // reference/learnOH-old/src/screens/NoticeDetail.tsx:86-90。
  ['ui_notice_publish_time', 'YYYY 年 M 月 D 日 dddd HH:mm', 'MMM D, YYYY HH:mm'],
  ['ui_weekday_sunday', '星期日', 'Sun'],
  ['ui_weekday_monday', '星期一', 'Mon'],
  ['ui_weekday_tuesday', '星期二', 'Tue'],
  ['ui_weekday_wednesday', '星期三', 'Wed'],
  ['ui_weekday_thursday', '星期四', 'Thu'],
  ['ui_weekday_friday', '星期五', 'Fri'],
  ['ui_weekday_saturday', '星期六', 'Sat'],
  ['ui_month_jan', '1 月', 'Jan'],
  ['ui_month_feb', '2 月', 'Feb'],
  ['ui_month_mar', '3 月', 'Mar'],
  ['ui_month_apr', '4 月', 'Apr'],
  ['ui_month_may', '5 月', 'May'],
  ['ui_month_jun', '6 月', 'Jun'],
  ['ui_month_jul', '7 月', 'Jul'],
  ['ui_month_aug', '8 月', 'Aug'],
  ['ui_month_sep', '9 月', 'Sep'],
  ['ui_month_oct', '10 月', 'Oct'],
  ['ui_month_nov', '11 月', 'Nov'],
  ['ui_month_dec', '12 月', 'Dec'],
  // --- 设备登记新增：提交前自检的提示 ---
  // 2026-09-12 真实登记被服务端判为"隐私/匿名模式"而拒绝信任：fingerGenPrint/fingerGenPrint3
  // 为空时该浏览器不可能被记为可信，而用户已经为此白花了一条短信。这条文案就是"替你挡下"时
  // 显示给用户的话（页面内横幅 + 应用内提示各用一次）。
  // --- 真实公告 + 快照新增 ---
  // 卡片右上角两个状态图标是无文字的 emoji（参考实现用 MaterialCommunityIcons 的
  // attachment / flag），所以这两条只作为 accessibilityText 存在，保证读屏也能拿到语义。
  ['ui_attachment_label', '含附件', 'Has attachment'],
  ['ui_marked_important_label', '重要公告', 'Marked important'],
  // 数据陈旧程度：与 ui_refreshed_at 拼在一起（"更新于 09:12:33 · 5 分钟前"）。
  // **不需要新键**：整句相对时间（含"前" / "ago"）由 core/i18n 的 formatRelativeTo 给出，
  // 它已按 locale 出措辞；再套一层 "{0} ago" 会在中文界面拼出"… ago"或在英文拼出
  // "ago ago"。取不到措辞时（relative.length===0）整段不显示，界面只留绝对时间。
  // --- 课程列表 + 详情 + 学期选择新增 ---
  // 课程卡片右下三个计数：参考实现是 MaterialIcons 的 notifications / event / folder，
  // ArkUI 没有可移植的等价符号（与公告图标的判断一致），故用 emoji + 这三条
  // 只作为 accessibilityText 的语义文案。数字本身逐字可见，是验收的判据。
  ['ui_course_unread_notices_label', '未读公告', 'Unread notices'],
  ['ui_course_unfinished_assignments_label', '未完成作业', 'Unfinished assignments'],
  ['ui_course_new_files_label', '新文件', 'New files'],
  // 课程 tab 头部那句"当前学期：<文案>"的前缀（学期文案本身来自 getSemesterTextFromId）。
  ['ui_courses_semester_label', '当前学期', 'Current semester'],
  ['ui_courses_empty', '暂无课程', 'No courses'],
  // 学期集合接口（queryxnxq）失败时**不假装完整**：显式说明列表可能不全。
  ['ui_course_semester_list_unavailable',
    '学期列表暂不可用，仅列出当前学期与已生效的学期。',
    'The semester list is unavailable; only the current and the active semester are listed.'],
  // 取数失败的错误态（会话失效用 loh_session_expired，这里只兜其余失败）。
  ['ui_courses_load_failed', '课程加载失败：{0}', 'Failed to load courses: {0}'],
  // 学期覆盖（脚本入口）生效时的界面标记：让"确实切过去了"在截图上可见。
  ['ui_courses_override_badge', '取证覆盖生效', 'Evidence override active'],
  // --- 学期切换编排（加载 / 结果提示 / 不自动返回）新增 ---
  // 切换在途的加载遮罩文案（遮罩上另有一行目标学期，取 getSemesterTextFromId）。
  ['ui_semester_switching', '正在切换学期…', 'Switching semester…'],
  // 全部域成功。{0} = 目标学期的界面文案。
  ['ui_semester_switch_succeeded', '已切换到{0}', 'Switched to {0}'],
  // 部分失败：{0} = 目标学期，{1} = 失败的域（顿号分隔的界面名），{2} = 第一条原因要点。
  ['ui_semester_switch_partial',
    '已切换到{0}，但{1}刷新失败：{2}',
    'Switched to {0}, but refreshing {1} failed: {2}'],
  // 全部失败：{0} = 目标学期，{1} = 原因要点。
  ['ui_semester_switch_failed', '切换到{0}失败：{1}', 'Failed to switch to {0}: {1}'],
  // --- 作业列表 + 详情新增 ---
  // 三种"空"必须给不同的话：没有作业（秋季真实状态）/ 没有未完成（春季 57 条全已交）/
  // 没有已完成。见 features/assignments/AssignmentText.emptyStateKey。
  ['ui_assignments_empty', '暂无作业', 'No assignments'],
  ['ui_assignments_none_unfinished', '没有未完成的作业', 'No unfinished assignments'],
  ['ui_assignments_none_finished', '没有已完成的作业', 'No finished assignments'],
  ['ui_assignments_load_failed', '作业加载失败：{0}', 'Failed to load assignments: {0}'],
  // "状态标记"要的未到期 / 已截止（参考实现用 dayjs 的相对时间那句表达，
  // 平台侧 Intl.RelativeTimeFormat 给不出同样的措辞 —— 换成一枚明确的本地化标记，
  // 见 features/assignments/AssignmentsPage.ets 的文件头说明）。
  ['ui_assignment_upcoming', '未到期', 'Not due'],
  ['ui_assignment_past_due', '已截止', 'Past due'],
  ['ui_assignment_deadline', '截止时间', 'Deadline'],
  ['ui_assignment_late_deadline', '补交截止', 'Late submission due'],
  ['ui_assignment_description', '作业内容', 'Description'],
  // 段标题：参考实现的 grade / key-variant 图标各配一个词。
  ['ui_assignment_grade', '成绩', 'Grade'],
  ['ui_assignment_answer', '参考答案', 'Answer'],
  // 时间行（参考实现的三条 dayjs 格式化模板，逐条对应）。
  ['ui_assignment_submitted_at', '提交于 {0}', 'Submitted at {0}'],
  ['ui_assignment_submitted_late_at', '补交于 {0}', 'Submitted late at {0}'],
  ['ui_assignment_graded_at', '批改于 {0}', 'Graded at {0}'],
  ['ui_assignment_graded_by_at', '{0} 批改于 {1}', 'Graded by {0} at {1}'],
  // 四类附件的语义标签（附件行只有图标 + 文件名，这四条进无障碍树与界面说明）。
  ['ui_assignment_attachment_label', '作业附件', 'Assignment attachment'],
  ['ui_assignment_submitted_attachment_label', '我的提交附件', 'Submitted attachment'],
  ['ui_assignment_grade_attachment_label', '批改附件', 'Grade attachment'],
  ['ui_assignment_answer_attachment_label', '答案附件', 'Answer attachment'],
  // 卡片右上角 emoji 标记的无障碍文案（参考实现那几个图标名对读屏就是名称）。
  ['ui_assignment_submitted_mark_label', '已提交', 'Submitted'],
  ['ui_assignment_graded_mark_label', '已评分', 'Graded'],
  ['ui_assignment_answer_mark_label', '含答案', 'Has answer'],
  // --- 优秀作业补做（yxzylist 列表 + viewYxzy 详情页） ---
  // 参考实现：卡片上 excellentHomeworkList.length > 0 时一枚黄色 medal（AssignmentCard.tsx:84-91）；
  // 详情页每条显示 gradeAttachment || submittedAttachment 与作者（匿名时用 loh_anonymous）。
  ['ui_assignment_excellent', '优秀作业', 'Excellent homework'],
  ['ui_assignment_excellent_by', '{0}的优秀作业', 'Excellent homework by {0}'],
  ['ui_assignment_excellent_mark_label', '含优秀作业', 'Has excellent homework'],
  ['ui_enrollment_fingerprint_not_ready',
    '浏览器指纹尚未就绪，此刻提交不会把该浏览器记为可信（服务端会提示"隐私或匿名模式"）。请稍等几秒后再次点击登录；若反复出现，请关闭本页重新登录。',
    'The browser fingerprint is not ready yet, so signing in now would not register this browser as trusted (the server would report a private/anonymous browser). Wait a few seconds and tap sign in again; if it keeps happening, close this page and sign in again.'],
  // --- 文件列表 + 详情 + 下载 + 预览 + 分享新增 ---
  // 参考实现已有的串（loh_file_download_failed / loh_open_file_failed / loh_share /
  // loh_open / loh_no_file_size / loh_no_file_description / loh_clear_file_cache* /
  // loh_file_use_document_dir / loh_file_omit_course_name）直接复用，不重复声明。
  ['ui_files_empty', '暂无文件', 'No files'],
  ['ui_files_load_failed', '文件加载失败：{0}', 'Failed to load files: {0}'],
  // 详情页的字段标签（参考实现那两行只有图标 + 值，没有文字；这里补文字进无障碍树）。
  ['ui_file_type_label', '类型', 'Type'],
  ['ui_file_size_label', '大小', 'Size'],
  ['ui_file_upload_time_label', '上传时间', 'Uploaded at'],
  // 下载进度：进度条本身是比例；这两条给"下载中"与"已接收 / 总量"的文本。
  // Content-Length 缺失时**不假装百分比**，只显示已接收字节（见 FileDetailPage）。
  ['ui_file_downloading', '下载中', 'Downloading'],
  ['ui_file_download_progress', '{0} / {1}', '{0} / {1}'],
  ['ui_file_download_received', '已接收 {0}', 'Received {0}'],
  // 非会话原因的拒绝（状态码非 200 且不是 403 / JSON 错误页）：说清是"响应不是文件内容"。
  ['ui_file_download_rejected', '下载被拒绝：{0}', 'Download rejected: {0}'],
  ['ui_file_download_empty', '服务端返回了空文件', 'The server returned an empty file'],
  // 预览：PDF 走 PDFKit，图片走 Image。渲染器起不来时**如实说**，不悄悄退回"跳第三方"。
  ['ui_file_preview_failed', '预览失败：{0}', 'Preview failed: {0}'],
  ['ui_file_preview_unavailable',
    '该文件类型不支持应用内预览，可下载后分享给其他应用。',
    'This file type cannot be previewed in the app; download it and share it with another app.'],
  ['ui_file_share_failed', '分享失败：{0}', 'Share failed: {0}'],
  // 文件详情的「交给系统打开方式」：文件还没落盘时点它要给一句可读的话，而不是什么都不发生。
  // 交给系统之后失败的文案复用参考实现已有的 loh_open_file_failed —— 它已经说了
  // "确保存在可打开此文件类型的应用"，正是设备上没有接收方时的原因。
  ['ui_file_open_not_ready',
    '文件尚未下载完成，暂时不能交给其他应用打开。',
    'The file has not finished downloading, so it cannot be handed to another app yet.'],
  ['ui_file_saved_at', '保存位置：{0}', 'Saved at: {0}'],
  // 详情页右上角那个"详情 / 预览"开关（参考实现用 preview / info-outline 两个图标）。
  ['ui_file_view_info', '详情', 'Info'],
  ['ui_file_view_preview', '预览', 'Preview'],
  // 文件设置页（值/语义在 data/settings；全局设置页的入口/外观归全局设置）。
  ['ui_file_settings_title', '文件设置', 'File settings'],
  ['ui_file_use_document_dir_on',
    '文件保存在 App 的"文档"中，只会随 App 卸载而被删除。',
    'Files are saved in the App Document folder and are deleted only when the app is uninstalled.'],
  ['ui_file_use_document_dir_off',
    '文件保存在 App 的"缓存"中，会在设备空间不足或其他系统预设情况下被自动清除以节约空间。',
    'Files are saved in the App cache folder; the system may clear it when space is low.'],
  ['ui_file_omit_course_name_on',
    '文件以"文件名"形式保存。',
    'Files are saved as "filename".'],
  ['ui_file_omit_course_name_off',
    '文件以"课程名-文件名"形式保存。',
    'Files are saved as "coursename-filename".'],
  ['ui_file_settings_root', '当前保存位置：{0}', 'Current save location: {0}'],
  // PDF 预览的翻页（`PdfView` 组件在模拟器上不可用，改用 pdfService 渲染单页 PixelMap，
  // 见 FileDetailPage 的 pdfDocument 字段说明）。
  ['ui_file_prev_page', '上一页', 'Previous page'],
  ['ui_file_next_page', '下一页', 'Next page'],
  ['ui_file_page_of', '第 {0} / {1} 页', 'Page {0} of {1}'],
  ['ui_file_cache_already_empty', '缓存目录已为空', 'The cache folder is already empty'],
  // --- 图标保真 + 页头信息架构新增 ---
  // 页头的"相对更新时间"四档（数据源 = 快照的 fetchedAtMillis；**不**每秒重算）。
  // 分档是纯函数（ui/components/UpdatedTime.ets 的 updatedTimeParts），单测钉边界：
  //   <60s → just now；1–59 分钟；1–23 小时；≥24 小时（天）。
  // 英文用 min / h / d 缩写，避免 "1 minutes ago" 这种单复数别扭。
  ['ui_updated_just_now', '刚刚更新', 'Updated just now'],
  ['ui_updated_minutes_ago', '{0} 分钟前更新', 'Updated {0} min ago'],
  ['ui_updated_hours_ago', '{0} 小时前更新', 'Updated {0} h ago'],
  ['ui_updated_days_ago', '{0} 天前更新', 'Updated {0} d ago'],
  // --- 作业提交新增 ---
  // 提交页底部那句「上次提交于 …」。参考实现在 AssignmentSubmission.tsx:445-453 把两种语言的
  // dayjs 模式**硬编码在屏幕里**（中文 '上次提交于 YYYY 年 M 月 D 日 dddd HH:mm'、
  // 英文 '[last submitted at] HH:mm, MMM D, YYYY'）。这里把整条模式（含前缀）变成资源，
  // 由 domain/render/NoticeDateText 的 formatNoticeDate 渲染 —— 与公告发布时间同一套机制。
  ['ui_assignment_submission_time',
    '上次提交于 YYYY 年 M 月 D 日 dddd HH:mm',
    '[last submitted at] HH:mm, MMM D, YYYY'],
  // --- 收藏 / 归档 / 隐藏课程新增 ---
  // 参考实现的滑动按钮**只换图标**（heart ↔ heart-off、archive-arrow-down ↔ archive-arrow-up、
  // visibility-off ↔ visibility），没有任何文字（CardWrapper.tsx:63-117）。
  // 本工程给按钮带 accessibilityText、并给"长按"那一支一个菜单（等价入口），
  // 因此需要三个"反向动作"的说法；正向动作直接用参考实现已有的 loh_fav / loh_archived / loh_hidden。
  ['ui_remove_favorite', '取消收藏', 'Remove from favorites'],
  ['ui_unarchive', '取消归档', 'Unarchive'],
  ['ui_unhide_course', '取消屏蔽', 'Unhide course'],
  // --- 设置与子页 + Mock 模式新增 ---
  // Mock 模式的**可见自证行**（设置页在 mock 用户下显示这一条）：
  // {0} = 进入 mock 模式后**实际发生过的网络请求数**。要点是它必须打在**消费点**——
  // 计数来自 data/remote/NetworkAudit（唯一的两处 http 出口：HttpClient / HttpDownloadPort），
  // 所以"界面可用 + 计数为 0"是同一张截图里可核的（自证方式）。
  ['ui_mock_mode_active',
    'Mock 模式（guest）：数据为样例，已发出的网络请求 = {0}',
    'Mock mode (guest): sample data, network requests issued = {0}'],
  // 关于页的「开源依赖」一节：参考实现把 package.json 的 dependencies 逐行列出，本工程根
  // oh-package.json5 的 dependencies 为空（只有 hypium / hamock 两个 devDependency），
  // 所以**如实说明没有第三方运行时依赖**，而不是照抄参考实现那份名单。
  ['ui_opensource_dependencies_none',
    '本应用不包含第三方运行时依赖，只使用 HarmonyOS SDK 提供的系统能力。',
    'This app bundles no third-party runtime dependencies; it uses only the HarmonyOS SDK system capabilities.'],
  // --- 提交入口被拦下时的那两句 ---
  // 提交按钮在"不能提交"时不再是一个点了没反应的灰按钮，而是说清原因。
  // 三种原因三句话：已截止复用参考实现已有的 loh_assignment_past_deadline（它说的就是这件事，
  // AssignmentDetail.tsx:84 的 assignmentPastDeadline），这里只补另外两种。
  //   - 正在提交中：上一次还没跑完，再点一次不该叠第二次请求；
  //   - 没有可提交的内容：正文、新附件、移除已上传附件三者都没有 —— 参考实现此时
  //     只把按钮置灰（AssignmentSubmission.tsx:274-276），没有任何文字。
  ['ui_assignment_submit_blocked_uploading',
    '正在提交中，请稍候',
    'Submission in progress; please wait'],
  ['ui_assignment_submit_blocked_nothing_to_submit',
    '请先填写正文或选择附件，再提交',
    'Write something or pick an attachment before submitting']
];