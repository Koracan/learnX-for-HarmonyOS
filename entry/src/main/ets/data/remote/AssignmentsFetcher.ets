/*
 * 作业抓取仓储（data 层）。
 *
 * 参考实现：DataProcessorModule.`fetchAssignments`——
 *   三个列表接口（未交 / 已交未评 / 已评），对每条记录：
 *     1. POST `detail` 取描述（JSON 的 `msg`）；
 *     2. GET `viewCj`（有 xszyid 时）或 `viewZy` 取详情页，解析**四类附件**；
 *   同一 id 在多份列表里出现时按"详情不丢"的原则合并。
 *
 * 移植后：网络走注入的 `FetchPort`，字段映射 / 四类附件 / 排序在 domain/parse/AssignmentParser。
 *
 * 锚点日志（验收项 1）：
 *   data.assignments fetched courses=<n> items=<n> elapsedMs=<n> requests=<n> failures=<n>
 */

import { Logger } from '../../core/log/Logger';
import { Assignment } from '../../domain/model/ContentItem';
import { CourseName } from '../../domain/parse/CourseName';
import { decodeHtmlEntities } from '../../domain/parse/Text';
import {
  AssignmentDetail, RawAssignment, assignmentDetailUrl,
  mergeAssignmentDetail, parseAssignment, parseAssignmentDetail, compareAssignmentsByUpcoming
} from '../../domain/parse/AssignmentParser';
import { FetchOutcome, FetchPort, Session } from './Port';
import { LEARN_ORIGIN } from './Requests';

export const ASSIGNMENTS_LOG_DOMAIN: string = 'data.assignments';

/** 作业列表来源：三个接口的语义（照参考实现 sources 表）。 */
export interface AssignmentListSource {
  path: string;
  submitted: boolean;
  graded: boolean;
}

export const ASSIGNMENT_LIST_SOURCES: AssignmentListSource[] = [
  { path: '/b/wlxt/kczy/zy/student/zyListWj', submitted: false, graded: false },
  { path: '/b/wlxt/kczy/zy/student/zyListYjwg', submitted: true, graded: false },
  { path: '/b/wlxt/kczy/zy/student/zyListYpg', submitted: true, graded: true }
];

/** 列表响应 → 原始记录数组。 */
export function extractAssignmentRows(body: string): RawAssignment[] {
  if (body.length === 0) {
    return [];
  }
  let parsed: Object;
  try {
    parsed = JSON.parse(body) as Object;
  } catch (error) {
    return [];
  }
  const root: Record<string, Object> = parsed as Record<string, Object>;
  if (String(root['result']) !== 'success') {
    return [];
  }
  const object: Object | undefined = root['object'] as Object | undefined;
  if (object === undefined || object === null) {
    return [];
  }
  const box: Record<string, Object> = object as Record<string, Object>;
  return box['aaData'] === undefined || box['aaData'] === null ? [] : box['aaData'] as RawAssignment[];
}

/**
 * 描述接口响应 → 描述 HTML 字符串（`result: success` 时取 `msg`）。
 *
 * 参考实现在这里做 `decodeHTML(descJson.msg || '')`，因此实体解码必须在这一步完成
 * （详情页 HTML 里的字段走另一条路径，各自解码）。
 */
export function extractAssignmentDescription(body: string): string {
  if (body.length === 0) {
    return '';
  }
  let parsed: Object;
  try {
    parsed = JSON.parse(body) as Object;
  } catch (error) {
    return '';
  }
  const root: Record<string, Object> = parsed as Record<string, Object>;
  if (String(root['result']) !== 'success') {
    return '';
  }
  const msg: Object | undefined = root['msg'] as Object | undefined;
  return msg === undefined || msg === null ? '' : decodeHtmlEntities(String(msg));
}

