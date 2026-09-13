/*
 * 作业详情页 —— 逐项对齐参考实现 `reference/learnOH-old/src/screens/AssignmentDetail.tsx`。
 *
 * ## 页面结构（对应参考实现行号）
 *
 * | 元素 | 参考实现 | 这里 |
 * | --- | --- | --- |
 * | 完成方式 / 提交方式两个 Chip | :152-161 | 同（映射见 AssignmentText.completionText / submissionText） |
 * | 标题 = `removeTags(title)` | :163 | 同 |
 * | 截止时间（绝对 + 相对） | :164-181 | 绝对时间用站点原文；相对时间用 `formatRelativeTo` |
 * | 补交截止 | :182-190 | 同 |
 * | 附件（四类之一） | :193-211 | 同（MCI `attachment` 图标 + 文件名，**可点**） |
 * | 已提交（附件 + 正文 + 提交时间） | :212-252 | 同 |
 * | 已评分（等级/分数 + 附件 + 评语 + 批改人与时间） | :253-298 | 同（等级本地化见 AssignmentText.gradeText） |
 * | 答案（附件 + 正文） | :299-326 | 同 |
 * | **优秀作业**（medal + `gradeAttachment \|\| submittedAttachment` + "X的优秀作业"） | :327-363 | 同（MCI `medal` + 附件行可点 → FileDetail；匿名用 `loh_anonymous`） |
 * | 描述（Web 容器渲染，含 KaTeX） | :122-130, :364-374 | 同：`ui/components/HtmlWebView` + `buildNoticeContent` |
 * | 附件点击 → `push('FileDetail')` | :132-145 | 同路由（`ROUTE_FILE_DETAIL`），参数逐项对齐 |
 *
 * ## 三处必须说明的判断
 *
 * 1. **提交入口的边界**（建页时只读，提交线接上）：参考实现在 headerRight 放了一个
 *    上传按钮（:105-120），点它进 `AssignmentSubmission`。建页时全程只读、不渲染该入口；
 *    后来把它接上：`submissionType !== OFFLINE` 时渲染 MaterialIcons `file-upload`，
 *    点击先问一句"提交入口能不能走、走不了是为什么"（canSubmit 那条纯判定在
 *    `domain/assignments/SubmissionState.submitBlockReason`；本页只可能拿到"已截止"这一种
 *    原因，提示文案见 `AssignmentText.submissionBlockedKey`），不能走就只提示、不进页面，
 *    能走才把整个 `Assignment` 推给 `ROUTE_ASSIGNMENT_SUBMISSION`。
 *    **本页仍然只读**：不构造提交请求、不落任何表单字段；真正的写操作在提交页里由用户二次确认后发出。
 *
 * 2. **优秀作业已交付**（补做）：数据来自参考实现那条**独立接口**
 *    `/b/wlxt/kczy/zy/student/yxzylist`（每门课一次 POST）+ 每条一次
 *    `viewYxzy?wlkcid=&xszyid=` 详情页（`AssignmentParser` 末尾那一节、
 *    `AssignmentsFetcher.fetchExcellent`）；失败**整段被吞**（只 warn）。
 *
 * 3. **附件点击的落点**：参考实现 `handleFileOpen` 传的 `id` 是**附件 id**
 *    （AssignmentDetail.tsx:134；对比公告详情传的是公告 id，NoticeDetail.tsx:64）。
 *    这里照作业那条走（`noticeId` 字段名沿用既有 `FileDetailRouteParams`，
 *    它是"文件缓存目录名"；字段名不改是为了不动已验收的导航契约 ——
 *    见边界说明）。`FileDetail` 的**真身**（下载/预览/分享）归文件详情页。
 *
 * 描述为什么走 Web 容器而不是纯文本：参考实现把描述喂给 `getWebViewTemplate`
 * （:122-130），模板里带 KaTeX 的 auto-render（`$$…$$` 与 `\(…\)` 才排版，
 * 单 `$` 不排版）。纯 Text 渲染会把公式
 * 变成字面量。
 */
