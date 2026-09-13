/*
 * 作业列表/详情的纯规则（features/assignments）：过期判定、状态标记、空态判定。
 *
 * **过滤视图本身已不在本文件**：all / unread / fav / archived / hidden /
 * unfinished / finished 七个视图与收藏 / 归档 / 屏蔽是同一套语义，统一在
 * `features/marks/FilteredContent.ets`（逐行对齐参考实现 data/selectors/filteredData.ts）。
 * 这里只留"单条作业怎么看"的规则。
 *
 * | 规则 | 参考实现 | 这里 |
 * | --- | --- | --- |
 * | 卡片上的"还剩 X / X 截止" | `dayjs().isAfter(dayjs(deadline))`（AssignmentCard.tsx:103-108） | `isPastDeadline`（`parseTimestamp` 对齐 dayjs：不可解析 = Invalid Date ⇒ 恒 false） |
 * | 卡片右上"答案"图标 | `answerContent \|\| answerAttachment`（AssignmentCard.tsx:76） | `hasAnswer` |
 * | 优秀作业标记 | `excellentHomeworkList.length > 0`（AssignmentCard.tsx:84-91） | `hasExcellentHomework` |
 *
 * **本文件不做排序**：顺序由 `data/remote/AssignmentsFetcher` 用
 * `domain/parse/AssignmentParser.compareAssignmentsByUpcoming` 一次定好，
 * 界面层再排一次就会出现"两套排序"（见统筹提示 C）。
 *
 * 纯函数、无平台依赖、无 i18n，是单测的主战场（entry/src/test/AssignmentList.test.ets）。
 */

import { Assignment } from '../../domain/model/ContentItem';
import { parseTimestamp } from '../../domain/parse/Text';

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

/**
 * 是否有**优秀作业**（参考实现 AssignmentCard.tsx:84-91：`excellentHomeworkList.length > 0`
 * 时显示一枚黄色 medal 图标）。`undefined` 与空数组都算没有。
 */
export function hasExcellentHomework(assignment: Assignment): boolean {
  const list = assignment.excellentHomeworkList;
  return list !== undefined && list.length > 0;
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
