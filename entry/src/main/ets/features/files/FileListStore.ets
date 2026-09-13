/*
 * 文件 tab 的界面状态（@ObservedV2 / @Trace，视图直接读）。
 *
 * 与 `CourseListStore` 同一形状，但只装"文件列表"这一件事：文件 tab 有自己的取数
 * （学期 → 课程列表 → 文件），不重复抓公告与作业（见 data/files/FileRepository 的说明）。
 *
 * 失败**不吞**：进 `errorMessage` 并由界面显式显示（对齐
 * "失败一律显式降级，绝不静默显示空列表"）。
 */

import { Logger } from '../../core/log/Logger';
import { CourseFile } from '../../domain/model/ContentItem';
import { FileRepository, FileSnapshot } from '../../data/files/FileRepository';

const logger: Logger = new Logger('features.files.store');

/** 列表加载阶段。 */
export enum FileLoadPhase {
  IDLE = 'idle',
  LOADING = 'loading',
  REFRESHING = 'refreshing',
  READY = 'ready',
  ERROR = 'error'
}

@ObservedV2
export class FileListStore {
  @Trace files: CourseFile[] = [];
  @Trace phase: FileLoadPhase = FileLoadPhase.IDLE;
  @Trace semesterId: string = '';
  @Trace fetchedAtMillis: number = 0;
  @Trace errorMessage: string = '';

  private readonly repository: FileRepository;
  private started: boolean = false;

  constructor(repository: FileRepository) {
    this.repository = repository;
  }

  isBusy(): boolean {
    return this.phase === FileLoadPhase.LOADING || this.phase === FileLoadPhase.REFRESHING;
  }

  /** 只在"首次加载且还没有任何数据"时显示居中指示器（与公告/课程列表同一规则）。 */
  isInitialLoading(): boolean {
    return this.phase === FileLoadPhase.LOADING && this.files.length === 0;
  }

  /** 空态：没有文件、不在取数、也没有错误。 */
  isEmpty(): boolean {
    return this.files.length === 0 && !this.isBusy() && this.phase !== FileLoadPhase.ERROR;
  }

  hasError(): boolean {
    return this.phase === FileLoadPhase.ERROR;
  }

  /** 首次进入：抓一次（切 tab 不重抓）。 */
  async loadOnce(): Promise<void> {
    if (this.started) {
      return;
    }
    this.started = true;
    this.phase = FileLoadPhase.LOADING;
    await this.refresh();
  }

  /**
   * 下拉刷新；失败保留旧数据并置错误态。
   *
   * **返回本轮是否成功**：学期切换的编排据此汇总「哪个域失败」，不去读 errorMessage。
   */
  async refresh(): Promise<boolean> {
    if (this.phase !== FileLoadPhase.LOADING) {
      this.phase = FileLoadPhase.REFRESHING;
    }
    try {
      const snapshot: FileSnapshot = await this.repository.refresh();
      this.files = snapshot.files;
      this.semesterId = snapshot.semesterId;
      this.fetchedAtMillis = snapshot.fetchedAtMillis;
      this.phase = FileLoadPhase.READY;
      this.errorMessage = '';
      logger.info('file list applied: semester=' + snapshot.semesterId
        + ' items=' + snapshot.files.length.toString());
      return true;
    } catch (error) {
      this.errorMessage = (error as Error).message;
      this.phase = FileLoadPhase.ERROR;
      logger.error('file refresh failed: ' + this.errorMessage);
      return false;
    }
  }
}