/** 合并同一作业的两份结果：详情字段取非空，提交/评分标记取"或"。 */
export function mergeAssignments(existing: Assignment, incoming: Assignment): Assignment {
  const merged: Assignment = existing;
  if (existing.description.length === 0 && incoming.description.length > 0) {
    merged.description = incoming.description;
  }
  if (existing.attachment === undefined && incoming.attachment !== undefined) {
    merged.attachment = incoming.attachment;
  }
  if (existing.answerAttachment === undefined && incoming.answerAttachment !== undefined) {
    merged.answerAttachment = incoming.answerAttachment;
  }
  if (existing.submittedAttachment === undefined && incoming.submittedAttachment !== undefined) {
    merged.submittedAttachment = incoming.submittedAttachment;
  }
  if (existing.gradeAttachment === undefined && incoming.gradeAttachment !== undefined) {
    merged.gradeAttachment = incoming.gradeAttachment;
  }
  if (existing.submitTime === undefined && incoming.submitTime !== undefined) {
    merged.submitTime = incoming.submitTime;
  }
  if (existing.grade === undefined && incoming.grade !== undefined) {
    merged.grade = incoming.grade;
  }
  if (existing.graderName === undefined && incoming.graderName !== undefined) {
    merged.graderName = incoming.graderName;
  }
  if (existing.gradeContent.length === 0 && incoming.gradeContent.length > 0) {
    merged.gradeContent = incoming.gradeContent;
  }
  merged.submitted = existing.submitted || incoming.submitted;
  merged.graded = existing.graded || incoming.graded;
  return merged;
}

/** 作业仓储。 */
export class AssignmentsFetcher {
  private readonly logger: Logger;
  private readonly port: FetchPort;
  private readonly session: Session;
  private readonly courseNames: Record<string, CourseName>;
  /** 非字符串截止时间的 warn 只打第一条（其余计入汇总行的 nonStringDeadlines）。 */
  private deadlineTypeWarned: boolean = false;

  constructor(logger: Logger, port: FetchPort, session: Session, courseNames: Record<string, CourseName>) {
    this.logger = logger;
    this.port = port;
    this.session = session;
    this.courseNames = courseNames;
  }

  /** 抓取并解析；返回按"未截止在前（由近及远）"排列的作业。 */
  async fetch(courseIds: string[]): Promise<Assignment[]> {
    const startedAt: number = Date.now();
    let requests: number = 0;
    let failures: number = 0;
    let nonStringDeadlines: number = 0;
    const byId: Map<string, Assignment> = new Map<string, Assignment>();
    const order: string[] = [];

    for (let i = 0; i < courseIds.length; i++) {
      const courseId: string = courseIds[i];
      for (let j = 0; j < ASSIGNMENT_LIST_SOURCES.length; j++) {
        const source: AssignmentListSource = ASSIGNMENT_LIST_SOURCES[j];
        requests++;
        const listOutcome: FetchOutcome = await this.port.postForm(this.session, {
          url: LEARN_ORIGIN + source.path + '?_csrf=' + this.session.csrfToken,
          courseId: courseId
        });
        if (!listOutcome.ok) {
          failures++;
          this.reportFailure(courseId, source.path, listOutcome);
        }
        const rows: RawAssignment[] = extractAssignmentRows(listOutcome.body);
        for (let k = 0; k < rows.length; k++) {
          const raw: RawAssignment = rows[k];
          if (this.noteDeadlineType(raw, courseId)) {
            nonStringDeadlines++;
          }
          const assignment: Assignment = parseAssignment(raw, courseId, this.courseNames,
            source.submitted, source.graded);
          const enriched: Assignment = await this.enrich(assignment, raw, courseId);
          requests += 2;
          const previous: Assignment | undefined = byId.get(enriched.id);
          if (previous === undefined) {
            byId.set(enriched.id, enriched);
            order.push(enriched.id);
          } else {
            byId.set(enriched.id, mergeAssignments(previous, enriched));
          }
        }
      }
    }

    const collected: Assignment[] = [];
    for (let i = 0; i < order.length; i++) {
      const item: Assignment | undefined = byId.get(order[i]);
      if (item !== undefined) {
        collected.push(item);
      }
    }
    const ordered: Assignment[] = compareAssignmentsByUpcoming(collected, Date.now());
    const elapsedMs: number = Date.now() - startedAt;
    this.logger.info(ASSIGNMENTS_LOG_DOMAIN + ' fetched courses=' + courseIds.length.toString()
      + ' items=' + ordered.length.toString()
      + ' elapsedMs=' + elapsedMs.toString()
      + ' requests=' + requests.toString()
      + ' failures=' + failures.toString()
      + ' nonStringDeadlines=' + nonStringDeadlines.toString());
    return ordered;
  }

