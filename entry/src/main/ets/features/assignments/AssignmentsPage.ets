/*
 * 作业 tab：作业列表 + 详情栈的根。
 *
 * ## 数据来源：**复用课程线的同一次抓取**，不新造取数
 *
 * 统筹给的硬前提：学期覆盖（`aa start --ps lohSemester …`）
 * **只作用于课程那条线**；作业/公告/文件的 `fetchWithSession` 连学期参数都没有。
 * 如果作业 tab 自己去抓，在覆盖态下仍会取"站点当前学期"⇒ 2026-2027 秋季 ⇒ 空列表，
 * 而"空"同时也是账号事实 ⇒ 两个原因在日志上长得一样。
 *
 * 所以本页**直接用 `CourseListStore`**（课程状态），它的
 * `refresh()` → `data/courses/CourseFetchSource` 里读一次 `effectiveSemesterOverride()`
 * （优先级 override > 界面选择 > 站点当前学期**只有那一份实现**），并把三域内容装进
 * `CourseSnapshot`。作业线拿的就是 `snapshot.assignments` —— 覆盖态下就是春季那 57 条。
 * 交付文档里说明了这样做的代价（进两个 tab = 两次抓取）。
 *
 * ## 排序：不在界面层再排一次
 *
 * `AssignmentsFetcher.fetch` 返回前已经用
 * `domain/parse/AssignmentParser.compareAssignmentsByUpcoming` 排好
 * （未到期在前由近及远、已过期在后由远及近，与参考实现逐条对齐）。
 * 这里**只过滤不排序**（见 AssignmentFilter.ets 的文件头）。
 *
 * ## 与参考实现 AssignmentCard.tsx 的对照
 *
 * | 项 | 参考实现 | 这里 |
 * | --- | --- | --- |
 * | 课程名 / 标题（removeTags）/ 描述预览（2 行） | :43-48, :94-98 | 同 |
 * | 状态标记 | 五个图标：附件(橙 MCI) / 已提交(绿勾 MCI) / 已评分(MaterialIcons grade) / 答案(蓝 MCI) / 优秀(MCI medal) | 同序同色，用**同一份字体的同一批码位** |
 * | 截止时间那句 | `dayjs().isAfter(deadline) ? fromNow()+'截止' : '还剩 '+to(deadline,true)`（:103-108） | **绝对时间**（站点原文 `YYYY-MM-DD HH:mm`）+ 状态标记"未到期 / 已截止" |
 * | 过滤 | FilterList 下拉（unfinished / finished / all / fav / archived / hidden） | 六个筛选片，**顺序与计数口径照 Filter.tsx:153-218**；默认视图 unfinished 照 settings.ts:26 |
 *
 * 截止时间那句为什么换措辞：dayjs 的 `humanize`（"5 个月前" / "还剩 3 天"）在平台侧没有等价物 ——
 * `Intl.RelativeTimeFormat` 只能给 "5个月前" / "3天后"，无法去掉/加上参考那句前后缀。
 * 与其拼出"还剩 3天后"这种两种语言都不通顺的句子，这里显示**站点自己的截止时间原文**
 * 加一枚**本地化状态标记**（未到期 / 已截止），语义等价且可截图核对。详见交付说明。
 */
