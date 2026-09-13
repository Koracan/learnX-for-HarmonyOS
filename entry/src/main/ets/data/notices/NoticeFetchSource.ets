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
import { NoticeFetchSource } from './RealNoticeRepository';

const logger: Logger = new Logger('data.notices.source');

export class HttpNoticeFetchSource implements NoticeFetchSource {
  private readonly port: FetchPort;
  private readonly courses: CourseListSource;
  private readonly decodeBase64: Base64Decoder;

  constructor(port: FetchPort, courses: CourseListSource, decodeBase64: Base64Decoder) {
    this.port = port;
    this.courses = courses;
    this.decodeBase64 = decodeBase64;
  }

  async fetchWithSession(session: Session): Promise<Notice[]> {
    const courseList: CourseListResult = await this.courses.fetch(session);
    const courseIds: string[] = Object.keys(courseList.names);
    if (courseIds.length === 0) {
      // 没有课程就不可能"没有公告" —— 这是取数失败，必须显式抛出（否则界面会显示空态，
      // 把"接口/会话坏了"说成"你没事"）。
      throw new Error('no courses for the current semester: ' + courseList.diagnostic);
    }
    const fetcher: NoticesFetcher = new NoticesFetcher(logger, this.port, session,
      courseList.names, this.decodeBase64);
    const notices: Notice[] = await fetcher.fetch(courseIds);
    logger.info('notice fetch source done: courses=' + courseIds.length.toString()
      + ' notices=' + notices.length.toString()
      + ' paths=' + NOTICE_LIST_PATHS.length.toString());
    return notices;
  }
}
