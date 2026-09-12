/*
 * 作业 tab（ticket 10）：作业列表 + 详情栈的根。
 *
 * ## 数据来源：**复用课程线的同一次抓取**，不新造取数
 *
 * 统筹给的硬前提（ticket 10 的统筹补充第 1 条）：学期覆盖（`aa start --ps lohSemester …`）
 * **只作用于课程那条线**；作业/公告/文件的 `fetchWithSession` 连学期参数都没有。
 * 如果作业 tab 自己去抓，在覆盖态下仍会取"站点当前学期"⇒ 2026-2027 秋季 ⇒ 空列表，
 * 而"空"同时也是账号事实 ⇒ 两个原因在日志上长得一样。
 *
 * 所以本页**直接用 `CourseListStore`**（ticket 12 交付的课程状态），它的
 * `refresh()` → `data/courses/CourseFetchSource` 里读一次 `effectiveSemesterOverride()`
 * （优先级 override > 界面选择 > 站点当前学期**只有那一份实现**），并把三域内容装进
 * `CourseSnapshot`。作业线拿的就是 `snapshot.assignments` —— 覆盖态下就是春季那 57 条。
 * 交付文档里说明了这样做的代价（进两个 tab = 两次抓取）。
 *
 * ## 排序：不在界面层再排一次
 *
 * `AssignmentsFetcher.fetch` 返回前已经用
 * `domain/parse/AssignmentParser.compareAssignmentsByUpcoming` 排好
 * （未到期在前由近及远、已过期在后由远及近，ticket 05 与参考实现逐条对齐）。
 * 这里**只过滤不排序**（见 AssignmentFilter.ets 的文件头）。
 *
 * ## 与参考实现 AssignmentCard.tsx 的对照
 *
 * | 项 | 参考实现 | 这里 |
 * | --- | --- | --- |
 * | 课程名 / 标题（removeTags）/ 描述预览（2 行） | :43-48, :94-98 | 同 |
 * | 状态标记 | 五个 MaterialCommunityIcons：附件(橙) / 已提交(绿勾) / 已评分(红) / 答案(蓝) | 同序同色，用 emoji + accessibilityText（理由见 docs/reference-quirks.md 第 16 条） |
 * | 截止时间那句 | `dayjs().isAfter(deadline) ? fromNow()+'截止' : '还剩 '+to(deadline,true)`（:103-108） | **绝对时间**（站点原文 `YYYY-MM-DD HH:mm`）+ 状态标记"未到期 / 已截止" |
 * | 过滤 | FilterList 下拉（all / unfinished / finished / fav / archived / hidden） | 三个筛选片（全部 / 未完成 / 已完成）；收藏/归档/屏蔽归 ticket 14 |
 *
 * 截止时间那句为什么换措辞：dayjs 的 `humanize`（"5 个月前" / "还剩 3 天"）在平台侧没有等价物 ——
 * `Intl.RelativeTimeFormat` 只能给 "5个月前" / "3天后"，无法去掉/加上参考那句前后缀。
 * 与其拼出"还剩 3天后"这种两种语言都不通顺的句子，这里显示**站点自己的截止时间原文**
 * 加一枚**本地化状态标记**（未到期 / 已截止），语义等价且可截图核对。详见 ticket 10 的交付说明。
 */
import { ConfigurationConstant } from '@kit.AbilityKit';
import { PLAIN_PALETTE, ThemeTokens, resolveTheme } from '../../ui/theme/Tokens';
import { i18nService } from '../../core/i18n/I18n';
import {
  DateTimeFormatOptions, PlatformDateTimeFormatter, formatDateTimeUsing, getSemesterTextFromId
} from '../../core/i18n/DateTimeUtil';
import { COLOR_MODE_KEY, LOCALE_VERSION_KEY } from '../../entryability/EntryAbility';
import { Logger } from '../../core/log/Logger';
import { Assignment } from '../../domain/model/ContentItem';
import { removeTags } from '../../domain/render/WebViewTemplate';
import { EmptyState } from '../../ui/components/EmptyState';
import { SessionHeaderProvider, createSessionHeaderProvider } from '../../core/web/SessionHeaderProvider';
import { CourseListStore } from '../courses/CourseListStore';
import { createCourseRepository } from '../courses/repository/CourseRepositoryProvider';
import { FileDetailPage } from '../files/FileDetailPage';
import { FileDetailRouteParams, ROUTE_FILE_DETAIL } from '../notices/NoticeRoutes';
import { AssignmentDetailPage } from './AssignmentDetailPage';
import { ROUTE_ASSIGNMENT_DETAIL } from './AssignmentRoutes';
import {
  AssignmentFilter, countAssignments, countPastDue, filterAssignments, hasAnswer,
  hasExcellentHomework, isAssignmentListEmpty, isPastDeadline
} from './AssignmentFilter';
import { deadlineText, dueStatusText, emptyStateKey } from './AssignmentText';
import {
  evidenceAssignmentsOr, logAssignmentEvidenceState
} from './AssignmentEvidence';

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
}

