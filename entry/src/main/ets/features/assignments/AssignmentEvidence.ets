/*
 * ticket 10 的**取证夹具**（提交态关闭）——与 ticket 04 的 NoticeDetailEvidence.ets 同一处置方式。
 *
 * ## 为什么需要它
 *
 * 验收第 1 条要覆盖"未到期在前、已过期在后"的排序与三种状态标记（未到期 / 已提交 / 已过期）。
 * 但账号事实（统筹给的事实 + ticket 12 实测）是：
 *   - 2026-2027 秋季：**没有作业**（列表为空，只能验空态）；
 *   - 2025-2026 春季：**57 条全部已截止、全部已提交**（只能验"已提交 / 已过期"两种形态，
 *     未完成计数为 0）。
 * ⇒ **"未到期"这一形态在真实数据上取不到**，只能靠夹具（ticket 10 的统筹提示 E 第 3 条）。
 *
 * 所以这里提供 4 条夹具作业，由 `MOCK_ASSIGNMENTS_FOR_EVIDENCE` 开关决定是否整体替换真实列表：
 *   - 提交态 false：列表渲染真实数据，行为与参考实现一致；
 *   - 取证态 true：列表渲染这 4 条 —— 两条未到期（一条带行间公式描述、一条带附件）、
 *     两条已过期（一条已提交且已评分且四类附件齐备、一条已提交含答案附件）。
 *
 * ## 取证要求（AGENTS.md）
 *
 * "取证开关必须自证生效"：`logAssignmentEvidenceState()` 把**实际生效值**与夹具形状
 * （条数 / 未到期数 / 已过期数 / 是否含公式）打进 hilog，于是"没截到未到期形态"
 * 与"开关没生效"能区分开。开关值在提交前用 `git show HEAD:<file>` 核对。
 *
 * 夹具**不参与任何断言**（单测用的是 entry/src/test 下自己的夹具），
 * 它只是"把真实数据取不到的形态变成可截图"的工具。
 */
import { Logger } from '../../core/log/Logger';
import { Assignment, Attachment } from '../../domain/model/ContentItem';

const logger: Logger = new Logger('features.assignments.evidence');

/** 取证开关：用夹具作业替换真实列表。**提交态必须为 false**。 */
export const MOCK_ASSIGNMENTS_FOR_EVIDENCE: boolean = false;

/** 一天的毫秒数。 */
const DAY_MILLIS: number = 24 * 3600 * 1000;

function pad2(value: number): string {
  return value < 10 ? '0' + value.toString() : value.toString();
}

/** epoch 毫秒 → 站点口径的 `YYYY-MM-DD HH:mm`（本地时间），与 `Assignment.deadline` 同一形状。 */
export function deadlineFromMillis(millis: number): string {
  const date: Date = new Date(millis);
  return date.getFullYear().toString() + '-' + pad2(date.getMonth() + 1) + '-'
    + pad2(date.getDate()) + ' ' + pad2(date.getHours()) + ':' + pad2(date.getMinutes());
}

/** 夹具里的行间公式（KaTeX：`$$…$$` 才渲染，单 `$` 不渲染，见 docs/reference-quirks.md 第 9 条）。 */
export const EVIDENCE_FORMULA_HTML: string =
  '<p>夹具描述：行间公式渲染取证。</p><p>$$E = mc^2$$</p>';

function attachment(name: string, id: string): Attachment {
  return {
    name: name,
    id: id,
    downloadUrl: 'https://learn.tsinghua.edu.cn/b/wlxt/kczy/zy/student/downloadFile?fileId='
      + id + '&wjid=' + id
  };
}