import { ConfigurationConstant } from '@kit.AbilityKit';
import { PLAIN_PALETTE, ThemeTokens, resolveTheme } from '../../ui/theme/Tokens';
import { i18nService } from '../../core/i18n/I18n';
import { PAGE_SHOWN_AT_KEY, pageHeaderUpdatedText } from '../shell/PageShown';
import { COLOR_MODE_KEY, LOCALE_VERSION_KEY } from '../../entryability/EntryAbility';
import { Logger } from '../../core/log/Logger';
import { Assignment } from '../../domain/model/ContentItem';
import { removeTags } from '../../domain/render/WebViewTemplate';
import { EmptyState } from '../../ui/components/EmptyState';
import { SearchButton } from '../../ui/components/SearchButton';
import { FilterChip } from '../../ui/components/FilterChip';
import { ToastController, ToastOverlay } from '../../ui/components/Toast';
import { ContentSwipeActions } from '../../ui/components/SwipeActions';
import { AppIcon } from '../../ui/icons/IconCatalog';
import { IconGlyph } from '../../ui/icons/IconGlyph';
import { SessionHeaderProvider, createSessionHeaderProvider } from '../../core/web/SessionHeaderProvider';
import { ContentFilter } from '../../domain/marks/ContentFilter';
import { MarksDomain, MarksTab } from '../../domain/marks/CollectionFlags';
import { CourseListStore } from '../courses/CourseListStore';
import { createCourseRepository } from '../courses/repository/CourseRepositoryProvider';
import { CollectionFlagsStore } from '../../data/marks/CollectionFlagsStore';
import { collectionFlagsStore } from '../marks/CollectionFlagsProvider';
import {
  AssignmentFilterCounts, FilteredAssignments, assignmentsForFilter, assignmentCounts,
  assignmentsContain, selectFilteredAssignments
} from '../marks/FilteredContent';
import { FileDetailPage } from '../files/FileDetailPage';
import { FileDetailRouteParams, ROUTE_FILE_DETAIL } from '../notices/NoticeRoutes';
import { AssignmentDetailPage } from './AssignmentDetailPage';
import { AssignmentSubmissionPage } from './AssignmentSubmissionPage';
import { ROUTE_ASSIGNMENT_DETAIL, ROUTE_ASSIGNMENT_SUBMISSION } from './AssignmentRoutes';
import {
  SPLIT_VIEW_ACTIVE_KEY, SPLIT_VIEW_DIVIDER_WIDTH, SPLIT_VIEW_MASTER_HIDDEN_KEY,
  SPLIT_VIEW_MASTER_WIDTH, migrateDetailRoutesBack, migrateDetailRoutesInto, pushDetailFromMaster
} from '../shell/SplitView';
import { countPastDue, hasAnswer, hasExcellentHomework, isPastDeadline } from './AssignmentFilter';
import { deadlineText, dueStatusText, emptyStateKey } from './AssignmentText';
import { evidenceAssignmentsOr, logAssignmentEvidenceState } from './AssignmentEvidence';
import { openSearch } from '../search/SearchEntry';

const logger: Logger = new Logger('features.assignments');

/** 单行作业的渲染参数（@Builder 按引用传参）。 */
interface AssignmentRowSpec {
  theme: ThemeTokens;
  assignment: Assignment;
  titleText: string;
  descriptionText: string;
  teacherText: string;
  deadlineLine: string;
  dueText: string;
  /** 已过截止时间（决定 dueText 的颜色）；不用"文案是否等于某串"来判断。 */
  dueIsPast: boolean;
  attachmentLabel: string;
  submittedLabel: string;
  gradedLabel: string;
  answerLabel: string;
  excellentLabel: string;
  /** 双栏时这一行是不是"右栏正在显示的那一条"（主栏保留高亮）。 */
  selected: boolean;
}

@Component
export struct AssignmentsPage {
  @StorageProp(COLOR_MODE_KEY) colorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageLink(LOCALE_VERSION_KEY) localeVersion: number = 0;
  /**
   * 「页面被显示」的时刻（AppStorage）：切走再切回、或从后台回到前台时由
   * `features/shell/PageShown.ets` 的 `markPageShown()` 刷新。
   * 页头那一行读它 ⇒ 键一变就用新的时间基准重算（这就是"相对时间不再冻结"的机制）。
   */
  @StorageProp(PAGE_SHOWN_AT_KEY) pageShownAtMillis: number = 0;
  @State refreshing: boolean = false;
  /** 当前过滤视图；初值 = 参考实现 settings.ts:26 的 assignment 默认值 unfinished。 */
  @State filter: ContentFilter = ContentFilter.UNFINISHED;

  private store: CourseListStore = new CourseListStore(createCourseRepository());
  /** 进程内单例：与公告 / 文件 / 课程三个列表共用同一份收藏与屏蔽状态。 */
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
  private session: SessionHeaderProvider = createSessionHeaderProvider();

