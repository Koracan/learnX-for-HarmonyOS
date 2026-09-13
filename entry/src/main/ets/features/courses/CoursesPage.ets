/*
 * 课程 tab：课程列表 + 详情栈的根。
 *
 * 对齐参考实现 `screens/Courses.tsx` 与 `components/CourseCard.tsx`：
 *
 * | 项 | 参考实现 | 这里 |
 * | --- | --- | --- |
 * | 卡片内容 | 教师名（Subheading）在上、课程名（Title）在下，右下三个计数（通知/事件/文件夹） | 同（顺序与位置照抄） |
 * | 计数 | `selectCoursesWithCounts`（未读公告 / 未完成作业 / 新文件），图标 MaterialIcons notifications/event/folder | `domain/courses/CourseCounts`（逐条对齐），图标为同一份字体的同一批码位 |
 * | 头部副标题 | `getSemesterTextFromId(currentSemesterId)`（:49） | 同，且**可点**进学期切换（见下） |
 * | 点击卡片 | `navigate('CourseDetail', item)`（:34-43） | 同（推入本 tab 的 NavPathStack） |
 * | 下拉刷新 | `getCoursesForSemester(currentSemesterId)` | `store.refresh()`（一次刷新含三域，计数才与列表同源） |
 * | 过滤 | FilterList 下拉（all / hidden） | 两个筛选片；屏蔽后课程从"全部"消失，可在"屏蔽"里取消 |
 *
 * **一处位置差异（有意）**：参考实现把"学期切换"放在设置栈
 * （`SemesterSelection` 路由在 `SettingsStackParams` 里），本工程的交付物把它与课程
 * 放在一起——头部那句学期文案可点。行为（列出可选学期、切换、列表随之更新）完全一致。
 *
 * 三种状态都显式呈现，**没有"失败就显示空列表"这条路**：
 *   - 首次加载 → 居中指示器；
 *   - 取数失败 → 错误文案（会话失效时用 `loh_session_expired`）；
 *   - 真的没有课程（且不在取数）→ 空态。
 */
import { ConfigurationConstant } from '@kit.AbilityKit';
import { ThemeTokens, resolveTheme } from '../../ui/theme/Tokens';
import { i18nService } from '../../core/i18n/I18n';
import { getSemesterTextFromId } from '../../core/i18n/DateTimeUtil';
import { COLOR_MODE_KEY, LOCALE_VERSION_KEY } from '../../entryability/EntryAbility';
import { Logger } from '../../core/log/Logger';
import { Assignment } from '../../domain/model/ContentItem';
import { CourseRecord } from '../../data/courses/CourseRepository';
import { EmptyState } from '../../ui/components/EmptyState';
import { SearchButton } from '../../ui/components/SearchButton';
import { FilterChip } from '../../ui/components/FilterChip';
import { ToastController, ToastOverlay } from '../../ui/components/Toast';
import { CourseHideAction } from '../../ui/components/SwipeActions';
import { PAGE_SHOWN_AT_KEY, pageHeaderUpdatedText } from '../shell/PageShown';
import { AppIcon } from '../../ui/icons/IconCatalog';
import { IconGlyph } from '../../ui/icons/IconGlyph';
import { SessionHeaderProvider, createSessionHeaderProvider } from '../../core/web/SessionHeaderProvider';
import { ContentFilter } from '../../domain/marks/ContentFilter';
import { MarksTab } from '../../domain/marks/CollectionFlags';
import { CollectionFlagsStore } from '../../data/marks/CollectionFlagsStore';
import { collectionFlagsStore } from '../marks/CollectionFlagsProvider';
import { isHiddenCourse } from '../marks/FilteredContent';
import { NoticeRecord } from '../../data/notices/NoticeRepository';
import { NoticeDetailPage } from '../notices/NoticeDetailPage';
import { ROUTE_NOTICE_DETAIL } from '../notices/NoticeRoutes';
import { CourseListStore } from './CourseListStore';
import { createCourseRepository } from './repository/CourseRepositoryProvider';
import { openSearch } from '../search/SearchEntry';
import {
  CourseDetailRouteParams, CourseFileDetailRouteParams, SemesterSelectionRouteParams,
  ROUTE_COURSE_DETAIL, ROUTE_COURSE_FILE_DETAIL, ROUTE_SEMESTER_SELECTION
} from './CourseRoutes';

