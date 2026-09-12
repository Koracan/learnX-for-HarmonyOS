/*
 * 作业列表与详情的规则单测（ticket 10 验收项 1 / 2 / 4 的可测部分）。
 *
 * 覆盖（每条都是"数字 / 边界 / 排序 / 状态"里的一类）：
 *   - 过滤视图与参考实现 selectFilteredAssignments 的取舍（unfinished = !submitted）；
 *   - **排序**：列表顺序就是取数顺序（compareAssignmentsByUpcoming：未到期在前由近及远、
 *     已过期在后），过滤**不得**改变它；
 *   - **边界**：now == deadline 不算已过期（对齐 dayjs().isAfter）；
 *   - **状态**：已截止 / 未到期 / 已提交 / 已评分 / 含答案；
 *   - 三种空态各自的资源键；
 *   - 成绩等级表（thu-learn-lib GRADE_LEVEL_MAP 的 25 项）与本地化映射（7 项）；
 *   - 完成方式 / 提交方式同时接受数字代码与站点中文标签；
 *   - 取证夹具的形状与**提交态开关为 false**（把 AGENTS.md 的"提交前核对开关已复原"变成断言）。
 *
 * 界面组件（ArkUI struct）不在 host 单测里实例化，所以这里测的是它们背后的纯规则。
 */

import { describe, it, expect } from '@ohos/hypium';
import { Assignment, Attachment } from '../main/ets/domain/model/ContentItem';
import { RawAssignment, compareAssignmentsByUpcoming, gradeLevelOf, parseAssignment } from
  '../main/ets/domain/parse/AssignmentParser';
import {
  countPastDue, hasAnswer, isAssignmentListEmpty, isPastDeadline, isUpcomingDeadline
} from '../main/ets/features/assignments/AssignmentFilter';
// ticket 14：过滤视图的实现从 features/assignments/AssignmentFilter 收敛到
// features/marks/FilteredContent（收藏 / 归档 / 屏蔽与这三种视图是同一套过滤语义）。
// 本文件里原来的 matchesFilter / filterAssignments / countAssignments 断言**期望值一字未改**，
// 只是调用点换成了新的等价实现（边界说明见 ticket 10 的追加节）。
import { ContentFilter } from '../main/ets/domain/marks/ContentFilter';
import { assignmentsForFilter, selectFilteredAssignments } from '../main/ets/features/marks/FilteredContent';
import {
  dueStatusKey, emptyStateKey, gradeLevelKey, isGroupCompletion, isOfflineSubmission
} from '../main/ets/features/assignments/AssignmentText';
import {
  MOCK_ASSIGNMENTS_FOR_EVIDENCE, deadlineFromMillis, mockAssignments
} from '../main/ets/features/assignments/AssignmentEvidence';

/** 造一条作业（只填断言要用的字段，其余给稳定默认值）。 */
function makeAssignment(id: string, deadline: string, submitted: boolean, graded: boolean): Assignment {
  return {
    id: id, baseId: id + '-base', title: 't-' + id, url: '', deadline: deadline,
    isLateSubmission: false, completionType: '1', submissionType: '2', submitUrl: '',
    courseId: 'c1', courseName: '课程', courseTeacherName: '教师',
    description: '', submittedContent: '', answerContent: '', gradeContent: '',
    submitted: submitted, graded: graded
  };
}

function attachment(name: string, id: string): Attachment {
  return { name: name, id: id, downloadUrl: 'https://x/' + id };
}

/** 一条列表记录的字段顺序（断言"没有重新排序"用）。 */
function idsOf(items: Assignment[]): string {
  let out: string = '';
  for (let i = 0; i < items.length; i++) {
    out += (i === 0 ? '' : ',') + items[i].id;
  }
  return out;
}

/** 某个过滤视图下可见的条目（等价于 ticket 10 的 filterAssignments）。 */
function viewOf(items: Assignment[], filter: ContentFilter): Assignment[] {
  return assignmentsForFilter(selectFilteredAssignments(items, [], [], []), filter);
}

