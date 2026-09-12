/*
 * 作业文案与语义映射（features/assignments，ticket 10）——纯映射 + i18n 取串。
 *
 * ## 为什么单独一层
 *
 * 参考实现把三件事放在 `helpers/i18n.ts` 与 `AssignmentDetail.tsx` 里：
 *   1. **成绩等级本地化**：`assignmentGradeLevelDescriptionMap`（helpers/i18n.ts:30-40）
 *      只给 7 个等级配了词（checked/distinction/exempted course/exemption/pass/failure/incomplete），
 *      其余等级（A+ / A / …）**原样显示等级串**；详情页优先显示等级、否则显示数字成绩（:263-269）。
 *   2. **完成方式 / 提交方式**：两个 Chip（:153-161）。参考实现比较的是 thu-learn-lib 的
 *      **数字枚举**（`HomeworkCompletionType.GROUP === 2`、`HomeworkSubmissionType.OFFLINE === 0`，
 *      types.js:65-73），而列表接口下发的是站点原文（夹具里是 `'个人'` / `'网络学堂'`）。
 *      两者形状不一致这件事见 docs/reference-quirks.md 第 19 条（ticket 10 新增，含实测）。
 *   3. **截止状态**：卡片上是相对时间那句话（AssignmentCard.tsx:103-108）。
 *
 * 纯映射部分（`gradeLevelKey` / `isGroupCompletion` / `isOfflineSubmission` / `dueStatusKey` /
 * `emptyStateKey`）**不碰 i18n、不碰平台**，可被 host 单测直接断言；
 * 取串部分集中在文件末尾，界面只调它们。
 */

import { Assignment } from '../../domain/model/ContentItem';
import { i18nService } from '../../core/i18n/I18n';
import { I18nKey } from '../../core/i18n/I18nKeys';
import { parseTimestamp } from '../../domain/parse/Text';
import { isPastDeadline } from './AssignmentFilter';
import { ContentFilter } from '../../domain/marks/ContentFilter';

/**
 * 成绩等级 → 资源键。**逐条对齐**参考实现 `helpers/i18n.ts:33-39` 的
 * `assignmentGradeLevelDescriptionMap`（7 个键；'exempted course' 含空格，是 thu-learn-lib 的原值）。
 * 表外的等级返回 undefined ⇒ 调用方按参考实现**原样显示等级串**。
 */
export function gradeLevelKey(level: string): I18nKey | undefined {
  if (level === 'checked') {
    return 'loh_reviewed';
  }
  if (level === 'distinction') {
    return 'loh_good';
  }
  if (level === 'exempted course') {
    return 'loh_exempted_course';
  }
  if (level === 'exemption') {
    return 'loh_exempted';
  }
  if (level === 'pass') {
    return 'loh_pass';
  }
  if (level === 'failure') {
    return 'loh_fail';
  }
  if (level === 'incomplete') {
    return 'loh_incomplete';
  }
  return undefined;
}

/** 等级串本身（未本地化时显示它）。空等级返回空串。 */
export function rawGradeLevel(assignment: Assignment): string {
  return assignment.gradeLevel === undefined ? '' : assignment.gradeLevel;
}

/**
 * 完成方式是否是"小组"。
 * 同时认数字代码 `'2'`（thu-learn-lib 的枚举值）与站点中文标签 `'小组'`。
 */
export function isGroupCompletion(value: string): boolean {
  return value === '2' || value === '小组';
}

/** 提交方式是否是"线下"。同时认数字代码 `'0'` 与站点中文标签 `'线下'`。 */
export function isOfflineSubmission(value: string): boolean {
  return value === '0' || value === '线下';
}

/** 截止状态标记的资源键（验收第 1 条"状态标记"里"未到期 / 已过期"那一枚）。 */
export function dueStatusKey(deadline: string, nowMillis: number): I18nKey {
  return isPastDeadline(deadline, nowMillis) ? 'ui_assignment_past_due' : 'ui_assignment_upcoming';
}

/**
 * 空态文案的资源键。
 *
 * 三种"空"必须给出**不同**的话（验收第 4 条）：
 *   - 全部视图为空 = 这个学期真的没有作业（2026-2027 秋季的真实账号状态）；
 *   - 未完成视图为空 = 都已完成/都已截止（2025-2026 春季 57 条的真实状态）；
 *   - 已完成视图为空 = 一条都没提交。
 * 显示成同一句"暂无作业"会让"没有作业"与"都做完了"看起来一样。
 */
export function emptyStateKey(filter: ContentFilter): I18nKey {
  if (filter === ContentFilter.UNFINISHED) {
    return 'ui_assignments_none_unfinished';
  }
  if (filter === ContentFilter.FINISHED) {
    return 'ui_assignments_none_finished';
  }
  if (filter === ContentFilter.ALL) {
    return 'ui_assignments_empty';
  }
  // 收藏 / 归档 / 屏蔽（与公告 / 文件同一口径：参考实现 Empty 组件的那句"无内容"）。
  return 'loh_empty';
}

// ---------------------------------------------------------------------------
// 以下需要 i18n（host 单测不调用；界面调用）
// ---------------------------------------------------------------------------

/** 成绩文案：等级优先（本地化，表外原样）→ 数字成绩 → 空串。 */
export function gradeText(assignment: Assignment): string {
  const level: string = rawGradeLevel(assignment);
  if (level.length > 0) {
    const key: I18nKey | undefined = gradeLevelKey(level);
    return key === undefined ? level : i18nService.t(key);
  }
  return assignment.grade === undefined ? '' : assignment.grade.toString();
}

/** 完成方式文案。 */
export function completionText(value: string): string {
  return i18nService.t(isGroupCompletion(value)
    ? 'loh_assignment_group_completion' : 'loh_assignment_individual_completion');
}

/** 提交方式文案。 */
export function submissionText(value: string): string {
  return i18nService.t(isOfflineSubmission(value)
    ? 'loh_assignment_offline_submission' : 'loh_assignment_online_submission');
}

/** 截止状态标记文案。 */
export function dueStatusText(deadline: string, nowMillis: number): string {
  return i18nService.t(dueStatusKey(deadline, nowMillis));
}

/**
 * 截止时间的绝对文案：站点下发的就是 `YYYY-MM-DD HH:mm`（`Assignment.deadline` 的既定形状），
 * 直接显示；不可解析时返回空串。
 */
export function deadlineText(deadline: string): string {
  return Number.isNaN(parseTimestamp(deadline)) ? '' : deadline;
}
