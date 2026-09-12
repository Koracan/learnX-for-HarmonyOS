/*
 * 作业响应解析——**纯函数，零平台依赖**（见 scripts/check-domain-purity.mjs）。
 *
 * 移植自参考实现 DataProcessorModule.ts 的 `fetchAssignments` 与 `processAssignments`：
 *   - 列表记录字段映射（xszyid / zyid / wlkcid / bt / jzsj / bjjzsj / sfbj / zywcfs / zytjfs / scsj / cj / jsm / pynr / pysj）；
 *   - `cj` 的两副面孔：分数（`grade`）与**等级代码**（`gradeLevel`，见 `gradeLevelOf`）；
 *   - 详情页四类附件块（附件 / 答案 / 已提交 / 成绩）的顺序与 thu-learn-lib
 *     `parseHomeworkAtUrl` 一致（fileDivs[0..3]）；
 *   - 三类正文：描述（JSON 详情 `msg`）、已提交正文、答案正文；
 *   - 排序：截止时间倒序 + 标识倒序（参考实现 actions/assignments.ts）。
 */

import { Assignment, Attachment } from '../model/ContentItem';
import { decodeHtmlEntities, compareByTimeThenIdDesc, parseTimestamp } from './Text';
import { splitAttachmentBlocks, extractAttachment } from './Attachment';
import { CourseName, UNKNOWN_COURSE_NAME } from './CourseName';

/** 列表接口 `aaData` 里的一条作业原始记录。 */
export interface RawAssignment {
  xszyid?: string;
  zyid: string;
  wlkcid?: string;
  bt?: string;
  jzsj?: string;
  bjjzsj?: string;
  sfbj?: string;
  zywcfs?: string;
  zytjfs?: string;
  scsj?: string;
  /** 批改时间（参考实现 thu-learn-lib 与之同名字段）。 */
  pysj?: string;
  cj?: number | string;
  jsm?: string;
  pynr?: string;
}

/**
 * 成绩代码 → 等级（thu-learn-lib `GRADE_LEVEL_MAP` 的逐条移植）。
 *
 * 参考实现（`node_modules/thu-learn-lib/lib/module/index.js:879`）是
 * `gradeLevel: GRADE_LEVEL_MAP.get(h.cj)`，表在 `utils.js:39`。**值原样照抄**
 * （'checked' / 'distinction' / 'exempted course' …），因为本地化映射在参考实现里是
 * 另一层（`helpers/i18n.ts` 的 `assignmentGradeLevelDescriptionMap`，只覆盖 7 个键）。
 *
 * 表里没有的代码返回 `undefined` —— 界面对这种记录回退显示数字成绩（照参考实现的
 * `gradeLevel ? ... : grade`）。
 */
export function gradeLevelOf(cj: number | string | undefined | null): string | undefined {
  if (cj === undefined || cj === null) {
    return undefined;
  }
  const code: number = typeof cj === 'number' ? cj : Number(cj);
  if (Number.isNaN(code)) {
    return undefined;
  }
  switch (code) {
    case -100: return 'checked';
    case -99: return 'A+';
    case -98: return 'A';
    case -92: return 'A-';
    case -87: return 'B+';
    case -85: return 'distinction';
    case -82: return 'B';
    case -78: return 'B-';
    case -74: return 'C+';
    case -71: return 'C';
    case -68: return 'C-';
    case -67: return 'G';
    case -66: return 'D+';
    case -64: return 'D';
    case -65: return 'exempted course';
    case -63: return 'pass';
    case -62: return 'EX';
    case -61: return 'exemption';
    case -60: return 'pass';
    case -59: return 'failure';
    case -55: return 'W';
    case -51: return 'I';
    case -50: return 'incomplete';
    case -31: return 'NA';
    case -30: return 'F';
    default: return undefined;
  }
}

/** 作业详情页解析结果：三类正文 + 四类附件。 */
export interface AssignmentDetail {
  description?: string;
  answerContent?: string;
  submittedContent?: string;
  attachment?: Attachment;
  answerAttachment?: Attachment;
  submittedAttachment?: Attachment;
  gradeAttachment?: Attachment;
}

function text(value: string | undefined): string {
  return value === undefined || value === null ? '' : value;
}

/** 补零到两位（截止时间的格式化）。 */
function pad2(value: number): string {
  return value < 10 ? '0' + value.toString() : value.toString();
}

/**
 * 截止时间的**规范化**。
 *
 * 站点有时把 `jzsj` 下发成 **epoch 毫秒的数字**：2026-09-12 在 2025-2026 春季学期的真实数据上，
 * **全部 57 条**作业都是数字（例 `1780243140000` = 2026-05-31 23:59 本地时间），
 * 于是 `Assignment.deadline`（本工程声明为字符串）在运行时是数字，卡片/详情里那一行渲染成空。
 * 参考实现在**渲染层**用 `dayjs(deadline)` 处理这种值（AssignmentCard.tsx:103-108），
 * 本工程把同一步提前到解析层：数字按本地时间格式化成 `YYYY-MM-DD HH:mm`
 * —— 也就是 `Assignment.deadline` 既定的形状，排序（parseTimestamp）与显示拿到同一个瞬时。
 *
 * **字符串一律原样保留**（ticket 05 的夹具与既有行为不受影响），只规范"非字符串"这一支。
 */
