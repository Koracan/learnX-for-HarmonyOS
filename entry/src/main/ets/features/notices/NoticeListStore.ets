/*
 * 公告列表的界面状态（@ObservedV2 / @Trace，视图直接读）。
 *
 * 视图不碰 Repository 的调用时序：它只读这里的 @Trace 字段。取数、快照先后
 * 顺序（先 loadSnapshot() 再 refresh()）都封在这里，换成真实实现时
 * 这一段不用动。
 */
import { Logger } from '../../core/log/Logger';
import { countUnread, isNoticeListEmpty, sortNoticesDesc } from './NoticeOrder';
import { NoticeRecord, NoticeRepository, NoticeSnapshot } from '../../data/notices/NoticeRepository';

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

  /**
   * 是否应当显示「居中加载指示器」：只在首次加载且还没有任何数据时。
   *
   * 下拉刷新（phase=REFRESHING）不能再叠一个居中 spinner：参考实现刷新时只有
   * RefreshControl 自己的指示器、列表照常可见，两个指示器同转会像卡了个浮层。
   * 这个缺陷在验收时被抓到（当时做了「验收后修复」）。
   */
  isInitialLoading(): boolean {
    return this.phase === NoticeLoadPhase.LOADING && this.items.length === 0;
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

  /**
   * 下拉刷新（也用于首次加载后的后台刷新）。失败时保留旧数据。
   *
   * **返回本轮是否成功**：学期切换的编排据此汇总「哪个域失败」，不去读 errorMessage
   * （并发的另一次成功取数会把它清空）。
   */
  async refresh(): Promise<boolean> {
    if (this.phase !== NoticeLoadPhase.LOADING) {
      this.phase = NoticeLoadPhase.REFRESHING;
    }
    try {
      const snapshot: NoticeSnapshot = await this.repository.refresh();
      this.apply(snapshot);
      this.phase = NoticeLoadPhase.READY;
      logger.info('refresh done: count=' + snapshot.items.length.toString()
        + ' unread=' + this.unreadCount().toString());
      return true;
    } catch (error) {
      this.errorMessage = (error as Error).message;
      this.phase = NoticeLoadPhase.ERROR;
      logger.error('refresh failed: ' + this.errorMessage);
      return false;
    }
  }

  /**
   * 记下"这一条已经打开过"：先把界面上的这一条换成一个已读的**新记录**，
   * 再把整个列表赋回去（蓝点与未读数立刻跟着变），最后交给数据源写进快照。
   *
   * 为什么要换新对象、而不是就地改 `item.hasRead`：`@Trace` 只看得到**被追踪字段本身**
   * 的赋值。就地改数组元素里的属性不会通知视图，界面会停在旧画面上
   * （实测：日志说已读、蓝点还在）。所以这里重建数组里的那一条，再赋值给 @Trace 字段。
   *
   * 界面先行是**有意**的：落盘是异步的、也可能失败，但用户刚点开这一条，
   * 蓝点不该等到磁盘确认才消失。写盘失败只记日志，下一次刷新会带着集合重写。
   */
  async markRead(noticeId: string): Promise<void> {
    let changed: boolean = false;
    const next: NoticeRecord[] = [];
    for (let i = 0; i < this.items.length; i++) {
      const item: NoticeRecord = this.items[i];
      if (item.id === noticeId && !item.hasRead) {
        const read: NoticeRecord = {
          id: item.id,
          title: item.title,
          content: item.content,
          publisher: item.publisher,
          courseId: item.courseId,
          courseName: item.courseName,
          courseTeacherName: item.courseTeacherName,
          publishTimeMillis: item.publishTimeMillis,
          hasRead: true,
          markedImportant: item.markedImportant,
          url: item.url
        };
        if (item.attachment !== undefined) {
          read.attachment = item.attachment;
        }
        next.push(read);
        changed = true;
      } else {
        next.push(item);
      }
    }
    if (changed) {
      this.items = next;
      logger.info('notice marked read: id=' + noticeId
        + ' unread=' + this.unreadCount().toString());
    }
    try {
      await this.repository.markRead(noticeId);
    } catch (error) {
      logger.warn('markRead persist failed: id=' + noticeId + ' ' + (error as Error).message);
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
