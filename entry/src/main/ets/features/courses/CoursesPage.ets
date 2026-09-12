/*
 * 课程 tab（ticket 12）：课程列表 + 详情栈的根。
 *
 * 对齐参考实现 `screens/Courses.tsx` 与 `components/CourseCard.tsx`：
 *
 * | 项 | 参考实现 | 这里 |
 * | --- | --- | --- |
 * | 卡片内容 | 教师名（Subheading）在上、课程名（Title）在下，右下三个计数（通知/事件/文件夹） | 同（顺序与位置照抄） |
 * | 计数 | `selectCoursesWithCounts`（未读公告 / 未完成作业 / 新文件） | `domain/courses/CourseCounts`（逐条对齐） |
 * | 头部副标题 | `getSemesterTextFromId(currentSemesterId)`（:49） | 同，且**可点**进学期切换（见下） |
 * | 点击卡片 | `navigate('CourseDetail', item)`（:34-43） | 同（推入本 tab 的 NavPathStack） |
 * | 下拉刷新 | `getCoursesForSemester(currentSemesterId)` | `store.refresh()`（一次刷新含三域，计数才与列表同源） |
 *
 * **一处位置差异（有意，写进 ticket Comments）**：参考实现把"学期切换"放在设置栈
 * （`SemesterSelection` 路由在 `SettingsStackParams` 里），ticket 12 的交付物把它与课程
 * 放在一起——头部那句学期文案可点。行为（列出可选学期、切换、列表随之更新）完全一致。
 *
 * 三种状态都显式呈现，**没有"失败就显示空列表"这条路**：
 *   - 首次加载 → 居中指示器；
 *   - 取数失败 → 错误文案（会话失效时用 ticket 08 的 `loh_session_expired`）；
 *   - 真的没有课程（且不在取数）→ 空态。
 */
import { ConfigurationConstant } from '@kit.AbilityKit';
import { ThemeTokens, resolveTheme } from '../../ui/theme/Tokens';
import { i18nService } from '../../core/i18n/I18n';
import {
  DateTimeFormatOptions, PlatformDateTimeFormatter, formatDateTimeUsing, formatRelativeTo
} from '../../core/i18n/DateTimeUtil';
import { getSemesterTextFromId } from '../../core/i18n/DateTimeUtil';
import { COLOR_MODE_KEY, LOCALE_VERSION_KEY } from '../../entryability/EntryAbility';
import { Logger } from '../../core/log/Logger';
import { CourseRecord } from '../../data/courses/CourseRepository';
import { EmptyState } from '../../ui/components/EmptyState';
import { SessionHeaderProvider, createSessionHeaderProvider } from '../../core/web/SessionHeaderProvider';
import { NoticeRecord } from '../../data/notices/NoticeRepository';
import { NoticeDetailPage } from '../notices/NoticeDetailPage';
import { ROUTE_NOTICE_DETAIL } from '../notices/NoticeRoutes';
import { CourseListStore } from './CourseListStore';
import { createCourseRepository } from './repository/CourseRepositoryProvider';
import {
  AssignmentDetailRouteParams, CourseDetailRouteParams, CourseFileDetailRouteParams,
  SemesterSelectionRouteParams,
  ROUTE_ASSIGNMENT_DETAIL, ROUTE_COURSE_DETAIL, ROUTE_COURSE_FILE_DETAIL, ROUTE_SEMESTER_SELECTION
} from './CourseRoutes';
import {
  AssignmentDetailPlaceholderPage, CourseFileDetailPlaceholderPage
} from './CourseDetailPlaceholder';
import { CourseDetailPage } from './CourseDetailPage';
import { SemesterSelectionPage } from './SemesterSelectionPage';

const logger: Logger = new Logger('features.courses');

/** 一行课程卡片的渲染参数。 */
interface CourseRowSpec {
  theme: ThemeTokens;
  course: CourseRecord;
  noticesLabel: string;
  assignmentsLabel: string;
  filesLabel: string;
}

