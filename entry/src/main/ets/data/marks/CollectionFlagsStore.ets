/*
 * 收藏 / 归档 / 隐藏课程的状态 store（data/marks）—— 界面只读这里的 @Trace 字段。
 *
 * ## 为什么是"一个 store + 四个列表共享"
 *
 * 参考实现把四个域放进同一个 redux state，`hidden` 落在 courses 域、而公告/作业/文件
 * 三个 selector 都读它（`data/selectors/filteredData.ts:20,74,108,144`）—— 也就是
 * "在课程页屏蔽一门课"必须立刻影响另外三个列表。若每个页面各持一份状态，这一点做不到。
 * 因此这里做成**进程内单例**（组装点见 features/marks/CollectionFlagsProvider）。
 *
 * ## 持久化
 *
 * 一个 preferences 键、一段 JSON（编解码是纯函数，见 domain/marks/CollectionFlagsCodec）。
 * 参考实现是 redux-persist + AsyncStorage（`data/reducers/root.ts:96-118` 的 whitelist
 * 含 favorites / archived / items，课程 whitelist 含 hidden）——**本工程不引入 redux-persist**，
 * 沿用本仓库既有的 preferences 快照做法（data/settings/PreferencesFileSettings、
 * data/notices/NoticeSnapshotFileStore）。
 *
 * 失败一律**不抛**：收藏状态写不进去只应表现为"这次没记住"，不该让列表页崩。
 * 但失败会进 hilog（error）与 errorMessage。
 */

import { Logger } from '../../core/log/Logger';
import { ContentFilter } from '../../domain/marks/ContentFilter';
import {
  CollectionFlags, DEFAULT_TAB_FILTER_SELECTIONS, MarksDomain, MarksTab, TabFilterSelections,
  copyTabFilterSelections, describeCollectionFlags, emptyCollectionFlags, tabFilterOf,
  withArchived, withFavorite, withHiddenCourse, withTabFilter
} from '../../domain/marks/CollectionFlags';
import {
  FlagsDecodeResult, decodeCollectionFlags, encodeCollectionFlags
} from '../../domain/marks/CollectionFlagsCodec';

const logger: Logger = new Logger('data.marks.store');

/**
 * 持久化端口：读写**一段 JSON 文本**（设备侧是 preferences，测试里是内存替身）。
 * 返回 null = "没保存过"（读失败与没保存过同义：状态回到默认值）。
 */
export interface CollectionFlagsPort {
  load(): Promise<string | null>;
  save(payload: string): Promise<boolean>;
}

/** 内存实现（测试 / Context 不可用时的降级：状态仍生效，只是不落盘）。 */
export class InMemoryCollectionFlagsPort implements CollectionFlagsPort {
  private payload: string | null = null;

  async load(): Promise<string | null> {
    return this.payload;
  }

  async save(payload: string): Promise<boolean> {
    this.payload = payload;
    return true;
  }
}

@ObservedV2
export class CollectionFlagsStore {
  @Trace noticeFavorites: string[] = [];
  @Trace noticeArchived: string[] = [];
  @Trace assignmentFavorites: string[] = [];
  @Trace assignmentArchived: string[] = [];
  @Trace fileFavorites: string[] = [];
  @Trace fileArchived: string[] = [];
  @Trace hiddenCourseIds: string[] = [];
  /** 四个列表各自记住的过滤视图（参考实现 settings.tabFilterSelections）。 */
  @Trace tabFilters: TabFilterSelections = copyTabFilterSelections(DEFAULT_TAB_FILTER_SELECTIONS);
  /** 是否已经从持久层读过一次。 */
  @Trace loaded: boolean = false;
  /** 读取被丢弃 / 写入失败时的原因（空串 = 无异常）。 */
  @Trace errorMessage: string = '';

  private readonly port: CollectionFlagsPort;
  private startPromise: Promise<void> | null = null;

  constructor(port: CollectionFlagsPort) {
    this.port = port;
  }

  /** 首次进入：读一次持久层（幂等；四个页面都会调）。 */
  loadOnce(): Promise<void> {
    if (this.startPromise === null) {
      this.startPromise = this.doLoad();
    }
    return this.startPromise;
  }