  aboutToAppear(): void {
    // 取证开关自证生效（AGENTS.md）：实际生效值进 hilog。
    logAssignmentEvidenceState();
    this.loadAndLog();
    logger.info('assignments page appear');
  }

  /** 首次取数完成后打一行消费点自证（不阻塞首帧）。 */
  private async loadAndLog(): Promise<void> {
    await this.store.loadOnce();
    await this.flags.loadOnce();
    this.filter = this.flags.filterFor(MarksTab.ASSIGNMENT);
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

  /** 真实数据（取证态下被夹具整体替换）。 */
  private sourceAssignments(): Assignment[] {
    return evidenceAssignmentsOr(this.store.assignments, Date.now());
  }

  /* ------------------------------------------------------------------ *
   * 收藏 / 归档 / 屏蔽（与公告 / 文件共用 features/marks 的同一套语义）
   * ------------------------------------------------------------------ */

  /** 过滤后的六个分组（逐行对齐参考实现 selectFilteredAssignments）。 */
  private filtered(): FilteredAssignments {
    return selectFilteredAssignments(this.sourceAssignments(), this.flags.assignmentFavorites,
      this.flags.assignmentArchived, this.flags.hiddenCourseIds);
  }

  /** 当前筛选下的可见列表；**顺序就是取数时的顺序**（不在这里排序）。 */
  private visibleAssignments(): Assignment[] {
    return assignmentsForFilter(this.filtered(), this.filter);
  }

  private counts(): AssignmentFilterCounts {
    return assignmentCounts(this.filtered());
  }

  /**
   * 消费点自证：把**实际生效的学期与来源**连同作业条数、六组计数打进 hilog。
   * 作业线的取证要求"既要看到 data.courses effective semester=… source=override，
   * 也要看到作业消费点的行"（见统筹提示）。
   */
  private logApplied(reason: string): void {
    const items: Assignment[] = this.sourceAssignments();
    const nowMillis: number = Date.now();
    const counts: AssignmentFilterCounts = this.counts();
    logger.info('assignments applied: reason=' + reason
      + ' semester=' + this.store.semesterId
      + ' source=' + this.store.semesterSource
      + ' siteCurrent=' + this.store.siteCurrentSemesterId
      + ' items=' + items.length.toString()
      + ' visible=' + this.visibleAssignments().length.toString()
      + ' filter=' + this.filter.toString()
      + ' all=' + counts.all.toString()
      + ' unfinished=' + counts.unfinished.toString()
      + ' finished=' + counts.finished.toString()
      + ' fav=' + counts.fav.toString()
      + ' archived=' + counts.archived.toString()
      + ' hidden=' + counts.hidden.toString()
      + ' favoriteIds=' + this.flags.assignmentFavorites.length.toString()
      + ' archivedIds=' + this.flags.assignmentArchived.length.toString()
      + ' hiddenCourses=' + this.flags.hiddenCourseIds.length.toString()
      + ' pastDue=' + countPastDue(items, nowMillis).toString());
  }

  /** 收藏 / 取消收藏（flag 语义与参考实现 FilterList.tsx:119-139 逐行对应）。 */
  private handleFav(item: Assignment, isFav: boolean): void {
    this.flags.setFavorite(MarksDomain.ASSIGNMENT, item.id, !isFav);
    if (isFav) {
      this.toast.show(this.s($r('app.string.loh_remove_from_fav')), '', null);
    } else {
      this.toast.show(this.s($r('app.string.loh_add_to_fav')), this.s($r('app.string.loh_undo')), () => {
        this.handleFav(item, true);
      });
    }
    this.logApplied('favorite');
  }

  /** 归档 / 取消归档（参考实现：取消归档那一支没有撤销按钮）。 */
  private handleArchive(item: Assignment, isArchived: boolean): void {
    this.flags.setArchived(MarksDomain.ASSIGNMENT, [item.id], !isArchived);
    if (isArchived) {
      this.toast.show(this.s($r('app.string.loh_undo_archive')), '', null);
    } else {
      this.toast.show(this.s($r('app.string.loh_archive_succeeded')), this.s($r('app.string.loh_undo')), () => {
        this.handleArchive(item, true);
      });
    }
    this.logApplied('archive');
  }

  /**
   * 页头那一行"相对更新时间"：`刚刚更新` / `N 分钟前更新` / …。
   * 数据源仍是快照的 `fetchedAtMillis`（不新增取数）；四档边界在 `ui/components/UpdatedTime.ets`。
   *
   * 原 `semesterText()` 已删除：学期只在**课程页头**显示（账号所有者点名）。
   *
   * 时间基准是"本页最近一次被显示的时刻"（`features/shell/PageShown.ets`）：切走再切回、
   * 回到前台都会重算；实现只有那一处，本页只订阅键并把两个数传进去。
   */
  private updatedText(): string {
    return pageHeaderUpdatedText(this.store.fetchedAtMillis, this.pageShownAtMillis);
  }

  private errorText(): string {
    const message: string = this.store.errorMessage;
    if (message.includes('requiresEnrollment=true')) {
      return i18nService.t('loh_session_expired');
    }
    return i18nService.t('ui_assignments_load_failed', message);
  }

  private async handlePullRefresh(): Promise<void> {
    this.refreshing = true;
    await this.store.refresh();
    this.refreshing = false;
    this.logApplied('refresh');
  }

  private selectFilter(next: ContentFilter): void {
    if (this.filter === next) {
      return;
    }
    this.filter = next;
    this.flags.selectFilter(MarksTab.ASSIGNMENT, next);
    this.logApplied('filter');
  }

  private openDetail(assignment: Assignment): void {
    logger.info('assignment tapped: id=' + assignment.id + ' courseId=' + assignment.courseId
      + ' submitted=' + assignment.submitted.toString()
      + ' graded=' + assignment.graded.toString()
      + ' deadline=' + assignment.deadline
      + ' split=' + this.splitActive.toString());
    this.selectedId = assignment.id;
    pushDetailFromMaster(this.stack, this.detailStack, this.splitActive,
      ROUTE_ASSIGNMENT_DETAIL, assignment);
  }

  /**
   * 分栏开关翻转（消费点自证）：进分栏把主栈上的详情段搬到右栏、左栏回列表；
   * 退出分栏把右栏的详情搬回主栈（**本工程补做**）。
   */
  onSplitViewChanged(): void {
    if (this.splitActive) {
      AppStorage.setOrCreate(SPLIT_VIEW_MASTER_HIDDEN_KEY, false);
      const moved: number = migrateDetailRoutesInto(this.stack, this.detailStack);
      logger.info('split view enter: tab=assignments moved=' + moved.toString()
        + ' masterRoutes=' + this.stack.getAllPathName().length.toString()
        + ' detailRoutes=' + this.detailStack.getAllPathName().length.toString());
    } else {
      const moved: number = migrateDetailRoutesBack(this.detailStack, this.stack);
      logger.info('split view exit: tab=assignments moved=' + moved.toString()
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
   * 页头（账号所有者点名）：**只剩「标题 + 相对更新时间」一行**。
   *
   * 移除的三项与理由：
   *   - `当前学期 <学期>`：学期**只在课程页**显示（这正是参考实现的做法，见 `screens/Courses.tsx:48-50`）；
   *   - `取证覆盖生效` 徽标：对用户无意义（覆盖生效的机制证据在 hilog 的消费点行）；
   *   - `未完成 n`：筛选片里已有同一个数字，重复。
   * **注意**：这里删掉的只是**界面元素**，取数与筛选行为一行未动。
   */
  @Builder
  header() {
    Column() {
      Row() {
        Text(this.s($r('app.string.loh_assignments')))
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
        // 页头右侧的搜索入口（参考实现 App.tsx:137-158 的 headerRight）。
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

  /**
   * 过滤条：六个视图与计数，**顺序与参考实现 Filter.tsx:153-218 一致**
   * （unfinished → finished → all → fav → archived → hidden；作业没有 unread 视图）。
   */
  @Builder
  filterRow() {
    Flex({ wrap: FlexWrap.Wrap }) {
      FilterChip({
        label: this.s($r('app.string.loh_unfinished')), count: this.counts().unfinished,
        active: this.filter === ContentFilter.UNFINISHED, isDark: this.isDark(),
        onTap: () => {
          this.selectFilter(ContentFilter.UNFINISHED);
        }
      })
      FilterChip({
        label: this.s($r('app.string.loh_finished')), count: this.counts().finished,
        active: this.filter === ContentFilter.FINISHED, isDark: this.isDark(),
        onTap: () => {
          this.selectFilter(ContentFilter.FINISHED);
        }
      })
      FilterChip({
        label: this.s($r('app.string.loh_all')), count: this.counts().all,
        active: this.filter === ContentFilter.ALL, isDark: this.isDark(),
        onTap: () => {
          this.selectFilter(ContentFilter.ALL);
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

  /** 滑动操作（右侧）：收藏（已归档的行不渲染）+ 归档。 */
  @Builder
  swipeEnd(item: Assignment, fav: boolean, archived: boolean) {
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

  /** 长按菜单（参考实现长按展开操作区 CardWrapper.tsx:161-166 的等价入口）。 */
  @Builder
  rowMenu(item: Assignment, fav: boolean, archived: boolean) {
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
   * 卡片右上角的状态标记 —— 逐项对齐参考实现 `AssignmentCard.tsx:52-92`：
   *   附件（MCI `attachment` orange500）→ 已提交（MCI `check` green500）→
   *   已评分（MaterialIcons `grade` red500）→ 有答案（MCI `key-variant` blue500）→
   *   优秀作业（MCI `medal` yellow500）。
   * 与参考实现**同一份字体、同一批码位**，不再是 emoji。
   */
  @Builder
  statusIcons(spec: AssignmentRowSpec) {
    Row() {
      if (spec.assignment.attachment !== undefined) {
        IconGlyph({
          icon: AppIcon.ATTACHMENT, glyphSize: spec.theme.sizes.iconSmall,
          color: PLAIN_PALETTE.orange500, label: spec.attachmentLabel,
          marginLeft: spec.theme.sizes.space1
        })
      }
      if (spec.assignment.submitted) {
        IconGlyph({
          icon: AppIcon.CHECK, glyphSize: spec.theme.sizes.iconSmall,
          color: PLAIN_PALETTE.green500, label: spec.submittedLabel,
          marginLeft: spec.theme.sizes.space1
        })
      }
      if (spec.assignment.graded) {
        IconGlyph({
          icon: AppIcon.GRADE, glyphSize: spec.theme.sizes.iconSmall,
          color: PLAIN_PALETTE.red500, label: spec.gradedLabel,
          marginLeft: spec.theme.sizes.space1
        })
      }
      if (hasAnswer(spec.assignment)) {
        IconGlyph({
          icon: AppIcon.KEY_VARIANT, glyphSize: spec.theme.sizes.iconSmall,
          color: PLAIN_PALETTE.blue500, label: spec.answerLabel,
          marginLeft: spec.theme.sizes.space1
        })
      }
      // 优秀作业（补做）：参考实现 AssignmentCard.tsx:84-91 的黄色 medal。
      if (hasExcellentHomework(spec.assignment)) {
        IconGlyph({
          icon: AppIcon.MEDAL, glyphSize: spec.theme.sizes.iconSmall,
          color: PLAIN_PALETTE.yellow500, label: spec.excellentLabel,
          marginLeft: spec.theme.sizes.space1
        })
      }
    }
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  assignmentRow(spec: AssignmentRowSpec) {
    Column() {
      Text(spec.assignment.courseName)
        .fontSize(spec.theme.typography.labelMedium.fontSize)
        .lineHeight(spec.theme.typography.labelMedium.lineHeight)
        .fontColor(spec.theme.colors.onSurfaceVariant)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Row() {
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
      if (spec.descriptionText.length > 0) {
        Text(spec.descriptionText)
          .fontSize(spec.theme.typography.bodyMedium.fontSize)
          .lineHeight(spec.theme.typography.bodyMedium.lineHeight)
          .fontColor(spec.theme.colors.onSurfaceVariant)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .margin({ top: spec.theme.sizes.space1 })
      }
      Row() {
        Text(spec.teacherText)
          .fontSize(spec.theme.typography.labelSmall.fontSize)
          .fontColor(spec.theme.colors.onSurfaceVariant)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(spec.deadlineLine)
          .fontSize(spec.theme.typography.labelSmall.fontSize)
          .fontColor(spec.theme.colors.onSurfaceVariant)
          .margin({ left: spec.theme.sizes.space2 })
        Text(spec.dueText)
          .fontSize(spec.theme.typography.labelSmall.fontSize)
          .fontColor(spec.dueIsPast ? spec.theme.colors.error : spec.theme.colors.primary)
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
    // 双栏时把"右栏正在显示的那一条"高亮出来（主栏保留高亮状态）。
    .backgroundColor(spec.selected ? spec.theme.colors.surfaceVariant : spec.theme.colors.surface)
    .onClick(() => {
      this.openDetail(spec.assignment);
    })
  }

  @Builder
  listBody() {
    Stack() {
      List({ space: 0 }) {
        ForEach(this.visibleAssignments(), (item: Assignment) => {
          ListItem() {
            this.assignmentRow({
              theme: this.theme(),
              assignment: item,
              titleText: removeTags(item.title),
              descriptionText: removeTags(item.description),
              teacherText: item.courseTeacherName,
              deadlineLine: deadlineText(item.deadline),
              dueText: dueStatusText(item.deadline, Date.now()),
              dueIsPast: isPastDeadline(item.deadline, Date.now()),
              attachmentLabel: this.s($r('app.string.ui_assignment_attachment_label')),
              submittedLabel: this.s($r('app.string.ui_assignment_submitted_mark_label')),
              gradedLabel: this.s($r('app.string.ui_assignment_graded_mark_label')),
              answerLabel: this.s($r('app.string.ui_assignment_answer_mark_label')),
              excellentLabel: this.s($r('app.string.ui_assignment_excellent_mark_label')),
              selected: this.splitActive && this.selectedId === item.id
            })
          }
          .swipeAction({
            // 收藏状态取**原始收藏集合**（理由同公告页：过滤后的 fav 分组只在 all 之内）。
            end: this.swipeEnd(item, this.flags.assignmentFavorites.includes(item.id),
              assignmentsContain(this.filtered().archived, item.id))
          })
          .bindContextMenu(this.rowMenu(item, this.flags.assignmentFavorites.includes(item.id),
            assignmentsContain(this.filtered().archived, item.id)), ResponseType.LongPress)
        }, (item: Assignment) =>
          item.id
          + '|' + (this.flags.assignmentFavorites.includes(item.id) ? 'fav' : 'nofav')
          + '|' + (assignmentsContain(this.filtered().archived, item.id) ? 'arch' : 'noarch')
          // 高亮态要进 key：否则 ForEach 认为这一项没变、不会重建行（选中态就不会跟着变）。
          + '|' + (this.splitActive && this.selectedId === item.id ? 'sel' : 'nosel'))
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
      } else if (this.visibleAssignments().length === 0 && !this.store.isBusy()) {
        EmptyState({
          message: i18nService.t(emptyStateKey(this.filter)),
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
    if (name === ROUTE_ASSIGNMENT_DETAIL) {
      NavDestination() {
        AssignmentDetailPage({
          assignment: param as Assignment,
          stack: stack,
          session: this.session,
          // 提交成功后要重新取数：把**同一个** CourseListStore 实例传下去，
          // 不新建一份取数路径（见 AssignmentsPage 文件头「复用课程线的同一次抓取」）。
          store: this.store
        })
      }
      .hideTitleBar(true)
    } else if (name === ROUTE_ASSIGNMENT_SUBMISSION) {
      NavDestination() {
        AssignmentSubmissionPage({
          assignment: param as Assignment,
          stack: stack,
          store: this.store
        })
      }
      .hideTitleBar(true)
    } else if (name === ROUTE_FILE_DETAIL) {
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

  /** 左栏内容 = 作业列表。 */
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
          logger.info('assignments pull refresh state: ' + state.toString());
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
