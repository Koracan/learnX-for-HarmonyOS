/*
 * 作业提交页 —— 逐项对齐参考实现
 * `reference/learnOH-old/src/screens/AssignmentSubmission.tsx`。
 *
 * ## 页面结构（对应参考实现行号）
 *
 * | 元素 | 参考实现 | 这里 |
 * | --- | --- | --- |
 * | 页头：返回 + 标题（作业提交）+ 右侧提交按钮 | :68, :250-276 | 自绘页头（本工程全部页面都 hideTitleBar(true)） |
 * | 正文多行输入，初值 = removeTags(submittedContent) 去 --> | :81-85, :304-320 | 同（初值在 domain/assignments/SubmissionState） |
 * | 自定义附件名输入（仅在新附件存在时） | :107-109, :321-329 | 同 |
 * | 上传进度条 0..1 | :311 | 同（Progress） |
 * | 已提交附件行（新附件存在或移除态时加删除线） | :341-357 | 同 |
 * | 新附件行（可移除） | :358-393 | 行**不**可点 |
 * | 移除已上传 / 撤销移除 / 移除已选择 | :394-420 | 同（文案随状态切换） |
 * | 文件 / 照片两个入口 | :421-444 | 同（平台 picker，见 AttachmentPickers） |
 * | 上次提交时间 | :445-453 | 同（模式走 i18n 资源 ui_assignment_submission_time） |
 * | 提交二次确认弹窗 | :250-268 | 同（系统对话框，可取消） |
 * | 失败提示 + **不丢已填内容** | :233-237 | 同（状态机 submitFailed + 页内错误条 + toast） |
 * | 成功后清 pending、重取该课程作业、toast、goBack() | :225-232 | 重取用 CourseListStore.refresh()（本工程没有「按课程取数」这条路径） |
 * | pendingAssignmentData（之前分享的） | :294-302, :376-380 | **不移植**：本工程没有系统分享入口 |
 *
 * ## 为什么失败不丢内容可以在 host 上证明
 *
 * 参考实现这条语义在 React 的 catch 分支里。这里把它抽成 domain/assignments/SubmissionState
 * 的纯迁移函数，单测直接断言 submitFailed 之后 content / attachment / customAttachmentName
 * 三个字段与失败前**逐字段相同**，而不是靠截图。
 *
 * ## 与参考实现的已知差异
 *
 *   - pendingAssignmentData（之前分享的）不移植 —— 本工程没有系统分享入口；
 *   - 新附件那一行不可点 —— 参考实现点它进 FileDetail（本地 URI 预览），
 *     而本工程的 FileDetail 契约是「先下载再预览」，本地未上传的 URI 不在该契约内。
 */
import { ConfigurationConstant } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { PLAIN_PALETTE, ThemeTokens, resolveTheme } from '../../ui/theme/Tokens';
import { i18nService } from '../../core/i18n/I18n';
import { COLOR_MODE_KEY, LOCALE_VERSION_KEY } from '../../entryability/EntryAbility';
import { Logger } from '../../core/log/Logger';
import { Assignment, Attachment } from '../../domain/model/ContentItem';
import { UploadProgress } from '../../data/remote/Port';
import { AssignmentSubmitter, SubmitOutcome } from '../../data/assignments/SubmitAssignment';
import {
  SubmissionState, SubmitBlockReason, canSubmit, initialSubmissionState, planSubmission,
  submitBlockReason, submitFailed, submitStarted, submitSucceeded, withAttachmentPicked,
  withContent, withCustomAttachmentName, withPickedAttachmentRemoved,
  withRemoveAttachmentToggled, withUploadProgress
} from '../../domain/assignments/SubmissionState';
import { PickedAttachment } from '../../domain/assignments/SubmissionForm';
import { formatNoticeDate, NoticeDateText } from '../../domain/render/NoticeDateText';
import { parseTimestamp } from '../../domain/parse/Text';
import { getExtension, stripExtension } from '../../domain/render/FileNames';
import { AppIcon } from '../../ui/icons/IconCatalog';
import { IconGlyph } from '../../ui/icons/IconGlyph';
import { CourseListStore } from '../courses/CourseListStore';
import { FileDetailRouteParams, ROUTE_FILE_DETAIL } from '../notices/NoticeRoutes';
import { submissionBlockedKey } from './AssignmentText';
import { AttachmentPickers, PickOutcome } from './AttachmentPickers';
import { createAssignmentSubmitter } from './repository/AssignmentSubmissionProvider';

