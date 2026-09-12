/*
 * 学生课程列表抓取（data/notices，ticket 09）。
 *
 * ## 为什么 ticket 09 需要它
 *
 * 公告列表接口是**按课程**查的（`aoData=[{"name":"wlkcid","value":<课程id>}]`），
 * 而 NoticeRecord 还要 `courseName` / `courseTeacherName`。参考实现里这两个输入来自
 * redux 的 `courses.names`，由 thu-learn-lib 的 `getCurrentSemester` + `getCourseList` 填。
 * ticket 12（课程与学期选择）会做完整的课程页；本文件**只做公告路径需要的那一小段**：
 *   1. GET `/b/kc/zhjw_v_code_xnxq/getCurrentAndNextSemester` → 当前学期 id；
 *   2. GET `/b/wlxt/kc/v_wlkc_xs_xkb_kcb_extend/student/loadCourseBySemesterId/<xnxq>/zh_CN`
 *      → `resultList[]`，逐条取 `wlkcid` / `kcm` / `jsm`。
 * 路径与参考实现逐字一致（reference/learnOH-old/node_modules/thu-learn-lib/lib/module/urls.js）。
 *
 * ## 边界
 *
 *   - **不缓存、不落盘**：课程名会变，而公告快照里的 courseName 是抓取当时的投影；
 *     每次 refresh 重取（与参考实现每次 getCourseList 一致）。
 *   - **失败不兜底**：取不到学期或课程列表时返回 `ok=false`，由 RealNoticeRepository
 *     向上抛错 ⇒ AuthedTaskRunner 判定 requiresEnrollment ⇒ 界面停回登录页。
 *     **绝不返回空课程表**（那会渲染成"没有公告"，把"会话/接口坏了"说成"你没事"）。
 */

import { Logger } from '../../core/log/Logger';
import { CourseName } from '../../domain/parse/CourseName';
import { LEARN_ORIGIN, Session } from '../remote/Requests';
import { authedGet } from '../remote/AuthedRequest';
import { FetchPort, GetSpec } from '../remote/Port';

export const COURSE_LIST_LOG_DOMAIN: string = 'data.courses';

/** 当前学期接口（照 thu-learn-lib urls.js: LEARN_CURRENT_SEMESTER）。 */
export const CURRENT_SEMESTER_PATH: string = '/b/kc/zhjw_v_code_xnxq/getCurrentAndNextSemester';

/** 学生课程列表接口（照 thu-learn-lib urls.js: LEARN_COURSE_LIST，学生分支）。 */
export const COURSE_LIST_PATH_PREFIX: string =
  '/b/wlxt/kc/v_wlkc_xs_xkb_kcb_extend/student/loadCourseBySemesterId/';

/**
 * 站点语言段。参考实现按界面语言在 `zh_CN` / `en_US` 之间切；公告仓储与界面语言无关，
 * 取 `zh_CN`（与 LoginClient 抓语言那一步的中文默认一致），并在日志里自证取值。
 */
export const COURSE_LIST_LANGUAGE: string = 'zh_CN';

/** 抓取结果：课程名表 + 为诊断留的计数。 */
export class CourseListResult {
  readonly names: Record<string, CourseName>;
  readonly courseCount: number;
  readonly semesterId: string;
  readonly diagnostic: string;

  constructor(names: Record<string, CourseName>, courseCount: number, semesterId: string, diagnostic: string) {
    this.names = names;
    this.courseCount = courseCount;
    this.semesterId = semesterId;
    this.diagnostic = diagnostic;
  }
}

/** 课程列表抓取端口（测试里用替身注入）。 */
export interface CourseListSource {
  fetch(session: Session): Promise<CourseListResult>;
}

/**
 * 从学期接口正文里抽出 `xnxq`。
 *
 * 为什么手工切而不用 JSON 解析：这一步必须在**任何**响应形状下都不炸（正文可能是
 * 登录页 HTML 或错误页）。找不到就返回空串，由调用方明确失败。
 * 站点返回形如 `{"result":"...","xnxq":"2026-2027-1",...}`。
 */
export function extractSemesterId(body: string): string {
  const marker: number = body.indexOf('"xnxq"');
  if (marker < 0) {
    return '';
  }
  const colon: number = body.indexOf(':', marker);
  if (colon < 0) {
    return '';
  }
  const start: number = body.indexOf('"', colon + 1);
  if (start < 0) {
    return '';
  }
  const end: number = body.indexOf('"', start + 1);
  if (end <= start) {
    return '';
  }
  return body.substring(start + 1, end);
}

/** 课程列表响应 → 课程名表。非 JSON / 数组缺失 / message 非 success 时返回 undefined。 */
export function parseCourseList(body: string): Record<string, CourseName> | undefined {
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
  const names: Record<string, CourseName> = {};
  const array: Object[] = list as Object[];
  for (let i = 0; i < array.length; i++) {
    const entry: Object = array[i];
    if (entry === null || typeof entry !== 'object') {
      continue;
    }
    const item: Record<string, Object> = entry as Record<string, Object>;
    const id: Object = item['wlkcid'];
    if (id === undefined || id === null) {
      continue;
    }
    const idText: string = String(id);
    if (idText.length === 0) {
      continue;
    }
    const kcm: Object = item['kcm'];
    const jsm: Object = item['jsm'];
    names[idText] = {
      name: kcm === undefined || kcm === null ? '' : String(kcm),
      teacherName: jsm === undefined || jsm === null ? '' : String(jsm)
    };
  }
  return names;
}

/** 设备实现：两个 GET，全部走注入的 FetchPort。 */
export class HttpCourseListSource implements CourseListSource {
  private readonly logger: Logger;
  private readonly port: FetchPort;

  constructor(logger: Logger, port: FetchPort) {
    this.logger = logger;
    this.port = port;
  }

  async fetch(session: Session): Promise<CourseListResult> {
    const semesterUrl: string = LEARN_ORIGIN + CURRENT_SEMESTER_PATH + '?_csrf=' + session.csrfToken;
    const semesterOutcome = await authedGet(this.port, session, this.logger, COURSE_LIST_LOG_DOMAIN, semesterUrl);
    if (!semesterOutcome.ok) {
      throw new Error('current semester request failed: status=' + semesterOutcome.status.toString());
    }
    const semesterId: string = extractSemesterId(semesterOutcome.body);
    if (semesterId.length === 0) {
      throw new Error('no xnxq in current semester response: bytes='
        + semesterOutcome.body.length.toString());
    }
    const courseUrl: string = LEARN_ORIGIN + COURSE_LIST_PATH_PREFIX + semesterId
      + '/' + COURSE_LIST_LANGUAGE + '?_csrf=' + session.csrfToken;
    const courseOutcome = await authedGet(this.port, session, this.logger, COURSE_LIST_LOG_DOMAIN, courseUrl);
    if (!courseOutcome.ok) {
      throw new Error('course list request failed: status=' + courseOutcome.status.toString());
    }
    const names: Record<string, CourseName> | undefined = parseCourseList(courseOutcome.body);
    if (names === undefined) {
      throw new Error('course list response not usable: bytes=' + courseOutcome.body.length.toString());
    }
    const count: number = Object.keys(names).length;
    const diagnostic: string = 'semester=' + semesterId + ' lang=' + COURSE_LIST_LANGUAGE
      + ' courses=' + count.toString() + ' bytes=' + courseOutcome.body.length.toString();
    this.logger.info(COURSE_LIST_LOG_DOMAIN + ' resolved ' + diagnostic);
    return new CourseListResult(names, count, semesterId, diagnostic);
  }
}
