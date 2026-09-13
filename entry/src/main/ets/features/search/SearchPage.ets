/*
 * 搜索页 —— 顶部搜索框 + 三个域的结果（公告 / 作业 / 文件），可跳详情。
 *
 * ## 与参考实现的对应关系（逐条给行号）
 *
 * | 项 | 参考实现 | 这里 |
 * | --- | --- | --- |
 * | 入口 | 页头右侧 search 图标，`App.tsx:137-158` 的 `headerRight`（`hideSearch` 可关） | 四个 tab 页各自的 `header()` 里放 `ui/components/SearchButton`；设置页（`SettingsPage`）没有 |
 * | 哪些页有 | 公告 / 作业 / 文件 / 课程四个 tab 都有；设置页显式关掉（`App.tsx:404,445,471,501` vs `:558`） | 同 |
 * | 搜索页本体 | `screens/Search.tsx`：Searchbar + SectionList 三段 + 三段都空才 Empty | 本文：Search + 三段列表 + 全空才 `EmptyState`（`loh_empty`，与参考实现 `Empty` 的 `t('empty')` 同义） |
 * | 初值 | `useState(route.params?.query ?? '')`（`:39`） | `@Prop initialQuery`（入口参数见 SearchRoutes） |
 * | 空查询自动聚焦 | `isFocused && searchQuery === ''` → `searchRef.current?.focus()`（`:41-45`） | `focusWhenEmpty()`（进页面 + 从详情返回时各一次，见 `onNavBarStateChange`），并在 `onFocus` 打消费点日志 |
 * | 进详情 | 有右栏引用则 `navigate` 进右栏并补 `disableAnimation: true`；否则 `navigation.push`（`:54-63`） | `pushDetailFromMaster(..., animated: !splitActive)`；单栏压本页自己的栈，分栏压右栏 |
 * | 排序/召回 | `useSearch`：手工精确/前缀合并层 + fuse + 按 id 去重（手工在前） | `features/search/SearchCore`（同构三段；引擎是本工程自写的加权评分，理由与边界见该文件头） |
 *
 * ## 数据从哪来（**不是**全局 state，这一点与参考实现不同）
 *
 * 参考实现的搜索页从 redux 的 `state.notices/assignments/files.items` 取数（`:35-37`）。
 * 本工程没有一个全局内容 store（每个 tab 页各持一份），所以这里
 * **复用课程线的同一次抓取**（`CourseListStore` 的一次 refresh 同时给出课程 + 三域内容，
 * 且读同一份"实际生效学期"），与 `AssignmentsPage` 完全同一处置。代价 = 打开搜索页时多一次抓取
 * （与"进两个 tab = 两次抓取"同一代价）。
 *
 * ## 喂进检索的条目 = **原始条目只排除被屏蔽课程**
 *
 * 参考实现喂的是原始 `items`（不是列表用的 `all` 分组）⇒ **归档项仍会被搜到**；要求
 * 照做，只额外排除**被屏蔽课程**。排除动作复用 features/marks/FilteredContent
 * 的三个 `*ExcludingHiddenCourses`（判据仍出自同一份 selector），不是第二套过滤。
 *
 * ## 分栏
 *
 * 搜索页自己就是一个"左栏 + 右栏"的版式：左栏 = 搜索框 + 结果（双栏时定宽 393vp），
 * 右栏 = 详情。理由：参考实现里 SearchStack 挂在**根**容器上，而根容器在分栏态下就是左栏
 * （`SplitView.tsx:109-135` 把 masterChild 收成 393vp），搜索结果的详情经
 * `useDetailNavigator()` 进**同一个右栏**。本工程的搜索页是盖在 ShellTabs 之上的根级页面，
 * 没有"外面那个右栏"可用，所以把同一套版式（`SPLIT_VIEW_MASTER_WIDTH` + 1px Divider +
 * `pushDetailFromMaster`）搬进本页内部，**可观察行为一致**（结果点开在右栏、左栏保留高亮）。
 * 与参考实现的唯一差别：右栏起始是空态（不会沿用"进搜索页之前那个右栏详情"）。
 *
 * ## 与参考实现的两处界面级补充（本工程口径）
 *
 * 1. 取数有 loading / error 两个状态（参考实现的 redux 数据早就绪，没有这两个状态）；
 * 2. 页头是自绘的左对齐页头 + 左上角关闭按钮（参考实现是导航栏 header，close 图标在左侧）。
 */

