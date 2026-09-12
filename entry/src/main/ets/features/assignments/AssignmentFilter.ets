/*
 * 作业列表的纯规则（features/assignments，ticket 10）：过滤、过期判定、空态判定。
 *
 * 这些是"界面怎么呈现"的规则，参考实现的对应物在 `data/selectors/filteredData.ts`：
 *
 * | 规则 | 参考实现 | 这里 |
 * | --- | --- | --- |
 * | unfinished | `all.filter(i => !i.submitted)`（:116） | `matchesFilter(..., UNFINISHED)` |
 * | finished | `all.filter(i => i.submitted)`（:117） | `matchesFilter(..., FINISHED)` |
 * | 卡片上的"还剩 X / X 截止" | `dayjs().isAfter(dayjs(deadline))`（AssignmentCard.tsx:103-108） | `isPastDeadline`（`parseTimestamp` 对齐 dayjs：不可解析 = Invalid Date ⇒ 恒 false） |
 * | 卡片右上"答案"图标 | `answerContent \|\| answerAttachment`（AssignmentCard.tsx:76） | `hasAnswer` |
 *
 * **本文件不做排序**：顺序由 `data/remote/AssignmentsFetcher` 用
 * `domain/parse/AssignmentParser.compareAssignmentsByUpcoming` 一次定好（ticket 05 已验收），
 * 界面层再排一次就会出现"两套排序"（见 ticket 10 Comments 的统筹提示 C）。
 *
 * 纯函数、无平台依赖、无 i18n，是单测的主战场（entry/src/test/AssignmentList.test.ets）。
 */

import { Assignment } from '../../domain/model/ContentItem';
import { parseTimestamp } from '../../domain/parse/Text';

/** 列表过滤视图（参考实现 FilterList 给作业的三个选项：all / unfinished / finished）。 */
export enum AssignmentFilter {
  ALL = 'all',
  UNFINISHED = 'unfinished',
  FINISHED = 'finished'
}

/** 该作业是否属于某个过滤视图（"未完成/已完成"= 参考实现的 `!submitted` / `submitted`）。 */
export function matchesFilter(assignment: Assignment, filter: AssignmentFilter): boolean {
  if (filter === AssignmentFilter.UNFINISHED) {
    return !assignment.submitted;
  }
  if (filter === AssignmentFilter.FINISHED) {
    return assignment.submitted;
  }
  return true;
}

/** 过滤后的新数组；**保持入参顺序**（绝不在这里排序）。 */
export function filterAssignments(items: Assignment[], filter: AssignmentFilter): Assignment[] {
  const out: Assignment[] = [];
  for (let i = 0; i < items.length; i++) {
    if (matchesFilter(items[i], filter)) {
      out.push(items[i]);
    }
  }
  return out;
}

/** 某个过滤视图下的条数（过滤条上的计数）。 */
export function countAssignments(items: Assignment[], filter: AssignmentFilter): number {
  let count: number = 0;
  for (let i = 0; i < items.length; i++) {
    if (matchesFilter(items[i], filter)) {
      count++;
    }
  }
  return count;
}

/**
 * 是否**已过截止时间**。
 *
 * 逐条对齐参考实现的 `dayjs().isAfter(dayjs(deadline))`：
 *   - 严格晚于才算已过（`now === deadline` 时 `isAfter` 为 false，这里同样返回 false）；
 *   - 截止时间不可解析（`parseTimestamp` 返回 NaN）= dayjs 的 Invalid Date ⇒ 恒 false。
 *
 * 边界由单测 `pastDeadlineBoundaryMatchesDayjsIsAfter` 钉住。
 */
export function isPastDeadline(deadline: string, nowMillis: number): boolean {
  const at: number = parseTimestamp(deadline);
  if (Number.isNaN(at)) {
    return false;
  }
  return at < nowMillis;
}

/** 未过截止时间（且截止时间可解析）——"未到期"状态标记的判据。 */
export function isUpcomingDeadline(deadline: string, nowMillis: number): boolean {
  const at: number = parseTimestamp(deadline);
  if (Number.isNaN(at)) {
    return false;
  }
  return at >= nowMillis;
}

/** 是否有答案（参考答案附件或答案正文）——参考实现卡片上的 key-variant 图标条件。 */
export function hasAnswer(assignment: Assignment): boolean {
  if (assignment.answerAttachment !== undefined) {
    return true;
  }
  return assignment.answerContent.trim().length > 0;
}

/**
 * 空态判定：可见列表为空且不在取数中。
 * busy 期间不显示空态，避免首帧闪一下"暂无作业"（与 features/notices/NoticeOrder 同一规则）。
 */
export function isAssignmentListEmpty(visible: Assignment[], busy: boolean): boolean {
  return visible.length === 0 && !busy;
}

/** 已过截止时间的条数（表头摘要用）。 */
export function countPastDue(items: Assignment[], nowMillis: number): number {
  let count: number = 0;
  for (let i = 0; i < items.length; i++) {
    if (isPastDeadline(items[i].deadline, nowMillis)) {
      count++;
    }
  }
  return count;
}