const logger: Logger = new Logger('features.assignments.submission');

/** 提交页要的作业默认值（父组件一定会覆盖；ArkTS 的 struct 成员必须有初值）。 */
function emptyAssignment(): Assignment {
  return {
    id: '', baseId: '', title: '', url: '', deadline: '', isLateSubmission: false,
    completionType: '', submissionType: '', submitUrl: '', courseId: '', courseName: '',
    courseTeacherName: '', gradeContent: '', submittedContent: '', answerContent: '',
    description: '', submitted: false, graded: false
  };
}

@Component
export struct AssignmentSubmissionPage {
  @StorageProp(COLOR_MODE_KEY) colorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageLink(LOCALE_VERSION_KEY) localeVersion: number = 0;

  assignment: Assignment = emptyAssignment();
  stack: NavPathStack | null = null;
  /** 提交成功后要重新取数的课程状态（与作业列表同一个实例；为 null 时只 toast）。 */
  store: CourseListStore | null = null;

  @State state: SubmissionState = initialSubmissionState('');

  private submitter: AssignmentSubmitter = createAssignmentSubmitter();
  private pickers: AttachmentPickers = new AttachmentPickers();

  aboutToAppear(): void {
    this.state = initialSubmissionState(this.assignment.submittedContent);
    logger.info('submission page appear: xszyid=' + this.studentHomeworkId()
      + ' submittedContentChars=' + this.assignment.submittedContent.length.toString()
      + ' contentChars=' + this.state.content.length.toString()
      + ' hasSubmittedAttachment=' + (this.assignment.submittedAttachment === undefined ? 'no' : 'yes')
      + ' submitTime=' + (this.assignment.submitTime === undefined ? 'none' : this.assignment.submitTime)
      + ' canSubmit=' + canSubmit(this.state).toString());
  }

