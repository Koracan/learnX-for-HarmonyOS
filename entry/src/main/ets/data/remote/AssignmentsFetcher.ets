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
 * **次序是两步，别只做第二步**（ticket 10 在真实数据上修正）：processor 先按截止时间倒序，
 * 再切成"未到期（由近及远）/ 已过期（由远及近）"。见 `fetch` 内的注释与
 * docs/reference-quirks.md 第 19 条。
 *
 * 另外每门课还会：
 *   3. POST `yxzylist` 取**优秀作业**列表，并对每条取优秀作业详情页（`viewYxzy`）解析附件；
 *      整段失败只 warn 一行（参考实现吞掉这条失败），见 docs/reference-quirks.md 第 21 条。
 *
 * 锚点日志（验收项 1；ticket 10 补做后多了 `excellent=`）：
 *   data.assignments fetched courses=<n> items=<n> elapsedMs=<n> requests=<n> failures=<n>
 *                            nonStringDeadlines=<n> excellent=<n>
 *   data.assignments excellent: course=<id> zyid=<id> items=<n> anonymous=<n> named=<n>
 */

import { Logger } from '../../core/log/Logger';
import { Assignment, ExcellentHomework } from '../../domain/model/ContentItem';
import { CourseName } from '../../domain/parse/CourseName';
import { decodeHtmlEntities } from '../../domain/parse/Text';
import {
  AssignmentDetail, RawAssignment, RawExcellent, assignmentDetailUrl,
  attachExcellentHomework, excellentHomeworkPageUrl,
  mergeAssignmentDetail, parseAssignment, parseAssignmentDetail, parseExcellentHomework,
  compareAssignmentsByUpcoming, sortAssignments
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

/** 优秀作业列表接口（thu-learn-lib `urls.js:50`）；表单与作业列表**同一个** `aoData`。 */
export const ASSIGNMENT_EXCELLENT_LIST_PATH: string = '/b/wlxt/kczy/zy/student/yxzylist';

/**
 * 优秀作业列表响应 → 原始记录数组。
 * 与作业列表同一个信封（`result: success` + `object.aaData`），判定逻辑一致。
 * 实测原文见 `.scratch/assignments/evidence/P1-excellent-probe-spring.txt`。
 */
export function extractExcellentRows(body: string): RawExcellent[] {
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
  return box['aaData'] === undefined || box['aaData'] === null ? [] : box['aaData'] as RawExcellent[];
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

/** 优秀作业抓取结果（条数 + 请求数，便于把请求数如实进汇总行）。 */
export interface ExcellentFetchOutcome {
  entries: ExcellentHomework[];
  requests: number;
  failures: number;
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

  /**
   * 抓取并解析；返回参考实现的最终次序：
   * **未到期在前（由近及远）→ 已过期在后（由远及近）**（见 fetch 内两步排序的说明）。
   */
  async fetch(courseIds: string[]): Promise<Assignment[]> {
    const startedAt: number = Date.now();
    let requests: number = 0;
    let failures: number = 0;
    let nonStringDeadlines: number = 0;
    const byId: Map<string, Assignment> = new Map<string, Assignment>();
    const order: string[] = [];
    const excellentEntries: ExcellentHomework[] = [];

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
      // 优秀作业：每门课**一次**列表 + 每条一次详情页（照参考实现）。
      // 列表失败只 warn，不影响作业列表与次序（参考实现 `// Don't block the whole process`，index.js:862-864）。
      const excellent: ExcellentFetchOutcome = await this.fetchExcellent(courseId);
      requests += excellent.requests;
      failures += excellent.failures;
      for (let e = 0; e < excellent.entries.length; e++) {
        excellentEntries.push(excellent.entries[e]);
      }
    }

    const collected: Assignment[] = [];
    for (let i = 0; i < order.length; i++) {
      const item: Assignment | undefined = byId.get(order[i]);
      if (item !== undefined) {
        collected.push(item);
      }
    }
    attachExcellentHomework(collected, excellentEntries);
    // 消费点自证：zyid → 优秀作业条数（补做项的取证要求：看得见"哪条作业挂了几条、几条匿名"）。
    for (let i = 0; i < collected.length; i++) {
      const list: ExcellentHomework[] | undefined = collected[i].excellentHomeworkList;
      if (list !== undefined) {
        let named: number = 0;
        for (let k = 0; k < list.length; k++) {
          if (!list[k].anonymous) {
            named++;
          }
        }
        this.logger.info(ASSIGNMENTS_LOG_DOMAIN + ' excellent: course=' + collected[i].courseId
          + ' zyid=' + collected[i].baseId + ' items=' + list.length.toString()
          + ' anonymous=' + (list.length - named).toString()
          + ' named=' + named.toString());
      }
    }
    // 参考实现的最终次序是**两步**：
    //   1. processor 先按截止时间倒序（DataProcessorModule.processAssignments 的 sort）；
    //   2. JS 侧再切成"未到期（reverse 成由近及远）+ 已过期（保持第 1 步的降序）"
    //      （actions/assignments.ts:123-128）。
    // ticket 05 的移植只搬了第 2 步 ⇒ **已过期段是接口返回顺序**；2026-09-12 在 2025-2026 春季
    // 的 57 条真实数据上实测：列表前三条的截止时间是 05-31 / 06-20 / 04-30，明显不是按时间。
    // ticket 10 补上第 1 步（顺序常量仍是同一个 compareAssignmentsByUpcoming）。
    const ordered: Assignment[] = compareAssignmentsByUpcoming(sortAssignments(collected), Date.now());
    const elapsedMs: number = Date.now() - startedAt;
    this.logger.info(ASSIGNMENTS_LOG_DOMAIN + ' fetched courses=' + courseIds.length.toString()
      + ' items=' + ordered.length.toString()
      + ' elapsedMs=' + elapsedMs.toString()
      + ' requests=' + requests.toString()
      + ' failures=' + failures.toString()
      + ' nonStringDeadlines=' + nonStringDeadlines.toString()
      + ' excellent=' + excellentEntries.length.toString());
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

  /**
   * 优秀作业：**每门课一次**列表请求（`yxzylist`，表单与作业列表同一个 `aoData`），
   * 再对**每条**取优秀作业详情页（`viewYxzy?wlkcid=&xszyid=`）解析两枚附件。
   *
   * 失败语义照参考实现（`index.js:859-864`）：**整段被吞**，只 warn 一行，
   * 作业列表、排序与其它课程都不受影响。详情页取不到时保留该条（只是没有附件），
   * 见 docs/reference-quirks.md 第 21 条。
   */
  private async fetchExcellent(courseId: string): Promise<ExcellentFetchOutcome> {
    const result: ExcellentFetchOutcome = { entries: [], requests: 1, failures: 0 };
    const listOutcome: FetchOutcome = await this.port.postForm(this.session, {
      url: LEARN_ORIGIN + ASSIGNMENT_EXCELLENT_LIST_PATH + '?_csrf=' + this.session.csrfToken,
      courseId: courseId
    });
    if (!listOutcome.ok) {
      result.failures = 1;
      this.logger.warn(ASSIGNMENTS_LOG_DOMAIN + ' excellent list failed course=' + courseId + ' '
        + (listOutcome.error === undefined ? 'HTTP ' + listOutcome.status.toString() : listOutcome.error)
        + ' -> assignment list/ordering unaffected (reference swallows this failure)');
      return result;
    }
    const rows: RawExcellent[] = extractExcellentRows(listOutcome.body);
    for (let i = 0; i < rows.length; i++) {
      const entry: ExcellentHomework = parseExcellentHomework(rows[i]);
      result.requests++;
      const page: FetchOutcome = await this.port.get(this.session, {
        url: excellentHomeworkPageUrl(courseId, entry.id)
      });
      if (page.ok && page.body.length > 0) {
        const detail: AssignmentDetail = parseAssignmentDetail(page.body);
        if (detail.gradeAttachment !== undefined) {
          entry.gradeAttachment = detail.gradeAttachment;
        }
        if (detail.submittedAttachment !== undefined) {
          entry.submittedAttachment = detail.submittedAttachment;
        }
      } else {
        result.failures++;
        this.logger.warn(ASSIGNMENTS_LOG_DOMAIN + ' excellent page failed course=' + courseId
          + ' xszyid=' + entry.id + ' -> keeping the entry without attachment');
      }
      result.entries.push(entry);
    }
    return result;
  }

  private reportFailure(courseId: string, path: string, outcome: FetchOutcome): void {
    const detail: string = outcome.error === undefined ? 'HTTP ' + outcome.status.toString() : outcome.error;
    this.logger.warn(ASSIGNMENTS_LOG_DOMAIN + ' request failed course=' + courseId + ' path=' + path + ' ' + detail);
  }
}