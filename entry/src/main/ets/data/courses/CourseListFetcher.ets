/*
 * 学生课程列表抓取（data/courses，ticket 12）——**课程这条线的唯一取数实现**。
 *
 * 本文件是 ticket 09 那份 `data/notices/CourseListFetcher` 的完整版：路径、语言段、
 * 手工抽 `xnxq` 的写法全部保留，**新增**的是"按指定学期取"（学期切换要它）与
 * 逐字段解析出的完整课程条目（`CourseEntry`）。旧文件已改成**转发层**，
 * 于是"取数逻辑"只有这一份（见 data/notices/CourseListFetcher.ets 的文件头）。
 *
 * 路径逐字照参考实现 `thu-learn-lib/lib/module/urls.js` 的 `LEARN_COURSE_LIST`（学生分支）：
 *   `/b/wlxt/kc/v_wlkc_xs_xkb_kcb_extend/student/loadCourseBySemesterId/<xnxq>/<lang>`
 * 照参考实现 `index.js:268-299` 的字段映射逐项解析：
 *
 * | 站点字段 | 参考实现字段 | 说明 |
 * | --- | --- | --- |
 * | `wlkcid` | `id` | 课程标识（实测形如 `2026-2027-1152226210` = `<xnxq><课程号>`） |
 * | `zywkcm` | `name` | 卡片显示名（走 decodeHTML） |
 * | `kcm` | `chineseName` | 中文名 |
 * | `ywkcm` | `englishName` | 英文名 |
 * | `jsm` | `teacherName` | 教师名 |
 * | `jsh` | `teacherNumber` | 教师工号 |
 * | `kch` | `courseNumber` | 课程号 |
 * | `kxh` | `courseIndex` | 课序号（`Number()`） |
 *
 * **没做的**：参考实现还给每门课补一次 `LEARN_COURSE_TIME_LOCATION`（上课时间地点）。
 * 那需要每课多一次请求，而 ticket 12 的验收（课程名 / 教师 / 三类计数）不需要它，
 * 故本 ticket 不取；见 ticket Comments 的未验证项。
 *
 * ## 原始响应可见性
 *
 * 每轮抓取都会把课程列表响应的**前 1800 字符**打进 hilog（`raw preview`）——
 * 验收要求"课程条数与顺序与站点原始响应对照"，而 ticket 09 的教训是
 * "在把失败归因给站点之前，先把我们收到的东西变成可观察量"。超长时显式标注截断。
 */

import { Logger } from '../../core/log/Logger';
import { CourseName } from '../../domain/parse/CourseName';
import { decodeHtmlEntities } from '../../domain/parse/Text';
import { LEARN_ORIGIN, Session } from '../remote/Requests';
import { authedGet } from '../remote/AuthedRequest';
import { FetchOutcome, FetchPort } from '../remote/Port';
import { SemesterSource } from './SemesterFetcher';

export const COURSE_LIST_LOG_DOMAIN: string = 'data.courses';

/** 学生课程列表接口前缀（照 thu-learn-lib urls.js: LEARN_COURSE_LIST，学生分支）。 */
export const COURSE_LIST_PATH_PREFIX: string =
  '/b/wlxt/kc/v_wlkc_xs_xkb_kcb_extend/student/loadCourseBySemesterId/';

/**
 * 站点语言段。参考实现按界面语言在 `zh_CN` / `en_US` 之间切；课程名与教师名与界面语言
 * 无关（本工程一律取中文名），取 `zh_CN`（与 LoginClient 抓语言那一步的中文默认一致），
 * 并在日志里自证取值。
 */
export const COURSE_LIST_LANGUAGE: string = 'zh_CN';

/** 原始响应预览的长度上限（hilog 单条 ~2400 字符会截断，留足余量）。 */
export const RAW_PREVIEW_LIMIT: number = 1800;

/** 一门课的完整条目（字段映射见文件头）。 */
export interface CourseEntry {
  id: string;
  /** 卡片显示名（参考实现 = `decodeHTML(zywkcm)`）。 */
  name: string;
  chineseName: string;
  englishName: string;
  teacherName: string;
  teacherNumber: string;
  courseNumber: string;
  courseIndex: number;
}

