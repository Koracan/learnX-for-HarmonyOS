/*
 * 作业响应解析——**纯函数，零平台依赖**（见 scripts/check-domain-purity.mjs）。
 *
 * 移植自参考实现 DataProcessorModule.ts 的 `fetchAssignments` 与 `processAssignments`：
 *   - 列表记录字段映射（xszyid / zyid / wlkcid / bt / jzsj / bjjzsj / sfbj / zywcfs / zytjfs / scsj / cj / jsm / pynr）；
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
  cj?: number | string;
  jsm?: string;
  pynr?: string;
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
    deadline: text(raw.jzsj),
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
  if (raw.bjjzsj !== undefined && raw.bjjzsj !== null && raw.bjjzsj.length > 0) {
    assignment.lateSubmissionDeadline = raw.bjjzsj;
  }
  if (raw.scsj !== undefined && raw.scsj !== null) {
    assignment.submitTime = raw.scsj;
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