import { ConfigurationConstant } from '@kit.AbilityKit';
import { ThemeTokens, resolveTheme } from '../../ui/theme/Tokens';
import { i18nService } from '../../core/i18n/I18n';
import { formatDateTimeShort, formatRelativeTo } from '../../core/i18n/DateTimeUtil';
import { Logger } from '../../core/log/Logger';
import { COLOR_MODE_KEY, LOCALE_VERSION_KEY } from '../../entryability/EntryAbility';
import { EmptyState } from '../../ui/components/EmptyState';
import { AppIcon } from '../../ui/icons/IconCatalog';
import { IconGlyph } from '../../ui/icons/IconGlyph';
import { fileMetaLine } from '../../domain/files/FilePath';
import { removeTags } from '../../domain/render/WebViewTemplate';
import { Assignment, CourseFile } from '../../domain/model/ContentItem';
import { NoticeRecord } from '../../data/notices/NoticeRepository';
import {
  SessionHeaderProvider, createSessionHeaderProvider, logSessionHeaderState
} from '../../core/web/SessionHeaderProvider';
import { CollectionFlagsStore } from '../../data/marks/CollectionFlagsStore';
import { collectionFlagsStore } from '../marks/CollectionFlagsProvider';
import {
  assignmentsExcludingHiddenCourses, filesExcludingHiddenCourses, noticesExcludingHiddenCourses
} from '../marks/FilteredContent';
import { searchAssignments, searchFiles, searchNotices } from './SearchCore';
import { closeSearch } from './SearchEntry';
import { CourseListStore } from '../courses/CourseListStore';
import { createCourseRepository } from '../courses/repository/CourseRepositoryProvider';
import { FileDetailPage } from '../files/FileDetailPage';
import { AssignmentDetailPage } from '../assignments/AssignmentDetailPage';
import { AssignmentSubmissionPage } from '../assignments/AssignmentSubmissionPage';
import { NoticeDetailPage } from '../notices/NoticeDetailPage';
import { FileDetailRouteParams, ROUTE_FILE_DETAIL, ROUTE_NOTICE_DETAIL } from '../notices/NoticeRoutes';
import { ROUTE_ASSIGNMENT_DETAIL, ROUTE_ASSIGNMENT_SUBMISSION } from '../assignments/AssignmentRoutes';
import {
  SPLIT_VIEW_ACTIVE_KEY, SPLIT_VIEW_DIVIDER_WIDTH, SPLIT_VIEW_MASTER_HIDDEN_KEY,
  SPLIT_VIEW_MASTER_WIDTH, migrateDetailRoutesBack, migrateDetailRoutesInto, pushDetailFromMaster
} from '../shell/SplitView';

const logger: Logger = new Logger('features.search');

/** 搜索输入框的 id：`focusControl.requestFocus` 用它把光标送进去（空查询自动聚焦）。 */
const SEARCH_INPUT_ID: string = 'learnoh-search-input';

/** 结果行共用的版式参数（三种类型各自的 `*Row` builder 填好它，点击处理在那边）。 */
interface SearchRowSpec {
  courseName: string;
  title: string;
  /** 副信息一行（公告 = 发布人 · 时间；作业 = 教师 · 截止；文件 = `TYPE SIZE`）。 */
  meta: string;
  /** 预览（正文 / 描述去标签后的 2 行）。 */
  preview: string;
  selected: boolean;
}