// 作业详情真身与它的路由（课程详情的作业标签页也推这一条）。
import { AssignmentDetailPage } from '../assignments/AssignmentDetailPage';
import { ROUTE_ASSIGNMENT_DETAIL } from '../assignments/AssignmentRoutes';
// 作业详情里的附件点击 → FileDetail 路由（文件详情页是真身）。
import { FileDetailPage } from '../files/FileDetailPage';
import { fileDetailParamsFromCourseFile } from '../files/FileRoutes';
import { FileDetailRouteParams, ROUTE_FILE_DETAIL } from '../notices/NoticeRoutes';
import { CourseDetailPage } from './CourseDetailPage';
import { SemesterSelectionPage } from './SemesterSelectionPage';
import {
  SPLIT_VIEW_ACTIVE_KEY, SPLIT_VIEW_DIVIDER_WIDTH, SPLIT_VIEW_MASTER_HIDDEN_KEY,
  SPLIT_VIEW_MASTER_WIDTH, migrateDetailRoutesBack, migrateDetailRoutesInto, pushDetailFromMaster
} from '../shell/SplitView';

const logger: Logger = new Logger('features.courses');

/** 一行课程卡片的渲染参数。 */
interface CourseRowSpec {
  theme: ThemeTokens;
  course: CourseRecord;
  noticesLabel: string;
  assignmentsLabel: string;
  filesLabel: string;
  /** 双栏时这一行是不是"右栏正在显示的那一条"（主栏保留高亮）。 */
  selected: boolean;
}

/** 一个计数单元的渲染参数。 */
interface CountSpec {
  theme: ThemeTokens;
  /** 参考实现用的是 MaterialIcons 的三个图标（见 countGroup 的说明）。 */
  icon: AppIcon;
  count: number;
  label: string;
}

@Component
export struct CoursesPage {
  @StorageProp(COLOR_MODE_KEY) colorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageLink(LOCALE_VERSION_KEY) localeVersion: number = 0;
  /**
   * 「页面被显示」的时刻（AppStorage）：切走再切回、或从后台回到前台时由
   * `features/shell/PageShown.ets` 的 `markPageShown()` 刷新。
   * 页头那一行读它 ⇒ 键一变就用新的时间基准重算（这就是"相对时间不再冻结"的机制）。
   */
  @StorageProp(PAGE_SHOWN_AT_KEY) pageShownAtMillis: number = 0;
  @State refreshing: boolean = false;
  /** 当前过滤视图；初值 = 参考实现 settings.ts:28 的 course 默认值 all。 */
  @State filter: ContentFilter = ContentFilter.ALL;

