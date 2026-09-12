/*
 * 课程数据的设备侧抓取（data/courses，ticket 12）：把"学期解析 → 课程列表 →
 * 三域抓取 → 计数"串成一次调用（一个 AuthedTaskRunner 任务里完成）。
 *
 * 语义要点（每条都有出处，别顺手改）：
 *
 * 1. **生效学期的优先级**：脚本/常量覆盖 > 界面选择 > 站点当前学期。
 *    覆盖只服务取证（ticket 10/13 要 2025-2026 春季的真实作业），被设置时就是权威值，
 *    并且**实际生效值每次都进 hilog**（见 SemesterOverride.describeSemesterOverride）。
 * 2. **站点当前学期 0 门课 = 失败信号**：用户提供的事实是本账号本学期课程非空，
 *    所以"当前学期"返回空列表必须抛错，不许渲染成"你没事"。
 *    **显式切到别的学期**时空结果是合法空态（那条学期可能真的没选课）。
 * 3. **学期集合接口失败不致命**：课程与计数不依赖它；失败时退化成
 *    "站点当前学期 + 实际生效学期"两项，并把 `semestersAvailable=false` 传上去（界面据此提示）。
 * 4. 三域抓取交给 ticket 05 的 `NoticesFetcher` / `AssignmentsFetcher` / `FilesFetcher`
 *    （**不复制取数逻辑**），课程名表用 `CourseListResult.names`（ticket 09 的同一口径）。
 */

import { Logger } from '../../core/log/Logger';
import { countsForCourse } from '../../domain/courses/CourseCounts';
import { Assignment, CourseFile, Notice } from '../../domain/model/ContentItem';
import { Base64Decoder } from '../../domain/parse/NoticeParser';
import { sortSemesterIds } from '../../domain/model/Semester';
import { AssignmentsFetcher } from '../remote/AssignmentsFetcher';
import { FilesFetcher } from '../remote/FilesFetcher';
import { NoticesFetcher } from '../remote/NoticesFetcher';
import { FetchPort, Session } from '../remote/Port';
import { noticeRecordOf } from '../notices/RealNoticeRepository';
import { NoticeRecord } from '../notices/NoticeRepository';
import { CourseEntry, CourseListResult, CourseListSource } from './CourseListFetcher';
import { CourseRecord, CourseSnapshot } from './CourseRepository';
import { SemesterResolution, SemesterSource } from './SemesterFetcher';
import { describeSemesterOverride, effectiveSemesterOverride } from './SemesterOverride';

export const COURSE_SOURCE_LOG_DOMAIN: string = 'data.courses';

/** 课程抓取端口（测试里注入替身）。 */
export interface CourseFetchSource {
  /**
   * 在给定会话里抓取课程快照；失败时抛出（消息进日志）。
   * @param selectedSemesterId 界面选择的学期；空串 = 由覆盖 / 站点当前学期决定。
   */
  fetchWithSession(session: Session, selectedSemesterId: string): Promise<CourseSnapshot>;
}

/** 由课程条目 + 三域内容算出卡片记录（三类计数逐门课算一次）。 */
export function buildCourseRecords(entries: CourseEntry[], notices: Notice[],
  assignments: Assignment[], files: CourseFile[], nowMillis: number): CourseRecord[] {
  const records: CourseRecord[] = [];
  for (let i = 0; i < entries.length; i++) {
    const entry: CourseEntry = entries[i];
    const counts = countsForCourse(entry.id, notices, assignments, files, nowMillis);
    records.push({
      id: entry.id,
      name: entry.name,
      chineseName: entry.chineseName,
      englishName: entry.englishName,
      teacherName: entry.teacherName,
      teacherNumber: entry.teacherNumber,
      courseNumber: entry.courseNumber,
      courseIndex: entry.courseIndex,
      unreadNoticeCount: counts.unreadNoticeCount,
      unfinishedAssignmentCount: counts.unfinishedAssignmentCount,
      unreadFileCount: counts.unreadFileCount
    });
  }
  return records;
}

/** 设备实现：三域抓取在同一个会话里串行完成（照参考实现逐课程串行）。 */
export class HttpCourseFetchSource implements CourseFetchSource {
  private readonly logger: Logger;
  private readonly port: FetchPort;
  private readonly semesters: SemesterSource;
  private readonly courses: CourseListSource;
  private readonly decodeBase64: Base64Decoder;

  constructor(port: FetchPort, semesters: SemesterSource, courses: CourseListSource,
    decodeBase64: Base64Decoder, logger: Logger) {
    this.port = port;
    this.semesters = semesters;
    this.courses = courses;
    this.decodeBase64 = decodeBase64;
    this.logger = logger;
  }