export function normalizeDeadline(value: string): string {
  if (typeof value === 'string') {
    return value;
  }
  const millis: number = Number(value);
  if (Number.isNaN(millis)) {
    return '';
  }
  const date: Date = new Date(millis);
  return date.getFullYear().toString() + '-' + pad2(date.getMonth() + 1) + '-'
    + pad2(date.getDate()) + ' ' + pad2(date.getHours()) + ':' + pad2(date.getMinutes());
}

/** 作业的稳定标识：优先学生作业标识，退回作业标识（照参考实现）。 */
export function assignmentKey(raw: RawAssignment): string {
  return raw.xszyid !== undefined && raw.xszyid !== null && raw.xszyid.length > 0 ? raw.xszyid : raw.zyid;
}

/** 作业详情页地址：有 xszyid 时走 viewCj，否则走 viewZy（照参考实现）。 */
export function assignmentDetailUrl(courseId: string, raw: RawAssignment): string {
  if (raw.xszyid !== undefined && raw.xszyid !== null && raw.xszyid.length > 0) {
    return 'https://learn.tsinghua.edu.cn/f/wlxt/kczy/zy/student/viewCj?wlkcid=' + courseId + '&xszyid=' + raw.xszyid;
  }
  return 'https://learn.tsinghua.edu.cn/f/wlxt/kczy/zy/student/viewZy?wlkcid=' + courseId + '&zyid=' + raw.zyid;
}

/** 作业提交页地址。 */
export function assignmentSubmitUrl(wlkcid: string, xszyid: string): string {
  return 'https://learn.tsinghua.edu.cn/f/wlxt/kczy/zy/student/tijiao?wlkcid=' + wlkcid + '&xszyid=' + xszyid;
}

/**
 * 解析作业详情页 HTML。
 *
 * 四类附件按块序映射，与 thu-learn-lib 的 `parseHomeworkAtUrl` 完全一致：
 * `[attachment, answerAttachment, submittedAttachment, gradeAttachment]`。
 * 块里没有附件时对应字段为 undefined（不是空对象）。
 */
export function parseAssignmentDetail(html: string): AssignmentDetail {
  const detail: AssignmentDetail = {};
  if (!html) {
    return detail;
  }
  const blocks: string[] = splitAttachmentBlocks(html);
  if (blocks.length > 0) {
    detail.attachment = extractAttachment(blocks[0]);
  }
  if (blocks.length > 1) {
    detail.answerAttachment = extractAttachment(blocks[1]);
  }
  if (blocks.length > 2) {
    detail.submittedAttachment = extractAttachment(blocks[2]);
  }
  if (blocks.length > 3) {
    detail.gradeAttachment = extractAttachment(blocks[3]);
  }
  return detail;
}

/**
 * 用详情结果补全一条作业。空值不覆盖已有值——参考实现的合并逻辑是
 * "已有附件 / 描述不被空结果冲掉"（`if (!assignment.attachment && existing.attachment)`）。
 */
export function mergeAssignmentDetail(base: Assignment, detail: AssignmentDetail): Assignment {
  const merged: Assignment = base;
  if (base.description.length === 0 && detail.description !== undefined && detail.description.length > 0) {
    merged.description = detail.description;
  }
  if (base.answerContent.length === 0 && detail.answerContent !== undefined) {
    merged.answerContent = detail.answerContent;
  }
  if (base.submittedContent.length === 0 && detail.submittedContent !== undefined) {
    merged.submittedContent = detail.submittedContent;
  }
  if (base.attachment === undefined && detail.attachment !== undefined) {
    merged.attachment = detail.attachment;
  }
  if (base.answerAttachment === undefined && detail.answerAttachment !== undefined) {
    merged.answerAttachment = detail.answerAttachment;
  }
  if (base.submittedAttachment === undefined && detail.submittedAttachment !== undefined) {
    merged.submittedAttachment = detail.submittedAttachment;
  }
  if (base.gradeAttachment === undefined && detail.gradeAttachment !== undefined) {
    merged.gradeAttachment = detail.gradeAttachment;
  }
  return merged;
}

/**
 * 列表记录 → 作业。
 * @param sourceSubmitted `zyListYjwg` / `zyListYpg` 两个列表接口的语义（照参考实现三份 sources 表）。
 * @param sourceGraded 仅 `zyListYpg`（已评分）为 true。
 */
