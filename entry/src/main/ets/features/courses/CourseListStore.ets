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
 *
 * **进程内单例**（见 CourseListStoreProvider）：学期选择与课程列表是同一份状态，
 * 参考实现把它放在全局 redux state 里。各页面各持一份会让"在设置里切的学期"
 * 只有设置页知道，课程 tab 仍按站点当前学期取数。
 *
 * **切换学期不阻塞点击**：selectSemester 同步记下选择（勾选标记与文案立刻可读），
 * 整轮取数在后台跑完再由 @Trace 推给所有读它的页面。
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
  /**
   * 正在应用的界面选择（空串 = 没有在途切换）。
   * 与 `semesterId`（**实际生效**值，来自已完成的快照）分开：切换在途时界面据此
   * 立刻把勾选标记挪到新选的那一行，而列表内容仍显示旧快照直到新快照落地。
   */
  @Trace pendingSemesterId: string = '';

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
    } finally {
      // 在途标记只在这**一轮取数**期间有效：成功则 semesterId 已换成新值，
      // 失败则保留旧值并由 errorMessage 显式降级——两种情况下都不能再算"在途"。
      this.pendingSemesterId = '';
    }
  }

  /**
   * 切换当前学期：**同步**记下选择并立刻返回，整轮重抓在后台跑。
   *
   * 为什么不 await：一轮 refresh 要串行取"学期集合 + 课程列表 + 三域内容"，
   * 耗时以秒计（实测切到 2025-2026 春季是 7.0 s）。点击若等它跑完才更新勾选
   * 标记 / 返回，用户看到的就是"点一下卡住好几秒"。选择是纯状态写入，
   * 没有理由等网络。
   *
   * 返回重抓的完成，**供调用方按需等待**（界面点击点不该等）；失败时保留旧列表
   * （errorMessage 里带原因），不假装切换成功。
   */
  selectSemester(semesterId: string): Promise<void> {
    logger.info('semester selected: ' + semesterId);
    this.selectedSemesterId = semesterId;
    this.pendingSemesterId = semesterId;
    logger.info('semester selection applied: ' + semesterId);
    return this.refresh();
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