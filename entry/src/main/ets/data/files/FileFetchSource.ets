/*
 * 文件 tab 的设备侧取数（data/files）：
 * 学期解析 → 课程列表 → `FilesFetcher`（同一份实现，**不复制取数逻辑**）。
 *
 * 学期的优先级与 `HttpCourseFetchSource` / 公告路径**完全一致**，且**只有一处实现**
 * （`resolveEffectiveSemester`：脚本覆盖 > 界面选择 > 站点当前学期）：
 *   - 覆盖（`aa start --ps lohSemester 2025-2026-2`）被设置时就是权威值；
 *   - 界面选择（学期切换页）此前**没有被这条路径消费** —— 这里只认"覆盖 / 站点当前"，
 *     所以切了学期之后文件下拉刷新两次拿到的是同一份数据（账号所有者报的"文件手动刷新
 *     也无效"）。现在进程级的界面选择也会被读进来；
 *   - 并且**实际生效值每次都进 hilog**（见 describeSemesterOverride 与 effective 那一行）；
 *   - 站点当前学期 0 个文件 → 抛错（失败信号，见 FileRepository 的文件头）；
 *   - 显式覆盖/选择到别的学期时空文件是**合法空态** + 一行 warn。
 */

import { Logger } from '../../core/log/Logger';
import { CourseFile } from '../../domain/model/ContentItem';
import { CourseListResult, CourseListSource } from '../courses/CourseListFetcher';
import { SemesterResolution, SemesterSource } from '../courses/SemesterFetcher';
import {
  EffectiveSemester, describeSemesterOverride, resolveEffectiveSemester
} from '../courses/SemesterOverride';
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
  /**
   * 抓取文件列表。
   * @param semesterId 界面显式传入的学期；空串 = 用进程级选择 / 脚本覆盖 / 站点当前。
   */
  fetchWithSession(session: Session, semesterId?: string): Promise<FileFetchResult>;
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

  async fetchWithSession(session: Session, semesterId?: string): Promise<FileFetchResult> {
    const requested: string = semesterId === undefined ? '' : semesterId;
    // 开关自证：每次刷新都打一行"常量 / 运行期 / 实际生效 / 来源"。
    this.logger.info(FILE_SOURCE_LOG_DOMAIN + ' ' + describeSemesterOverride());
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
      this.logger.warn(FILE_SOURCE_LOG_DOMAIN + ' semester resolution failed ('
        + message + ') -> falling back to override/selection');
      resolution = SemesterResolution.unavailable(message);
    }

    // 生效学期只有一处判定：脚本覆盖 > 界面选择 > 站点当前学期（见 SemesterOverride）。
    const resolved: EffectiveSemester = resolveEffectiveSemester({
      siteCurrentSemesterId: resolution.currentSemesterId,
      explicitSelection: requested
    });
    const effective: string = resolved.semesterId;
    const source: string = resolved.source;
    if (effective.length === 0) {
      throw new Error('no effective semester for the file tab:'
        + ' site current unknown and no override/selection');
    }
    this.logger.info(FILE_SOURCE_LOG_DOMAIN + ' effective semester=' + effective
      + ' source=' + source + ' siteCurrent=' + resolution.currentSemesterId);

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
      this.logger.warn(FILE_SOURCE_LOG_DOMAIN + ' file list empty for semester ' + effective
        + ' (source=' + source + ' courses=' + courseIds.length.toString()
        + ') -> rendering the empty state');
    }

    this.logger.info(FILE_SOURCE_LOG_DOMAIN + ' snapshot semester=' + effective + ' source=' + source
      + ' courses=' + courseIds.length.toString() + ' files=' + files.length.toString());
    return { files: files, semesterId: effective, siteCurrentSemesterId: resolution.currentSemesterId };
  }
}
