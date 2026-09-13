/*
 * 课程 tab 的界面状态（@ObservedV2 / @Trace，视图直接读）。
 *
 * 一次 refresh 拿到**课程 + 三域内容 + 学期集合**（CourseSnapshot），三处界面都读它：
 *   - 课程列表（courses + 三类计数）；
 *   - 课程详情的三个标签页（notices / assignments / files 按 courseId 过滤）；
 *   - 学期切换页（semesters + 当前生效的 semesterId）。
 *
 * 界面不碰取数时序：失败**不吞**，进 errorMessage 并由界面显式显示
 * （对齐"失败一律显式降级，绝不静默显示空列表"）。
 */

import { Logger } from '../../core/log/Logger';
import { Assignment, CourseFile } from '../../domain/model/ContentItem';
import { NoticeRecord } from '../../data/notices/NoticeRepository';
import { CourseRecord, CourseRepository, CourseSnapshot } from '../../data/courses/CourseRepository';

const logger: Logger = new Logger('features.courses.store');

/** 列表加载阶段。 */
export enum CourseLoadPhase {
  IDLE = 'idle',
  LOADING = 'loading',
  REFRESHING = 'refreshing',
  READY = 'ready',
  ERROR = 'error'
}

@ObservedV2
export class CourseListStore {
  @Trace courses: CourseRecord[] = [];
  @Trace notices: NoticeRecord[] = [];
  @Trace assignments: Assignment[] = [];
  @Trace files: CourseFile[] = [];
  @Trace phase: CourseLoadPhase = CourseLoadPhase.IDLE;
  @Trace semesterId: string = '';
  @Trace siteCurrentSemesterId: string = '';
  @Trace semesterSource: string = '';
  @Trace semesters: string[] = [];
  @Trace semestersAvailable: boolean = false;
  @Trace fetchedAtMillis: number = 0;
  @Trace errorMessage: string = '';
  /** 界面选择的学期（空串 = 交给覆盖开关 / 站点当前学期）。 */
  @Trace selectedSemesterId: string = '';

  private readonly repository: CourseRepository;
  private started: boolean = false;

  constructor(repository: CourseRepository) {
    this.repository = repository;
  }

  isBusy(): boolean {
    return this.phase === CourseLoadPhase.LOADING || this.phase === CourseLoadPhase.REFRESHING;
  }

  /** 只在"首次加载且还没有任何数据"时显示居中指示器（与公告列表同一规则）。 */
  isInitialLoading(): boolean {
    return this.phase === CourseLoadPhase.LOADING && this.courses.length === 0;
  }

  /** 空态：没有课程且不在取数、也没有错误。 */
  isEmpty(): boolean {
    return this.courses.length === 0 && !this.isBusy() && this.phase !== CourseLoadPhase.ERROR;
  }

  hasError(): boolean {
    return this.phase === CourseLoadPhase.ERROR;
  }

  /** 首次进入：抓一次。只跑一次（切 tab 不重抓）。 */
  async loadOnce(): Promise<void> {
    if (this.started) {
      return;
    }
    this.started = true;
    this.phase = CourseLoadPhase.LOADING;
    await this.refresh();
  }

  /** 下拉刷新；使用当前的选择。失败保留旧数据并置错误态。 */
  async refresh(): Promise<void> {
    if (this.phase !== CourseLoadPhase.LOADING) {
      this.phase = CourseLoadPhase.REFRESHING;
    }
    try {
      const snapshot: CourseSnapshot = await this.repository.refresh(this.selectedSemesterId);
      this.apply(snapshot);
      this.phase = CourseLoadPhase.READY;
      this.errorMessage = '';
    } catch (error) {
      this.errorMessage = (error as Error).message;
      this.phase = CourseLoadPhase.ERROR;
      const rawStack: string | undefined = (error as Error).stack;
      const stack: string = rawStack === undefined ? 'n/a' : rawStack;
      logger.error('course refresh failed: ' + this.errorMessage + ' stack=' + stack);
    }
  }

  /**
   * 切换当前学期：记下选择并立刻重抓（切换后课程列表随之更新）。
   * 失败时**保留旧列表**（调用方看错误提示），不假装切换成功。
   */
  async selectSemester(semesterId: string): Promise<void> {
    logger.info('semester selected: ' + semesterId);
    this.selectedSemesterId = semesterId;
    await this.refresh();
  }

  /** 该课程的公告（详情页第一个标签页）。 */
  noticesFor(courseId: string): NoticeRecord[] {
    const out: NoticeRecord[] = [];
    for (const item of this.notices) {
      if (item.courseId === courseId) {
        out.push(item);
      }
    }
    return out;
  }

  assignmentsFor(courseId: string): Assignment[] {
    const out: Assignment[] = [];
    for (const item of this.assignments) {
      if (item.courseId === courseId) {
        out.push(item);
      }
    }
    return out;
  }

  filesFor(courseId: string): CourseFile[] {
    const out: CourseFile[] = [];
    for (const item of this.files) {
      if (item.courseId === courseId) {
        out.push(item);
      }
    }
    return out;
  }

  private apply(snapshot: CourseSnapshot): void {
    this.courses = snapshot.courses;
    this.notices = snapshot.notices;
    this.assignments = snapshot.assignments;
    this.files = snapshot.files;
    this.semesterId = snapshot.semesterId;
    this.siteCurrentSemesterId = snapshot.siteCurrentSemesterId;
    this.semesterSource = snapshot.semesterSource;
    this.semesters = snapshot.semesters;
    this.semestersAvailable = snapshot.semestersAvailable;
    this.fetchedAtMillis = snapshot.fetchedAtMillis;
    // 取证要点：把**实际生效**的学期与来源打进 hilog（"没抓到"与"没生效"必须能区分）。
    logger.info('course list applied: semester=' + snapshot.semesterId
      + ' source=' + snapshot.semesterSource
      + ' siteCurrent=' + snapshot.siteCurrentSemesterId
      + ' courses=' + snapshot.courses.length.toString()
      + ' semesters=' + snapshot.semesters.length.toString()
      + ' semestersAvailable=' + snapshot.semestersAvailable.toString());
  }
}