/** 夹具作业：**已按 `compareAssignmentsByUpcoming` 的次序**排好（未到期由近及远 → 已过期由远及近）。 */
export function mockAssignments(nowMillis: number): Assignment[] {
  const upcoming1: Assignment = {
    id: 'mock-upcoming-1', baseId: 'mock-base-1', studentHomeworkId: 'mock-upcoming-1',
    title: '夹具·未到期（含公式）', url: '', deadline: deadlineFromMillis(nowMillis + 2 * DAY_MILLIS),
    isLateSubmission: false, completionType: '1', submissionType: '2', submitUrl: '',
    courseId: 'mock-course-1', courseName: '夹具课程（未到期）', courseTeacherName: '夹具教师',
    description: EVIDENCE_FORMULA_HTML, submitted: false, graded: false,
    gradeContent: '', submittedContent: '', answerContent: ''
  };
  const upcoming2: Assignment = {
    id: 'mock-upcoming-2', baseId: 'mock-base-2', studentHomeworkId: 'mock-upcoming-2',
    title: '夹具·未到期（带附件）', url: '', deadline: deadlineFromMillis(nowMillis + 5 * DAY_MILLIS),
    isLateSubmission: false, completionType: '2', submissionType: '0', submitUrl: '',
    courseId: 'mock-course-1', courseName: '夹具课程（未到期）', courseTeacherName: '夹具教师',
    description: '<p>夹具描述：这条有作业附件。</p>', submitted: false, graded: false,
    gradeContent: '', submittedContent: '', answerContent: '',
    attachment: attachment('夹具作业要求.pdf', 'mock-att-upcoming')
  };
  const past1: Assignment = {
    id: 'mock-past-1', baseId: 'mock-base-3', studentHomeworkId: 'mock-past-1',
    title: '夹具·已过期（已提交已评分，四类附件）', url: '',
    deadline: deadlineFromMillis(nowMillis - 1 * DAY_MILLIS),
    lateSubmissionDeadline: deadlineFromMillis(nowMillis + 1 * DAY_MILLIS),
    isLateSubmission: true, completionType: '1', submissionType: '2', submitUrl: '',
    submitTime: deadlineFromMillis(nowMillis - 2 * DAY_MILLIS),
    grade: -85, gradeLevel: 'distinction', graderName: '夹具教师',
    gradeTime: deadlineFromMillis(nowMillis - 12 * 3600 * 1000),
    courseId: 'mock-course-2', courseName: '夹具课程（已过期）', courseTeacherName: '夹具教师',
    description: '<p>夹具描述：这条已评分为优秀。</p>',
    submittedContent: '<p>夹具提交正文</p>', answerContent: '<p>夹具答案正文</p>',
    gradeContent: '夹具评语：完成质量高。', submitted: true, graded: true,
    attachment: attachment('夹具作业要求.pdf', 'mock-att-main'),
    submittedAttachment: attachment('夹具我的提交.pdf', 'mock-att-submitted'),
    gradeAttachment: attachment('夹具批改结果.pdf', 'mock-att-grade'),
    answerAttachment: attachment('夹具参考答案.pdf', 'mock-att-answer')
  };
  const past2: Assignment = {
    id: 'mock-past-2', baseId: 'mock-base-4', studentHomeworkId: 'mock-past-2',
    title: '夹具·已过期（已提交未评分）', url: '',
    deadline: deadlineFromMillis(nowMillis - 30 * DAY_MILLIS),
    isLateSubmission: false, completionType: '1', submissionType: '2', submitUrl: '',
    submitTime: deadlineFromMillis(nowMillis - 31 * DAY_MILLIS),
    courseId: 'mock-course-2', courseName: '夹具课程（已过期）', courseTeacherName: '夹具教师',
    description: '<p>夹具描述：这条已提交未评分。</p>',
    submittedContent: '', answerContent: '<p>夹具答案正文</p>',
    gradeContent: '', submitted: true, graded: false,
    answerAttachment: attachment('夹具参考答案.pdf', 'mock-att-answer-2')
  };
  return [upcoming1, upcoming2, past1, past2];
}

/** 取证态下的列表（关闭时原样返回真实数据）。 */
export function evidenceAssignmentsOr(real: Assignment[], nowMillis: number): Assignment[] {
  return MOCK_ASSIGNMENTS_FOR_EVIDENCE ? mockAssignments(nowMillis) : real;
}

/** 把开关的**实际生效值**与夹具形状打进 hilog（ticket 10 取证要求）。 */
export function logAssignmentEvidenceState(): void {
  const now: number = Date.now();
  const mock: Assignment[] = mockAssignments(now);
  let upcoming: number = 0;
  for (let i = 0; i < mock.length; i++) {
    if (mock[i].submitted === false) {
      upcoming++;
    }
  }
  logger.info('assignments evidence: mock=' + MOCK_ASSIGNMENTS_FOR_EVIDENCE.toString()
    + ' count=' + mock.length.toString()
    + ' unfinished=' + upcoming.toString()
    + ' past=' + (mock.length - upcoming).toString()
    + ' hasDisplayMath=' + EVIDENCE_FORMULA_HTML.includes('$$').toString());
}