  async fetchWithSession(session: Session, selectedSemesterId: string): Promise<CourseSnapshot> {
    // 开关自证：每次刷新都打一行"常量 / 运行期 / 实际生效 / 来源"。
    this.logger.info(COURSE_SOURCE_LOG_DOMAIN + ' ' + describeSemesterOverride());
    const override: string = effectiveSemesterOverride();
    const selected: string = selectedSemesterId.trim();

    let resolution: SemesterResolution;
    try {
      resolution = await this.semesters.resolve(session);
    } catch (error) {
      const message: string = (error as Error).message;
      if (override.length === 0 && selected.length === 0) {
        // arkts-limited-throw：只能抛 Error 类型，所以这里重新包装而不是 `throw error`。
        throw new Error('semester resolution failed: ' + message);
      }
      this.logger.warn(COURSE_SOURCE_LOG_DOMAIN + ' semester resolution failed ('
        + message + ') -> falling back to override/selection');
      resolution = SemesterResolution.unavailable(message);
    }

    let effective: string = resolution.currentSemesterId;
    let source: string = 'site-current';
    if (selected.length > 0) {
      effective = selected;
      source = 'selection';
    }
    if (override.length > 0) {
      effective = override;
      source = 'override';
    }
    if (effective.length === 0) {
      throw new Error('no effective semester: site current unknown and no override/selection');
    }
    this.logger.info(COURSE_SOURCE_LOG_DOMAIN + ' effective semester=' + effective
      + ' source=' + source);
    if (source === 'override') {
      // 覆盖生效时把"站点当前学期"也打出来，便于判读"确实切过去了"而不是本来就一样。
      this.logger.info(COURSE_SOURCE_LOG_DOMAIN + ' override active: siteCurrent='
        + resolution.currentSemesterId + ' effective=' + effective);
    }

    const list: CourseListResult = await this.courses.fetch(session, effective);
    const courseIds: string[] = Object.keys(list.names);
    if (list.courseCount === 0) {
      this.requireNonEmptyOrExplain(resolution, effective, source);
    }

    let notices: Notice[] = [];
    let assignments: Assignment[] = [];
    let files: CourseFile[] = [];
    if (courseIds.length > 0) {
      notices = await new NoticesFetcher(this.logger, this.port, session, list.names,
        this.decodeBase64).fetch(courseIds);
      assignments = await new AssignmentsFetcher(this.logger, this.port, session,
        list.names).fetch(courseIds);
      files = await new FilesFetcher(this.logger, this.port, session, list.names).fetch(courseIds);
    }

    const nowMillis: number = Date.now();
    const records: CourseRecord[] = buildCourseRecords(list.entries, notices, assignments, files, nowMillis);
    const noticeRecords: NoticeRecord[] = [];
    for (let i = 0; i < notices.length; i++) {
      noticeRecords.push(noticeRecordOf(notices[i]));
    }
    const semesters: string[] = this.semesterPickerList(resolution, effective);
    const snapshot: CourseSnapshot = {
      courses: records,
      notices: noticeRecords,
      assignments: assignments,
      files: files,
      semesterId: effective,
      siteCurrentSemesterId: resolution.currentSemesterId,
      semesterSource: source,
      semesters: semesters,
      semestersAvailable: resolution.listOk,
      fetchedAtMillis: nowMillis
    };
    this.logger.info(COURSE_SOURCE_LOG_DOMAIN + ' snapshot semester=' + effective
      + ' source=' + source + ' courses=' + records.length.toString()
      + ' notices=' + notices.length.toString()
      + ' assignments=' + assignments.length.toString()
      + ' files=' + files.length.toString()
      + ' semesters=' + semesters.length.toString()
      + ' semestersAvailable=' + resolution.listOk.toString());
    return snapshot;
  }

  /**
   * 0 门课时的判读：站点当前学期为空 ⇒ 抛错（失败信号）；显式切到别的学期 ⇒ 合法空态 + warn。
   */
  private requireNonEmptyOrExplain(resolution: SemesterResolution, effective: string,
    source: string): void {
    const isSiteCurrent: boolean = resolution.currentSemesterId.length > 0
      && effective === resolution.currentSemesterId;
    if (isSiteCurrent) {
      throw new Error('course list is EMPTY for the site current semester ' + effective
        + ' (source=' + source + '): this account has courses this semester,'
        + ' so an empty list means the fetch/degrade path is broken, not "no courses"');
    }
    this.logger.warn(COURSE_SOURCE_LOG_DOMAIN + ' course list empty for selected semester '
      + effective + ' (source=' + source + ' siteCurrent='
      + resolution.currentSemesterId + ') -> rendering the empty state');
  }

  /** 学期选择页的列表：优先站点集合；不可用时退化成"当前 + 生效"。 */
  private semesterPickerList(resolution: SemesterResolution, effective: string): string[] {
    if (resolution.semesters.length > 0) {
      return resolution.semesters;
    }
    const fallback: string[] = [];
    if (resolution.currentSemesterId.length > 0) {
      fallback.push(resolution.currentSemesterId);
    }
    if (effective.length > 0 && effective !== resolution.currentSemesterId) {
      fallback.push(effective);
    }
    return sortSemesterIds(fallback, 'desc');
  }
}