/** 字段取值：缺失/null 一律成空串（不抛、不写 'undefined'）。 */
function textOf(item: Record<string, Object>, key: string): string {
  const value: Object = item[key];
  if (value === undefined || value === null) {
    return '';
  }
  return String(value);
}

/** 课程列表响应 → 原始条目数组。非 JSON / `resultList` 缺失 / message 非 success 时返回 undefined。 */
function parseResultList(body: string): Object[] | undefined {
  let parsed: Object;
  try {
    parsed = JSON.parse(body) as Object;
  } catch (error) {
    return undefined;
  }
  if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
    return undefined;
  }
  const root: Record<string, Object> = parsed as Record<string, Object>;
  const message: Object = root['message'];
  if (message !== undefined && message !== null && String(message) !== 'success') {
    return undefined;
  }
  const list: Object = root['resultList'];
  if (list === undefined || list === null || !Array.isArray(list)) {
    return undefined;
  }
  return list as Object[];
}

/** 课程列表响应 → 完整课程条目（参考实现的字段口径）。 */
export function parseCourseEntries(body: string): CourseEntry[] | undefined {
  const rows: Object[] | undefined = parseResultList(body);
  if (rows === undefined) {
    return undefined;
  }
  const entries: CourseEntry[] = [];
  for (let i = 0; i < rows.length; i++) {
    const row: Object = rows[i];
    if (row === null || typeof row !== 'object') {
      continue;
    }
    const item: Record<string, Object> = row as Record<string, Object>;
    const id: string = textOf(item, 'wlkcid');
    if (id.length === 0) {
      continue;
    }
    const chineseName: string = decodeHtmlEntities(textOf(item, 'kcm'));
    const englishName: string = decodeHtmlEntities(textOf(item, 'ywkcm'));
    const displayName: string = decodeHtmlEntities(textOf(item, 'zywkcm'));
    const indexText: string = textOf(item, 'kxh');
    entries.push({
      id: id,
      // 参考实现用 zywkcm；它为空时退回 kcm（绝不显示空课程名）。
      name: displayName.length > 0 ? displayName : chineseName,
      chineseName: chineseName,
      englishName: englishName,
      teacherName: decodeHtmlEntities(textOf(item, 'jsm')),
      teacherNumber: textOf(item, 'jsh'),
      courseNumber: textOf(item, 'kch'),
      courseIndex: indexText.length > 0 ? Number(indexText) : 0
    });
  }
  return entries;
}

/**
 * 课程列表响应 → 课程名表（`courseId → {name, teacherName}`）。
 *
 * **ticket 09 的既有口径原样保留**：`name` 取 `kcm`（不是 `zywkcm`）、**不解码实体**。
 * 这条被 ticket 09 的验收（公告卡片的 `courseName`）钉住，本 ticket 不动它；
 * 卡片显示名另走 `CourseEntry.name`（参考实现口径）。两者的差异会在
 * `raw preview` 之后由 `nameFields` 一行自证（实测两个字段是否相同）。
 */
export function parseCourseList(body: string): Record<string, CourseName> | undefined {
  const rows: Object[] | undefined = parseResultList(body);
  if (rows === undefined) {
    return undefined;
  }
  const names: Record<string, CourseName> = {};
  for (let i = 0; i < rows.length; i++) {
    const row: Object = rows[i];
    if (row === null || typeof row !== 'object') {
      continue;
    }
    const item: Record<string, Object> = row as Record<string, Object>;
    const id: string = textOf(item, 'wlkcid');
    if (id.length === 0) {
      continue;
    }
    names[id] = { name: textOf(item, 'kcm'), teacherName: textOf(item, 'jsm') };
  }
  return names;
}

/** 抓取结果：完整条目 + 兼容 ticket 09 的课程名表 + 为诊断留的计数。 */
export class CourseListResult {
  /** `courseId → {name(kcm), teacherName}`；公告/作业/文件解析器用它。 */
  readonly names: Record<string, CourseName>;
  readonly entries: CourseEntry[];
  readonly courseCount: number;
  readonly semesterId: string;
  readonly diagnostic: string;