export default function assignmentListTest() {
  describe('features.assignments.list', () => {
    it('filtersFollowTheReferenceSelectors', 0, () => {
      const a: Assignment = makeAssignment('a', '2020-09-01 00:00', false, false);
      const b: Assignment = makeAssignment('b', '2020-09-02 00:00', true, false);
      const c: Assignment = makeAssignment('c', '2020-09-03 00:00', true, true);
      const all: Assignment[] = [a, b, c];
      expect(idsOf(viewOf([a], ContentFilter.ALL))).assertEqual('a');
      expect(idsOf(viewOf([a], ContentFilter.UNFINISHED))).assertEqual('a');
      expect(idsOf(viewOf([a], ContentFilter.FINISHED))).assertEqual('');
      expect(idsOf(viewOf([b], ContentFilter.UNFINISHED))).assertEqual('');
      expect(idsOf(viewOf([b], ContentFilter.FINISHED))).assertEqual('b');
      expect(idsOf(viewOf(all, ContentFilter.ALL))).assertEqual('a,b,c');
      expect(idsOf(viewOf(all, ContentFilter.UNFINISHED))).assertEqual('a');
      expect(idsOf(viewOf(all, ContentFilter.FINISHED))).assertEqual('b,c');
      // 入参不被修改（选择器返回新数组）
      expect(all.length).assertEqual(3);
    });

    it('keepsTheFetcherOrderAndNeverResorts', 0, () => {
      // now = 2020-09-15 12:00 本地
      const now: number = new Date(2020, 8, 15, 12, 0, 0).getTime();
      const items: Assignment[] = [
        makeAssignment('p1', '2020-09-01 00:00', true, false),
        makeAssignment('u1', '2020-09-20 00:00', false, false),
        makeAssignment('u2', '2020-09-16 00:00', false, false),
        makeAssignment('p2', '2020-09-10 00:00', true, true)
      ];
      // 取数侧（AssignmentsFetcher.fetch 的最后一步）就是这个函数：
      const ordered: Assignment[] = compareAssignmentsByUpcoming(items, now);
      expect(idsOf(ordered)).assertEqual('u2,u1,p1,p2');
      // 列表层只过滤：未到期在前、已过期在后，过滤不改变次序
      expect(idsOf(viewOf(ordered, ContentFilter.ALL))).assertEqual('u2,u1,p1,p2');
      expect(idsOf(viewOf(ordered, ContentFilter.UNFINISHED))).assertEqual('u2,u1');
      expect(idsOf(viewOf(ordered, ContentFilter.FINISHED))).assertEqual('p1,p2');
      // 该次序也满足"按截止时间：未到期（由近及远）→ 已过期（由远及近）"
      expect(isPastDeadline(ordered[0].deadline, now)).assertFalse();
      expect(isPastDeadline(ordered[1].deadline, now)).assertFalse();
      expect(isPastDeadline(ordered[2].deadline, now)).assertTrue();
      expect(isPastDeadline(ordered[3].deadline, now)).assertTrue();
    });

    it('pastDeadlineBoundaryMatchesDayjsIsAfter', 0, () => {
      const now: number = new Date(2020, 8, 15, 12, 0, 0).getTime();
      const same: string = '2020-09-15 12:00';
      expect(isPastDeadline(same, now)).assertFalse();
      expect(isUpcomingDeadline(same, now)).assertTrue();
      expect(isPastDeadline(deadlineFromMillis(now - 1), now)).assertTrue();
      expect(isUpcomingDeadline(deadlineFromMillis(now - 1), now)).assertFalse();
      expect(isPastDeadline(deadlineFromMillis(now + 1), now)).assertFalse();
      // 不可解析 = dayjs 的 Invalid Date：两个判定都 false（不会把"没有截止时间"说成未到期）
      expect(isPastDeadline('', now)).assertFalse();
      expect(isUpcomingDeadline('', now)).assertFalse();
      expect(isPastDeadline('not a date', now)).assertFalse();
    });

    it('countsPerViewAndPastDue', 0, () => {
      const now: number = new Date(2020, 8, 15, 12, 0, 0).getTime();
      const items: Assignment[] = [
        makeAssignment('u1', '2020-09-16 00:00', false, false),
        makeAssignment('p1', '2020-09-10 00:00', true, false),
        makeAssignment('p2', '2020-09-01 00:00', true, true)
      ];
      expect(viewOf(items, ContentFilter.ALL).length).assertEqual(3);
      expect(viewOf(items, ContentFilter.UNFINISHED).length).assertEqual(1);
      expect(viewOf(items, ContentFilter.FINISHED).length).assertEqual(2);
      expect(countPastDue(items, now)).assertEqual(2);
    });

    it('emptyStateDependsOnTheViewAndOnBusy', 0, () => {
      const one: Assignment[] = [makeAssignment('a', '2020-09-01 00:00', false, false)];
      expect(isAssignmentListEmpty([], false)).assertTrue();
      expect(isAssignmentListEmpty([], true)).assertFalse();
      expect(isAssignmentListEmpty(one, false)).assertFalse();
      expect(emptyStateKey(ContentFilter.ALL)).assertEqual('ui_assignments_empty');
      expect(emptyStateKey(ContentFilter.UNFINISHED)).assertEqual('ui_assignments_none_unfinished');
      expect(emptyStateKey(ContentFilter.FINISHED)).assertEqual('ui_assignments_none_finished');
      // ticket 14 的三个新视图用参考实现 Empty 的那句（无内容），而不是"暂无作业"。
      expect(emptyStateKey(ContentFilter.FAV)).assertEqual('loh_empty');
      expect(emptyStateKey(ContentFilter.ARCHIVED)).assertEqual('loh_empty');
      expect(emptyStateKey(ContentFilter.HIDDEN)).assertEqual('loh_empty');
    });

    it('allSubmittedAndPastShowsTheUnfinishedEmptyState', 0, () => {
      // 2025-2026 春季的真实形态：57 条全部已截止、全部已提交（未完成计数 0）
      // now 取 6 月 1 日（不是 5-31 23:59 —— 那正好落在边界上，而边界另有专门用例钉住）。
      const now: number = new Date(2026, 5, 1, 0, 0, 0).getTime();
      const items: Assignment[] = [
        makeAssignment('s1', '2026-05-01 23:59', true, false),
        makeAssignment('s2', '2026-05-31 23:59', true, true)
      ];
      const visible: Assignment[] = viewOf(items, ContentFilter.UNFINISHED);
      expect(visible.length).assertEqual(0);
      expect(isAssignmentListEmpty(visible, false)).assertTrue();
      expect(emptyStateKey(ContentFilter.UNFINISHED)).assertEqual('ui_assignments_none_unfinished');
      expect(countPastDue(items, now)).assertEqual(2);
    });

    it('hasAnswerUsesAttachmentOrContent', 0, () => {
      const none: Assignment = makeAssignment('a', '2020-09-01 00:00', false, false);
      expect(hasAnswer(none)).assertFalse();
      const withAttachment: Assignment = makeAssignment('b', '2020-09-01 00:00', false, false);
      withAttachment.answerAttachment = attachment('答案.pdf', 'w1');
      expect(hasAnswer(withAttachment)).assertTrue();
      const withContent: Assignment = makeAssignment('c', '2020-09-01 00:00', false, false);
      withContent.answerContent = '<p>见附件</p>';
      expect(hasAnswer(withContent)).assertTrue();
      const blank: Assignment = makeAssignment('d', '2020-09-01 00:00', false, false);
      blank.answerContent = '   ';
      expect(hasAnswer(blank)).assertFalse();
    });

    it('dueStatusKeyMatchesIsPastDeadline', 0, () => {
      const now: number = new Date(2020, 8, 15, 12, 0, 0).getTime();
      expect(dueStatusKey(deadlineFromMillis(now + 3600 * 1000), now)).assertEqual('ui_assignment_upcoming');
      expect(dueStatusKey(deadlineFromMillis(now - 3600 * 1000), now)).assertEqual('ui_assignment_past_due');
      expect(dueStatusKey('', now)).assertEqual('ui_assignment_upcoming');
    });

    it('gradeLevelTableMatchesThuLearnLib', 0, () => {
      expect(gradeLevelOf(-100)).assertEqual('checked');
      expect(gradeLevelOf(-99)).assertEqual('A+');
      expect(gradeLevelOf(-98)).assertEqual('A');
      expect(gradeLevelOf(-92)).assertEqual('A-');
      expect(gradeLevelOf(-87)).assertEqual('B+');
      expect(gradeLevelOf(-85)).assertEqual('distinction');
      expect(gradeLevelOf(-82)).assertEqual('B');
      expect(gradeLevelOf(-78)).assertEqual('B-');
      expect(gradeLevelOf(-74)).assertEqual('C+');
      expect(gradeLevelOf(-71)).assertEqual('C');
      expect(gradeLevelOf(-68)).assertEqual('C-');
      expect(gradeLevelOf(-67)).assertEqual('G');
      expect(gradeLevelOf(-66)).assertEqual('D+');
      expect(gradeLevelOf(-64)).assertEqual('D');
      expect(gradeLevelOf(-65)).assertEqual('exempted course');
      expect(gradeLevelOf(-63)).assertEqual('pass');
      expect(gradeLevelOf(-62)).assertEqual('EX');
      expect(gradeLevelOf(-61)).assertEqual('exemption');
      expect(gradeLevelOf(-60)).assertEqual('pass');
      expect(gradeLevelOf(-59)).assertEqual('failure');
      expect(gradeLevelOf(-55)).assertEqual('W');
      expect(gradeLevelOf(-51)).assertEqual('I');
      expect(gradeLevelOf(-50)).assertEqual('incomplete');
      expect(gradeLevelOf(-31)).assertEqual('NA');
      expect(gradeLevelOf(-30)).assertEqual('F');
      // 分数与表外代码：没有等级（界面回退显示数字成绩）
      expect(gradeLevelOf(88) === undefined).assertTrue();
      expect(gradeLevelOf(0) === undefined).assertTrue();
      expect(gradeLevelOf('88') === undefined).assertTrue();
      expect(gradeLevelOf(undefined) === undefined).assertTrue();
      expect(gradeLevelOf(null) === undefined).assertTrue();
      expect(gradeLevelOf('') === undefined).assertTrue();
      expect(gradeLevelOf('abc') === undefined).assertTrue();
      // 站点有时把数字下发成字符串
      expect(gradeLevelOf('-100')).assertEqual('checked');
    });

    it('gradeLevelKeyCoversTheSevenMappedLevels', 0, () => {
      expect(gradeLevelKey('checked')).assertEqual('loh_reviewed');
      expect(gradeLevelKey('distinction')).assertEqual('loh_good');
      expect(gradeLevelKey('exempted course')).assertEqual('loh_exempted_course');
      expect(gradeLevelKey('exemption')).assertEqual('loh_exempted');
      expect(gradeLevelKey('pass')).assertEqual('loh_pass');
      expect(gradeLevelKey('failure')).assertEqual('loh_fail');
      expect(gradeLevelKey('incomplete')).assertEqual('loh_incomplete');
      // 表外的等级参考实现原样显示等级串
      expect(gradeLevelKey('A+') === undefined).assertTrue();
      expect(gradeLevelKey('') === undefined).assertTrue();
    });

    it('completionAndSubmissionAcceptCodesAndSiteLabels', 0, () => {
      expect(isGroupCompletion('2')).assertTrue();
      expect(isGroupCompletion('小组')).assertTrue();
      expect(isGroupCompletion('1')).assertFalse();
      expect(isGroupCompletion('个人')).assertFalse();
      expect(isGroupCompletion('')).assertFalse();
      expect(isOfflineSubmission('0')).assertTrue();
      expect(isOfflineSubmission('线下')).assertTrue();
      expect(isOfflineSubmission('2')).assertFalse();
      expect(isOfflineSubmission('网络学堂')).assertFalse();
    });

    it('parsesGradeLevelAndGradeTimeFromRawRecord', 0, () => {
      const leveled: RawAssignment = {
        zyid: 'z1', xszyid: 'x1', bt: 't', jzsj: '2020-09-01 23:59', cj: -100
      };
      const parsed: Assignment = parseAssignment(leveled, 'c1', {}, true, true);
      expect(parsed.gradeLevel).assertEqual('checked');
      expect(parsed.grade).assertEqual(-100);
      expect(parsed.gradeTime === undefined).assertTrue();
      // pysj 在真实数据上可能是 epoch 毫秒数字（与 jzsj 同一现象），走同一条规范化
      const numeric: RawAssignment =
        JSON.parse('{"zyid":"z2","cj":-85,"pysj":1780243140000}') as RawAssignment;
      const parsedNumeric: Assignment = parseAssignment(numeric, 'c1', {}, true, true);
      expect(parsedNumeric.gradeLevel).assertEqual('distinction');
      const expected: string = deadlineFromMillis(1780243140000);
      expect(parsedNumeric.gradeTime).assertEqual(expected);
      // 字符串原样保留；没有等级时回退数字成绩
      const scored: RawAssignment = {
        zyid: 'z3', cj: 88, pysj: '2020-09-02 10:00'
      };
      const parsedScored: Assignment = parseAssignment(scored, 'c1', {}, true, true);
      expect(parsedScored.gradeLevel === undefined).assertTrue();
      expect(parsedScored.grade).assertEqual(88);
      expect(parsedScored.gradeTime).assertEqual('2020-09-02 10:00');
    });

    it('normalizesNumericSubmitAndLateDeadlines', 0, () => {
      // 站点把三个时间字段都下发成 epoch 毫秒数字（2026-09-12 实测 scsj=1780143131000 /
      // pysj=1780243140000 / jzsj 57 条全部是数字）；界面显示的是 Assignment 的字符串字段，
      // 所以解析层必须规范化，否则详情页会出现"提交于 1780143131000"这种字面量。
      const numeric: RawAssignment =
        JSON.parse('{"zyid":"z4","scsj":1780143131000,"bjjzsj":1780243140000}') as RawAssignment;
      const parsed: Assignment = parseAssignment(numeric, 'c1', {}, true, false);
      expect(parsed.submitTime).assertEqual(deadlineFromMillis(1780143131000));
      expect(parsed.lateSubmissionDeadline).assertEqual(deadlineFromMillis(1780243140000));
      // 字符串原样保留（ticket 05 的既有行为）
      const strings: RawAssignment = {
        zyid: 'z5', scsj: '2020-08-30 10:00', bjjzsj: '2020-09-08 23:59'
      };
      const parsedStrings: Assignment = parseAssignment(strings, 'c1', {}, true, false);
      expect(parsedStrings.submitTime).assertEqual('2020-08-30 10:00');
      expect(parsedStrings.lateSubmissionDeadline).assertEqual('2020-09-08 23:59');
      // null / 缺失 ⇒ 字段不存在（参考实现的 h.scsj === null ? undefined : h.scsj）
      const none: RawAssignment =
        JSON.parse('{"zyid":"z6","scsj":null,"bjjzsj":null}') as RawAssignment;
      const parsedNone: Assignment = parseAssignment(none, 'c1', {}, false, false);
      expect(parsedNone.submitTime === undefined).assertTrue();
      expect(parsedNone.lateSubmissionDeadline === undefined).assertTrue();
    });

    it('evidenceFixtureCoversTheUpcomingFormAndIsOffAtCommit', 0, () => {
      // AGENTS.md："提交前用 git show HEAD:<文件> 核对开关已复原" —— 这里再加一道程序化断言。
      expect(MOCK_ASSIGNMENTS_FOR_EVIDENCE).assertFalse();
      const now: number = new Date(2026, 8, 12, 12, 0, 0).getTime();
      const mock: Assignment[] = mockAssignments(now);
      expect(mock.length).assertEqual(4);
      // 未到期在前（由近及远）→ 已过期在后
      expect(idsOf(mock)).assertEqual('mock-upcoming-1,mock-upcoming-2,mock-past-1,mock-past-2');
      expect(viewOf(mock, ContentFilter.UNFINISHED).length).assertEqual(2);
      expect(viewOf(mock, ContentFilter.FINISHED).length).assertEqual(2);
      expect(countPastDue(mock, now)).assertEqual(2);
      // 四类附件齐备的那一条（详情页四类附件可点的取证载体）
      const graded: Assignment = mock[2];
      expect(graded.graded).assertTrue();
      expect(graded.gradeLevel).assertEqual('distinction');
      expect(graded.attachment !== undefined).assertTrue();
      expect(graded.submittedAttachment !== undefined).assertTrue();
      expect(graded.gradeAttachment !== undefined).assertTrue();
      expect(graded.answerAttachment !== undefined).assertTrue();
      // 未到期那条带行间公式（详情页"描述含公式"的取证载体）
      expect(mock[0].description.includes('$$E = mc^2$$')).assertTrue();
      expect(mock[0].submitted).assertFalse();
    });
  });
}