/** 一个计数单元的渲染参数。 */
interface CountSpec {
  theme: ThemeTokens;
  symbol: string;
  count: number;
  label: string;
}

@Component
export struct CoursesPage {
  @StorageProp(COLOR_MODE_KEY) colorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageLink(LOCALE_VERSION_KEY) localeVersion: number = 0;
  @State refreshing: boolean = false;

  private store: CourseListStore = new CourseListStore(createCourseRepository());
  private stack: NavPathStack = new NavPathStack();
  private session: SessionHeaderProvider = createSessionHeaderProvider();

  aboutToAppear(): void {
    this.store.loadOnce();
    logger.info('courses page appear');
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

  /** 实际生效的学期文案（覆盖生效时界面上看到的就是它——验收要的"学期标识"）。 */
  private semesterText(): string {
    const semesterId: string = this.store.semesterId;
    if (semesterId.length === 0) {
      return '';
    }
    return getSemesterTextFromId(semesterId, i18nService.locale(), i18nService);
  }

  private updatedText(): string {
    if (this.store.fetchedAtMillis <= 0) {
      return '';
    }
    const options: DateTimeFormatOptions = {
      hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false
    };
    const stamp: string = formatDateTimeUsing(this.store.fetchedAtMillis,
      new PlatformDateTimeFormatter(i18nService.locale(), options));
    const updated: string = i18nService.t('ui_refreshed_at', stamp);
    const ago: string = formatRelativeTo(this.store.fetchedAtMillis, Date.now(), i18nService.locale());
    if (ago.length === 0) {
      return updated;
    }
    return updated + ' · ' + ago;
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
  }

  private openCourse(course: CourseRecord): void {
    logger.info('course tapped: id=' + course.id + ' name=' + course.name);
    const params: CourseDetailRouteParams = {
      courseId: course.id,
      courseName: course.name,
      courseTeacherName: course.teacherName
    };
    this.stack.pushPath({ name: ROUTE_COURSE_DETAIL, param: params });
  }

  private openSemesterSelection(): void {
    logger.info('semester picker opened: effective=' + this.store.semesterId
      + ' source=' + this.store.semesterSource);
    const params: SemesterSelectionRouteParams = { activeSemesterId: this.store.semesterId };
    this.stack.pushPath({ name: ROUTE_SEMESTER_SELECTION, param: params });
  }

  @Builder
  header() {
    Column() {
      Text(this.s($r('app.string.loh_courses')))
        .fontSize(this.theme().typography.headlineSmall.fontSize)
        .lineHeight(this.theme().typography.headlineSmall.lineHeight)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.theme().colors.onSurface)
      Row() {
        Text(this.s($r('app.string.ui_courses_semester_label')))
          .fontSize(this.theme().typography.labelSmall.fontSize)
          .fontColor(this.theme().colors.onSurfaceVariant)
        Text(this.semesterText())
          .fontSize(this.theme().typography.labelMedium.fontSize)
          .fontColor(this.theme().colors.primary)
          .margin({ left: this.theme().sizes.space1 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Blank()
        if (this.store.semesterSource === 'override') {
          Text(this.s($r('app.string.ui_courses_override_badge')))
            .fontSize(this.theme().typography.labelSmall.fontSize)
            .fontColor(this.theme().colors.error)
        }
      }
      .width('100%')
      .margin({ top: this.theme().sizes.space1 })
      .onClick(() => {
        this.openSemesterSelection();
      })
      Row() {
        Text(this.updatedText())
          .fontSize(this.theme().typography.labelSmall.fontSize)
          .fontColor(this.theme().colors.onSurfaceVariant)
          .layoutWeight(1)
        Text(this.store.courses.length.toString())
          .fontSize(this.theme().typography.labelSmall.fontSize)
          .fontColor(this.theme().colors.primary)
      }
      .width('100%')
      .margin({ top: this.theme().sizes.space1 })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({
      left: this.theme().sizes.contentPadding,
      right: this.theme().sizes.contentPadding,
      top: this.theme().sizes.space4,
      bottom: this.theme().sizes.space3
    })
  }

  /**
   * 一个计数单元：符号 + 数字（参考实现是 MaterialIcons 的
   * notifications / event / folder，颜色取 `theme.colors.outline`）。
   * 参考实现那三个图标名在 ArkUI 里不可移植（见台账第 16 条对公告图标的同一判断），
   * 这里用 emoji + accessibilityText：语义文字进无障碍树，数字仍然逐字可见。
   */
  @Builder
  countGroup(spec: CountSpec) {
    Row() {
      Text(spec.symbol)
        .fontSize(spec.theme.sizes.iconSmall)
        .fontColor(spec.theme.colors.outline)
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
          theme: spec.theme, symbol: '🔔', count: spec.course.unreadNoticeCount, label: spec.noticesLabel
        })
        this.countGroup({
          theme: spec.theme, symbol: '📅', count: spec.course.unfinishedAssignmentCount,
          label: spec.assignmentsLabel
        })
        this.countGroup({
          theme: spec.theme, symbol: '📁', count: spec.course.unreadFileCount, label: spec.filesLabel
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
    .backgroundColor(spec.theme.colors.surface)
    .onClick(() => {
      this.openCourse(spec.course);
    })
  }

  @Builder
  listBody() {
    Stack() {
      List({ space: 0 }) {
        ForEach(this.store.courses, (item: CourseRecord) => {
          ListItem() {
            this.courseRow({
              theme: this.theme(),
              course: item,
              noticesLabel: this.s($r('app.string.ui_course_unread_notices_label')),
              assignmentsLabel: this.s($r('app.string.ui_course_unfinished_assignments_label')),
              filesLabel: this.s($r('app.string.ui_course_new_files_label'))
            })
          }
        }, (item: CourseRecord) => item.id)
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
      } else if (this.store.isEmpty()) {
        EmptyState({
          message: this.s($r('app.string.ui_courses_empty')),
          isDark: this.isDark()
        })
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  destinationBuilder(name: string, param: object) {
    if (name === ROUTE_COURSE_DETAIL) {
      NavDestination() {
        CourseDetailPage({
          params: param as CourseDetailRouteParams,
          store: this.store,
          stack: this.stack
        })
      }
      .hideTitleBar(true)
    } else if (name === ROUTE_SEMESTER_SELECTION) {
      NavDestination() {
        SemesterSelectionPage({ store: this.store, stack: this.stack })
      }
      .hideTitleBar(true)
    } else if (name === ROUTE_NOTICE_DETAIL) {
      // 课程详情里点公告 → 公告详情页（ticket 04 的页面，压在本 tab 自己的栈上）。
      NavDestination() {
        NoticeDetailPage({
          notice: param as NoticeRecord,
          stack: this.stack,
          session: this.session
        })
      }
      .hideTitleBar(true)
    } else if (name === ROUTE_ASSIGNMENT_DETAIL) {
      NavDestination() {
        AssignmentDetailPlaceholderPage({
          params: param as AssignmentDetailRouteParams,
          stack: this.stack
        })
      }
      .hideTitleBar(true)
    } else if (name === ROUTE_COURSE_FILE_DETAIL) {
      NavDestination() {
        CourseFileDetailPlaceholderPage({
          params: param as CourseFileDetailRouteParams,
          stack: this.stack
        })
      }
      .hideTitleBar(true)
    }
  }

  build() {
    Navigation(this.stack) {
      Column() {
        this.header()
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
    }
    .navDestination(this.destinationBuilder)
    .hideTitleBar(true)
    .mode(NavigationMode.Stack)
    .width('100%')
    .height('100%')
  }
}