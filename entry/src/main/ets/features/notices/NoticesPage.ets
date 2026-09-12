/*
 * 公告（Notice）tab：真实数据源之上的列表页 + 详情栈的根（ticket 03/04）。
 *
 * 分工：
 *   - 数据与阶段在 NoticeListStore（@ObservedV2/@Trace），本组件只读；
 *   - 取色一律 resolveTheme()，文案一律走资源；
 *   - 时间用 core/i18n 的 formatRelativeTo（与参考实现 NoticeCard 的
 *     dayjs(publishTime).fromNow() 对齐），拿不到 ICU 措辞时退回绝对时间。
 *
 * 导航（ticket 04，接 ticket 03 的选型「每个 tab 一个 NavPathStack」）：
 *   本组件的 `Navigation` 就是这个 tab 的栈：列表是**根内容**，公告详情是
 *   `NavDestination`。这样切到别的 tab 再切回来时，栈（含正打开的详情页）原样保留，
 *   与参考实现"每 tab 一个 stack"一致。详情页只读列表项本身，不做二次取数
 *   （对应参考实现 `navigation.push('NoticeDetail', notice)`）。
 *
 * 界面只依赖 NoticeRepository 接口（经 createNoticeRepository() 注入）。
 *
 * 【ticket 09】数据源已从 Mock 换成真实仓库（data/notices/RealNoticeRepository）。
 * 【ticket 14】加了收藏 / 归档 / 屏蔽：过滤条 + 滑动操作 + 撤销 Toast。
 *   - 过滤语义逐行对齐参考实现 data/selectors/filteredData.ts（见 features/marks/FilteredContent）；
 *   - `未读 n` 从页头**移到过滤条**：参考实现的未读数就是 FilterList / Filter 上的角标
 *     （components/FilterList.tsx:246、Filter.tsx:181-187），页头没有这个元素 ——
 *     同一信息不再两处显示（对账结论见 ticket 14 交付）。
 */
import { ConfigurationConstant } from '@kit.AbilityKit';
import { PLAIN_PALETTE, ThemeTokens, resolveTheme } from '../../ui/theme/Tokens';
import { i18nService } from '../../core/i18n/I18n';
import { formatDateTimeShort, formatRelativeTo } from '../../core/i18n/DateTimeUtil';
import { Logger } from '../../core/log/Logger';
import { COLOR_MODE_KEY, LOCALE_VERSION_KEY } from '../../entryability/EntryAbility';
import { EmptyState } from '../../ui/components/EmptyState';
import { FilterChip } from '../../ui/components/FilterChip';
import { ToastController, ToastOverlay } from '../../ui/components/Toast';
import { ContentSwipeActions } from '../../ui/components/SwipeActions';
import { AppIcon } from '../../ui/icons/IconCatalog';
import { IconGlyph } from '../../ui/icons/IconGlyph';
import { updatedTimeText } from '../../ui/components/UpdatedTime';
import { SessionHeaderProvider, createSessionHeaderProvider, logSessionHeaderState } from '../../core/web/SessionHeaderProvider';
import { ContentFilter } from '../../domain/marks/ContentFilter';
import { MarksDomain, MarksTab } from '../../domain/marks/CollectionFlags';
import { isUnread } from './NoticeOrder';
import { removeTags } from '../../domain/render/WebViewTemplate';
import { NoticeListStore } from './NoticeListStore';
import { NoticeRecord } from '../../data/notices/NoticeRepository';
import { createNoticeRepository } from './repository/NoticeRepositoryProvider';
import { CollectionFlagsStore } from '../../data/marks/CollectionFlagsStore';
import { collectionFlagsStore } from '../marks/CollectionFlagsProvider';
import {
  FilteredNotices, NoticeFilterCounts, isInGroupNotices, noticeCounts, noticesForFilter,
  selectFilteredNotices
} from '../marks/FilteredContent';
import { FileDetailPage } from '../files/FileDetailPage';
import { FileDetailRouteParams, ROUTE_FILE_DETAIL, ROUTE_NOTICE_DETAIL } from './NoticeRoutes';
import { NoticeDetailPage } from './NoticeDetailPage';

const logger: Logger = new Logger('features.notices');

