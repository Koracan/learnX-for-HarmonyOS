/*
 * `NoticeFetchSource` 的设备实现（data/notices）：
 * 把 `NoticesFetcher` 与课程列表接成 RealNoticeRepository 要的形状。
 *
 * 为什么需要这一层：
 *   - `NoticesFetcher` 的构造签名接受一个 `Session`，而数据路径
 *     每次任务都要用**当次**的会话（重登后 cookie/csrf 会轮换）。本类每次 fetch 都用
 *     传入的 session 现构造一次 fetcher，避免把会话固化在对象字段里；
 *   - 公告是**按课程**查的，课程表由 CourseListSource 取（见 CourseListFetcher 的说明）。
 *
 * ## 生效学期（此前这里**没有**选择这一档）
 *
 * 公告的课程列表请求此前走 `this.courses.fetch(session)`（**不带学期**）⇒ 有效学期
 * 由"站点当前学期"决定，**不认**界面选择。于是切了学期之后，公告下拉刷新两次拿到的
 * 是同一份数据 —— 这正是账号所有者报的"公告手动刷新也无效"。
 * 现在与课程 / 文件两条线**共用同一份优先级判定**（`resolveEffectiveSemester`：
 * 脚本覆盖 > 界面选择 > 站点当前学期），并把生效学期显式传给课程列表。
 *
 * 失败一律抛出（消息里带诊断），由 RealNoticeRepository 翻成 reject：
 * **绝不返回空集合**。
 */

import { Logger } from '../../core/log/Logger';
import { Notice } from '../../domain/model/ContentItem';
import { NOTICE_LIST_PATHS, NoticesFetcher } from '../remote/NoticesFetcher';
import { Base64Decoder } from '../../domain/parse/NoticeParser';
import { FetchPort } from '../remote/Port';
import { Session } from '../remote/Requests';
import { CourseListResult, CourseListSource } from './CourseListFetcher';
import { SemesterResolution, SemesterSource } from '../courses/SemesterFetcher';
import {
  EffectiveSemester, describeSemesterOverride, resolveEffectiveSemester
} from '../courses/SemesterOverride';
import { NoticeFetchSource } from './RealNoticeRepository';

export const NOTICE_SOURCE_LOG_DOMAIN: string = 'data.notices.source';

const logger: Logger = new Logger(NOTICE_SOURCE_LOG_DOMAIN);

export class HttpNoticeFetchSource implements NoticeFetchSource {
  private readonly port: FetchPort;
  private readonly semesters: SemesterSource;
  private readonly courses: CourseListSource;
  private readonly decodeBase64: Base64Decoder;

  constructor(port: FetchPort, semesters: SemesterSource, courses: CourseListSource,
    decodeBase64: Base64Decoder) {
    this.port = port;
    this.semesters = semesters;
    this.courses = courses;
    this.decodeBase64 = decodeBase64;
  }

  async fetchWithSession(session: Session, semesterId?: string): Promise<Notice[]> {
    const requested: string = semesterId === undefined ? '' : semesterId;
    // 开关自证：每次刷新都打一行"常量 / 运行期 / 实际生效 / 来源"。
    logger.info(NOTICE_SOURCE_LOG_DOMAIN + ' ' + describeSemesterOverride());
    const preResolved: EffectiveSemester = resolveEffectiveSemester({
      siteCurrentSemesterId: '', explicitSelection: requested
    });

    let resolution: SemesterResolution;
    try {
      resolution = await this.semesters.resolve(session);
    } catch (error) {
      const message: string = (error as Error).message;
      if (preResolved.semesterId.length === 0) {
        throw new Error('semester resolution failed: ' + message);
      }
      logger.warn(NOTICE_SOURCE_LOG_DOMAIN + ' semester resolution failed ('
        + message + ') -> falling back to override/selection');
      resolution = SemesterResolution.unavailable(message);
    }

    const resolved: EffectiveSemester = resolveEffectiveSemester({
      siteCurrentSemesterId: resolution.currentSemesterId,
      explicitSelection: requested
    });
    const effective: string = resolved.semesterId;
    if (effective.length === 0) {
      throw new Error('no effective semester for the notice path:'
        + ' site current unknown and no override/selection');
    }

    const courseList: CourseListResult = await this.courses.fetch(session, effective);
    const courseIds: string[] = Object.keys(courseList.names);
    if (courseIds.length === 0) {
      // 没有课程就不可能"没有公告" —— 这是取数失败，必须显式抛出（否则界面会显示空态，
      // 把"接口/会话坏了"说成"你没事"）。
      throw new Error('no courses for the current semester: ' + courseList.diagnostic);
    }
    const fetcher: NoticesFetcher = new NoticesFetcher(logger, this.port, session,
      courseList.names, this.decodeBase64);
    const notices: Notice[] = await fetcher.fetch(courseIds);
    logger.info(NOTICE_SOURCE_LOG_DOMAIN + ' effective semester=' + effective
      + ' source=' + resolved.source
      + ' siteCurrent=' + resolution.currentSemesterId
      + ' courses=' + courseIds.length.toString());
    logger.info('notice fetch source done: courses=' + courseIds.length.toString()
      + ' notices=' + notices.length.toString()
      + ' paths=' + NOTICE_LIST_PATHS.length.toString());
    return notices;
  }
}