  private theme(): ThemeTokens {
    return resolveTheme(this.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
  }

  private s(resource: Resource): string {
    return i18nService.tKey(resource);
  }

  private studentHomeworkId(): string {
    const id: string | undefined = this.assignment.studentHomeworkId;
    return id === undefined ? '' : id;
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 2000 });
    } catch (error) {
      logger.warn('toast failed: ' + (error as Error).message);
    }
  }

  /** 上次提交时间（参考实现 :445-453；模式与词表全部来自 i18n 资源）。 */
  private submissionTimeText(): string {
    const time: string | undefined = this.assignment.submitTime;
    if (time === undefined || time.length === 0) {
      return '';
    }
    const at: number = parseTimestamp(time);
    if (Number.isNaN(at)) {
      return '';
    }
    const text: NoticeDateText = {
      pattern: this.s($r('app.string.ui_assignment_submission_time')),
      weekdays: [
        this.s($r('app.string.ui_weekday_sunday')),
        this.s($r('app.string.ui_weekday_monday')),
        this.s($r('app.string.ui_weekday_tuesday')),
        this.s($r('app.string.ui_weekday_wednesday')),
        this.s($r('app.string.ui_weekday_thursday')),
        this.s($r('app.string.ui_weekday_friday')),
        this.s($r('app.string.ui_weekday_saturday'))
      ],
      months: [
        this.s($r('app.string.ui_month_jan')),
        this.s($r('app.string.ui_month_feb')),
        this.s($r('app.string.ui_month_mar')),
        this.s($r('app.string.ui_month_apr')),
        this.s($r('app.string.ui_month_may')),
        this.s($r('app.string.ui_month_jun')),
        this.s($r('app.string.ui_month_jul')),
        this.s($r('app.string.ui_month_aug')),
        this.s($r('app.string.ui_month_sep')),
        this.s($r('app.string.ui_month_oct')),
        this.s($r('app.string.ui_month_nov')),
        this.s($r('app.string.ui_month_dec'))
      ],
      am: '',
      pm: ''
    };
    return formatNoticeDate(at, text);
  }

  /** 已提交附件 → FileDetail 的参数（与作业详情页同一条路由、同样的字段映射）。 */
  private submittedAttachmentParams(attachment: Attachment): FileDetailRouteParams {
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

  private openSubmittedAttachment(): void {
    const attachment: Attachment | undefined = this.assignment.submittedAttachment;
    if (attachment === undefined || this.stack === null) {
      return;
    }
    const params: FileDetailRouteParams = this.submittedAttachmentParams(attachment);
    logger.info('submission submitted attachment tapped: name=' + params.attachmentName);
    this.stack.pushPath({ name: ROUTE_FILE_DETAIL, param: params });
  }

  // ------------------------------------------------------------------
  // 事件处理（全部只把纯状态机的结果写回 @State）
  // ------------------------------------------------------------------

  private handleContentChange(text: string): void {
    this.state = withContent(this.state, text);
  }

  private handleCustomNameChange(text: string): void {
    this.state = withCustomAttachmentName(this.state, text);
  }

  private handleToggleRemoveAttachment(): void {
    this.state = withRemoveAttachmentToggled(this.state);
    logger.info('submission remove-attachment toggled: remove=' + this.state.removeAttachment.toString()
      + ' canSubmit=' + canSubmit(this.state).toString());
  }

  private handleRemovePickedAttachment(): void {
    this.state = withPickedAttachmentRemoved(this.state);
    logger.info('submission picked attachment cleared');
  }

  private applyPickOutcome(outcome: PickOutcome, source: string): void {
    if (outcome.cancelled) {
      // 取消**不是失败**（参考实现 :131-133）：状态一字不动。
      logger.info('submission pick cancelled: source=' + source);
      return;
    }
    if (outcome.failed || outcome.picked === undefined) {
      logger.warn('submission pick failed: source=' + source + ' message=' + outcome.message);
      this.toast(this.s($r('app.string.loh_file_pick_failed')));
      return;
    }
    const picked: PickedAttachment = outcome.picked;
    this.state = withAttachmentPicked(this.state, picked);
    logger.info('submission attachment picked: source=' + source + ' name=' + picked.name
      + ' mime=' + picked.mimeType + ' canSubmit=' + canSubmit(this.state).toString());
  }

  private async handleDocumentPick(): Promise<void> {
    const outcome: PickOutcome = await this.pickers.pickDocument(this.assignment.title);
    this.applyPickOutcome(outcome, 'documents');
  }

  private async handlePhotoPick(): Promise<void> {
    const outcome: PickOutcome = await this.pickers.pickPhoto(this.assignment.title);
    this.applyPickOutcome(outcome, 'photos');
  }

  /**
   * 「提交」此刻不能走的原因（`undefined` = 可以走）。
   *
   * 判定只有一份：`domain/assignments/SubmissionState.submitBlockReason`。按钮的外观、
   * 点击时说的话都读它，避免"灰按钮"与"提示"各判一套。
   *
   * **本页不把截止时间算进来**（第一项固定传 `false`）：逾期与否的最终裁判是站点
   * （补交截止 `bjjzsj` 那一支也是站点说了算），本地在这里再发明一道闸，可能挡住一次
   * 合法的补交；参考实现的提交按钮同样只读"在飞 / 有没有内容"，完全不读截止
   * （AssignmentSubmission.tsx:274-276）。进本页的唯一入口在作业详情页，那里已经判过截止。
   */
  private blockReason(): SubmitBlockReason | undefined {
    return submitBlockReason(false, this.state);
  }

  /**
   * 点「提交」：能走才进二次确认（与改动前同一条路径）；不能走就说**为什么**。
   *
   * 改动前这里是一个 `enabled(false)` 的灰按钮：点下去既没有请求、也没有任何说明
   * （未选附件 / 正在提交中两种情形看起来一模一样）。拦截本身一字未改 ——
   * 能否提交的判据仍是 `canSubmit` 那一套（本页不看截止），不能走时依然**不发任何请求**。
   */
  private handleSubmitPress(): void {
    const reason: SubmitBlockReason | undefined = this.blockReason();
    if (reason !== undefined) {
      logger.info('submission blocked: reason=' + reason
        + ' xszyid=' + this.studentHomeworkId()
        + ' deadline=' + this.assignment.deadline);
      this.toast(i18nService.t(submissionBlockedKey(reason)));
      return;
    }
    this.confirmThenSubmit();
  }

  /** 二次确认（参考实现 :250-268）：取消 ⇒ 什么都不做。 */
  private async confirmThenSubmit(): Promise<void> {
    const options: promptAction.ShowDialogOptions = {
      title: this.s($r('app.string.loh_submit_assignment')),
      message: this.s($r('app.string.loh_submit_assignment_confirmation')),
      buttons: [
        { text: this.s($r('app.string.loh_cancel')), color: this.theme().colors.onSurfaceVariant },
        { text: this.s($r('app.string.loh_ok')), color: this.theme().colors.primary }
      ]
    };
    try {
      const response: promptAction.ShowDialogSuccessResponse =
        await this.getUIContext().getPromptAction().showDialog(options);
      if (response.index !== 1) {
        logger.info('submission cancelled at the confirmation dialog');
        return;
      }
    } catch (error) {
      // 对话框起不来时**不静默提交**：写一行日志并中止（写操作不能没有确认）。
      logger.error('submission confirm dialog failed: ' + (error as Error).message);
      return;
    }
    await this.doSubmit();
  }

  private async doSubmit(): Promise<void> {
    const plan = planSubmission(this.state, this.studentHomeworkId());
    if (plan === undefined) {
      // 参考实现 source.ts:161-163：无正文、无附件、不移除 ⇒ 直接返回。
      logger.info('submission skipped: nothing to submit');
      return;
    }
    const requestId: string = 'submit_' + Date.now().toString();
    this.state = submitStarted(this.state);
    logger.info('submission started: requestId=' + requestId
      + ' xszyid=' + plan.studentHomeworkId
      + ' contentChars=' + plan.content.length.toString()
      + ' removeAttachment=' + plan.removeAttachment.toString()
      + ' file=' + (plan.attachment === undefined ? '(none)' : plan.attachment.name));
    const outcome: SubmitOutcome = await this.submitter.submit(plan, requestId,
      (progress: UploadProgress): void => {
        this.state = withUploadProgress(this.state, progress.sent, progress.total);
      });
    if (!outcome.ok) {
      // 参考实现 :233-237：只复位 uploading / error / progress，**已填内容一字不动**。
      this.state = submitFailed(this.state);
      logger.warn('submission failed: status=' + outcome.status.toString()
        + ' serverRejected=' + outcome.serverRejected.toString()
        + ' requiresEnrollment=' + outcome.requiresEnrollment.toString()
        + ' contentChars=' + this.state.content.length.toString()
        + ' attachmentKept=' + (this.state.attachment === undefined ? 'no' : 'yes')
        + ' diag=' + outcome.diagnostic);
      this.toast(this.s($r('app.string.loh_assignment_submission_failed')));
      return;
    }
    this.state = submitSucceeded(this.state);
    logger.info('submission succeeded: status=' + outcome.status.toString());
    // 参考实现成功后 dispatch(getAssignmentsForCourse(courseId))；本工程没有按课程取数这条路径，
    // 用课程状态（与作业列表同一个实例）整体刷新一次。
    if (this.store !== null) {
      await this.store.refresh();
    }
    this.toast(this.s($r('app.string.loh_assignment_submission_succeeded')));
    if (this.stack !== null) {
      this.stack.pop();
    }
  }

  // ------------------------------------------------------------------
  // 视图
  // ------------------------------------------------------------------

  @Builder
  headerRow() {
    Row() {
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
      Text(this.s($r('app.string.loh_assignment_submission')))
        .fontSize(this.theme().typography.titleMedium.fontSize)
        .fontColor(this.theme().colors.onSurface)
        .margin({ left: this.theme().sizes.space1 })
      Blank()
      Text(this.s($r('app.string.loh_submit')))
        .fontSize(this.theme().typography.titleMedium.fontSize)
        .fontWeight(FontWeight.Bold)
        // 不能提交时外观仍是灰的（判据与改动前一致），但**保持可点**：
        // 点下去要说清是"已截止 / 正在提交中 / 没有可提交的内容"里的哪一种。
        .fontColor(this.blockReason() === undefined
          ? this.theme().colors.primary : this.theme().colors.onSurfaceDisabled)
        .onClick(() => {
          this.handleSubmitPress();
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({
      left: this.theme().sizes.contentPadding,
      right: this.theme().sizes.contentPadding,
      top: this.theme().sizes.space2,
      bottom: this.theme().sizes.space2
    })
  }

  @Builder
  progressBar() {
    if (this.state.uploading || this.state.progress > 0) {
      Progress({ value: this.state.progress * 100, total: 100, type: ProgressType.Linear })
        .width('100%')
        .color(this.theme().colors.primary)
    }
  }

  @Builder
  contentEditor() {
    Column() {
      TextArea({
        text: this.state.content,
        placeholder: this.s($r('app.string.loh_assignment_submission_content_placeholder'))
      })
        .width('100%')
        .layoutWeight(1)
        .enabled(!this.state.removeAttachment && !this.state.uploading)
        .backgroundColor(this.theme().colors.surface)
        .fontColor(this.theme().colors.onSurface)
        .onChange((value: string) => {
          this.handleContentChange(value);
        })
      if (this.state.attachment !== undefined) {
        TextInput({
          text: this.state.customAttachmentName,
          placeholder: this.s($r('app.string.loh_assignment_submission_filename_placeholder'))
        })
          .width('100%')
          .enabled(!this.state.removeAttachment && !this.state.uploading)
          .backgroundColor(this.theme().colors.surface)
          .fontColor(this.theme().colors.onSurface)
          .margin({ top: this.theme().sizes.space2 })
          .onChange((value: string) => {
            this.handleCustomNameChange(value);
          })
      }
    }
    .width('100%')
    .layoutWeight(1)
    .padding({
      left: this.theme().sizes.contentPadding,
      right: this.theme().sizes.contentPadding,
      top: this.theme().sizes.space2
    })
  }

  @Builder
  submittedAttachmentRow() {
    if (this.assignment.submittedAttachment !== undefined) {
      Row() {
        IconGlyph({
          icon: AppIcon.ATTACHMENT, glyphSize: this.theme().sizes.iconSmall,
          color: PLAIN_PALETTE.orange500,
          label: this.s($r('app.string.ui_assignment_submitted_attachment_label'))
        })
        Text(this.assignment.submittedAttachment.name)
          .fontSize(this.theme().typography.bodyLarge.fontSize)
          .fontColor(this.state.attachment !== undefined || this.state.removeAttachment
            ? this.theme().colors.onSurfaceDisabled : this.theme().colors.primary)
          .decoration({
            type: this.state.attachment !== undefined || this.state.removeAttachment
              ? TextDecorationType.LineThrough : TextDecorationType.None,
            color: this.theme().colors.onSurfaceDisabled
          })
          .layoutWeight(1)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ left: this.theme().sizes.space2 })
        Blank()
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ top: this.theme().sizes.space1, bottom: this.theme().sizes.space1 })
      .onClick(() => {
        this.openSubmittedAttachment();
      })
    }
  }

  @Builder
  pickedAttachmentRow() {
    if (!this.state.removeAttachment && this.state.attachment !== undefined) {
      Row() {
        IconGlyph({
          icon: AppIcon.ATTACHMENT, glyphSize: this.theme().sizes.iconSmall,
          color: PLAIN_PALETTE.orange500,
          label: this.s($r('app.string.ui_assignment_attachment_label'))
        })
        Text(this.state.attachment.name)
          .fontSize(this.theme().typography.bodyLarge.fontSize)
          .fontColor(this.theme().colors.onSurface)
          .layoutWeight(1)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ left: this.theme().sizes.space2 })
        Blank()
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ top: this.theme().sizes.space1, bottom: this.theme().sizes.space1 })
    }
  }

  @Builder
  actionButton(label: string, danger: boolean, action: () => void) {
    Button(label)
      .fontSize(this.theme().typography.labelMedium.fontSize)
      .backgroundColor(danger ? this.theme().colors.error : this.theme().colors.primaryContainer)
      .fontColor(danger ? this.theme().colors.onPrimary : this.theme().colors.onPrimaryContainer)
      .enabled(!this.state.uploading)
      .margin({ left: this.theme().sizes.space1 })
      .onClick(action)
  }

  @Builder
  actionRow() {
    Row() {
      if (this.assignment.submittedAttachment !== undefined) {
        this.actionButton(this.state.removeAttachment
          ? this.s($r('app.string.loh_undo_remove_uploaded_attachment'))
          : this.s($r('app.string.loh_remove_uploaded_attachment')),
          this.state.removeAttachment,
          () => {
            this.handleToggleRemoveAttachment();
          })
      }
      if (!this.state.removeAttachment && this.state.attachment !== undefined) {
        this.actionButton(this.s($r('app.string.loh_remove_picked_attachment')), false,
          () => {
            this.handleRemovePickedAttachment();
          })
      }
      if (!this.state.removeAttachment) {
        this.actionButton(this.s($r('app.string.loh_documents')), false,
          () => {
            this.handleDocumentPick();
          })
        this.actionButton(this.s($r('app.string.loh_photos')), false,
          () => {
            this.handlePhotoPick();
          })
      }
      Blank()
    }
    .width('100%')
  }

  @Builder
  detailSection() {
    Column() {
      this.submittedAttachmentRow()
      this.pickedAttachmentRow()
      this.actionRow()
      if (this.submissionTimeText().length > 0) {
        Text(this.submissionTimeText())
          .fontSize(this.theme().typography.labelSmall.fontSize)
          .fontColor(this.theme().colors.onSurfaceVariant)
          .width('100%')
          .margin({ top: this.theme().sizes.space1 })
      }
      if (this.state.error) {
        Text(this.s($r('app.string.loh_assignment_submission_failed')))
          .fontSize(this.theme().typography.bodyMedium.fontSize)
          .fontColor(this.theme().colors.error)
          .width('100%')
          .margin({ top: this.theme().sizes.space1 })
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({
      left: this.theme().sizes.contentPadding,
      right: this.theme().sizes.contentPadding,
      top: this.theme().sizes.space2,
      bottom: this.theme().sizes.space3
    })
  }

  build() {
    Column() {
      this.headerRow()
      this.progressBar()
      this.contentEditor()
      Divider()
        .strokeWidth(this.theme().sizes.borderWidth)
        .color(this.theme().colors.outlineVariant)
      this.detailSection()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme().colors.background)
  }
}