  private async doLoad(): Promise<void> {
    try {
      const payload: string | null = await this.port.load();
      if (payload === null) {
        logger.info('collection flags load: absent -> defaults');
      } else {
        const decoded: FlagsDecodeResult = decodeCollectionFlags(payload);
        if (decoded.discardReason.length > 0) {
          this.errorMessage = decoded.discardReason;
          logger.warn('collection flags load: discarded reason=' + decoded.discardReason);
        } else {
          this.applyFlags(decoded.flags);
          this.tabFilters = copyTabFilterSelections(decoded.tabFilters);
          // 消费点自证：把**实际生效**的收藏/归档/屏蔽打进 hilog（AGENTS.md 的取证要求）。
          logger.info('collection flags applied: source=stored '
            + describeCollectionFlags(decoded.flags)
            + ' tabs=notice:' + decoded.tabFilters.notice.toString()
            + ',assignment:' + decoded.tabFilters.assignment.toString()
            + ',file:' + decoded.tabFilters.file.toString()
            + ',course:' + decoded.tabFilters.course.toString());
        }
      }
    } catch (error) {
      this.errorMessage = (error as Error).message;
      logger.error('collection flags load failed: ' + this.errorMessage);
    }
    this.loaded = true;
  }

  /** 当前状态的副本（持久化与日志用）。 */
  snapshot(): CollectionFlags {
    return {
      noticeFavorites: this.noticeFavorites.slice(),
      noticeArchived: this.noticeArchived.slice(),
      assignmentFavorites: this.assignmentFavorites.slice(),
      assignmentArchived: this.assignmentArchived.slice(),
      fileFavorites: this.fileFavorites.slice(),
      fileArchived: this.fileArchived.slice(),
      hiddenCourseIds: this.hiddenCourseIds.slice()
    };
  }

  /** 某个列表当前生效的过滤视图（未记过时是参考实现的默认值）。 */
  filterFor(tab: MarksTab): ContentFilter {
    return tabFilterOf(this.tabFilters, tab);
  }

  /** 记住某个列表的过滤视图并写回（参考实现 setSetting('tabFilterSelections', …)）。 */
  async selectFilter(tab: MarksTab, filter: ContentFilter): Promise<void> {
    this.tabFilters = withTabFilter(this.tabFilters, tab, filter);
    logger.info('tab filter selected: tab=' + tab.toString() + ' filter=' + filter.toString());
    await this.persist('tab-filter');
  }

  /** 收藏置真 / 置假（flag 语义与参考实现 `setFavNotice(id, flag)` 相同）。 */
  async setFavorite(domain: MarksDomain, id: string, flag: boolean): Promise<void> {
    const next: CollectionFlags = withFavorite(this.snapshot(), domain, id, flag);
    this.applyFlags(next);
    logger.info('favorite set: domain=' + domain.toString() + ' id=' + id
      + ' flag=' + flag.toString() + ' ' + describeCollectionFlags(next));
    await this.persist('favorite');
  }

  /** 归档置真 / 置假（参考实现的 action 收 id 数组，界面每次只传一条）。 */
  async setArchived(domain: MarksDomain, ids: string[], flag: boolean): Promise<void> {
    const next: CollectionFlags = withArchived(this.snapshot(), domain, ids, flag);
    this.applyFlags(next);
    logger.info('archive set: domain=' + domain.toString() + ' ids=' + ids.length.toString()
      + ' flag=' + flag.toString() + ' ' + describeCollectionFlags(next));
    await this.persist('archive');
  }

  /** 屏蔽 / 取消屏蔽一门课（参考实现 setHideCourse(courseId, flag)）。 */
  async setHidden(courseId: string, flag: boolean): Promise<void> {
    const next: CollectionFlags = withHiddenCourse(this.snapshot(), courseId, flag);
    this.applyFlags(next);
    logger.info('hide course set: courseId=' + courseId + ' flag=' + flag.toString()
      + ' ' + describeCollectionFlags(next));
    await this.persist('hide');
  }

  private applyFlags(flags: CollectionFlags): void {
    this.noticeFavorites = flags.noticeFavorites;
    this.noticeArchived = flags.noticeArchived;
    this.assignmentFavorites = flags.assignmentFavorites;
    this.assignmentArchived = flags.assignmentArchived;
    this.fileFavorites = flags.fileFavorites;
    this.fileArchived = flags.fileArchived;
    this.hiddenCourseIds = flags.hiddenCourseIds;
  }

  /** 写回持久层；失败不抛，只记日志。 */
  private async persist(reason: string): Promise<boolean> {
    const payload: string = encodeCollectionFlags(this.snapshot(),
      copyTabFilterSelections(this.tabFilters));
    try {
      const ok: boolean = await this.port.save(payload);
      if (!ok) {
        this.errorMessage = 'save_failed';
        logger.error('collection flags save failed: reason=' + reason
          + ' chars=' + payload.length.toString());
      } else {
        logger.info('collection flags save ok: reason=' + reason
          + ' chars=' + payload.length.toString());
      }
      return ok;
    } catch (error) {
      this.errorMessage = (error as Error).message;
      logger.error('collection flags save failed: reason=' + reason
        + ' message=' + this.errorMessage);
      return false;
    }
  }
}
