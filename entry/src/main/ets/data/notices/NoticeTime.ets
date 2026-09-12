/*
 * 公告时间解析 —— **纯字符串运算，零平台依赖**。
 *
 * 【ticket 09 迁移】这段逻辑原在 features/notices/NoticeOrder.ets（ticket 03）。
 * 现在 data/notices 也需要它（把 domain 的 `Notice.publishTime` 字符串换算成
 * NoticeRecord.publishTimeMillis 才能落快照），而 data 不能依赖 features。
 * 于是把它移到 data/notices 这一处，features/notices/NoticeOrder **再导出**同名函数，
 * 既有调用点（含单测）一行不用改——只有一份实现。
 *
 * 语义逐条对齐参考实现 data/actions/notices.ts 的
 * `dayjs(publishTime).unix()`：站点下发的是本地时间（无时区），按本地时区解释。
 *
 * 【ticket 12 边界】它只服务**公告发布时间**（卡片的排序键）。作业截止时间的比较在
 * `domain/courses/CourseCounts`，走 `domain/parse/Text.parseTimestamp`——那里对
 * RFC3339 与 `YYYY-MM-DD HH:mm(:ss)` 都做本地时区补全，而 dayjs 也是同一套宽容解析。
 * 真实站点下发的时间串两种形状相同（`YYYY-MM-DD HH:mm`），两条路径在真实数据上一致。
 */

/** 参考实现的 publishTime 形如 '2020-09-25 07:21'（本地时间，无时区）。 */
const TIME_LENGTH: number = 16;

/** 只接受纯数字片段（不用正则：ArkTS 的 RegExpMatchArray 会撞 arkts-no-structural-typing）。 */
function isAllDigits(text: string): boolean {
  if (text.length === 0) {
    return false;
  }
  for (let i = 0; i < text.length; i++) {
    const code: number = text.charCodeAt(i);
    if (code < 48 || code > 57) {
      return false;
    }
  }
  return true;
}

/**
 * 'YYYY-MM-DD HH:mm' → epoch 毫秒（本地时区，对齐 dayjs 的默认解析）。
 * 无法解析时返回 0（排到最后），不抛异常：抓取数据可能有脏值。
 * 解析是手写的（定长 + 分隔符 + 数字校验），不依赖 ICU 或宿主正则实现。
 */
export function parseNoticeTime(text: string): number {
  if (text.length < TIME_LENGTH) {
    return 0;
  }
  const third: string = text.charAt(10);
  if (text.charAt(4) !== '-' || text.charAt(7) !== '-' || (third !== ' ' && third !== 'T')
    || text.charAt(13) !== ':') {
    return 0;
  }
  const yearText: string = text.substring(0, 4);
  const monthText: string = text.substring(5, 7);
  const dayText: string = text.substring(8, 10);
  const hourText: string = text.substring(11, 13);
  const minuteText: string = text.substring(14, 16);
  if (!isAllDigits(yearText) || !isAllDigits(monthText) || !isAllDigits(dayText)
    || !isAllDigits(hourText) || !isAllDigits(minuteText)) {
    return 0;
  }
  const year: number = Number(yearText);
  const month: number = Number(monthText);
  const day: number = Number(dayText);
  const hour: number = Number(hourText);
  const minute: number = Number(minuteText);
  if (month < 1 || month > 12 || day < 1 || day > 31 || hour > 23 || minute > 59) {
    return 0;
  }
  return new Date(year, month - 1, day, hour, minute, 0, 0).getTime();
}