export function parseAssignment(
  raw: RawAssignment,
  courseId: string,
  courseNames: Record<string, CourseName>,
  sourceSubmitted: boolean,
  sourceGraded: boolean
): Assignment {
  const known: CourseName | undefined = courseNames[courseId];
  const wlkcid: string = raw.wlkcid !== undefined && raw.wlkcid !== null && raw.wlkcid.length > 0
    ? raw.wlkcid : courseId;
  const xszyid: string | undefined = raw.xszyid !== undefined && raw.xszyid !== null && raw.xszyid.length > 0
    ? raw.xszyid : undefined;
  const assignment: Assignment = {
    id: assignmentKey(raw),
    baseId: text(raw.zyid),
    title: decodeHtmlEntities(text(raw.bt)),
    url: assignmentDetailUrl(courseId, raw),
    deadline: normalizeDeadline(text(raw.jzsj)),
    isLateSubmission: raw.sfbj === '1',
    completionType: text(raw.zywcfs),
    submissionType: text(raw.zytjfs),
    submitUrl: assignmentSubmitUrl(wlkcid, text(raw.xszyid)),
    courseId: courseId,
    courseName: known !== undefined ? known.name : UNKNOWN_COURSE_NAME,
    courseTeacherName: known !== undefined ? known.teacherName : '',
    description: '',
    attachment: undefined,
    submittedAttachment: undefined,
    gradeAttachment: undefined,
    answerAttachment: undefined,
    gradeContent: text(raw.pynr),
    submittedContent: '',
    answerContent: '',
    submitted: sourceSubmitted,
    graded: sourceGraded
  };
  if (xszyid !== undefined) {
    assignment.studentHomeworkId = xszyid;
  }
  // 三个时间字段与 jzsj 同一现象：站点把它们下发成 epoch 毫秒**数字**（2026-09-12 实测
  // `scsj=1780143131000`、`pysj=1780243140000`、jzsj 57/57 条）。参考实现在渲染层用
  // dayjs(...) 吃掉数字，本工程统一在解析层规范化成 `YYYY-MM-DD HH:mm`（与 deadline 同一函数）。
  if (raw.bjjzsj !== undefined && raw.bjjzsj !== null) {
    assignment.lateSubmissionDeadline = normalizeDeadline(text(raw.bjjzsj));
  }
  if (raw.scsj !== undefined && raw.scsj !== null) {
    assignment.submitTime = normalizeDeadline(text(raw.scsj));
  }
  if (raw.cj !== undefined && raw.cj !== null) {
    const grade: number = Number(raw.cj);
    if (!Number.isNaN(grade)) {
      assignment.grade = grade;
    }
  }
  if (raw.jsm !== undefined && raw.jsm !== null) {
    assignment.graderName = raw.jsm;
  }
  // 等级与批改时间（参考实现 index.js:879,882 的 `gradeLevel` / `gradeTime`）。
  const level: string | undefined = gradeLevelOf(raw.cj);
  if (level !== undefined) {
    assignment.gradeLevel = level;
  }
  if (raw.pysj !== undefined && raw.pysj !== null) {
    assignment.gradeTime = normalizeDeadline(text(raw.pysj));
  }
  return assignment;
}

/** 作业排序：截止时间倒序，同时间按标识倒序。 */
export function sortAssignments(assignments: Assignment[]): Assignment[] {
  const sorted: Assignment[] = assignments.slice();
  sorted.sort((left: Assignment, right: Assignment): number =>
    compareByTimeThenIdDesc(left.deadline, left.id, right.deadline, right.id));
  return sorted;
}

/**
 * 参考实现 actions/assignments.ts 的最终次序：**未截止的在前（由近及远），已截止的在后（由远及近？）**
 * ——原文是 `[未来的.reverse(), ...已截止的]`，即未来段取升序、过去段取降序。
 * `nowMs` 显式传入以便单测固定"现在"。
 */
export function compareAssignmentsByUpcoming(assignments: Assignment[], nowMs: number): Assignment[] {
  const upcoming: Assignment[] = [];
  const past: Assignment[] = [];
  for (let i = 0; i < assignments.length; i++) {
    const deadline: number = parseTimestamp(assignments[i].deadline);
    if (!Number.isNaN(deadline) && deadline > nowMs) {
      upcoming.push(assignments[i]);
    } else {
      past.push(assignments[i]);
    }
  }
  upcoming.reverse();
  const ordered: Assignment[] = [];
  for (let i = 0; i < upcoming.length; i++) {
    ordered.push(upcoming[i]);
  }
  for (let i = 0; i < past.length; i++) {
    ordered.push(past[i]);
  }
  return ordered;
}

/** 列表响应 → 已排序作业（截止时间倒序 + 标识倒序）。 */
export function parseAssignmentList(
  rawRecords: RawAssignment[],
  courseId: string,
  courseNames: Record<string, CourseName>,
  sourceSubmitted: boolean,
  sourceGraded: boolean
): Assignment[] {
  const parsed: Assignment[] = [];
  for (let i = 0; i < rawRecords.length; i++) {
    parsed.push(parseAssignment(rawRecords[i], courseId, courseNames, sourceSubmitted, sourceGraded));
  }
  return sortAssignments(parsed);
}