/** 单行公告的渲染参数；@Builder 按引用传参（见 ticket 01 Comments 的教训）。 */
interface NoticeRowSpec {
  theme: ThemeTokens;
  notice: NoticeRecord;
  timeText: string;
  /** 已经过 removeTags 的标题（去注释/去标签/解码实体/折叠空白）。 */
  titleText: string;
  /** 已经过 removeTags 的正文预览；空串表示没有正文。 */
  contentText: string;
  /** 状态图标的无障碍文案（参考实现在图标上有 name，本工程的矢量图标同样需要它）。 */
  attachmentLabel: string;
  importantLabel: string;
}

@Component
export struct NoticesPage {
  /** 系统配色，EntryAbility 写入；变化时本组件重建。 */
  @StorageProp(COLOR_MODE_KEY) colorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  /** 语言版本号；变化时本组件重建并重新取串。 */
  @StorageLink(LOCALE_VERSION_KEY) localeVersion: number = 0;
  /** Refresh 组件自身的两态绑定。 */
  @State refreshing: boolean = false;
  /** 当前过滤视图（初值 = 参考实现 settings.ts:24-29 的 notice 默认值 all）。 */
  @State filter: ContentFilter = ContentFilter.ALL;

  private store: NoticeListStore = new NoticeListStore(createNoticeRepository());
  /** 进程内单例：屏蔽一门课要同时影响公告 / 作业 / 文件三个列表。 */
  private flags: CollectionFlagsStore = collectionFlagsStore();
  private toast: ToastController = new ToastController();
  private listScroller: Scroller = new Scroller();
  /** 公告 tab 自己的导航栈（ticket 04）。 */
  private stack: NavPathStack = new NavPathStack();
  /** Web 容器的会话注入端口（Mock 阶段是空实现，见 core/web/SessionHeaderProvider.ets）。 */
  private session: SessionHeaderProvider = createSessionHeaderProvider();

  aboutToAppear(): void {
    this.store.loadOnce();
    this.loadFlags();
    // 把会话端口的**实际生效值**打进 hilog：取证时"没抓到"与"端口没接上"必须能区分。
    logSessionHeaderState(this.session);
    logger.info('notices page appear');
  }

  /** 读一次收藏状态，并恢复记住的过滤视图；消费点自证打在 `notices applied` 行。 */
  private async loadFlags(): Promise<void> {
    await this.flags.loadOnce();
    this.filter = this.flags.filterFor(MarksTab.NOTICE);
    this.logApplied('initial');
  }

