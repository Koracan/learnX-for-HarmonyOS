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
  ['ui_month_dec', '12 月', 'Dec']
];
