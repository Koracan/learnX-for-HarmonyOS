/*
 * 文件 tab：文件列表 + 详情栈的根。
 *
 * 对齐参考实现 `screens/Files.tsx` 与 `components/FileCard.tsx`：
 *
 * | 项 | 参考实现 | 这里 |
 * | --- | --- | --- |
 * | 取数 | `getAllFilesForCourses(courseIds)`（:29-32，courseIds 取自已加载的课程） | `FileListStore.refresh()`（自己解析学期 + 取课程列表 + 取文件；见 data/files/FileRepository 的说明） |
 * | 次序 | processor 按上传时间倒序 | `data/remote/FilesFetcher.fetch`（同一比较器） |
 * | 卡片 | 课程名 / 标题（removeTags）/ 描述 2 行 / `TYPE SIZE` 一行 / 相对时间（:37-78） | 同（"显示大小与类型"就是那一行） |
 * | 点击 | `navigate('FileDetail', item)` | 推本 tab 的 `ROUTE_FILE_DETAIL`（真身 FileDetailPage） |
 * | 下拉刷新 | `handleRefresh` | 同 |
 * | 过滤 | FilterList 下拉（all / unread / fav / archived / hidden） | 五个筛选片，计数口径照 Filter.tsx:153-218 |
 *
 * 三种状态都显式呈现，**没有"失败就显示空列表"这条路**（与课程/公告列表同一口径）。
 */

import { ConfigurationConstant } from '@kit.AbilityKit';
import { ThemeTokens, resolveTheme } from '../../ui/theme/Tokens';
import { i18nService } from '../../core/i18n/I18n';
import { formatRelativeTo } from '../../core/i18n/DateTimeUtil';
import { COLOR_MODE_KEY, LOCALE_VERSION_KEY } from '../../entryability/EntryAbility';
import { Logger } from '../../core/log/Logger';
import { parseTimestamp } from '../../domain/parse/Text';
import { CourseFile } from '../../domain/model/ContentItem';
import { fileMetaLine } from '../../domain/files/FilePath';
import { removeTags } from '../../domain/render/WebViewTemplate';
import { EmptyState } from '../../ui/components/EmptyState';
import { SearchButton } from '../../ui/components/SearchButton';
import { FilterChip } from '../../ui/components/FilterChip';
import { ToastController, ToastOverlay } from '../../ui/components/Toast';
import { ContentSwipeActions } from '../../ui/components/SwipeActions';
import { PAGE_SHOWN_AT_KEY, pageHeaderUpdatedText } from '../shell/PageShown';
import { loadFailureText } from '../shell/LoadFailureText';
import { AppIcon } from '../../ui/icons/IconCatalog';
import { IconGlyph } from '../../ui/icons/IconGlyph';
import { ContentFilter } from '../../domain/marks/ContentFilter';
import { MarksDomain, MarksTab } from '../../domain/marks/CollectionFlags';
import { CollectionFlagsStore } from '../../data/marks/CollectionFlagsStore';
import {
  FileFilterCounts, FilteredFiles, fileCounts, filesContain, filesForFilter,
  selectFilteredFiles
} from '../marks/FilteredContent';
import { collectionFlagsStore } from '../marks/CollectionFlagsProvider';
import { FileListStore } from './FileListStore';
import { fileListRowKey } from './FileRowKey';
import { fileListStore } from './FileListStoreProvider';
import { fileRepository } from './repository/FileRepositoryProvider';
import { FileDetailPage } from './FileDetailPage';
import { FileDetailRouteParams, ROUTE_FILE_DETAIL } from '../notices/NoticeRoutes';
import { openSearch } from '../search/SearchEntry';
import {
  SPLIT_VIEW_ACTIVE_KEY, SPLIT_VIEW_DIVIDER_WIDTH, SPLIT_VIEW_MASTER_HIDDEN_KEY,
  SPLIT_VIEW_MASTER_WIDTH, masterPaneBottomReserve, migrateDetailRoutesBack, migrateDetailRoutesInto,
  pushDetailFromMaster
} from '../shell/SplitView';

