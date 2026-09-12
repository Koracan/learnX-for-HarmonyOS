/*
 * 作业详情页（ticket 10）—— 逐项对齐参考实现 `reference/learnOH-old/src/screens/AssignmentDetail.tsx`。
 *
 * ## 页面结构（对应参考实现行号）
 *
 * | 元素 | 参考实现 | 这里 |
 * | --- | --- | --- |
 * | 完成方式 / 提交方式两个 Chip | :152-161 | 同（映射见 AssignmentText.completionText / submissionText） |
 * | 标题 = `removeTags(title)` | :163 | 同 |
 * | 截止时间（绝对 + 相对） | :164-181 | 绝对时间用站点原文；相对时间用 `formatRelativeTo` |
 * | 补交截止 | :182-190 | 同 |
 * | 附件（四类之一） | :193-211 | 同（📄 + 文件名，**可点**） |
 * | 已提交（附件 + 正文 + 提交时间） | :212-252 | 同 |
 * | 已评分（等级/分数 + 附件 + 评语 + 批改人与时间） | :253-298 | 同（等级本地化见 AssignmentText.gradeText） |
 * | 答案（附件 + 正文） | :299-326 | 同 |
 * | 描述（Web 容器渲染，含 KaTeX） | :122-130, :364-374 | 同：`ui/components/HtmlWebView` + `buildNoticeContent` |
 * | 附件点击 → `push('FileDetail')` | :132-145 | 同路由（`ROUTE_FILE_DETAIL`），参数逐项对齐 |
 *
 * ## 三处必须说明的判断
 *
 * 1. **没有提交入口（硬红线）**：参考实现在 headerRight 放了一个"上传"按钮
 *    （:105-120），点它进 `AssignmentSubmission`。本工程把**提交**归 ticket 13
 *    （真实账号、不可逆写入），本 ticket **全程只读**：页面上不渲染任何提交按钮，
 *    也不构造提交请求。`Assignment.submitUrl` 只随列表项带过来、不在此页使用。
 *
 * 2. **不显示"优秀作业"**：参考实现还有一段 `excellentHomeworkList`（:327-363），
 *    其数据来自**另一条接口**（thu-learn-lib `getExcellentHomeworkListByHomework`，
 *    每门课一次 POST）；ticket 05 已验收的 `AssignmentsFetcher` 语义里没有它，
 *    而课工单的四条验收标准也没有它。改那条取数属于改已验收前提（要两边写边界说明），
 *    因此本 ticket 不取、不显示，并在交付说明里登记为**未交付项**。
 *
 * 3. **附件点击的落点**：参考实现 `handleFileOpen` 传的 `id` 是**附件 id**
 *    （AssignmentDetail.tsx:134；对比公告详情传的是公告 id，NoticeDetail.tsx:64）。
 *    这里照作业那条走（`noticeId` 字段名沿用 ticket 04 的 `FileDetailRouteParams`，
 *    它是"文件缓存目录名"；字段名不改是为了不动 ticket 04 已验收的导航契约 ——
 *    见 ticket 11 的边界说明）。`FileDetail` 的**真身**（下载/预览/分享）归 ticket 11。
 *
 * 描述为什么走 Web 容器而不是纯文本：参考实现把描述喂给 `getWebViewTemplate`
 * （:122-130），模板里带 KaTeX 的 auto-render（`$$…$$` 与 `\(…\)` 才排版，
 * 单 `$` 不排版 —— docs/reference-quirks.md 第 9 条锁定）。纯 Text 渲染会把公式
 * 变成字面量。
 */
import { ConfigurationConstant } from '@kit.AbilityKit';
import { PLAIN_PALETTE, ThemeTokens, resolveTheme } from '../../ui/theme/Tokens';
import { i18nService } from '../../core/i18n/I18n';
import { formatRelativeTo } from '../../core/i18n/DateTimeUtil';
import { COLOR_MODE_KEY } from '../../entryability/EntryAbility';
import { Logger } from '../../core/log/Logger';
import { Assignment, Attachment } from '../../domain/model/ContentItem';
import { parseTimestamp } from '../../domain/parse/Text';
import { buildNoticeContent, removeTags } from '../../domain/render/WebViewTemplate';
import { getExtension, stripExtension } from '../../domain/render/FileNames';
import { HtmlWebView } from '../../ui/components/HtmlWebView';
import { SessionHeaderProvider } from '../../core/web/SessionHeaderProvider';
import { FileDetailRouteParams, ROUTE_FILE_DETAIL } from '../notices/NoticeRoutes';
import { completionText, deadlineText, dueStatusText, gradeText, submissionText } from './AssignmentText';

const logger: Logger = new Logger('features.assignments.detail');

/** 一行附件（📄 + 文件名）。 */
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

  aboutToAppear(): void {
    // 站点原文进 hilog：完成方式 / 提交方式的**实际取值**决定 AssignmentText 的映射
    // （参考实现比较数字枚举，而站点可能下发中文标签，见 docs/reference-quirks.md 第 19 条）。
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
      + ' descriptionChars=' + this.assignment.description.length.toString());
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

  @Builder
  headerRow() {
    Row() {
      Text('‹')
        .fontSize(this.theme().typography.headlineSmall.fontSize)
        .fontColor(this.theme().colors.primary)
        .width(this.theme().sizes.controlHeight)
        .height(this.theme().sizes.controlHeight)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          if (this.stack !== null) {
            this.stack.pop();
          }
        })
        .accessibilityText(this.s($r('app.string.loh_back')))
      Text(this.s($r('app.string.loh_assignments')))
        .fontSize(this.theme().typography.titleMedium.fontSize)
        .fontColor(this.theme().colors.onSurfaceVariant)
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

  /** 一行附件（📄 + 文件名 + 说明标签），整行可点。 */
  @Builder
  attachmentRow(spec: AttachmentSpec) {
    Column() {
      Row() {
        Text('📄')
          .fontSize(this.theme().sizes.iconMedium)
          .fontColor(PLAIN_PALETTE.orange500)
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
    this.sectionTitle('✓', this.s($r('app.string.loh_submitted')))
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
    this.sectionTitle('🎓', this.s($r('app.string.ui_assignment_grade')))
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
    this.sectionTitle('🔑', this.s($r('app.string.ui_assignment_answer')))
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

  /** 段标题（符号 + 语义文字）。 */
  @Builder
  sectionTitle(symbol: string, title: string) {
    Row() {
      Text(symbol)
        .fontSize(this.theme().sizes.iconSmall)
        .fontColor(this.theme().colors.primary)
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
          // 描述（含公式）交 Web 容器渲染（参考实现 :122-130, :364-374）。
          this.sectionTitle('📝', this.s($r('app.string.ui_assignment_description')))
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
