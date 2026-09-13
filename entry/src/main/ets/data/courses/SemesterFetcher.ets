/*
 * 学期抓取（data/courses，ticket 12）：站点当前学期 + 全部可选学期。
 *
 * 路径逐字照参考实现 `thu-learn-lib/lib/module/urls.js`：
 *   - `LEARN_CURRENT_SEMESTER` = `/b/kc/zhjw_v_code_xnxq/getCurrentAndNextSemester`
 *   - `LEARN_SEMESTER_LIST`    = `/b/wlxt/kc/v_wlkc_xs_xktjb_coassb/queryxnxq`
 * 两者都**必须带 `?_csrf=`**（裸请求会得到站点自己的
 * 403 报错页，而 `isNoLoginResponse` 把 403 当会话失效 ⇒ 会被误判成掉线并降级）。
 *
 * 排序照参考实现：`semesters?.sort().reverse()` = 最新在前。
 * 这里用 `domain/model/Semester.sortSemesterIds(ids,'desc')`——它与 `sort().reverse()`
 * 在合法 id 上结果一致（单测 Semester.test.ets 已钉住），且对非法 id 不会静默错序。
 *
 * **学期集合接口失败不致命**（ticket 12 的取舍，见 CourseFetchSource 的说明）：
 * 课程与三类计数仍然可用，脚本覆盖（SemesterOverride）也不依赖这个接口。
 * 但失败会被记成 warn，并让 `semestersAvailable=false` 显式传到界面。
 */

import { Logger } from '../../core/log/Logger';
import { sortSemesterIds } from '../../domain/model/Semester';
import { LEARN_ORIGIN, Session } from '../remote/Requests';
import { authedGet } from '../remote/AuthedRequest';
import { FetchOutcome, FetchPort } from '../remote/Port';

export const SEMESTER_LOG_DOMAIN: string = 'data.courses';

/** 当前（与下一）学期接口。 */
export const CURRENT_SEMESTER_PATH: string = '/b/kc/zhjw_v_code_xnxq/getCurrentAndNextSemester';

/** 全部可选学期接口（参考实现的 LEARN_SEMESTER_LIST）。 */
export const SEMESTER_LIST_PATH: string = '/b/wlxt/kc/v_wlkc_xs_xktjb_coassb/queryxnxq';

/**
 * 从学期接口正文里抽出 `xnxq`。
 *
 * 为什么手工切而不用 JSON 解析：这一步必须在**任何**响应形状下都不炸（正文可能是
 * 登录页 HTML 或错误页）。找不到就返回空串，由调用方明确失败。
 * 站点返回形如 `{"result":{"xnxq":"2026-2027-1",...},"message":"success","resultList":[]}`。
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

/**
 * 学期集合响应 → 学期 id 数组（照参考实现 `getSemesterIdList`：必须是 JSON 数组，
 * 且 `filter(s => s != null)`）。非 JSON / 非数组时返回 undefined（**显式失败信号**）。
 */
export function parseSemesterList(body: string): string[] | undefined {
  let parsed: Object;
  try {
    parsed = JSON.parse(body) as Object;
  } catch (error) {
    return undefined;
  }
  if (!Array.isArray(parsed)) {
    return undefined;
  }
  const rows: Object[] = parsed as Object[];
  const ids: string[] = [];
  for (let i = 0; i < rows.length; i++) {
    const row: Object = rows[i];
    if (row === null || row === undefined) {
      continue;
    }
    const text: string = String(row);
    if (text.length > 0) {
      ids.push(text);
    }
  }
  return ids;
}

/** 一次学期解析的结果（不抛异常时的形状）。 */
export class SemesterResolution {
  /** 站点报的当前学期；接口失败时为空串。 */
  readonly currentSemesterId: string;
  /** 全部可选学期（最新在前）；接口失败或形状不符时为空数组。 */
  readonly semesters: string[];
  /** 学期集合接口是否给出可用结果。 */
  readonly listOk: boolean;
  readonly diagnostic: string;

  constructor(currentSemesterId: string, semesters: string[], listOk: boolean, diagnostic: string) {
    this.currentSemesterId = currentSemesterId;
    this.semesters = semesters;
    this.listOk = listOk;
    this.diagnostic = diagnostic;
  }

  static unavailable(diagnostic: string): SemesterResolution {
    return new SemesterResolution('', [], false, diagnostic);
  }
}

/** 学期来源端口（测试注入替身）。 */
export interface SemesterSource {
  /** 站点当前学期 id；失败时抛错。 */
  currentSemesterId(session: Session): Promise<string>;
  /** 站点当前学期 + 全部可选学期；当前学期失败时抛错，学期集合失败只记 warn。 */
  resolve(session: Session): Promise<SemesterResolution>;
}

/** 设备实现：两个 GET，全部走注入的 FetchPort。 */
export class HttpSemesterSource implements SemesterSource {
  private readonly logger: Logger;
  private readonly port: FetchPort;

  constructor(logger: Logger, port: FetchPort) {
    this.logger = logger;
    this.port = port;
  }

  async currentSemesterId(session: Session): Promise<string> {
    const url: string = LEARN_ORIGIN + CURRENT_SEMESTER_PATH + '?_csrf=' + session.csrfToken;
    const outcome: FetchOutcome = await authedGet(this.port, session, this.logger,
      SEMESTER_LOG_DOMAIN, url);
    if (!outcome.ok) {
      throw new Error('current semester request failed: status=' + outcome.status.toString());
    }
    const id: string = extractSemesterId(outcome.body);
    if (id.length === 0) {
      throw new Error('no xnxq in current semester response: bytes=' + outcome.body.length.toString());
    }
    return id;
  }

  async resolve(session: Session): Promise<SemesterResolution> {
    const current: string = await this.currentSemesterId(session);
    const listUrl: string = LEARN_ORIGIN + SEMESTER_LIST_PATH + '?_csrf=' + session.csrfToken;
    const listOutcome: FetchOutcome = await authedGet(this.port, session, this.logger,
      SEMESTER_LOG_DOMAIN, listUrl);
    let semesters: string[] = [];
    let listOk: boolean = false;
    if (listOutcome.ok) {
      const parsed: string[] | undefined = parseSemesterList(listOutcome.body);
      if (parsed !== undefined) {
        semesters = sortSemesterIds(parsed, 'desc');
        listOk = true;
      }
    }
    if (!listOk) {
      // **不抛**：课程列表与三类计数不依赖学期集合；脚本覆盖也不依赖它。
      this.logger.warn(SEMESTER_LOG_DOMAIN + ' semester list unavailable status='
        + listOutcome.status.toString() + ' bytes=' + listOutcome.body.length.toString()
        + ' -> semester picker falls back to current + selected');
    }
    const diagnostic: string = 'current=' + current + ' list=' + semesters.length.toString()
      + ' listOk=' + listOk.toString();
    this.logger.info(SEMESTER_LOG_DOMAIN + ' semesters resolved ' + diagnostic);
    return new SemesterResolution(current, semesters, listOk, diagnostic);
  }
}