const logger: Logger = new Logger('features.files');

/** 一行文件卡片的渲染参数（文本在构造时算好，避免 build 里做重活）。 */
interface FileRowSpec {
  theme: ThemeTokens;
  courseName: string;
  titleText: string;
  descriptionText: string;
  /** `TYPE SIZE`。 */
  metaText: string;
  timeText: string;
  isNew: boolean;
  newLabel: string;
  /** 双栏时这一行是不是"右栏正在显示的那一条"（主栏保留高亮）。 */
  selected: boolean;
}

@Component
export struct FilesPage {
  @StorageProp(COLOR_MODE_KEY) colorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageLink(LOCALE_VERSION_KEY) localeVersion: number = 0;
  /**
   * 「页面被显示」的时刻（AppStorage）：切走再切回、或从后台回到前台时由
   * `features/shell/PageShown.ets` 的 `markPageShown()` 刷新。
   * 页头那一行读它 ⇒ 键一变就用新的时间基准重算（这就是"相对时间不再冻结"的机制）。
   */
  @StorageProp(PAGE_SHOWN_AT_KEY) pageShownAtMillis: number = 0;
  @State refreshing: boolean = false;
  /** 当前过滤视图；初值 = 参考实现 settings.ts:27 的 file 默认值 all。 */
  @State filter: ContentFilter = ContentFilter.ALL;

  private store: FileListStore | null = null;
  /** 进程内单例：与公告 / 作业 / 课程三个列表共用同一份收藏与屏蔽状态。 */
  private flags: CollectionFlagsStore = collectionFlagsStore();
  private toast: ToastController = new ToastController();
  /** 主栈：单栏时详情压在这里，也就是左栏。 */
  private stack: NavPathStack = new NavPathStack();
  /** 右栏（详情）的栈：见 features/shell/SplitView.ets 的文件头。 */
  private detailStack: NavPathStack = new NavPathStack();
  /** 双栏开关：来源是根布局实测尺寸（features/shell/SplitView.ets），消费点就是这个版式。 */
  @StorageProp(SPLIT_VIEW_ACTIVE_KEY) @Watch('onSplitViewChanged') splitActive: boolean = false;
  /** 主栏是否被隐藏（参考实现的 showMaster 取反；由文件详情的全屏按钮翻转）。 */
  @StorageProp(SPLIT_VIEW_MASTER_HIDDEN_KEY) masterHidden: boolean = false;
  /** 主栏当前高亮的那一条（= 右栏正在显示的那一条）。 */
  @State selectedId: string = '';

  aboutToAppear(): void {
    // 进程内单例：学期切换的编排要能驱动它（见 FileListStoreProvider）。
    const store: FileListStore = fileListStore();
    this.store = store;
    store.loadOnce();
    this.loadFlags();
    logger.info('files page appear');
  }

  /** 读一次收藏状态，并恢复记住的过滤视图。 */
  private async loadFlags(): Promise<void> {
    await this.flags.loadOnce();
    this.filter = this.flags.filterFor(MarksTab.FILE);
    this.logApplied('initial');
  }