  /**
   * 站点给的 `jzsj`（截止时间）**不保证是字符串**：2026-09-12 在 2025-2026 春季学期的真实数据上，
   * 这个值让 `domain/parse/Text.parseTimestamp` 的 `raw.trim()` 抛 "undefined is not callable"，
   * 整条课程/作业链路随之失败。实测原文见 .scratch/courses/evidence/。
   *
   * 这里只做**诊断**（第一条打 warn，总数进汇总行），解析与比较的语义在
   * `parseTimestamp` 里按 dayjs 对齐（数字 ⇒ epoch 毫秒）。
   * @returns 该行的 `jzsj` 是否不是字符串
   */
  private noteDeadlineType(raw: RawAssignment, courseId: string): boolean {
    // 不用 `raw as Record<string, Object>`：ArkTS 的类型检查拒绝这种不重叠的转换
    // （实测 "Conversion of type 'RawAssignment' to type 'Record<string, Object>' may be a mistake"）。
    // 声明成 string | undefined 后再做 typeof 判定即可——运行时该值可能是数字。
    const deadline: string | undefined = raw.jzsj;
    if (deadline === undefined || deadline === null || typeof deadline === 'string') {
      // 缺失 / null 由 parseAssignment 的 text() 转成空串（"没有截止时间"是合法状态），
      // 只有"给了值但不是字符串"才是本工单要诊断的那种行。
      return false;
    }
    if (!this.deadlineTypeWarned) {
      this.deadlineTypeWarned = true;
      this.logger.warn(ASSIGNMENTS_LOG_DOMAIN + ' non-string deadline: course=' + courseId
        + ' type=' + typeof deadline + ' value=' + String(deadline)
        + ' (parseTimestamp treats numbers as epoch ms, everything else as unparseable)');
    }
    return true;
  }

  /** 补描述与详情页（描述失败不影响详情，反之亦然——照参考实现两个独立 try/catch）。 */
  private async enrich(base: Assignment, raw: RawAssignment, courseId: string): Promise<Assignment> {
    const descriptionOutcome: FetchOutcome = await this.port.postForm(this.session, {
      url: LEARN_ORIGIN + '/b/wlxt/kczy/zy/student/detail?_csrf=' + this.session.csrfToken,
      id: raw.zyid
    });
    const description: string = extractAssignmentDescription(descriptionOutcome.body);
    const detail: AssignmentDetail = { description: description };

    const detailOutcome: FetchOutcome = await this.port.get(this.session, { url: assignmentDetailUrl(courseId, raw) });
    if (detailOutcome.ok && detailOutcome.body.length > 0) {
      const htmlDetail: AssignmentDetail = parseAssignmentDetail(detailOutcome.body);
      if (htmlDetail.attachment !== undefined) {
        detail.attachment = htmlDetail.attachment;
      }
      if (htmlDetail.answerAttachment !== undefined) {
        detail.answerAttachment = htmlDetail.answerAttachment;
      }
      if (htmlDetail.submittedAttachment !== undefined) {
        detail.submittedAttachment = htmlDetail.submittedAttachment;
      }
      if (htmlDetail.gradeAttachment !== undefined) {
        detail.gradeAttachment = htmlDetail.gradeAttachment;
      }
    }
    return mergeAssignmentDetail(base, detail);
  }

  private reportFailure(courseId: string, path: string, outcome: FetchOutcome): void {
    const detail: string = outcome.error === undefined ? 'HTTP ' + outcome.status.toString() : outcome.error;
    this.logger.warn(ASSIGNMENTS_LOG_DOMAIN + ' request failed course=' + courseId + ' path=' + path + ' ' + detail);
  }
}