/** 一个筛选片的渲染参数。 */
interface FilterSpec {
  theme: ThemeTokens;
  label: string;
  count: number;
  active: boolean;
  /** 该片对应的过滤视图；点击在 builder 内部转成 selectFilter（@Builder 的参数只传数据）。 */
  value: AssignmentFilter;
}

@Component
export struct AssignmentsPage {
  @StorageProp(COLOR_MODE_KEY) colorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageLink(LOCALE_VERSION_KEY) localeVersion: number = 0;
  @State refreshing: boolean = false;
  @State filter: AssignmentFilter = AssignmentFilter.ALL;

  private store: CourseListStore = new CourseListStore(createCourseRepository());
  private stack: NavPathStack = new NavPathStack();
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

  /** 当前筛选下的可见列表；**顺序就是取数时的顺序**（不在这里排序）。 */
  private visibleAssignments(): Assignment[] {
    return filterAssignments(this.sourceAssignments(), this.filter);
  }

  /**
   * 消费点自证：把**实际生效的学期与来源**连同作业条数打进 hilog。
   * 作业线的取证要求"既要看到 data.courses effective semester=… source=override，
   * 也要看到作业消费点的行"（见 ticket 10 的统筹提示第 1 条）。
   */
  private logApplied(reason: string): void {
    const items: Assignment[] = this.sourceAssignments();
    const nowMillis: number = Date.now();
    logger.info('assignments applied: reason=' + reason
      + ' semester=' + this.store.semesterId
      + ' source=' + this.store.semesterSource
      + ' siteCurrent=' + this.store.siteCurrentSemesterId
      + ' items=' + items.length.toString()
      + ' visible=' + this.visibleAssignments().length.toString()
      + ' filter=' + this.filter
      + ' unfinished=' + countAssignments(items, AssignmentFilter.UNFINISHED).toString()
      + ' finished=' + countAssignments(items, AssignmentFilter.FINISHED).toString()
      + ' pastDue=' + countPastDue(items, nowMillis).toString());
  }

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
    return i18nService.t('ui_refreshed_at', stamp);
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

  private selectFilter(next: AssignmentFilter): void {
    if (this.filter === next) {
      return;
    }
    this.filter = next;
    this.logApplied('filter');
  }

  private openDetail(assignment: Assignment): void {
    logger.info('assignment tapped: id=' + assignment.id + ' courseId=' + assignment.courseId
      + ' submitted=' + assignment.submitted.toString()
      + ' graded=' + assignment.graded.toString()
      + ' deadline=' + assignment.deadline);
    this.stack.pushPath({ name: ROUTE_ASSIGNMENT_DETAIL, param: assignment });
  }

  @Builder
  header() {
    Column() {
      Text(this.s($r('app.string.loh_assignments')))
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
      Row() {
        Text(this.updatedText())
          .fontSize(this.theme().typography.labelSmall.fontSize)
          .fontColor(this.theme().colors.onSurfaceVariant)
          .layoutWeight(1)
        Text(this.s($r('app.string.loh_unfinished')) + ' '
          + countAssignments(this.sourceAssignments(), AssignmentFilter.UNFINISHED).toString())
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
      bottom: this.theme().sizes.space2
    })
  }

  /** 一个筛选片（参考实现 FilterList 的下拉被换成同一屏的三个片，行为一样：切视图）。 */
  @Builder
  filterChip(spec: FilterSpec) {
    Text(spec.label + ' ' + spec.count.toString())
      .fontSize(spec.theme.typography.labelMedium.fontSize)
      .fontColor(spec.active ? spec.theme.colors.onPrimaryContainer : spec.theme.colors.onSurfaceVariant)
      .backgroundColor(spec.active ? spec.theme.colors.primaryContainer : spec.theme.colors.surface)
      .borderRadius(spec.theme.sizes.controlHeight / 2)
      .padding({
        left: spec.theme.sizes.space3,
        right: spec.theme.sizes.space3,
        top: spec.theme.sizes.space1,
        bottom: spec.theme.sizes.space1
      })
      .margin({ right: spec.theme.sizes.space2 })
      .onClick(() => {
        this.selectFilter(spec.value);
      })
  }