  constructor(names: Record<string, CourseName>, entries: CourseEntry[], semesterId: string,
    diagnostic: string) {
    this.names = names;
    this.entries = entries;
    this.courseCount = entries.length;
    this.semesterId = semesterId;
    this.diagnostic = diagnostic;
  }
}

/** 课程列表抓取端口（测试里用替身注入）。 */
export interface CourseListSource {
  /**
   * 抓取指定学期的课程列表。
   * @param semesterId 为空时按站点当前学期取（ticket 09 的调用点依赖这条默认行为）。
   */
  fetch(session: Session, semesterId?: string): Promise<CourseListResult>;
}

/** 设备实现：一次 GET（学期先由 SemesterSource 解析或由调用方给定）。 */
export class HttpCourseListSource implements CourseListSource {
  private readonly logger: Logger;
  private readonly port: FetchPort;
  private readonly semesters: SemesterSource;

  constructor(logger: Logger, port: FetchPort, semesters: SemesterSource) {
    this.logger = logger;
    this.port = port;
    this.semesters = semesters;
  }

  async fetch(session: Session, semesterId?: string): Promise<CourseListResult> {
    const requested: string = semesterId === undefined ? '' : semesterId;
    let effective: string = requested;
    if (effective.length === 0) {
      effective = await this.semesters.currentSemesterId(session);
    }
    const url: string = LEARN_ORIGIN + COURSE_LIST_PATH_PREFIX + effective
      + '/' + COURSE_LIST_LANGUAGE + '?_csrf=' + session.csrfToken;
    const outcome: FetchOutcome = await authedGet(this.port, session, this.logger,
      COURSE_LIST_LOG_DOMAIN, url);
    if (!outcome.ok) {
      throw new Error('course list request failed: status=' + outcome.status.toString()
        + ' semester=' + effective);
    }
    const entries: CourseEntry[] | undefined = parseCourseEntries(outcome.body);
    const names: Record<string, CourseName> | undefined = parseCourseList(outcome.body);
    if (entries === undefined || names === undefined) {
      throw new Error('course list response not usable: bytes=' + outcome.body.length.toString()
        + ' semester=' + effective);
    }
    const diagnostic: string = 'semester=' + effective + ' requested=' + requested
      + ' lang=' + COURSE_LIST_LANGUAGE + ' courses=' + entries.length.toString()
      + ' bytes=' + outcome.body.length.toString();
    this.logger.info(COURSE_LIST_LOG_DOMAIN + ' resolved ' + diagnostic);
    this.logNameFields(entries);
    this.logRawPreview(outcome.body);
    return new CourseListResult(names, entries, effective, diagnostic);
  }

  /**
   * 逐字段自证：`kcm`（ticket 09 的公告 courseName）与 `zywkcm`（参考实现的显示名）
   * 在**真实响应**上是否相同。这行是"课程/学期字段逐字段与站点原始响应对照"的一半。
   */
  private logNameFields(entries: CourseEntry[]): void {
    for (let i = 0; i < entries.length; i++) {
      const entry: CourseEntry = entries[i];
      this.logger.info(COURSE_LIST_LOG_DOMAIN + ' course[' + i.toString() + '] id=' + entry.id
        + ' name=' + entry.name
        + ' kcm=' + entry.chineseName
        + ' ywkcm=' + entry.englishName
        + ' jsm=' + entry.teacherName
        + ' jsh=' + entry.teacherNumber
        + ' kch=' + entry.courseNumber
        + ' kxh=' + entry.courseIndex.toString());
    }
  }

  /** 站点原始响应预览（截断时显式标注）。 */
  private logRawPreview(body: string): void {
    const truncated: boolean = body.length > RAW_PREVIEW_LIMIT;
    const preview: string = truncated ? body.substring(0, RAW_PREVIEW_LIMIT) : body;
    this.logger.info(COURSE_LIST_LOG_DOMAIN + ' raw preview chars=' + body.length.toString()
      + ' truncated=' + truncated.toString() + ' body=' + preview);
  }
}
