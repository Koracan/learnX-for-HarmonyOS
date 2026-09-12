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
  ['ui_exported', '已导出 {0} 条 / {1} 字节', 'Exported {0} records / {1} bytes'],
  ['ui_export_failed', '导出失败：{0}', 'Export failed: {0}'],
  ['ui_locale_live_demo', '语言切换（无需重启）', 'Language switch (no restart)'],
  ['ui_switch_chinese', '切到中文', 'Switch to Chinese'],
  ['ui_switch_english', '切到英文', 'Switch to English'],
  ['ui_current_locale', '当前语言', 'Current locale'],
  ['ui_relative_time_sample', '相对时间示例', 'Relative time sample'],
  ['ui_date_time_sample', '日期时间示例', 'Date/time sample'],
  ['ui_semester_sample', '学期文案示例', 'Semester text sample'],
  ['ui_language', '语言', 'Language'],
  // --- ticket 03（导航骨架 + 公告列表）新增 ---
  ['ui_tab_notices', '公告', 'Notices'],
  ['ui_tab_placeholder', '该页面将在后续迭代中实现', 'This page will be implemented in a later iteration'],
  ['ui_empty_notices', '暂无公告', 'No notices'],
  ['ui_refreshed_at', '更新于 {0}', 'Updated {0}'],
  // --- ticket 04（公告详情 + HTML 渲染）新增 ---
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
  // --- ticket 07（设备登记）新增：提交前自检的提示 ---
  // 2026-09-12 真实登记被服务端判为"隐私/匿名模式"而拒绝信任：fingerGenPrint/fingerGenPrint3
  // 为空时该浏览器不可能被记为可信，而用户已经为此白花了一条短信。这条文案就是"替你挡下"时
  // 显示给用户的话（页面内横幅 + 应用内提示各用一次）。
  // --- ticket 09（真实公告 + 快照）新增 ---
  // 卡片右上角两个状态图标是无文字的 emoji（参考实现用 MaterialCommunityIcons 的
  // attachment / flag），所以这两条只作为 accessibilityText 存在，保证读屏也能拿到语义。
  ['ui_attachment_label', '含附件', 'Has attachment'],
  ['ui_marked_important_label', '重要公告', 'Marked important'],
  // 数据陈旧程度：与 ui_refreshed_at 拼在一起（"更新于 09:12:33 · 5 分钟前"）。
  // **不需要新键**：整句相对时间（含"前" / "ago"）由 core/i18n 的 formatRelativeTo 给出，
  // 它已按 locale 出措辞；再套一层 "{0} ago" 会在中文界面拼出"… ago"或在英文拼出
  // "ago ago"。取不到措辞时（relative.length===0）整段不显示，界面只留绝对时间。
  // --- ticket 12（课程列表 + 详情 + 学期选择）新增 ---
  // 课程卡片右下三个计数：参考实现是 MaterialIcons 的 notifications / event / folder，
  // ArkUI 没有可移植的等价符号（同 ticket 09 对公告图标的判断），故用 emoji + 这三条
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
  // 取数失败的错误态（会话失效用 ticket 08 的 loh_session_expired，这里只兜其余失败）。
  ['ui_courses_load_failed', '课程加载失败：{0}', 'Failed to load courses: {0}'],
  // 学期覆盖（脚本入口）生效时的界面标记：让"确实切过去了"在截图上可见。
  ['ui_courses_override_badge', '取证覆盖生效', 'Evidence override active'],
  // --- ticket 10（作业列表 + 详情）新增 ---
  // 三种"空"必须给不同的话：没有作业（秋季真实状态）/ 没有未完成（春季 57 条全已交）/
  // 没有已完成。见 features/assignments/AssignmentText.emptyStateKey。
  ['ui_assignments_empty', '暂无作业', 'No assignments'],
  ['ui_assignments_none_unfinished', '没有未完成的作业', 'No unfinished assignments'],
  ['ui_assignments_none_finished', '没有已完成的作业', 'No finished assignments'],
  ['ui_assignments_load_failed', '作业加载失败：{0}', 'Failed to load assignments: {0}'],
  // 验收第 1 条要的"状态标记"：未到期 / 已截止（参考实现用 dayjs 的相对时间那句表达，
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
  ['ui_enrollment_fingerprint_not_ready',
    '浏览器指纹尚未就绪，此刻提交不会把该浏览器记为可信（服务端会提示"隐私或匿名模式"）。请稍等几秒后再次点击登录；若反复出现，请关闭本页重新登录。',
    'The browser fingerprint is not ready yet, so signing in now would not register this browser as trusted (the server would report a private/anonymous browser). Wait a few seconds and tap sign in again; if it keeps happening, close this page and sign in again.']
];