  private theme(): ThemeTokens {
    return resolveTheme(this.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
  }

  private isDark(): boolean {
    return this.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  }

  /** UI 取串入口：与 $r 同一资源，但走逻辑层门面，便于语言变化后重取。 */
  private s(resource: Resource): string {
    return i18nService.tKey(resource);
  }

  /** 相对时间优先，措辞不可用时退回绝对时间。 */
  private timeTextOf(notice: NoticeRecord): string {
    const locale: string = i18nService.locale();
    const relative: string = formatRelativeTo(notice.publishTimeMillis, Date.now(), locale);
    if (relative.length > 0) {
      return relative;
    }
    return formatDateTimeShort(notice.publishTimeMillis, locale);
  }

  /**
   * 页头那一行"相对更新时间"（ticket 11.5 Part B）：`刚刚更新` / `N 分钟前更新` / …。
   * 原来的"更新于 HH:mm:ss · N 分钟前"是**绝对时间 + ICU 相对措辞**两段拼接；
   * 账号所有者裁定只保留相对措辞，四档边界在 `ui/components/UpdatedTime.ets`（有单测）。
   */
  private updatedText(): string {
    return updatedTimeText(this.store.fetchedAtMillis, Date.now());
  }

  /* ------------------------------------------------------------------ *
   * ticket 14：收藏 / 归档 / 屏蔽
   * ------------------------------------------------------------------ */

  /** 原始条目（收藏 / 归档 / 屏蔽三个标记作用在它之上）。 */
  private sourceItems(): NoticeRecord[] {
    return this.store.items;
  }

  /** 过滤后的五个分组（逐行对齐参考实现 selectFilteredNotices）。 */
  private filtered(): FilteredNotices {
    return selectFilteredNotices(this.sourceItems(), this.flags.noticeFavorites,
      this.flags.noticeArchived, this.flags.hiddenCourseIds);
  }

  /** 当前视图可见的条目。 */
  private visibleItems(): NoticeRecord[] {
    return noticesForFilter(this.filtered(), this.filter);
  }

  private counts(): NoticeFilterCounts {
    return noticeCounts(this.filtered());
  }

  /**
   * 消费点自证：把**实际生效**的过滤视图、五组计数与收藏/归档/屏蔽的原始 id 数打进 hilog。
   * （AGENTS.md：开关自证要打在消费点，只在设置点打一行不足以证明到达了每条数据路径。）
   */
  private logApplied(reason: string): void {
    const counts: NoticeFilterCounts = this.counts();
    logger.info('notices applied: reason=' + reason
      + ' filter=' + this.filter.toString()
      + ' items=' + this.sourceItems().length.toString()
      + ' all=' + counts.all.toString()
      + ' unread=' + counts.unread.toString()
      + ' fav=' + counts.fav.toString()
      + ' archived=' + counts.archived.toString()
      + ' hidden=' + counts.hidden.toString()
      + ' favoriteIds=' + this.flags.noticeFavorites.length.toString()
      + ' archivedIds=' + this.flags.noticeArchived.length.toString()
      + ' hiddenCourses=' + this.flags.hiddenCourseIds.length.toString());
  }

  /** 收藏 / 取消收藏（flag 语义与参考实现 FilterList.tsx:119-139 逐行对应）。 */
  private handleFav(item: NoticeRecord, isFav: boolean): void {
    this.flags.setFavorite(MarksDomain.NOTICE, item.id, !isFav);
    if (isFav) {
      // 参考实现：取消收藏 → `removeFromFav` + 撤销（撤销即重新收藏）。
      this.toast.show(this.s($r('app.string.loh_remove_from_fav')), '', null);
    } else {
      this.toast.show(this.s($r('app.string.loh_add_to_fav')), this.s($r('app.string.loh_undo')), () => {
        this.handleFav(item, true);
      });
    }
    this.logApplied('favorite');
  }

  /** 归档 / 取消归档（参考实现 FilterList.tsx:141-158：取消归档那一支**没有**撤销按钮）。 */
  private handleArchive(item: NoticeRecord, isArchived: boolean): void {
    this.flags.setArchived(MarksDomain.NOTICE, [item.id], !isArchived);
    if (isArchived) {
      this.toast.show(this.s($r('app.string.loh_undo_archive')), '', null);
    } else {
      this.toast.show(this.s($r('app.string.loh_archive_succeeded')), this.s($r('app.string.loh_undo')), () => {
        this.handleArchive(item, true);
      });
    }
    this.logApplied('archive');
  }

  private selectFilter(next: ContentFilter): void {
    if (this.filter === next) {
      return;
    }
    this.filter = next;
    // 按 tab 记住选择（参考实现 setSetting('tabFilterSelections', …)）。
    this.flags.selectFilter(MarksTab.NOTICE, next);
    this.logApplied('filter');
  }

  private async handlePullRefresh(): Promise<void> {
    this.refreshing = true;
    await this.store.refresh();
    this.refreshing = false;
    this.logApplied('refresh');
  }

  /** 点一行 → 把整个公告压进本 tab 的详情栈（对齐参考实现 navigation.push）。 */
  private openDetail(notice: NoticeRecord): void {
    logger.info('notice tapped: id=' + notice.id + ' title=' + notice.title);
    this.stack.pushPath({ name: ROUTE_NOTICE_DETAIL, param: notice });
  }

  /**
   * 页头（ticket 11.5 Part B，账号所有者点名）：**标题 + 相对更新时间同一行**。
   *
   * 参考实现的页头是居中的 `HeaderTitle(title, subtitle)` 且**没有**更新时间元素
   * （有意偏离，见 docs/accepted-deviations.md 第 24 条）。
   *
   * 【ticket 14】原来这里还有一枚"未读 n"：**已移除**。参考实现的未读数是过滤条上的角标
   * （FilterList.tsx:246 / Filter.tsx:181-187），而本 ticket 落地过滤条后同一信息会出现两处
   * —— 按工单第 9 行的对账要求二选一，取"删掉自造页头、未读数由筛选条承担"。
   */
  @Builder
  header() {
    Column() {
      Row() {
        Text(this.s($r('app.string.ui_tab_notices')))
          .fontSize(this.theme().typography.headlineSmall.fontSize)
          .lineHeight(this.theme().typography.headlineSmall.lineHeight)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.theme().colors.onSurface)
        Text(this.updatedText())
          .fontSize(this.theme().typography.labelSmall.fontSize)
          .fontColor(this.theme().colors.onSurfaceVariant)
          .margin({ left: this.theme().sizes.space2 })
          .maxLines(1)
        Blank()
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({
      left: this.theme().sizes.contentPadding,
      right: this.theme().sizes.contentPadding,
      top: this.theme().sizes.space4,
      bottom: this.theme().sizes.space2
    })
  }

  /**
   * 过滤条（ticket 14）：五个视图与各自的角标计数，顺序照参考实现 Filter.tsx:153-218
   * （all → unread → fav → archived → hidden）。参考实现是下拉列表，这里是同屏筛选片
   * （ticket 10 起的版式选择，见交付里的偏离说明）；**计数口径一字未改**。
   */
  @Builder
  filterRow() {
    Flex({ wrap: FlexWrap.Wrap }) {
      FilterChip({
        label: this.s($r('app.string.loh_all')), count: this.counts().all,
        active: this.filter === ContentFilter.ALL, isDark: this.isDark(),
        onTap: () => {
          this.selectFilter(ContentFilter.ALL);
        }
      })
      FilterChip({
        label: this.s($r('app.string.loh_unread')), count: this.counts().unread,
        active: this.filter === ContentFilter.UNREAD, isDark: this.isDark(),
        onTap: () => {
          this.selectFilter(ContentFilter.UNREAD);
        }
      })
      FilterChip({
        label: this.s($r('app.string.loh_fav')), count: this.counts().fav,
        active: this.filter === ContentFilter.FAV, isDark: this.isDark(),
        onTap: () => {
          this.selectFilter(ContentFilter.FAV);
        }
      })
      FilterChip({
        label: this.s($r('app.string.loh_archived')), count: this.counts().archived,
        active: this.filter === ContentFilter.ARCHIVED, isDark: this.isDark(),
        onTap: () => {
          this.selectFilter(ContentFilter.ARCHIVED);
        }
      })
      FilterChip({
        label: this.s($r('app.string.loh_hidden')), count: this.counts().hidden,
        active: this.filter === ContentFilter.HIDDEN, isDark: this.isDark(),
        onTap: () => {
          this.selectFilter(ContentFilter.HIDDEN);
        }
      })
    }
    .width('100%')
    .padding({
      left: this.theme().sizes.contentPadding,
      right: this.theme().sizes.contentPadding,
      bottom: this.theme().sizes.space2
    })
  }

  /** 滑动操作（右侧）：收藏（已归档的行不渲染）+ 归档，逐项对齐 CardWrapper.tsx:82-115。 */
  @Builder
  swipeEnd(item: NoticeRecord, fav: boolean, archived: boolean) {
    ContentSwipeActions({
      fav: fav,
      archived: archived,
      // 按钮无文字：无障碍文案要说明**点下去会发生什么**（参考实现的图标两态就是干这个）。
      favLabel: this.s(fav ? $r('app.string.ui_remove_favorite') : $r('app.string.loh_fav')),
      archiveLabel: this.s(archived ? $r('app.string.ui_unarchive') : $r('app.string.loh_archived')),
      onFav: () => {
        this.handleFav(item, fav);
      },
      onArchive: () => {
        this.handleArchive(item, archived);
      }
    })
  }

  /**
   * 长按菜单：参考实现长按卡片会展开右侧操作区（CardWrapper.tsx:161-166）。
   * ArkUI 的 `swipeAction` 没有"以编程方式展开"的 API，这里用同一动作集的菜单作为等价入口。
   */
  @Builder
  rowMenu(item: NoticeRecord, fav: boolean, archived: boolean) {
    Menu() {
      if (!archived) {
        MenuItem({
          content: this.s(fav ? $r('app.string.ui_remove_favorite') : $r('app.string.loh_fav'))
        })
          .onClick(() => {
            this.handleFav(item, fav);
          })
      }
      MenuItem({
        content: this.s(archived ? $r('app.string.ui_unarchive') : $r('app.string.loh_archived'))
      })
        .onClick(() => {
          this.handleArchive(item, archived);
        })
    }
  }

  /**
   * 卡片右上角的三个状态标记 —— 逐项对齐参考实现 `NoticeCard.tsx:45-69`：
   *   附件（MCI `attachment`，`Colors.orange500`）→ 重要（MCI `flag`，`Colors.red500`）→
   *   未读（MCI `checkbox-blank-circle`，`Colors.blue500`）。
   *
   * ticket 11.5 起这三个标记是**与参考实现同源**的字体图标（内嵌同一份 MCI TTF，同一批码位），
   * 不再是 emoji / 自绘圆点；仍不用 SymbolGlyph（理由见台账第 16 条的改判）。
   * 图标本身不带文字，故每个都带 accessibilityText（键已声明）。
   */
  @Builder
  statusIcons(spec: NoticeRowSpec) {
    Row() {
      if (spec.notice.attachment !== undefined) {
        IconGlyph({
          icon: AppIcon.ATTACHMENT, glyphSize: spec.theme.sizes.iconSmall,
          color: PLAIN_PALETTE.orange500, label: spec.attachmentLabel,
          marginLeft: spec.theme.sizes.space1
        })
      }
      if (spec.notice.markedImportant) {
        IconGlyph({
          icon: AppIcon.FLAG, glyphSize: spec.theme.sizes.iconSmall,
          color: PLAIN_PALETTE.red500, label: spec.importantLabel,
          marginLeft: spec.theme.sizes.space1
        })
      }
      if (isUnread(spec.notice)) {
        // 参考实现：MCI checkbox-blank-circle（蓝色）。ticket 11.5 起不再是"画出来的圆点"，
        // 而是同一个字形的字体图标（形状判据升级，见台账第 16 条的改判）。
        // 与改动前一致：未读圆点**没有** accessibilityText（原来是自绘 Column），
        // 不新增无障碍节点属性；回退态下它显示目录里的短名 '[new]'。
        IconGlyph({
          icon: AppIcon.CHECKBOX_BLANK_CIRCLE, glyphSize: spec.theme.sizes.iconSmall,
          color: PLAIN_PALETTE.blue500, label: '',
          marginLeft: spec.theme.sizes.space1
        })
      }
    }
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  noticeRow(spec: NoticeRowSpec) {
    Column() {
      Text(spec.notice.courseName)
        .fontSize(spec.theme.typography.labelMedium.fontSize)
        .lineHeight(spec.theme.typography.labelMedium.lineHeight)
        .fontColor(spec.theme.colors.onSurfaceVariant)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Row() {
        // 标题：removeTags（参考实现 NoticeCard.tsx:42）
        Text(spec.titleText)
          .fontSize(spec.theme.typography.titleMedium.fontSize)
          .lineHeight(spec.theme.typography.titleMedium.lineHeight)
          .fontWeight(FontWeight.Medium)
          .fontColor(spec.theme.colors.onSurface)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        this.statusIcons(spec)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      .margin({ top: spec.theme.sizes.space1 })
      // 正文预览：removeTags(content)，numberOfLines={2}（参考实现 NoticeCard.tsx:71-75）
      if (spec.contentText.length > 0) {
        Text(spec.contentText)
          .fontSize(spec.theme.typography.bodyMedium.fontSize)
          .lineHeight(spec.theme.typography.bodyMedium.lineHeight)
          .fontColor(spec.theme.colors.onSurfaceVariant)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .margin({ top: spec.theme.sizes.space1 })
      }
      Row() {
        Text(spec.notice.publisher)
          .fontSize(spec.theme.typography.labelSmall.fontSize)
          .fontColor(spec.theme.colors.onSurfaceVariant)
        Text(spec.timeText)
          .fontSize(spec.theme.typography.labelSmall.fontSize)
          .fontColor(spec.theme.colors.onSurfaceVariant)
          .margin({ left: spec.theme.sizes.space2 })
        Blank()
      }
      .width('100%')
      .margin({ top: spec.theme.sizes.space2 })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({
      left: spec.theme.sizes.contentPadding,
      right: spec.theme.sizes.contentPadding,
      top: spec.theme.sizes.space3,
      bottom: spec.theme.sizes.space3
    })
    .backgroundColor(spec.theme.colors.surface)
    .onClick(() => {
      this.openDetail(spec.notice);
    })
  }

  /** 空态文案：三个既有视图沿用原句，收藏 / 归档 / 屏蔽用参考实现 Empty 的那句（无内容）。 */
  private emptyMessage(): string {
    if (this.filter === ContentFilter.ALL) {
      return this.s($r('app.string.ui_empty_notices'));
    }
    if (this.filter === ContentFilter.UNREAD) {
      return this.s($r('app.string.ui_empty_notices'));
    }
    return this.s($r('app.string.loh_empty'));
  }

  @Builder
  listBody() {
    Stack() {
      List({ space: 0, scroller: this.listScroller }) {
        ForEach(this.visibleItems(), (item: NoticeRecord) => {
          ListItem() {
            this.noticeRow({
              theme: this.theme(),
              notice: item,
              timeText: this.timeTextOf(item),
              // 标题与正文都过 removeTags（去注释/去标签/解码实体/折叠空白）：
              // 契约是两层的——解析层不解码（docs/reference-quirks.md 第 4 条上半，锁定），
              // 渲染层解码（同一张表的下半）。此前直接渲染 raw title，含标签时会露出字面量。
              titleText: removeTags(item.title),
              contentText: removeTags(item.content),
              attachmentLabel: this.s($r('app.string.ui_attachment_label')),
              importantLabel: this.s($r('app.string.ui_marked_important_label'))
            })
          }
          .swipeAction({
            end: this.swipeEnd(item, isInGroupNotices(this.filtered().fav, item.id),
              isInGroupNotices(this.filtered().archived, item.id))
          })
          .bindContextMenu(this.rowMenu(item, isInGroupNotices(this.filtered().fav, item.id),
            isInGroupNotices(this.filtered().archived, item.id)), ResponseType.LongPress)
        }, (item: NoticeRecord) =>
          item.id + '|' + (item.hasRead ? 'read' : 'unread')
          + '|' + (isInGroupNotices(this.filtered().fav, item.id) ? 'fav' : 'nofav')
          + '|' + (isInGroupNotices(this.filtered().archived, item.id) ? 'arch' : 'noarch'))
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Auto)
      .divider({
        strokeWidth: this.theme().sizes.borderWidth,
        color: this.theme().colors.outlineVariant,
        startMargin: this.theme().sizes.contentPadding,
        endMargin: this.theme().sizes.contentPadding
      })

      // 只有「首次加载且无数据」才盖居中指示器；下拉刷新只用 Refresh 自己的指示器（避免两个 spinner 同转）
      if (this.store.isInitialLoading()) {
        Column() {
          LoadingProgress()
            .width(this.theme().sizes.iconLarge)
            .height(this.theme().sizes.iconLarge)
            .color(this.theme().colors.primary)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.visibleItems().length === 0 && !this.store.isBusy()) {
        EmptyState({
          message: this.emptyMessage(),
          isDark: this.isDark()
        })
      }
    }
    .width('100%')
    .height('100%')
  }

  /** 详情栈的出栈目标：公告详情 / 文件详情真身（ticket 11 起不再是占位页）。 */
  @Builder
  destinationBuilder(name: string, param: object) {
    if (name === ROUTE_NOTICE_DETAIL) {
      NavDestination() {
        NoticeDetailPage({
          notice: param as NoticeRecord,
          stack: this.stack,
          session: this.session
        })
      }
      .hideTitleBar(true)
    } else if (name === ROUTE_FILE_DETAIL) {
      NavDestination() {
        FileDetailPage({ params: param as FileDetailRouteParams, stack: this.stack })
      }
      .hideTitleBar(true)
    }
  }

  build() {
    Navigation(this.stack) {
      Stack() {
        Column() {
          this.header()
          this.filterRow()
          Refresh({ refreshing: $$this.refreshing, promptText: this.s($r('app.string.loh_refresh')) }) {
            this.listBody()
          }
          .layoutWeight(1)
          .width('100%')
          .onRefreshing(() => {
            this.handlePullRefresh();
          })
          // 把 Refresh 的状态机打进 hilog：Inactive/Drag/OverDrag/Refresh/Done。
          // 这是"下拉刷新确实被触发并进入刷新态"的确定性证据（截图只能尽力抓时机）。
          .onStateChange((state: RefreshStatus) => {
            logger.info('pull refresh state: ' + state.toString());
          })
        }
        .width('100%')
        .height('100%')
        .backgroundColor(this.theme().colors.background)

        // 撤销浮层（ticket 14）：3 秒窗口，逐字对齐参考实现 Toast.tsx:51-54。
        ToastOverlay({ controller: this.toast, isDark: this.isDark() })
      }
      .width('100%')
      .height('100%')
    }
    .navDestination(this.destinationBuilder)
    .hideTitleBar(true)
    .mode(NavigationMode.Stack)
    .width('100%')
    .height('100%')
  }
}
