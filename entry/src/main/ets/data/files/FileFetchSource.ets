/*
 * 文件 tab 的设备侧取数（data/files，ticket 11）：
 * 学期解析 → 课程列表 → `FilesFetcher`（ticket 05 的同一份实现，**不复制取数逻辑**）。
 *
 * 学期的优先级与 `HttpCourseFetchSource` **完全一致**（覆盖 > 站点当前；
 * 文件 tab 没有"界面选择学期"这个入口，所以没有 selection 这一档）：
 *   - 覆盖（`aa start --ps lohSemester 2025-2026-2`）被设置时就是权威值，
 *     并且**实际生效值每次都进 hilog**（见 describeSemesterOverride）；
 *   - 站点当前学期 0 个文件 → 抛错（失败信号，见 FileRepository 的文件头）；
 *   - 显式覆盖到别的学期时空文件是**合法空态** + 一行 warn。
 */

import { Logger } from '../../core/log/Logger';
import { CourseFile } from '../../domain/model/ContentItem';
import { CourseListResult, CourseListSource } from '../courses/CourseListFetcher';
import { SemesterResolution, SemesterSource } from '../courses/SemesterFetcher';
import { describeSemesterOverride, effectiveSemesterOverride } from '../courses/SemesterOverride';
import { FilesFetcher } from '../remote/FilesFetcher';
import { FetchPort, Session } from '../remote/Port';

export const FILE_SOURCE_LOG_DOMAIN: string = 'data.files';

/** 一次文件取数的产物。 */
export interface FileFetchResult {
  files: CourseFile[];
  /** 实际生效的学期。 */
  semesterId: string;
  /** 站点报的当前学期。 */
  siteCurrentSemesterId: string;
}

/** 文件抓取端口（测试注入替身）。 */
export interface FileFetchSource {
  fetchWithSession(session: Session): Promise<FileFetchResult>;
}

/** 设备实现。 */
export class HttpFileFetchSource implements FileFetchSource {
  private readonly logger: Logger;
  private readonly port: FetchPort;
  private readonly semesters: SemesterSource;
  private readonly courses: CourseListSource;

  constructor(port: FetchPort, semesters: SemesterSource, courses: CourseListSource, logger: Logger) {
    this.port = port;
    this.semesters = semesters;
    this.courses = courses;
    this.logger = logger;
  }

  async fetchWithSession(session: Session): Promise<FileFetchResult> {
    // 开关自证：每次刷新都打一行"常量 / 运行期 / 实际生效 / 来源"。
    this.logger.info(FILE_SOURCE_LOG_DOMAIN + ' ' + describeSemesterOverride());
    const override: string = effectiveSemesterOverride();

    let resolution: SemesterResolution;
    try {
      resolution = await this.semesters.resolve(session);
    } catch (error) {
      const message: string = (error as Error).message;
      if (override.length === 0) {
        throw new Error('semester resolution failed: ' + message);
      }
      this.logger.warn(FILE_SOURCE_LOG_DOMAIN + ' semester resolution failed ('
        + message + ') -> falling back to override');
      resolution = SemesterResolution.unavailable(message);
    }

    const effective: string = override.length > 0 ? override : resolution.currentSemesterId;
    const source: string = override.length > 0 ? 'override' : 'site-current';
    if (effective.length === 0) {
      throw new Error('no effective semester for the file tab: site current unknown and no override');
    }
    this.logger.info(FILE_SOURCE_LOG_DOMAIN + ' effective semester=' + effective + ' source=' + source);

    const list: CourseListResult = await this.courses.fetch(session, effective);
    const courseIds: string[] = Object.keys(list.names);
    if (list.courseCount === 0 && source === 'site-current') {
      throw new Error('course list is EMPTY for the site current semester ' + effective
        + ': an empty list means the fetch/degrade path is broken, not "no courses"');
    }

    const files: CourseFile[] = courseIds.length === 0
      ? []
      : await new FilesFetcher(this.logger, this.port, session, list.names).fetch(courseIds);

    if (files.length === 0) {
      if (source === 'site-current') {
        throw new Error('file list is EMPTY for the site current semester ' + effective
          + ' (courses=' + courseIds.length.toString()
          + '): this account has files this semester, so an empty list means the fetch/degrade'
          + ' path is broken, not "no files"');
      }
      this.logger.warn(FILE_SOURCE_LOG_DOMAIN + ' file list empty for override semester ' + effective
        + ' (courses=' + courseIds.length.toString() + ') -> rendering the empty state');
    }

    this.logger.info(FILE_SOURCE_LOG_DOMAIN + ' snapshot semester=' + effective + ' source=' + source
      + ' courses=' + courseIds.length.toString() + ' files=' + files.length.toString());
    return { files: files, semesterId: effective, siteCurrentSemesterId: resolution.currentSemesterId };
  }
}