  private theme(): ThemeTokens {
    return resolveTheme(this.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
  }

  private isDark(): boolean {
    return this.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  }

  private s(resource: Resource): string {
    return i18nService.tKey(resource);
  }

  /* ------------------------------------------------------------------ *
   * 收藏 / 归档 / 屏蔽
   * ------------------------------------------------------------------ */

  private sourceFiles(): CourseFile[] {
    const store: FileListStore | null = this.store;
    return store === null ? [] : store.files;
  }

  private filtered(): FilteredFiles {
    return selectFilteredFiles(this.sourceFiles(), this.flags.fileFavorites,
      this.flags.fileArchived, this.flags.hiddenCourseIds);
  }

  private visibleFiles(): CourseFile[] {
    return filesForFilter(this.filtered(), this.filter);
  }

  private counts(): FileFilterCounts {
    return fileCounts(this.filtered());
  }

  /** 消费点自证：实际生效的过滤视图 + 五组计数 + 收藏/归档/屏蔽的原始 id 数。 */
  private logApplied(reason: string): void {
    const counts: FileFilterCounts = this.counts();
    logger.info('files applied: reason=' + reason
      + ' semester=' + (this.store === null ? '' : this.store.semesterId)
      + ' items=' + this.sourceFiles().length.toString()
      + ' filter=' + this.filter.toString()
      + ' all=' + counts.all.toString()
      + ' unread=' + counts.unread.toString()
      + ' fav=' + counts.fav.toString()
      + ' archived=' + counts.archived.toString()
      + ' hidden=' + counts.hidden.toString()
      + ' favoriteIds=' + this.flags.fileFavorites.length.toString()
      + ' archivedIds=' + this.flags.fileArchived.length.toString()
      + ' hiddenCourses=' + this.flags.hiddenCourseIds.length.toString());
  }

  private handleFav(item: CourseFile, isFav: boolean): void {
    this.flags.setFavorite(MarksDomain.FILE, item.id, !isFav);
    if (isFav) {
      this.toast.show(this.s($r('app.string.loh_remove_from_fav')), '', null);
    } else {
      this.toast.show(this.s($r('app.string.loh_add_to_fav')), this.s($r('app.string.loh_undo')), () => {
        this.handleFav(item, true);
      });
    }
    this.logApplied('favorite');
  }

  private handleArchive(item: CourseFile, isArchived: boolean): void {
    this.flags.setArchived(MarksDomain.FILE, [item.id], !isArchived);
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
    this.flags.selectFilter(MarksTab.FILE, next);
    this.logApplied('filter');
  }

  /**
   * 页头那一行"相对更新时间"：`刚刚更新` / `N 分钟前更新` / …。
   * 原来是 ICU 的裸相对措辞（"5分钟前"），现在统一成同一套页头文案。
   *
   * 时间基准是"本页最近一次被显示的时刻"（`features/shell/PageShown.ets`）：切走再切回、
   * 回到前台都会重算；实现只有那一处，本页只订阅键并把两个数传进去。
   */
  private updatedText(): string {
    const store: FileListStore | null = this.store;
    if (store === null) {
      return '';
    }
    return pageHeaderUpdatedText(store.fetchedAtMillis, this.pageShownAtMillis);
  }

  private errorText(): string {
    const store: FileListStore | null = this.store;
    // 断网 / 会话失效 / 其它三类与对应文案只有一处：features/shell/LoadFailureText。
    return loadFailureText(store === null ? '' : store.errorMessage, 'ui_files_load_failed');
  }

  private timeTextOf(file: CourseFile): string {
    const millis: number = parseTimestamp(file.uploadTime);
    if (millis <= 0) {
      return file.uploadTime;
    }
    const relative: string = formatRelativeTo(millis, Date.now(), i18nService.locale());
    return relative.length > 0 ? relative : file.uploadTime;
  }

  /** 列表项 → 详情路由参数（详情页自己算缓存键，见 FileDetailPage.request）。 */
  private paramsFor(file: CourseFile): FileDetailRouteParams {
    const extension: string = file.fileType.length > 0 ? '.' + file.fileType : '';
    return {
      noticeId: file.fileId.length > 0 ? file.fileId : file.id,
      courseName: file.courseName,
      courseTeacherName: file.courseTeacherName,
      title: file.title,
      attachmentName: file.title + extension,
      downloadUrl: file.downloadUrl,
      fileType: file.fileType,
      size: file.size,
      uploadTime: file.uploadTime,
      description: file.description
    };
  }

  private openFile(file: CourseFile): void {
    logger.info('file tapped: id=' + file.id + ' title="' + file.title + '" type=' + file.fileType
      + ' split=' + this.splitActive.toString());
    this.selectedId = file.id;
    pushDetailFromMaster(this.stack, this.detailStack, this.splitActive,
      ROUTE_FILE_DETAIL, this.paramsFor(file));
  }

  /**
   * 分栏开关翻转（消费点自证）：进分栏把主栈上的详情段搬到右栏、左栏回列表；
   * 退出分栏把右栏的详情搬回主栈（**本工程补做**）。
   */
  onSplitViewChanged(): void {
    if (this.splitActive) {
      AppStorage.setOrCreate(SPLIT_VIEW_MASTER_HIDDEN_KEY, false);
      const moved: number = migrateDetailRoutesInto(this.stack, this.detailStack);
      logger.info('split view enter: tab=files moved=' + moved.toString()
        + ' masterRoutes=' + this.stack.getAllPathName().length.toString()
        + ' detailRoutes=' + this.detailStack.getAllPathName().length.toString());
    } else {
      const moved: number = migrateDetailRoutesBack(this.detailStack, this.stack);
      logger.info('split view exit: tab=files moved=' + moved.toString()
        + ' masterRoutes=' + this.stack.getAllPathName().length.toString()
        + ' detailRoutes=' + this.detailStack.getAllPathName().length.toString());
    }
  }

  /** 左栏宽度：单栏铺满；双栏定宽 393（参考实现 Numbers.splitViewMasterWidth），全屏态收成 0。 */
  private masterPaneWidth(): Length {
    if (!this.splitActive) {
      return '100%';
    }
    return this.masterHidden ? 0 : SPLIT_VIEW_MASTER_WIDTH;
  }

  /**
   * 分栏态下主栏底部要为底栏留出的空高（单栏态为 0）。
   *
   * 分栏态壳层的内容区拿满整屏、底栏浮在主栏底部之上，所以这一段必须由页面自己让出来，
   * 否则列表最后一行会被底栏盖住。取值只有一个来源：features/shell/SplitView。
   */
  private masterPaneReserve(): number {
    return masterPaneBottomReserve(this.theme(), this.splitActive, this.masterHidden);
  }

  private async handlePullRefresh(): Promise<void> {
    this.refreshing = true;
    const store: FileListStore | null = this.store;
    if (store !== null) {
      await store.refresh();
    }
    this.refreshing = false;
    this.logApplied('refresh');
  }

  /**
   * 页头：**「标题 + 相对更新时间」同一行**，最右侧是搜索入口。
   *
   * 学期**只在课程页**显示；文件列表每行本来就带课程名，这里再写一遍学期是冗余。
   * 「文件设置」只留设置页那一条入口——页头再放一个就是同一功能的第二个入口。
   * 文件条数不在这里显示：它没有标签、看不出在数什么，而下面五个筛选片上的计数
   * 本来就带标签（全部 / 未读 / 收藏 / 已归档 / 已屏蔽）。
   */
  @Builder
  header() {
    Column() {
      Row() {
        Text(this.s($r('app.string.loh_files')))
          .fontSize(this.theme().typography.headlineSmall.fontSize)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.theme().colors.onSurface)
        Text(this.updatedText())
          .fontSize(this.theme().typography.labelSmall.fontSize)
          .fontColor(this.theme().colors.onSurfaceVariant)
          .margin({ left: this.theme().sizes.space2 })
          .maxLines(1)
        Blank()
        // 页头最右侧的搜索入口（参考实现的 headerRight）。
        SearchButton({
          isDark: this.isDark(),
          label: this.s($r('app.string.loh_search')),
          onTap: () => {
            openSearch('');
          }
        })
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

  /** 过滤条：all → unread → fav → archived → hidden（Filter.tsx:153-218 的顺序）。 */
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

  @Builder
  swipeEnd(item: CourseFile, fav: boolean, archived: boolean) {
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

  @Builder
  rowMenu(item: CourseFile, fav: boolean, archived: boolean) {
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

  @Builder
  fileRow(spec: FileRowSpec) {
    Column() {
      Row() {
        Text(spec.courseName)
          .fontSize(spec.theme.typography.labelMedium.fontSize)
          .fontColor(spec.theme.colors.onSurfaceVariant)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        if (spec.isNew) {
          // 参考实现 FileCard.tsx:55-62：MCI `checkbox-blank-circle`（blue500）。
          // 颜色这里仍取既有令牌 primary（Part A 只改形状与来源，不动配色）。
          IconGlyph({
            icon: AppIcon.CHECKBOX_BLANK_CIRCLE, glyphSize: spec.theme.sizes.iconSmall,
            color: spec.theme.colors.primary, label: spec.newLabel
          })
        }
      }
      .width('100%')

      Text(spec.titleText)
        .fontSize(spec.theme.typography.titleMedium.fontSize)
        .fontWeight(FontWeight.Medium)
        .fontColor(spec.theme.colors.onSurface)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      if (spec.descriptionText.length > 0) {
        Text(spec.descriptionText)
          .fontSize(spec.theme.typography.bodyMedium.fontSize)
          .fontColor(spec.theme.colors.onSurfaceVariant)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .margin({ top: spec.theme.sizes.space1 })
      }

      Row() {
        // **大小与类型**在同一行里逐字可见。
        Text(spec.metaText)
          .fontSize(spec.theme.typography.labelSmall.fontSize)
          .fontColor(spec.theme.colors.onSurfaceVariant)
          .layoutWeight(1)
        Text(spec.timeText)
          .fontSize(spec.theme.typography.labelSmall.fontSize)
          .fontColor(spec.theme.colors.onSurfaceVariant)
          .margin({ left: spec.theme.sizes.space2 })
      }
      .width('100%')
      .margin({ top: spec.theme.sizes.space1 })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({
      left: spec.theme.sizes.contentPadding,
      right: spec.theme.sizes.contentPadding,
      top: spec.theme.sizes.space3,
      bottom: spec.theme.sizes.space3
    })
    // 双栏时把"右栏正在显示的那一条"高亮出来（主栏保留高亮状态）。
    .backgroundColor(spec.selected ? spec.theme.colors.surfaceVariant : spec.theme.colors.surface)
  }

  @Builder
  listBody() {
    Stack() {
      List({ space: 0 }) {
        ForEach(this.visibleFiles(), (item: CourseFile) => {
          ListItem() {
            this.fileRow({
              theme: this.theme(),
              courseName: item.courseName,
              titleText: removeTags(item.title),
              descriptionText: removeTags(item.description),
              metaText: fileMetaLine(item.fileType, item.size),
              timeText: this.timeTextOf(item),
              isNew: item.isNew,
              newLabel: this.s($r('app.string.ui_course_new_files_label')),
              selected: this.splitActive && this.selectedId === item.id
            })
          }
          .swipeAction({
            // 收藏状态取**原始收藏集合**（理由同公告页：过滤后的 fav 分组只在 all 之内）。
            end: this.swipeEnd(item, this.flags.fileFavorites.includes(item.id),
              filesContain(this.filtered().archived, item.id))
          })
          .bindContextMenu(this.rowMenu(item, this.flags.fileFavorites.includes(item.id),
            filesContain(this.filtered().archived, item.id)), ResponseType.LongPress)
          .onClick(() => {
            this.openFile(item);
          })
        }, (item: CourseFile) =>
          // key 由 fileListRowKey 统一构造（纯函数，见 FileRowKey.ets 的文件头）：
          // 上一版漏了 **isNew（"新文件"蓝点）与 size（体积文本）**：两者都在行上渲染、
          // 刷新就会变（mock 快照会把站点文本换成包内真实字节数）⇒ 补齐。
          fileListRowKey(item,
            this.flags.fileFavorites.includes(item.id),
            filesContain(this.filtered().archived, item.id),
            this.splitActive && this.selectedId === item.id))
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

      // 加载 / 失败态**靠上**：整屏 100% 高的容器一旦居中，首行内容就浮在页面中部，
      // 列表一旦为空或报错，观感与"内容靠上"的列表页完全不同。文字仍水平居中。
      if (this.store !== null && this.store.isInitialLoading()) {
        Column() {
          LoadingProgress()
            .width(this.theme().sizes.iconLarge)
            .height(this.theme().sizes.iconLarge)
            .color(this.theme().colors.primary)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .align(Alignment.Top)
      } else if (this.store !== null && this.store.hasError()) {
        Column() {
          Text(this.errorText())
            .fontSize(this.theme().typography.bodyMedium.fontSize)
            .fontColor(this.theme().colors.error)
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .align(Alignment.Top)
        .padding({
          left: this.theme().sizes.contentPadding,
          right: this.theme().sizes.contentPadding,
          top: this.theme().sizes.space4,
          bottom: this.theme().sizes.contentPadding
        })
      } else if (this.visibleFiles().length === 0 && this.store !== null && !this.store.isBusy()) {
        EmptyState({
          message: this.filter === ContentFilter.ALL
            ? this.s($r('app.string.ui_files_empty')) : this.s($r('app.string.loh_empty')),
          isDark: this.isDark()
        })
      }
    }
    .width('100%')
    .height('100%')
  }

  /**
   * 详情目标的**真身**：同一份路由表被两个导航容器共用。
   *
   * `stack` 决定"返回 / 继续压栈"落到哪个栈 —— 左栏传主栈，右栏传详情栈。
   * 两个 `Navigation` 因此各自独立（对应参考实现的两个 `NavigationContainer`，
   * 见 features/shell/SplitView.ets 的文件头），而不是一个现成的主从组件。
   */
  @Builder
  routeTo(name: string, param: object, stack: NavPathStack) {
    if (name === ROUTE_FILE_DETAIL) {
      NavDestination() {
        FileDetailPage({ params: param as FileDetailRouteParams, stack: stack })
      }
      .hideTitleBar(true)
    }
  }

  /** 左栏的 `navDestination`（详情栈 = 主栈）。 */
  @Builder
  masterDestination(name: string, param: object) {
    this.routeTo(name, param, this.stack)
  }

  /** 右栏的 `navDestination`（详情栈 = 本页的 detailStack）。 */
  @Builder
  detailDestination(name: string, param: object) {
    this.routeTo(name, param, this.detailStack)
  }

  /** 左栏内容 = 文件列表。 */
  @Builder
  masterPane() {
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
        .onStateChange((state: RefreshStatus) => {
          logger.info('files pull refresh state: ' + state.toString());
        })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.theme().colors.background)

      ToastOverlay({ controller: this.toast, isDark: this.isDark() })
    }
    .width('100%')
    .height('100%')
  }

  /** 右栏的栈根：还没选中条目时的空态（对应参考实现 `DetailStack` 的 `EmptyDetail`）。 */
  @Builder
  detailPane() {
    Column() {
      EmptyState({ message: this.s($r('app.string.loh_empty')), isDark: this.isDark() })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme().colors.background)
  }

  /**
   * 版式：`Row` = 左栏 + **1px `Divider`** + 右栏，逐项对齐参考实现
   * `SplitView.tsx:109-135`。单栏时右栏整段不渲染、分隔线 `Visibility.None`（不占位）。
   */
  build() {
    Row() {
      Column() {
        Navigation(this.stack) {
          this.masterPane()
        }
        .navDestination(this.masterDestination)
        .hideTitleBar(true)
        .mode(NavigationMode.Stack)
        .width('100%')
        .height('100%')
      }
      .width(this.masterPaneWidth())
      .height('100%')
      // 主栏底部预留：分栏态 = barH（底栏浮在上面，别让最后一行被盖住），单栏态 = 0。
      .padding({ bottom: this.masterPaneReserve() })

      Divider()
        .vertical(true)
        .strokeWidth(SPLIT_VIEW_DIVIDER_WIDTH)
        .color(this.theme().colors.outlineVariant)
        .height('100%')
        .visibility(this.splitActive ? Visibility.Visible : Visibility.None)

      if (this.splitActive) {
        Column() {
          Navigation(this.detailStack) {
            this.detailPane()
          }
          .navDestination(this.detailDestination)
          .hideTitleBar(true)
          .mode(NavigationMode.Stack)
          .width('100%')
          .height('100%')
          // 右栏 NavDestination 的进入/退出转场会画到本 Navigation 的边界之外（盖住左栏一截），
          // 就地裁剪：动画只允许出现在右栏自己的范围内。
          .clip(true)
        }
        .layoutWeight(1)
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
  }
}