  private store: CourseListStore = new CourseListStore(createCourseRepository());
  /** 进程内单例：屏蔽一门课要立刻影响公告 / 作业 / 文件三个列表。 */
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
    this.store.loadOnce();
    this.loadFlags();
    logger.info('courses page appear');
  }

  private async loadFlags(): Promise<void> {
    await this.flags.loadOnce();
    this.filter = this.flags.filterFor(MarksTab.COURSE);
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
   * 屏蔽课程（参考实现 selectFilteredCourses 的 {all, hidden}）
   * ------------------------------------------------------------------ */

  /** "全部"视图：没被屏蔽的课程。 */
  private visibleCourses(): CourseRecord[] {
    const out: CourseRecord[] = [];
    for (let i = 0; i < this.store.courses.length; i++) {
      const course: CourseRecord = this.store.courses[i];
      if (!isHiddenCourse(this.flags.hiddenCourseIds, course.id)) {
        out.push(course);
      }
    }
    return out;
  }

  /** "屏蔽"视图：被屏蔽的课程（屏蔽后仍能在这里取消）。 */
  private hiddenCourses(): CourseRecord[] {
    const out: CourseRecord[] = [];
    for (let i = 0; i < this.store.courses.length; i++) {
      const course: CourseRecord = this.store.courses[i];
      if (isHiddenCourse(this.flags.hiddenCourseIds, course.id)) {
        out.push(course);
      }
    }
    return out;
  }

  private shownCourses(): CourseRecord[] {
    return this.filter === ContentFilter.HIDDEN ? this.hiddenCourses() : this.visibleCourses();
  }

  /** 消费点自证：实际生效的过滤视图 + 课程数 + 屏蔽 id 集合（截图与日志两头可核）。 */
  private logApplied(reason: string): void {
    logger.info('courses applied: reason=' + reason
      + ' semester=' + this.store.semesterId
      + ' source=' + this.store.semesterSource
      + ' filter=' + this.filter.toString()
      + ' courses=' + this.store.courses.length.toString()
      + ' all=' + this.visibleCourses().length.toString()
      + ' hidden=' + this.hiddenCourses().length.toString()
      + ' hiddenCourseIds=' + this.flags.hiddenCourseIds.length.toString());
  }

  /**
   * 屏蔽 / 取消屏蔽（参考实现 FilterList.tsx:160-171 逐行对应）：
   * 取消屏蔽那一支的提示是"已撤销屏蔽"、**没有**撤销按钮；屏蔽那一支有。
   */
  private handleHide(course: CourseRecord, isHidden: boolean): void {
    this.flags.setHidden(course.id, !isHidden);
    if (isHidden) {
      this.toast.show(this.s($r('app.string.loh_undo_hide')), '', null);
    } else {
      this.toast.show(this.s($r('app.string.loh_hide_succeeded')), this.s($r('app.string.loh_undo')), () => {
        this.handleHide(course, true);
      });
    }
    this.logApplied('hide');
  }

  private selectFilter(next: ContentFilter): void {
    if (this.filter === next) {
      return;
    }
    this.filter = next;
    this.flags.selectFilter(MarksTab.COURSE, next);
    this.logApplied('filter');
  }

  /** 实际生效的学期文案（覆盖生效时界面上看到的就是它——要的"学期标识"）。 */
  private semesterText(): string {
    const semesterId: string = this.store.semesterId;
    if (semesterId.length === 0) {
      return '';
    }
    return getSemesterTextFromId(semesterId, i18nService.locale(), i18nService);
  }

  /**
   * 页头那一行"相对更新时间"：`刚刚更新` / `N 分钟前更新` / …。
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
    return i18nService.t('ui_courses_load_failed', message);
  }

  private async handlePullRefresh(): Promise<void> {
    this.refreshing = true;
    await this.store.refresh();
    this.refreshing = false;
    this.logApplied('refresh');
  }

  private openCourse(course: CourseRecord): void {
    logger.info('course tapped: id=' + course.id + ' name=' + course.name
      + ' split=' + this.splitActive.toString());
    const params: CourseDetailRouteParams = {
      courseId: course.id,
      courseName: course.name,
      courseTeacherName: course.teacherName
    };
    this.selectedId = course.id;
    pushDetailFromMaster(this.stack, this.detailStack, this.splitActive, ROUTE_COURSE_DETAIL, params);
  }

  private openSemesterSelection(): void {
    logger.info('semester picker opened: effective=' + this.store.semesterId
      + ' source=' + this.store.semesterSource);
    const params: SemesterSelectionRouteParams = { activeSemesterId: this.store.semesterId };
    // 学期切换也在参考实现的**详情**白名单里（SplitView.tsx:61），双栏时同样进右栏。
    pushDetailFromMaster(this.stack, this.detailStack, this.splitActive,
      ROUTE_SEMESTER_SELECTION, params);
  }

  /**
   * 分栏开关翻转（消费点自证）：进分栏把主栈上的详情段搬到右栏、左栏回列表；
   * 退出分栏把右栏的详情搬回主栈（**本工程补做**）。
   */
  onSplitViewChanged(): void {
    if (this.splitActive) {
      AppStorage.setOrCreate(SPLIT_VIEW_MASTER_HIDDEN_KEY, false);
      const moved: number = migrateDetailRoutesInto(this.stack, this.detailStack);
      logger.info('split view enter: tab=courses moved=' + moved.toString()
        + ' masterRoutes=' + this.stack.getAllPathName().length.toString()
        + ' detailRoutes=' + this.detailStack.getAllPathName().length.toString());
    } else {
      const moved: number = migrateDetailRoutesBack(this.detailStack, this.stack);
      logger.info('split view exit: tab=courses moved=' + moved.toString()
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
   * 页头（账号所有者点名）：**「标题 + 学期 + 相对更新时间」压在标题所在的那一行区域内**。
   *
   * **"同一行"的语义（账号所有者 2026-09-12 澄清）**：指的是**三项都落在标题所在的那一行**
   * —— 不是"排成一行文字"。标题字号大（headlineSmall 24vp），右侧**竖排两行小字**（学期在上、更新时间在下）
   * 正是原话与账号所有者给的示意图所表达的样子；统筹一度按字面读成"必须单行"并据此打回一次，已被否定。
   * 参考实现同构：`components/HeaderTitle.tsx:25-43` 是 `flexDirection:'row'`，左侧大标题、右侧一小段副标题。
   *
   * 与参考实现的关系：参考实现**只有课程页**给页头传学期副标题（`screens/Courses.tsx:48-50`），
   * 这一条我们照做；而"更新时间"是参考实现没有的元素（有意偏离）。
   *
   * 移除的两项：`当前学期` 前缀（三个字占位但没有信息量）、课程条数那个**裸数字**
   * （没有标签，且列表就在下方），以及 `取证覆盖生效` 徽标（对用户无意义）。
   * **学期文本仍然可点** → 学期切换页（行为一字未改）。
   */
  @Builder
  header() {
    Row() {
      Text(this.s($r('app.string.loh_courses')))
        .fontSize(this.theme().typography.headlineSmall.fontSize)
        .lineHeight(this.theme().typography.headlineSmall.lineHeight)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.theme().colors.onSurface)
      Column() {
        // 实际生效的学期（覆盖/界面选择/站点当前学期三者的结果）——界面信号只剩这一处。
        Text(this.semesterText())
          .fontSize(this.theme().typography.labelMedium.fontSize)
          .fontColor(this.theme().colors.primary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.updatedText())
          .fontSize(this.theme().typography.labelSmall.fontSize)
          .fontColor(this.theme().colors.onSurfaceVariant)
          .maxLines(1)
          .margin({ top: this.theme().sizes.space1 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: this.theme().sizes.space3 })
      .onClick(() => {
        this.openSemesterSelection();
      })
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
    .alignItems(VerticalAlign.Center)
    .padding({
      left: this.theme().sizes.contentPadding,
      right: this.theme().sizes.contentPadding,
      top: this.theme().sizes.space4,
      bottom: this.theme().sizes.space2
    })
  }

  /** 过滤条：课程只有 all / hidden 两个视图（参考实现 selectFilteredCourses）。 */
  @Builder
  filterRow() {
    Flex({ wrap: FlexWrap.Wrap }) {
      FilterChip({
        label: this.s($r('app.string.loh_all')), count: this.visibleCourses().length,
        active: this.filter === ContentFilter.ALL, isDark: this.isDark(),
        onTap: () => {
          this.selectFilter(ContentFilter.ALL);
        }
      })
      FilterChip({
        label: this.s($r('app.string.loh_hidden')), count: this.hiddenCourses().length,
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

  /** 滑动操作：屏蔽 / 取消屏蔽（参考实现 CardWrapper.tsx:63-79）。 */
  @Builder
  swipeEnd(course: CourseRecord) {
    CourseHideAction({
      hidden: isHiddenCourse(this.flags.hiddenCourseIds, course.id),
      label: this.s(isHiddenCourse(this.flags.hiddenCourseIds, course.id)
        ? $r('app.string.ui_unhide_course') : $r('app.string.loh_hidden')),
      onHide: () => {
        this.handleHide(course, isHiddenCourse(this.flags.hiddenCourseIds, course.id));
      }
    })
  }

  /** 长按菜单（参考实现长按展开操作区 CardWrapper.tsx:161-166 的等价入口）。 */
  @Builder
  rowMenu(course: CourseRecord) {
    Menu() {
      MenuItem({
        content: this.s(isHiddenCourse(this.flags.hiddenCourseIds, course.id)
          ? $r('app.string.ui_unhide_course') : $r('app.string.loh_hidden'))
      })
        .onClick(() => {
          this.handleHide(course, isHiddenCourse(this.flags.hiddenCourseIds, course.id));
        })
    }
  }

  /**
   * 一个计数单元：图标 + 数字（参考实现是 MaterialIcons 的
   * notifications / event / folder，颜色取 `theme.colors.outline`）。
   * 改用**与参考实现同源的字体图标**（同一份 TTF、同一批码位），不再是 emoji；
   * 语义文字仍进无障碍树（`accessibilityText`），数字仍然逐字可见。
   */
  @Builder
  countGroup(spec: CountSpec) {
    Row() {
      IconGlyph({
        icon: spec.icon, glyphSize: spec.theme.sizes.iconSmall, color: spec.theme.colors.outline
      })
      Text(spec.count.toString())
        .fontSize(spec.theme.typography.labelMedium.fontSize)
        .fontColor(spec.theme.colors.outline)
        .margin({ left: spec.theme.sizes.space1 })
    }
    .alignItems(VerticalAlign.Center)
    .margin({ left: spec.theme.sizes.space3 })
    .accessibilityText(spec.label + ' ' + spec.count.toString())
  }

  @Builder
  courseRow(spec: CourseRowSpec) {
    Column() {
      Text(spec.course.teacherName)
        .fontSize(spec.theme.typography.labelMedium.fontSize)
        .lineHeight(spec.theme.typography.labelMedium.lineHeight)
        .fontColor(spec.theme.colors.onSurfaceVariant)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Row() {
        Text(spec.course.name)
          .fontSize(spec.theme.typography.titleMedium.fontSize)
          .lineHeight(spec.theme.typography.titleMedium.lineHeight)
          .fontWeight(FontWeight.Medium)
          .fontColor(spec.theme.colors.onSurface)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        this.countGroup({
          theme: spec.theme, icon: AppIcon.NOTIFICATIONS, count: spec.course.unreadNoticeCount,
          label: spec.noticesLabel
        })
        this.countGroup({
          theme: spec.theme, icon: AppIcon.EVENT, count: spec.course.unfinishedAssignmentCount,
          label: spec.assignmentsLabel
        })
        this.countGroup({
          theme: spec.theme, icon: AppIcon.FOLDER, count: spec.course.unreadFileCount,
          label: spec.filesLabel
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)
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
    .onClick(() => {
      this.openCourse(spec.course);
    })
  }

  @Builder
  listBody() {
    Stack() {
      List({ space: 0 }) {
        ForEach(this.shownCourses(), (item: CourseRecord) => {
          ListItem() {
            this.courseRow({
              theme: this.theme(),
              course: item,
              noticesLabel: this.s($r('app.string.ui_course_unread_notices_label')),
              assignmentsLabel: this.s($r('app.string.ui_course_unfinished_assignments_label')),
              filesLabel: this.s($r('app.string.ui_course_new_files_label')),
              selected: this.splitActive && this.selectedId === item.id
            })
          }
          .swipeAction({ end: this.swipeEnd(item) })
          .bindContextMenu(this.rowMenu(item), ResponseType.LongPress)
        }, (item: CourseRecord) =>
          item.id + '|' + (isHiddenCourse(this.flags.hiddenCourseIds, item.id) ? 'hidden' : 'shown')
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
      } else if (this.shownCourses().length === 0 && !this.store.isBusy()) {
        EmptyState({
          message: this.filter === ContentFilter.HIDDEN
            ? this.s($r('app.string.loh_empty')) : this.s($r('app.string.ui_courses_empty')),
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
    if (name === ROUTE_COURSE_DETAIL) {
      NavDestination() {
        CourseDetailPage({
          params: param as CourseDetailRouteParams,
          store: this.store,
          stack: stack
        })
      }
      .hideTitleBar(true)
    } else if (name === ROUTE_SEMESTER_SELECTION) {
      NavDestination() {
        SemesterSelectionPage({ store: this.store, stack: stack })
      }
      .hideTitleBar(true)
    } else if (name === ROUTE_NOTICE_DETAIL) {
      // 课程详情里点公告 → 公告详情页（压在本 tab 自己的栈上）。
      NavDestination() {
        NoticeDetailPage({
          notice: param as NoticeRecord,
          stack: stack,
          session: this.session
        })
      }
      .hideTitleBar(true)
    } else if (name === ROUTE_ASSIGNMENT_DETAIL) {
      // 作业详情真身（参数就是整个 Assignment）。
      NavDestination() {
        AssignmentDetailPage({
          assignment: param as Assignment,
          stack: stack,
          session: this.session
        })
      }
      .hideTitleBar(true)
    } else if (name === ROUTE_FILE_DETAIL) {
      // 作业详情里的附件点击 → 文件详情真身。
      NavDestination() {
        FileDetailPage({ params: param as FileDetailRouteParams, stack: stack })
      }
      .hideTitleBar(true)
    } else if (name === ROUTE_COURSE_FILE_DETAIL) {
      // 课程详情的"文件"标签页 → 同一条文件详情真身（参数转换见 FileRoutes）。
      NavDestination() {
        FileDetailPage({
          params: fileDetailParamsFromCourseFile(param as CourseFileDetailRouteParams),
          stack: stack
        })
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

  /** 左栏内容 = 课程列表。 */
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
          logger.info('courses pull refresh state: ' + state.toString());
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
