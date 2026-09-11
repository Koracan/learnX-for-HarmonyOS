/*
 * 公告列表的纯规则：时间解析、倒序排序、未读判定、空态判定。
 *
 * 排序语义逐条对齐参考实现 data/actions/notices.ts：
 *   (a, b) => dayjs(b.publishTime).unix() - dayjs(a.publishTime).unix()
 *             || b.id.localeCompare(a.id)
 * 即先按发布时间倒序，时间相同再按 id 倒序。这里用 epoch 毫秒做第一键
 * （unix() 是秒，二者同序）。
 *
 * 纯函数、无平台依赖，是单测的主战场（entry/src/test/Notices.test.ets）。
 */
import { NoticeRecord } from './repository/NoticeRepository';

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

/** 发布时间倒序；同一时间按 id 倒序（参考实现的 localeCompare 语义）。 */
export function compareNoticesDesc(a: NoticeRecord, b: NoticeRecord): number {
  const byTime: number = b.publishTimeMillis - a.publishTimeMillis;
  if (byTime !== 0) {
    return byTime;
  }
  return b.id.localeCompare(a.id);
}

/** 返回排序后的新数组，不修改入参。 */
export function sortNoticesDesc(items: NoticeRecord[]): NoticeRecord[] {
  const copy: NoticeRecord[] = items.slice();
  copy.sort(compareNoticesDesc);
  return copy;
}

/** 未读判定：hasRead 为 false 即未读。 */
export function isUnread(notice: NoticeRecord): boolean {
  return !notice.hasRead;
}

/** 未读条数。 */
export function countUnread(items: NoticeRecord[]): number {
  let count: number = 0;
  for (const item of items) {
    if (isUnread(item)) {
      count++;
    }
  }
  return count;
}

/**
 * 空态判定：没有数据且不在加载/刷新中。
 * busy 期间不显示空态，避免首帧闪一下“暂无公告”。
 */
export function isNoticeListEmpty(items: NoticeRecord[], busy: boolean): boolean {
  return items.length === 0 && !busy;
}