import { ConfigurationConstant } from '@kit.AbilityKit';
import { PLAIN_PALETTE, ThemeTokens, resolveTheme } from '../../ui/theme/Tokens';
import { i18nService } from '../../core/i18n/I18n';
import { formatRelativeTo } from '../../core/i18n/DateTimeUtil';
import { COLOR_MODE_KEY } from '../../entryability/EntryAbility';
import { Logger } from '../../core/log/Logger';
import { Assignment, Attachment, ExcellentHomework } from '../../domain/model/ContentItem';
import { parseTimestamp } from '../../domain/parse/Text';
import { excellentDisplayAttachment } from '../../domain/parse/AssignmentParser';
import { SubmitBlockReason, submitBlockReason } from '../../domain/assignments/SubmissionState';
import { buildNoticeContent, removeTags } from '../../domain/render/WebViewTemplate';
import { getExtension, stripExtension } from '../../domain/render/FileNames';
import { HtmlWebView } from '../../ui/components/HtmlWebView';
import { AppIcon } from '../../ui/icons/IconCatalog';
import { IconGlyph } from '../../ui/icons/IconGlyph';
import { SessionHeaderProvider } from '../../core/web/SessionHeaderProvider';
import { FileDetailRouteParams, ROUTE_FILE_DETAIL } from '../notices/NoticeRoutes';
import { CourseListStore } from '../courses/CourseListStore';
import { ROUTE_ASSIGNMENT_SUBMISSION } from './AssignmentRoutes';
import { isPastDeadline } from './AssignmentFilter';
import {
  completionText, deadlineText, dueStatusText, gradeText, isOfflineSubmission,
  submissionBlockedKey, submissionText
} from './AssignmentText';

const logger: Logger = new Logger('features.assignments.detail');

/** 一行附件（MCI `attachment` 图标 + 文件名）。 */
interface AttachmentSpec {
  theme: ThemeTokens;
  attachment: Attachment;
  label: string;
  kind: string;
}

@Component
export struct AssignmentDetailPage {
  @StorageProp(COLOR_MODE_KEY) colorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  /** 由 NavDestination 传入的作业（列表项本身，详情页不做二次取数）。 */
  assignment: Assignment = {
    id: '', baseId: '', title: '', url: '', deadline: '', isLateSubmission: false,
    completionType: '', submissionType: '', submitUrl: '', courseId: '', courseName: '',
    courseTeacherName: '', gradeContent: '', submittedContent: '', answerContent: '',
    description: '', submitted: false, graded: false
  };
  stack: NavPathStack | null = null;
  session: SessionHeaderProvider | null = null;
  /** 提交成功后要重新取数的课程状态（由作业列表页传入；为 null 时提交页只 toast）。 */
  store: CourseListStore | null = null;