@Component
export struct SearchPage {
  @StorageProp(COLOR_MODE_KEY) colorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageLink(LOCALE_VERSION_KEY) localeVersion: number = 0;
  /** 入口带来的初始查询（参考实现 `route.params?.query ?? ''`）。 */
  @Prop initialQuery: string = '';
  @State query: string = '';
  /** 主栏当前高亮的那一条（= 右栏正在显示的那一条）。 */
  @State selectedId: string = '';
  @StorageProp(SPLIT_VIEW_ACTIVE_KEY) @Watch('onSplitViewChanged') splitActive: boolean = false;
  @StorageProp(SPLIT_VIEW_MASTER_HIDDEN_KEY) masterHidden: boolean = false;

  /** 数据源：课程线同一次抓取（课程 + 三域内容 + 生效学期）。 */
  private store: CourseListStore = new CourseListStore(createCourseRepository());
  /** 屏蔽课程状态：与四个列表共用同一份进程内单例。 */
  private flags: CollectionFlagsStore = collectionFlagsStore();
  /** 单栏时详情压在这个栈上（= 左栏）；分栏时它只承载"结果列表"这一层。 */
  private stack: NavPathStack = new NavPathStack();
  /** 右栏（详情）的栈（同一套迁移助手）。 */
  private detailStack: NavPathStack = new NavPathStack();
  private session: SessionHeaderProvider = createSessionHeaderProvider();
  private started: boolean = false;
  /*
   * 检索结果缓存：查询变化 / 数据到位时各算一次（不在 build 里反复算）。
   *
   * **必须是 @State**：实测踩到的坑（模拟器 Pura 90，2026-09-13）—— 最初写成普通字段时，
   * 输入框里文字变了、hilog 里 `search applied` 的命中数也变了，但**列表一动不动**：
   * 界面只在"查询词变化"时被标脏，而 `results()` 依赖的是这三个**未被观察**的字段，
   * 于是它从不重建（表现为"搜什么都是进页面那一刻的结果"）。改成 @State 后
   * 赋值即驱动 `results()` 重建。
   */
  @State noticeHits: NoticeRecord[] = [];
  @State assignmentHits: Assignment[] = [];
  @State fileHits: CourseFile[] = [];
  /** 候选数（只进日志，不驱动界面）。 */
  private candidateCounts: number[] = [0, 0, 0];

  aboutToAppear(): void {
    this.query = this.initialQuery;
    logSessionHeaderState(this.session);
    this.loadOnce();
    this.focusWhenEmpty('appear');
    logger.info('search page appear: initialQuery="' + this.initialQuery + '"');
  }

