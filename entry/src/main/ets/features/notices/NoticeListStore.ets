/*
 * 公告列表的界面状态（spec.md 第 3 节：@ObservedV2 / @Trace，视图直接读）。
 *
 * 视图不碰 Repository 的调用时序：它只读这里的 @Trace 字段。取数、快照先后
 * 顺序（先 loadSnapshot() 再 refresh()）都封在这里，ticket 09 换成真实实现时
 * 这一段不用动。
 */
import { Logger } from '../../core/log/Logger';
import { countUnread, isNoticeListEmpty, sortNoticesDesc } from './NoticeOrder';
import { NoticeRecord, NoticeRepository, NoticeSnapshot } from './repository/NoticeRepository';

const logger: Logger = new Logger('features.notices.store');

/** 列表加载阶段。 */
export enum NoticeLoadPhase {
  /** 还没开始取数。 */
  IDLE = 'idle',
  /** 首次加载（本地无快照）。 */
  LOADING = 'loading',
  /** 下拉刷新 / 后台刷新。 */
  REFRESHING = 'refreshing',
  /** 有数据（或空集合）且不在取数。 */
  READY = 'ready',
  /** 取数失败。 */
  ERROR = 'error'
}

@ObservedV2
export class NoticeListStore {
  @Trace items: NoticeRecord[] = [];
  @Trace phase: NoticeLoadPhase = NoticeLoadPhase.IDLE;
  @Trace fetchedAtMillis: number = 0;
  @Trace fromSnapshot: boolean = false;
  @Trace errorMessage: string = '';

  private readonly repository: NoticeRepository;
  private started: boolean = false;

  constructor(repository: NoticeRepository) {
    this.repository = repository;
  }

  /** 是否正在取数（首次加载或刷新）。 */
  isBusy(): boolean {
    return this.phase === NoticeLoadPhase.LOADING || this.phase === NoticeLoadPhase.REFRESHING;
  }

  /** 空态：没有数据且不在取数（见 NoticeOrder.isNoticeListEmpty）。 */
  isEmpty(): boolean {
    return isNoticeListEmpty(this.items, this.isBusy());
  }

  /** 未读条数。 */
  unreadCount(): number {
    return countUnread(this.items);
  }

  /** 首次进入：先读快照（可能没有），再后台刷新。只跑一次。 */
  async loadOnce(): Promise<void> {
    if (this.started) {
      return;
    }
    this.started = true;
    this.phase = NoticeLoadPhase.LOADING;
    try {
      const snapshot: NoticeSnapshot | null = await this.repository.loadSnapshot();
      if (snapshot !== null) {
        this.apply(snapshot);
        logger.info('snapshot applied: count=' + snapshot.items.length.toString());
      }
    } catch (error) {
      // 快照读失败不致命：下面的 refresh() 还有机会拿到数据。
      logger.warn('loadSnapshot failed: ' + (error as Error).message);
    }
    await this.refresh();
  }

  /** 下拉刷新（也用于首次加载后的后台刷新）。失败时保留旧数据。 */
  async refresh(): Promise<void> {
    if (this.phase !== NoticeLoadPhase.LOADING) {
      this.phase = NoticeLoadPhase.REFRESHING;
    }
    try {
      const snapshot: NoticeSnapshot = await this.repository.refresh();
      this.apply(snapshot);
      this.phase = NoticeLoadPhase.READY;
      logger.info('refresh done: count=' + snapshot.items.length.toString()
        + ' unread=' + this.unreadCount().toString());
    } catch (error) {
      this.errorMessage = (error as Error).message;
      this.phase = NoticeLoadPhase.ERROR;
      logger.error('refresh failed: ' + this.errorMessage);
    }
  }

  /** 落地一个快照：仍按发布时间倒序排一次（对齐参考实现 action 的排序）。 */
  private apply(snapshot: NoticeSnapshot): void {
    this.items = sortNoticesDesc(snapshot.items);
    this.fetchedAtMillis = snapshot.fetchedAtMillis;
    this.fromSnapshot = snapshot.fromSnapshot;
    this.errorMessage = '';
  }
}