  aboutToAppear(): void {
    // 站点原文进 hilog：完成方式 / 提交方式的**实际取值**决定 AssignmentText 的映射
    // （参考实现比较数字枚举，而站点可能下发中文标签）。
    logger.info('assignment detail appear: id=' + this.assignment.id
      + ' deadline=' + this.assignment.deadline
      + ' submitted=' + this.assignment.submitted.toString()
      + ' graded=' + this.assignment.graded.toString()
      + ' completionType=' + this.assignment.completionType
      + ' submissionType=' + this.assignment.submissionType
      + ' grade=' + (this.assignment.grade === undefined ? 'none' : this.assignment.grade.toString())
      + ' gradeLevel=' + (this.assignment.gradeLevel === undefined ? 'none' : this.assignment.gradeLevel)
      + ' gradeTime=' + (this.assignment.gradeTime === undefined ? 'none' : this.assignment.gradeTime)
      + ' attachments='
      + (this.assignment.attachment === undefined ? '-' : 'main')
      + (this.assignment.submittedAttachment === undefined ? '-' : 'submitted')
      + (this.assignment.gradeAttachment === undefined ? '-' : 'grade')
      + (this.assignment.answerAttachment === undefined ? '-' : 'answer')
      + ' descriptionChars=' + this.assignment.description.length.toString()
      + ' excellent=' + this.excellentList().length.toString());
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

  /**
   * 可选文本是否可用：`undefined` 与空串都算"没有"。
   * 参考实现用的是真值判断（`submitTime ? dayjs(...).format(...) : t('submitted')`，
   * AssignmentDetail.tsx:236-247；`lateSubmissionDeadline && (...)`，:182），照它做。
   */
  private hasText(value: string | undefined): boolean {
    return value !== undefined && value.length > 0;
  }

  /** 有没有补交截止（可选字段；`''` 与 undefined 都算没有）。 */
  private hasLateDeadline(): boolean {
    return this.hasText(this.assignment.lateSubmissionDeadline);
  }

  /** 补交截止的文案（调用前用 hasLateDeadline 判过）。 */
  private lateDeadlineText(): string {
    const late: string | undefined = this.assignment.lateSubmissionDeadline;
    return late === undefined ? '' : deadlineText(late);
  }

  /** "提交于 / 补交于"这一行；没有提交时间时退回"已提交"（参考实现 :236-247）。 */
  private submittedCaption(): string {
    const submitTime: string | undefined = this.assignment.submitTime;
    if (submitTime === undefined || submitTime.length === 0) {
      return this.s($r('app.string.loh_submitted'));
    }
    return i18nService.t(this.assignment.isLateSubmission
      ? 'ui_assignment_submitted_late_at' : 'ui_assignment_submitted_at', submitTime);
  }

  /** "（某某）批改于 …"这一行；没有批改时间时整行不显示（参考实现 :283-293）。 */
  private gradedCaption(): string {
    const gradeTime: string | undefined = this.assignment.gradeTime;
    if (gradeTime === undefined || gradeTime.length === 0) {
      return '';
    }
    const grader: string | undefined = this.assignment.graderName;
    if (grader === undefined || grader.length === 0) {
      return i18nService.t('ui_assignment_graded_at', gradeTime);
    }
    return i18nService.t('ui_assignment_graded_by_at', grader, gradeTime);
  }

  /** 截止时间的相对措辞（ICU）；不可解析时为空串（那一行不显示）。 */
  private relativeOf(time: string): string {
    const at: number = parseTimestamp(time);
    if (Number.isNaN(at)) {
      return '';
    }
    return formatRelativeTo(at, Date.now(), i18nService.locale());
  }

  /** 描述交给 Web 容器的正文（空描述兜底后），与公告详情同一条模板链路。 */
  private preparedDescription(): string {
    return buildNoticeContent(this.assignment.description,
      this.s($r('app.string.loh_no_assignment_description')));
  }

  /**
   * 附件 → FileDetail 的参数，逐项对齐参考实现 AssignmentDetail.tsx:132-145：
   * `title = stripExtension(name)`、`fileType = getExtension(name) ?? ''`、`id = 附件 id`。
   */
  private fileParams(attachment: Attachment): FileDetailRouteParams {
    const extension: string | undefined = getExtension(attachment.name);
    return {
      noticeId: attachment.id === undefined ? '' : attachment.id,
      courseName: this.assignment.courseName,
      courseTeacherName: this.assignment.courseTeacherName,
      title: stripExtension(attachment.name),
      attachmentName: attachment.name,
      downloadUrl: attachment.downloadUrl,
      fileType: extension === undefined ? '' : extension
    };
  }

  private openAttachment(attachment: Attachment, kind: string): void {
    const params: FileDetailRouteParams = this.fileParams(attachment);
    logger.info('assignment attachment tapped: kind=' + kind
      + ' name=' + params.attachmentName + ' fileType=' + params.fileType
      + ' id=' + params.noticeId);
    if (this.stack === null) {
      logger.error('assignment attachment tapped but no NavPathStack');
      return;
    }
    this.stack.pushPath({ name: ROUTE_FILE_DETAIL, param: params });
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 2000 });
    } catch (error) {
      logger.warn('toast failed: ' + (error as Error).message);
    }
  }

  /**
   * 进提交页（参考实现 AssignmentDetail.tsx:82-101 的 handleSubmit）。
   *
   * 两件事逐条照做：
   *   1. **不能提交时就只提示、不进入**，而且提示要说清**不能的原因**
   *      （`dayjs().isAfter(deadline)` ⇒ 已截止；判定与提交页共用同一个纯函数，
   *      本页没有提交页的状态，所以只可能拿到"已截止"）；
   *   2. 否则把**整个 Assignment**（含 `studentHomeworkId`、`submittedContent`、
   *      `submittedAttachment`、`submitTime`）推给提交页 —— 参考实现也是 `...route.params`。
   *
   * 注意：这里**只推路由，不发任何请求**；真正的写操作要用户在提交页再点一次「提交」并确认。
   */
  private openSubmission(): void {
    const reason: SubmitBlockReason | undefined =
      submitBlockReason(isPastDeadline(this.assignment.deadline, Date.now()), undefined);
    if (reason !== undefined) {
      // 日志保留 `submission entry blocked:` 这个前缀：拦截证据一直按它检索。
      logger.info('submission entry blocked: reason=' + reason
        + ' deadline=' + this.assignment.deadline);
      this.toast(i18nService.t(submissionBlockedKey(reason)));
      return;
    }
    if (this.stack === null) {
      logger.error('submission entry tapped but no NavPathStack');
      return;
    }
    logger.info('submission entry tapped: id=' + this.assignment.id
      + ' xszyid=' + (this.assignment.studentHomeworkId === undefined
        ? 'none' : this.assignment.studentHomeworkId)
      + ' deadline=' + this.assignment.deadline);
    this.stack.pushPath({ name: ROUTE_ASSIGNMENT_SUBMISSION, param: this.assignment });
  }

  @Builder
  headerRow() {
    Row() {
      // 返回：参考实现的详情页是导航栈默认的 MaterialIcons `arrow-back`（此前这里是
      // 一个近似形状的字符 U+2039）。外层 Stack 保持**原有的 40×40 点击目标**，布局尺寸不变。
      Stack() {
        IconGlyph({
          icon: AppIcon.ARROW_BACK, glyphSize: this.theme().sizes.iconMedium,
          color: this.theme().colors.primary, label: this.s($r('app.string.loh_back'))
        })
      }
      .width(this.theme().sizes.controlHeight)
      .height(this.theme().sizes.controlHeight)
      .onClick(() => {
        if (this.stack !== null) {
          this.stack.pop();
        }
      })
      Text(this.s($r('app.string.loh_assignments')))
        .fontSize(this.theme().typography.titleMedium.fontSize)
        .fontColor(this.theme().colors.onSurfaceVariant)
      Blank()
      // 提交入口：参考实现只在 `submissionType !== OFFLINE` 时渲染
      // headerRight 的那枚 MaterialIcons `file-upload`（AssignmentDetail.tsx:99-120）。
      if (!isOfflineSubmission(this.assignment.submissionType)) {
        Stack() {
          IconGlyph({
            icon: AppIcon.FILE_UPLOAD, glyphSize: this.theme().sizes.iconMedium,
            color: this.theme().colors.primary, label: this.s($r('app.string.loh_submit_assignment'))
          })
        }
        .width(this.theme().sizes.controlHeight)
        .height(this.theme().sizes.controlHeight)
        .onClick(() => {
          this.openSubmission();
        })
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  titleSection() {
    Column() {
      Row() {
        Text(completionText(this.assignment.completionType))
          .fontSize(this.theme().typography.labelMedium.fontSize)
          .fontColor(this.theme().colors.onSurfaceVariant)
          .border({
            width: this.theme().sizes.borderWidth,
            color: this.theme().colors.outline,
            radius: this.theme().sizes.controlHeight / 2
          })
          .padding({
            left: this.theme().sizes.space2,
            right: this.theme().sizes.space2,
            top: this.theme().sizes.space1,
            bottom: this.theme().sizes.space1
          })
        Text(submissionText(this.assignment.submissionType))
          .fontSize(this.theme().typography.labelMedium.fontSize)
          .fontColor(this.theme().colors.onSurfaceVariant)
          .border({
            width: this.theme().sizes.borderWidth,
            color: this.theme().colors.outline,
            radius: this.theme().sizes.controlHeight / 2
          })
          .padding({
            left: this.theme().sizes.space2,
            right: this.theme().sizes.space2,
            top: this.theme().sizes.space1,
            bottom: this.theme().sizes.space1
          })
          .margin({ left: this.theme().sizes.space2 })
        Blank()
      }
      .width('100%')
      Text(removeTags(this.assignment.title))
        .fontSize(this.theme().typography.headlineSmall.fontSize)
        .lineHeight(this.theme().typography.headlineSmall.lineHeight)
        .fontColor(this.theme().colors.onSurface)
        .width('100%')
        .margin({ top: this.theme().sizes.space2 })
      Text(this.assignment.courseName)
        .fontSize(this.theme().typography.labelMedium.fontSize)
        .fontColor(this.theme().colors.onSurfaceVariant)
        .width('100%')
        .margin({ top: this.theme().sizes.space1 })
      Row() {
        Text(this.s($r('app.string.ui_assignment_deadline')))
          .fontSize(this.theme().typography.labelSmall.fontSize)
          .fontColor(this.theme().colors.onSurfaceVariant)
        Text(deadlineText(this.assignment.deadline))
          .fontSize(this.theme().typography.labelSmall.fontSize)
          .fontColor(this.theme().colors.onSurface)
          .margin({ left: this.theme().sizes.space1 })
        Text(dueStatusText(this.assignment.deadline, Date.now()))
          .fontSize(this.theme().typography.labelSmall.fontSize)
          .fontColor(PLAIN_PALETTE.red500)
          .margin({ left: this.theme().sizes.space2 })
        Blank()
      }
      .width('100%')
      .margin({ top: this.theme().sizes.space2 })
      if (this.relativeOf(this.assignment.deadline).length > 0) {
        Text(this.relativeOf(this.assignment.deadline))
          .fontSize(this.theme().typography.labelSmall.fontSize)
          .fontColor(this.theme().colors.onSurfaceVariant)
          .width('100%')
          .margin({ top: this.theme().sizes.space1 })
      }
      if (this.hasLateDeadline()) {
        Row() {
          Text(this.s($r('app.string.ui_assignment_late_deadline')))
            .fontSize(this.theme().typography.labelSmall.fontSize)
            .fontColor(this.theme().colors.onSurfaceVariant)
          Text(this.lateDeadlineText())
            .fontSize(this.theme().typography.labelSmall.fontSize)
            .fontColor(this.theme().colors.onSurface)
            .margin({ left: this.theme().sizes.space1 })
          Blank()
        }
        .width('100%')
        .margin({ top: this.theme().sizes.space1 })
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(this.theme().sizes.contentPadding)
  }

  /** 一行附件（MCI `attachment` 图标 + 文件名 + 说明标签），整行可点。 */
  @Builder
  attachmentRow(spec: AttachmentSpec) {
    Column() {
      Row() {
        // 参考实现 AssignmentDetail.tsx:196-201：MCI `attachment`。
        IconGlyph({
          icon: AppIcon.ATTACHMENT, glyphSize: this.theme().sizes.iconMedium,
          color: PLAIN_PALETTE.orange500, label: spec.label
        })
        Text(spec.attachment.name)
          .fontSize(this.theme().typography.bodyLarge.fontSize)
          .fontColor(this.theme().colors.primary)
          .layoutWeight(1)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ left: this.theme().sizes.space3 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      Text(spec.label)
        .fontSize(this.theme().typography.labelSmall.fontSize)
        .fontColor(spec.theme.colors.onSurfaceVariant)
        .margin({ top: spec.theme.sizes.space1 })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({
      left: this.theme().sizes.contentPadding,
      right: this.theme().sizes.contentPadding,
      top: this.theme().sizes.space2,
      bottom: this.theme().sizes.space2
    })
    .onClick(() => {
      this.openAttachment(spec.attachment, spec.kind);
    })
  }

  /** 一段可能为空的正文（参考实现 `removeTags(x) ? <Text>…</Text> : null`）。 */
  @Builder
  bodyText(text: string) {
    if (text.length > 0) {
      Text(text)
        .fontSize(this.theme().typography.bodyMedium.fontSize)
        .lineHeight(this.theme().typography.bodyMedium.lineHeight)
        .fontColor(this.theme().colors.onSurface)
        .width('100%')
        .padding({
          left: this.theme().sizes.contentPadding,
          right: this.theme().sizes.contentPadding,
          top: this.theme().sizes.space2,
          bottom: this.theme().sizes.space2
        })
    }
  }

  @Builder
  captionRow(text: string) {
    Text(text)
      .fontSize(this.theme().typography.labelSmall.fontSize)
      .fontColor(this.theme().colors.onSurfaceVariant)
      .width('100%')
      .padding({
        left: this.theme().sizes.contentPadding,
        right: this.theme().sizes.contentPadding,
        top: this.theme().sizes.space1,
        bottom: this.theme().sizes.space2
      })
  }

  /** 已提交段（参考实现 :212-252）。 */
  @Builder
  submittedSection() {
    this.sectionTitle(AppIcon.CHECK, this.s($r('app.string.loh_submitted')))
    if (this.assignment.submittedAttachment !== undefined) {
      this.attachmentRow({
        theme: this.theme(), attachment: this.assignment.submittedAttachment,
        label: this.s($r('app.string.ui_assignment_submitted_attachment_label')),
        kind: 'submitted'
      })
    }
    this.bodyText(removeTags(this.assignment.submittedContent))
    this.captionRow(this.submittedCaption())
    Divider()
      .strokeWidth(this.theme().sizes.borderWidth)
      .color(this.theme().colors.outlineVariant)
  }

  /** 已评分段（参考实现 :253-298）：等级优先、否则数字成绩。 */
  @Builder
  gradedSection() {
    this.sectionTitle(AppIcon.GRADE, this.s($r('app.string.ui_assignment_grade')))
    this.bodyText(gradeText(this.assignment))
    if (this.assignment.gradeAttachment !== undefined) {
      this.attachmentRow({
        theme: this.theme(), attachment: this.assignment.gradeAttachment,
        label: this.s($r('app.string.ui_assignment_grade_attachment_label')),
        kind: 'grade'
      })
    }
    this.bodyText(removeTags(this.assignment.gradeContent))
    this.captionRow(this.gradedCaption())
    Divider()
      .strokeWidth(this.theme().sizes.borderWidth)
      .color(this.theme().colors.outlineVariant)
  }

  /** 答案段（参考实现 :299-326）。 */
  @Builder
  answerSection() {
    this.sectionTitle(AppIcon.KEY_VARIANT, this.s($r('app.string.ui_assignment_answer')))
    if (this.assignment.answerAttachment !== undefined) {
      this.attachmentRow({
        theme: this.theme(), attachment: this.assignment.answerAttachment,
        label: this.s($r('app.string.ui_assignment_answer_attachment_label')),
        kind: 'answer'
      })
    }
    this.bodyText(removeTags(this.assignment.answerContent))
    Divider()
      .strokeWidth(this.theme().sizes.borderWidth)
      .color(this.theme().colors.outlineVariant)
  }

  /** 本次作业的优秀作业列表（`undefined` 时给空数组，供 ForEach 用）。 */
  private excellentList(): ExcellentHomework[] {
    const list: ExcellentHomework[] | undefined = this.assignment.excellentHomeworkList;
    return list === undefined ? [] : list;
  }

  /** 优秀作业渲染用的附件：**批改附件优先、再已提交附件**（参考实现 :329-331）。 */
  private excellentName(entry: ExcellentHomework): string {
    const attachment: Attachment | undefined = excellentDisplayAttachment(entry);
    return attachment === undefined ? '' : attachment.name;
  }

  /** "X的优秀作业"；匿名（或没有姓名）时用 `loh_anonymous`（参考实现 `t('anonymous')`）。 */
  private excellentCaption(entry: ExcellentHomework): string {
    const anonymous: boolean = entry.anonymous || entry.authorName.length === 0;
    const who: string = anonymous ? this.s($r('app.string.loh_anonymous')) : entry.authorName;
    return i18nService.t('ui_assignment_excellent_by', who);
  }

  /** 点优秀作业：有附件才跳 FileDetail（与四类附件同一条路由）。 */
  private openExcellent(entry: ExcellentHomework): void {
    const attachment: Attachment | undefined = excellentDisplayAttachment(entry);
    if (attachment === undefined) {
      logger.info('excellent tapped without attachment: xszyid=' + entry.id);
      return;
    }
    this.openAttachment(attachment, 'excellent');
  }

  /**
   * 一条优秀作业（参考实现 AssignmentDetail.tsx:327-363 的一段 Fragment）：
   * MCI `medal`（黄色；此前这里是 emoji）
   * + 附件名（可点 → FileDetail）+ "X的优秀作业"。
   */
  @Builder
  excellentRow(entry: ExcellentHomework) {
    Column() {
      Row() {
        // 参考实现 AssignmentDetail.tsx:338-343：MCI `medal`（这里仍取卡片用的黄色令牌）。
        IconGlyph({
          icon: AppIcon.MEDAL, glyphSize: this.theme().sizes.iconSmall,
          color: PLAIN_PALETTE.yellow500, label: this.excellentCaption(entry)
        })
        Text(this.excellentName(entry))
          .fontSize(this.theme().typography.bodyLarge.fontSize)
          .fontColor(this.theme().colors.primary)
          .layoutWeight(1)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ left: this.theme().sizes.space2 })
        Blank()
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      Text(this.excellentCaption(entry))
        .fontSize(this.theme().typography.labelSmall.fontSize)
        .fontColor(this.theme().colors.onSurfaceVariant)
        .margin({ top: this.theme().sizes.space1 })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({
      left: this.theme().sizes.contentPadding,
      right: this.theme().sizes.contentPadding,
      top: this.theme().sizes.space2,
      bottom: this.theme().sizes.space2
    })
    .onClick(() => {
      this.openExcellent(entry);
    })
  }

  /**
   * 段标题（图标 + 语义文字）。图标与参考实现逐段对应：
   * 已提交 = MCI `check`（:215-220）、已评分 = MaterialIcons `grade`（:256-261）、
   * 答案 = MCI `key-variant`（:302-307）、优秀作业 = MCI `medal`（:338-343）。
   */
  @Builder
  sectionTitle(icon: AppIcon, title: string) {
    Row() {
      IconGlyph({ icon: icon, glyphSize: this.theme().sizes.iconSmall, color: this.theme().colors.primary })
      Text(title)
        .fontSize(this.theme().typography.labelMedium.fontSize)
        .fontColor(this.theme().colors.primary)
        .margin({ left: this.theme().sizes.space2 })
      Blank()
    }
    .width('100%')
    .padding({
      left: this.theme().sizes.contentPadding,
      right: this.theme().sizes.contentPadding,
      top: this.theme().sizes.space3
    })
  }

  /**
   * 只有文字的段标题（"作业内容"）。参考实现这一段**没有图标**：
   * 描述直接交给 `AutoHeightWebView`（AssignmentDetail.tsx:364-374），没有段标题。
   * 我们保留自己的段标题文字（既有的信息层级），但不给它配图标——
   * 这比"随便挑一个参考实现没用过的图标"更忠实。
   */
  @Builder
  sectionTitleText(title: string) {
    Row() {
      Text(title)
        .fontSize(this.theme().typography.labelMedium.fontSize)
        .fontColor(this.theme().colors.primary)
      Blank()
    }
    .width('100%')
    .padding({
      left: this.theme().sizes.contentPadding,
      right: this.theme().sizes.contentPadding,
      top: this.theme().sizes.space3
    })
  }

  build() {
    Column() {
      this.headerRow()
      Scroll() {
        Column() {
          this.titleSection()
          Divider()
            .strokeWidth(this.theme().sizes.borderWidth)
            .color(this.theme().colors.outlineVariant)
          if (this.assignment.attachment !== undefined) {
            this.attachmentRow({
              theme: this.theme(), attachment: this.assignment.attachment,
              label: this.s($r('app.string.ui_assignment_attachment_label')),
              kind: 'main'
            })
            Divider()
              .strokeWidth(this.theme().sizes.borderWidth)
              .color(this.theme().colors.outlineVariant)
          }
          if (this.assignment.submitted) {
            this.submittedSection()
          }
          if (this.assignment.graded) {
            this.gradedSection()
          }
          if (this.assignment.answerAttachment !== undefined
            || this.assignment.answerContent.trim().length > 0) {
            this.answerSection()
          }
          // 优秀作业（参考实现 :327-363，位于答案段之后、描述之前）。
          if (this.excellentList().length > 0) {
            this.sectionTitle(AppIcon.MEDAL, this.s($r('app.string.ui_assignment_excellent')))
            ForEach(this.excellentList(), (entry: ExcellentHomework) => {
              this.excellentRow(entry)
            }, (entry: ExcellentHomework) => 'excellent|' + entry.id)
            Divider()
              .strokeWidth(this.theme().sizes.borderWidth)
              .color(this.theme().colors.outlineVariant)
          }
          // 描述（含公式）交 Web 容器渲染（参考实现 :122-130, :364-374）。
          this.sectionTitleText(this.s($r('app.string.ui_assignment_description')))
          HtmlWebView({
            content: this.preparedDescription(),
            emptyText: this.s($r('app.string.loh_no_assignment_description')),
            isDark: this.isDark(),
            session: this.session
          })
        }
        .width('100%')
        .padding({ bottom: this.theme().sizes.space6 })
      }
      .width('100%')
      .layoutWeight(1)
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme().colors.background)
  }
}