  /** 首次取数（只跑一次）：三域内容 + 屏蔽课程状态，然后算一次结果。 */
  private async loadOnce(): Promise<void> {
    if (this.started) {
      return;
    }
    this.started = true;
    await this.store.loadOnce();
    await this.flags.loadOnce();
    this.recompute('initial');
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

  /** 空查询自动聚焦（参考实现 `Search.tsx:41-45`）。延后一帧：Search 这时才挂到树上。 */
  private focusWhenEmpty(reason: string): void {
    if (this.query.length > 0) {
      return;
    }
    setTimeout(() => {
      if (this.query.length === 0) {
        focusControl.requestFocus(SEARCH_INPUT_ID);
        logger.info('search focus requested: reason=' + reason);
      }
    }, 300);
  }

  /* ------------------------------------------------------------------ *
   * 检索（数据口径 + 三段结果）
   * ------------------------------------------------------------------ */

  /** 喂进检索的公告 = 原始条目减被屏蔽课程（FilteredContent 的同一份判据）。 */
  private noticeCandidates(): NoticeRecord[] {
    return noticesExcludingHiddenCourses(this.store.notices, this.flags.hiddenCourseIds);
  }

  private assignmentCandidates(): Assignment[] {
    return assignmentsExcludingHiddenCourses(this.store.assignments, this.flags.hiddenCourseIds);
  }

  private fileCandidates(): CourseFile[] {
    return filesExcludingHiddenCourses(this.store.files, this.flags.hiddenCourseIds);
  }

  /**
   * 重算三段结果。**消费点自证**打在这里：查询词、候选数、命中数、屏蔽课程数一起进 hilog
   * （AGENTS.md：开关/口径的实际生效值要打在消费点，只看设置点不足以证明到达了数据路径）。
   */
  private recompute(reason: string): void {
    const notices: NoticeRecord[] = this.noticeCandidates();
    const assignments: Assignment[] = this.assignmentCandidates();
    const files: CourseFile[] = this.fileCandidates();
    this.candidateCounts = [notices.length, assignments.length, files.length];
    this.noticeHits = searchNotices(notices, this.query);
    this.assignmentHits = searchAssignments(assignments, this.query);
    this.fileHits = searchFiles(files, this.query);
    logger.info('search applied: reason=' + reason
      + ' query="' + this.query + '"'
      + ' candidates=' + notices.length.toString() + '/' + assignments.length.toString()
      + '/' + files.length.toString()
      + ' hits=' + this.noticeHits.length.toString() + '/' + this.assignmentHits.length.toString()
      + '/' + this.fileHits.length.toString()
      + ' hiddenCourses=' + this.flags.hiddenCourseIds.length.toString()
      + ' items=' + this.store.notices.length.toString() + '/'
      + this.store.assignments.length.toString() + '/' + this.store.files.length.toString());
  }

  private totalHits(): number {
    return this.noticeHits.length + this.assignmentHits.length + this.fileHits.length;
  }

  /* ------------------------------------------------------------------ *
   * 跳详情（单栏压本页主栈 / 分栏进右栏）
   * ------------------------------------------------------------------ */

  private fileParams(file: CourseFile): FileDetailRouteParams {
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

  private openNotice(item: NoticeRecord): void {
    logger.info('search result tapped: type=notice id=' + item.id + ' split=' + this.splitActive.toString());
    this.selectedId = item.id;
    // 分栏 → 右栏（参考实现给这次 navigate 补 disableAnimation:true，等价于 animated:false）。
    pushDetailFromMaster(this.stack, this.detailStack, this.splitActive,
      ROUTE_NOTICE_DETAIL, item, !this.splitActive);
  }

  private openAssignment(item: Assignment): void {
    logger.info('search result tapped: type=assignment id=' + item.id + ' split=' + this.splitActive.toString());
    this.selectedId = item.id;
    pushDetailFromMaster(this.stack, this.detailStack, this.splitActive,
      ROUTE_ASSIGNMENT_DETAIL, item, !this.splitActive);
  }

  private openFile(file: CourseFile): void {
    logger.info('search result tapped: type=file id=' + file.id + ' type=' + file.fileType
      + ' split=' + this.splitActive.toString());
    this.selectedId = file.id;
    pushDetailFromMaster(this.stack, this.detailStack, this.splitActive,
      ROUTE_FILE_DETAIL, this.fileParams(file), !this.splitActive);
  }

  /** 分栏开关翻转：与四个 tab 页同一套迁移（含退出分栏的对称回迁）。 */
  onSplitViewChanged(): void {
    if (this.splitActive) {
      AppStorage.setOrCreate(SPLIT_VIEW_MASTER_HIDDEN_KEY, false);
      const moved: number = migrateDetailRoutesInto(this.stack, this.detailStack);
      logger.info('split view enter: tab=search moved=' + moved.toString()
        + ' masterRoutes=' + this.stack.getAllPathName().length.toString()
        + ' detailRoutes=' + this.detailStack.getAllPathName().length.toString());
    } else {
      const moved: number = migrateDetailRoutesBack(this.detailStack, this.stack);
      logger.info('split view exit: tab=search moved=' + moved.toString()
        + ' masterRoutes=' + this.stack.getAllPathName().length.toString()
        + ' detailRoutes=' + this.detailStack.getAllPathName().length.toString());
    }
  }

  private masterPaneWidth(): Length {
    if (!this.splitActive) {
      return '100%';
    }
    return this.masterHidden ? 0 : SPLIT_VIEW_MASTER_WIDTH;
  }

  private timeTextOf(notice: NoticeRecord): string {
    const locale: string = i18nService.locale();
    const relative: string = formatRelativeTo(notice.publishTimeMillis, Date.now(), locale);
    if (relative.length > 0) {
      return relative;
    }
    return formatDateTimeShort(notice.publishTimeMillis, locale);
  }

  private errorText(): string {
    const message: string = this.store.errorMessage;
    if (message.includes('requiresEnrollment=true')) {
      return i18nService.t('loh_session_expired');
    }
    // 搜索页的数据来自**课程线的同一次抓取**（CourseListStore），所以失败文案用课程那条键。
    return i18nService.t('ui_courses_load_failed', message);
  }

  /* ------------------------------------------------------------------ *
   * 界面
   * ------------------------------------------------------------------ */

  /** 页头：左上角关闭 + 标题「搜索」（参考实现的 headerLeft=close / title=search / headerRight=null）。 */
  @Builder
  header() {
    Row() {
      Row() {
        IconGlyph({
          icon: AppIcon.CLOSE,
          glyphSize: this.theme().sizes.iconMedium,
          color: this.theme().colors.onSurface,
          // 关闭按钮的无障碍文案复用具名键 `loh_back`（返回/Back）—— 不新造键。
          label: this.s($r('app.string.loh_back'))
        })
      }
      .padding(this.theme().sizes.space2)
      .onClick(() => {
        // 关闭 = 弹**根栈**（见 SearchEntry.closeSearch 的注释：这里不能弹本页内部的详情栈）。
        closeSearch();
      })
      Text(this.s($r('app.string.loh_search')))
        .fontSize(this.theme().typography.headlineSmall.fontSize)
        .lineHeight(this.theme().typography.headlineSmall.lineHeight)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.theme().colors.onSurface)
        .margin({ left: this.theme().sizes.space2 })
      Blank()
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({
      left: this.theme().sizes.space2,
      right: this.theme().sizes.contentPadding,
      top: this.theme().sizes.space2,
      bottom: this.theme().sizes.space1
    })
  }

  /** 搜索框（参考实现的 Paper Searchbar：placeholder = searchPlaceholder）。 */
  @Builder
  searchBar() {
    Search({
      value: this.query,
      placeholder: this.s($r('app.string.loh_search_placeholder'))
    })
      .id(SEARCH_INPUT_ID)
      .key(SEARCH_INPUT_ID)
      .height(this.theme().sizes.controlHeight)
      .width('100%')
      .backgroundColor(this.theme().colors.surfaceVariant)
      .placeholderColor(this.theme().colors.outline)
      .textFont({ size: this.theme().typography.bodyLarge.fontSize })
      .onChange((value: string) => {
        this.query = value;
        this.recompute('typing');
      })
      .onFocus(() => {
        // 消费点自证：自动聚焦真的到了输入框（只打"我请求了 focus"不足以证明）。
        logger.info('search input focused: query="' + this.query + '"');
      })
      .onBlur(() => {
        logger.info('search input blurred: query="' + this.query + '"');
      })
      .margin({
        left: this.theme().sizes.contentPadding,
        right: this.theme().sizes.contentPadding,
        bottom: this.theme().sizes.space2
      })
  }

  @Builder
  sectionHeader(title: string) {
    Text(title)
      .fontSize(this.theme().typography.titleSmall.fontSize)
      .fontColor(this.theme().colors.outline)
      .width('100%')
      .padding({
        left: this.theme().sizes.contentPadding,
        right: this.theme().sizes.contentPadding,
        top: this.theme().sizes.space3,
        bottom: this.theme().sizes.space2
      })
  }

  /** 结果行共用的版式：类型（段头已给）+ 所属课程 + 标题 + 一行副信息。 */
  @Builder
  rowBody(spec: SearchRowSpec) {
    Column() {
      Text(spec.courseName)
        .fontSize(this.theme().typography.labelMedium.fontSize)
        .fontColor(this.theme().colors.onSurfaceVariant)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Text(spec.title)
        .fontSize(this.theme().typography.titleMedium.fontSize)
        .lineHeight(this.theme().typography.titleMedium.lineHeight)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.theme().colors.onSurface)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .margin({ top: this.theme().sizes.space1 })
      if (spec.preview.length > 0) {
        Text(spec.preview)
          .fontSize(this.theme().typography.bodyMedium.fontSize)
          .lineHeight(this.theme().typography.bodyMedium.lineHeight)
          .fontColor(this.theme().colors.onSurfaceVariant)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .margin({ top: this.theme().sizes.space1 })
      }
      if (spec.meta.length > 0) {
        Text(spec.meta)
          .fontSize(this.theme().typography.labelSmall.fontSize)
          .fontColor(this.theme().colors.onSurfaceVariant)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .margin({ top: this.theme().sizes.space2 })
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({
      left: this.theme().sizes.contentPadding,
      right: this.theme().sizes.contentPadding,
      top: this.theme().sizes.space3,
      bottom: this.theme().sizes.space3
    })
    .backgroundColor(spec.selected ? this.theme().colors.surfaceVariant : this.theme().colors.surface)
  }

  /** 公告结果行：类型由段头给出，行内标出**所属课程**。 */
  @Builder
  noticeRow(item: NoticeRecord) {
    ListItem() {
      this.rowBody({
        courseName: item.courseName,
        title: removeTags(item.title),
        meta: item.publisher + ' · ' + this.timeTextOf(item),
        preview: removeTags(item.content),
        selected: this.splitActive && this.selectedId === item.id
      })
    }
    .onClick(() => {
      this.openNotice(item);
    })
  }

  /** 作业结果行。 */
  @Builder
  assignmentRow(item: Assignment) {
    ListItem() {
      this.rowBody({
        courseName: item.courseName,
        title: removeTags(item.title),
        meta: item.courseTeacherName + ' · ' + item.deadline,
        preview: removeTags(item.description),
        selected: this.splitActive && this.selectedId === item.id
      })
    }
    .onClick(() => {
      this.openAssignment(item);
    })
  }

  /** 文件结果行（副信息就是文件列表那一行 `TYPE SIZE`）。 */
  @Builder
  fileRow(item: CourseFile) {
    ListItem() {
      this.rowBody({
        courseName: item.courseName,
        title: removeTags(item.title),
        meta: fileMetaLine(item.fileType, item.size),
        preview: removeTags(item.description),
        selected: this.splitActive && this.selectedId === item.id
      })
    }
    .onClick(() => {
      this.openFile(item);
    })
  }

  @Builder
  results() {
    Stack() {
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
      } else if (this.store.hasError()) {
        Column() {
          Text(this.errorText())
            .fontSize(this.theme().typography.bodyMedium.fontSize)
            .fontColor(this.theme().colors.error)
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .padding(this.theme().sizes.contentPadding)
      } else if (this.totalHits() === 0) {
        // 三段都空 → Empty（参考实现 Search.tsx:77-86 的同一个判据）。
        EmptyState({ message: this.s($r('app.string.loh_empty')), isDark: this.isDark() })
      } else {
        List({ space: 0 }) {
          if (this.noticeHits.length > 0) {
            ListItem() {
              this.sectionHeader(this.s($r('app.string.ui_tab_notices')))
            }
            ForEach(this.noticeHits, (item: NoticeRecord) => {
              this.noticeRow(item)
            }, (item: NoticeRecord) => 'n' + item.id
              + '|' + (this.splitActive && this.selectedId === item.id ? 'sel' : 'nosel'))
          }
          if (this.assignmentHits.length > 0) {
            ListItem() {
              this.sectionHeader(this.s($r('app.string.loh_assignments')))
            }
            ForEach(this.assignmentHits, (item: Assignment) => {
              this.assignmentRow(item)
            }, (item: Assignment) => 'a' + item.id
              + '|' + (this.splitActive && this.selectedId === item.id ? 'sel' : 'nosel'))
          }
          if (this.fileHits.length > 0) {
            ListItem() {
              this.sectionHeader(this.s($r('app.string.loh_files')))
            }
            ForEach(this.fileHits, (item: CourseFile) => {
              this.fileRow(item)
            }, (item: CourseFile) => 'f' + item.id
              + '|' + (this.splitActive && this.selectedId === item.id ? 'sel' : 'nosel'))
          }
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
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  masterPane() {
    Column() {
      this.header()
      this.searchBar()
      this.results()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme().colors.background)
  }

  /**
   * 详情目标的真身：同一份路由表被两个导航容器共用（与四个 tab 页同一模式）。
   *
   * 路由集合 = 参考实现 SearchStack 的三条（NoticeDetail / AssignmentDetail / FileDetail）
   * **加** AssignmentSubmission：参考实现里提交页挂在**根级**的 AssignmentSubmissionStack 上，
   * 作业详情从搜索栈里 `navigate('AssignmentSubmissionStack')` 能到达（react-navigation 会向上找）；
   * 本工程的路由是本地的 NavDestination，不登记就进不去，所以必须一并登记（可观察行为一致）。
   */
  @Builder
  routeTo(name: string, param: object, stack: NavPathStack) {
    if (name === ROUTE_NOTICE_DETAIL) {
      NavDestination() {
        NoticeDetailPage({ notice: param as NoticeRecord, stack: stack, session: this.session })
      }
      .hideTitleBar(true)
    } else if (name === ROUTE_ASSIGNMENT_DETAIL) {
      NavDestination() {
        AssignmentDetailPage({
          assignment: param as Assignment, stack: stack, session: this.session, store: this.store
        })
      }
      .hideTitleBar(true)
    } else if (name === ROUTE_ASSIGNMENT_SUBMISSION) {
      NavDestination() {
        AssignmentSubmissionPage({ assignment: param as Assignment, stack: stack, store: this.store })
      }
      .hideTitleBar(true)
    } else if (name === ROUTE_FILE_DETAIL) {
      NavDestination() {
        FileDetailPage({ params: param as FileDetailRouteParams, stack: stack })
      }
      .hideTitleBar(true)
    }
  }

  @Builder
  masterDestination(name: string, param: object) {
    this.routeTo(name, param, this.stack)
  }

  @Builder
  detailDestination(name: string, param: object) {
    this.routeTo(name, param, this.detailStack)
  }

  /** 右栏的栈根：还没选中结果时的空态（对应参考实现 DetailStack 的 EmptyDetail）。 */
  @Builder
  detailPane() {
    Column() {
      EmptyState({ message: this.s($r('app.string.loh_empty')), isDark: this.isDark() })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme().colors.background)
  }

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
        // 从详情返回（左栏重新可见）且查询为空 → 重新聚焦（参考实现的 useIsFocused 那一支）。
        .onNavBarStateChange((isVisible: boolean) => {
          logger.info('search navbar visibility: ' + isVisible.toString());
          if (isVisible) {
            this.focusWhenEmpty('returned');
          }
        })
      }
      .width(this.masterPaneWidth())
      .height('100%')

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
        }
        .layoutWeight(1)
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
  }
}