  @Builder
  filterRow() {
    Row() {
      this.filterChip({
        theme: this.theme(), label: this.s($r('app.string.loh_all')),
        count: countAssignments(this.sourceAssignments(), AssignmentFilter.ALL),
        active: this.filter === AssignmentFilter.ALL,
        value: AssignmentFilter.ALL
      })
      this.filterChip({
        theme: this.theme(), label: this.s($r('app.string.loh_unfinished')),
        count: countAssignments(this.sourceAssignments(), AssignmentFilter.UNFINISHED),
        active: this.filter === AssignmentFilter.UNFINISHED,
        value: AssignmentFilter.UNFINISHED
      })
      this.filterChip({
        theme: this.theme(), label: this.s($r('app.string.loh_finished')),
        count: countAssignments(this.sourceAssignments(), AssignmentFilter.FINISHED),
        active: this.filter === AssignmentFilter.FINISHED,
        value: AssignmentFilter.FINISHED
      })
      Blank()
    }
    .width('100%')
    .padding({
      left: this.theme().sizes.contentPadding,
      right: this.theme().sizes.contentPadding,
      bottom: this.theme().sizes.space2
    })
  }

  /**
   * 卡片右上角的状态标记 —— 逐项对齐参考实现 `AssignmentCard.tsx:52-92`：
   *   附件（📎 orange500）→ 已提交（✓ green500）→ 已评分（🎓 red500）→ 有答案（🔑 blue500）。
   * 为什么用 emoji：MaterialCommunityIcons 在 ArkUI 没有可移植的等价符号
   * （docs/reference-quirks.md 第 16 条对公告图标已有同一判断）。
   */
  @Builder
  statusIcons(spec: AssignmentRowSpec) {
    Row() {
      if (spec.assignment.attachment !== undefined) {
        Text('📎')
          .fontSize(spec.theme.sizes.iconSmall)
          .fontColor(PLAIN_PALETTE.orange500)
          .margin({ left: spec.theme.sizes.space1 })
          .accessibilityText(spec.attachmentLabel)
      }
      if (spec.assignment.submitted) {
        Text('✓')
          .fontSize(spec.theme.sizes.iconSmall)
          .fontColor(PLAIN_PALETTE.green500)
          .margin({ left: spec.theme.sizes.space1 })
          .accessibilityText(spec.submittedLabel)
      }
      if (spec.assignment.graded) {
        Text('🎓')
          .fontSize(spec.theme.sizes.iconSmall)
          .fontColor(PLAIN_PALETTE.red500)
          .margin({ left: spec.theme.sizes.space1 })
          .accessibilityText(spec.gradedLabel)
      }
      if (hasAnswer(spec.assignment)) {
        Text('🔑')
          .fontSize(spec.theme.sizes.iconSmall)
          .fontColor(PLAIN_PALETTE.blue500)
          .margin({ left: spec.theme.sizes.space1 })
          .accessibilityText(spec.answerLabel)
      }
      // 优秀作业（ticket 10 补做）：参考实现 AssignmentCard.tsx:84-91 的黄色 medal。
      if (hasExcellentHomework(spec.assignment)) {
        Text('🏅')
          .fontSize(spec.theme.sizes.iconSmall)
          .fontColor(PLAIN_PALETTE.yellow500)
          .margin({ left: spec.theme.sizes.space1 })
          .accessibilityText(spec.excellentLabel)
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
    .backgroundColor(spec.theme.colors.surface)
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
              excellentLabel: this.s($r('app.string.ui_assignment_excellent_mark_label'))
            })
          }
        }, (item: Assignment) => item.id)
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
      } else if (isAssignmentListEmpty(this.visibleAssignments(), this.store.isBusy())) {
        EmptyState({
          message: i18nService.t(emptyStateKey(this.filter)),
          isDark: this.isDark()
        })
      }
    }
    .width('100%')
    .height('100%')
  }

  /** 详情栈的出栈目标：作业详情（本 ticket）+ 文件详情占位（附件点击，真身见 ticket 11）。 */
  @Builder
  destinationBuilder(name: string, param: object) {
    if (name === ROUTE_ASSIGNMENT_DETAIL) {
      NavDestination() {
        AssignmentDetailPage({
          assignment: param as Assignment,
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
    }
    .navDestination(this.destinationBuilder)
    .hideTitleBar(true)
    .mode(NavigationMode.Stack)
    .width('100%')
    .height('100%')
  }
}
