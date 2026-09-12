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
 *
 * 【ticket 09 迁移】时间解析（parseNoticeTime）已移到 data/notices/NoticeTime.ets
 * （data 层也要用它把 publishTime 落进快照），本文件**再导出**它，调用点不变。
 * 排序/未读/空态三条规则留在 features，因为它们是"界面怎么呈现"的规则。
 */
import { NoticeRecord } from '../../data/notices/NoticeRepository';
import { parseNoticeTime } from '../../data/notices/NoticeTime';

export { parseNoticeTime };

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
