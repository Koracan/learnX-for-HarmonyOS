/*
 * 文件详情页（ticket 11）：下载（真进度）→ 应用内预览 → 分享。
 *
 * ## 与参考实现 `screens/FileDetail.tsx` 的对照
 *
 * | 项 | 参考实现 | 这里 |
 * | --- | --- | --- |
 * | 进入即自动下载 | `useEffect(() => handleDownload(false))` :152-154 | 同（`aboutToAppear`） |
 * | 刷新按钮 | `handleDownload(true)`（强制重下） :114 | 同 |
 * | 进度条 | `<ProgressBar progress={progress}/>`（库的 `bytesWritten` **恒为 0**） | 平台 HTTP 层 `dataReceive` 的**真实**字节数 + `Content-Length`；无 Content-Length 时不显示百分比 |
 * | PDF 预览 | `react-native-pdf` 的 `<Pdf>` :170-175 | **HMS PDFKit** 的 `PdfView` + `loadDocument(path)` |
 * | 图片预览 | `<WebView source={{uri:'file://'+path}}/>` :176-188 | ArkUI **`Image`** + `image.createPixelMap(path)` |
 * | 其他类型 | 信息面板（标题/类型/体积/描述）+ 分享 + **跳系统打开方式** | 信息面板 + 分享；**不再外跳**（有意偏离） |
 * | 会话过期 | 落盘后按"小文件含 `<html`"猜 | 落盘前按 `Content-Type` 判定 → 不落盘 + `loh_session_expired` |
 *
 * 描述/体积：附件来源没有 `description`（`Attachment` 里就没有这个字段），
 * 所以描述行按参考实现显示 `loh_no_file_description`；体积优先显示站点给的文本，
 * 下载完成后显示**落盘真实字节数**格式化后的值（参考实现 :73-75 同一行为）。
 */

import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileUri } from '@kit.CoreFileKit';
import { systemShare } from '@kit.ShareKit';
import { pdfService } from '@kit.PDFKit';
import { ThemeTokens, resolveTheme } from '../../ui/theme/Tokens';
import { i18nService } from '../../core/i18n/I18n';
import { Logger } from '../../core/log/Logger';
import { COLOR_MODE_KEY, LOCALE_VERSION_KEY } from '../../entryability/EntryAbility';
import { cacheKeyFor, fileKindOf, FileKind, formatSize } from '../../domain/files/FilePath';
import { isSessionLossReason } from '../../domain/files/FileDownloadPolicy';
import { removeTags } from '../../domain/render/WebViewTemplate';
import { FileDownloadOutcome, FileDownloadRequest } from '../../data/files/FileDownloader';
import { FileDownloadReport } from '../../data/files/FileRepository';
import { describeFileSettings } from '../../data/settings/FileSettings';
import { FileDetailRouteParams } from '../notices/NoticeRoutes';
import { fileRepository, fileSettingsStore } from './repository/FileRepositoryProvider';
import { AppIcon } from '../../ui/icons/IconCatalog';
import { IconGlyph } from '../../ui/icons/IconGlyph';
import { SPLIT_VIEW_ACTIVE_KEY, SPLIT_VIEW_MASTER_HIDDEN_KEY } from '../shell/SplitView';

const logger: Logger = new Logger('features.files.detail');

/** 详情页状态。 */
export enum FileDetailPhase {
  IDLE = 'idle',
  DOWNLOADING = 'downloading',
  READY = 'ready',
  ERROR = 'error'
}

/** 信息面板的一行。 */
interface InfoRowSpec {
  theme: ThemeTokens;
  label: string;
  value: string;
}

@Component
export struct FileDetailPage {
  @StorageProp(COLOR_MODE_KEY) colorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageLink(LOCALE_VERSION_KEY) localeVersion: number = 0;
  /**
   * 双栏是否生效：全屏按钮**只在双栏时**渲染，对齐参考实现 `FileDetail.tsx:108` 的 `showDetail &&`。
   * 读的是根布局判据的消费点值（features/shell/SplitView.ets）。
   */
  @StorageProp(SPLIT_VIEW_ACTIVE_KEY) splitActive: boolean = false;
  /** 主栏是否被隐藏（参考实现的 `showMaster` 取反，`FileDetail.tsx:110-111` 翻转它）。 */
  @StorageProp(SPLIT_VIEW_MASTER_HIDDEN_KEY) masterHidden: boolean = false;

  /** 由 NavDestination 传入的参数（公告/作业附件、课程文件都走它）。 */
  params: FileDetailRouteParams = {
    noticeId: '', courseName: '', courseTeacherName: '', title: '',
    attachmentName: '', downloadUrl: '', fileType: ''
  };
  /** 本 tab 的导航栈（返回用）。 */
  stack: NavPathStack | null = null;

  @State phase: FileDetailPhase = FileDetailPhase.IDLE;
  @State received: number = 0;
  @State total: number = -1;
  @State bytes: number = 0;
  @State localPath: string = '';
  @State errorText: string = '';
  @State showInfo: boolean = false;
  @State previewError: string = '';
  @State pixelMap: image.PixelMap | undefined = undefined;
  @State settingsSummary: string = '';
  /**
   * true = **平台缺少预览能力**（不是文件坏了）。
   *
   * 实测（模拟器 Pura 90 / HarmonyOS 6.1.0(23)）：HMS PDFKit 的原生模块
   * `@hms:officeservice.pdfservice` **在本机不存在**（hilog: `Load native module failed`），
   * 于是 `pdfService` 是 `undefined`，读它的成员抛 TypeError。
   * 这种情况要显示"该类型不支持应用内预览、可下载后分享"，而不是把一句 JS 报错甩给用户。
   */
  @State previewUnsupported: boolean = false;

  /**
   * PDF 文档句柄（`pdfService.PdfDocument`，同步 API）。
   *
   * **为什么不用 `PdfView` 组件**：模拟器实测（HarmonyOS 6.1.0(23)）`@hms:officeservice.PdfView`
   * 在运行期**不导出** `pdfViewManager`（编译期 d.ts 里有、运行期报
   * "does not provide an export name 'pdfViewManager'"），于是整个组件构造失败、应用直接崩。
   * 改用同一套 PDFKit 的 `pdfService` 命名空间（`PdfDocument.loadDocument` + `PdfPage.getPagePixelMap`）
   * 把页面渲染成 `PixelMap`，交给 ArkUI 的 `Image` —— **仍然是应用内渲染**，不跳第三方。
   * 取证见 ticket 11 的 B 系列证据（含那次崩溃的 hilog）。
   */
  private pdfDocument: pdfService.PdfDocument | null = null;
  @State pdfPageIndex: number = 0;
  @State pdfPageCount: number = 0;
  @State pdfPage: image.PixelMap | undefined = undefined;
  private started: boolean = false;

  aboutToAppear(): void {
    this.bootstrap();
  }

  private theme(): ThemeTokens {
    return resolveTheme(this.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
  }

  private s(resource: Resource): string {
    return i18nService.tKey(resource);
  }

  private kind(): FileKind {
    return fileKindOf(this.params.fileType);
  }

  private previewable(): boolean {
    return this.kind() !== FileKind.OTHER;
  }

  /** 进入即"读设置 → 自动下载"（参考实现 :152-154）。 */
  private async bootstrap(): Promise<void> {
    if (this.started) {
      return;
    }
    this.started = true;
    const settings = fileSettingsStore();
    const value = await settings.load();
    // 消费点自证：设置页改的是同一份 store，这里读到的是**实际生效值**。
    this.settingsSummary = describeFileSettings(value);
    logger.info('file detail appear: title="' + this.params.title + '" type=' + this.params.fileType
      + ' noticeId=' + this.params.noticeId + ' url=' + this.params.downloadUrl);
    logger.info('file detail effective ' + this.settingsSummary);
    await this.startDownload(false);
  }

  private request(refresh: boolean): FileDownloadRequest {
    return {
      downloadUrl: this.params.downloadUrl,
      // ticket 10 边界说明第 2 条：附件 id 可能是空串，cacheKeyFor 会兜底到地址末段。
      cacheKey: cacheKeyFor(this.params.noticeId, this.params.downloadUrl),
      courseName: this.params.courseName,
      title: this.params.title,
      fileType: this.params.fileType,
      refresh: refresh
    };
  }

  private async startDownload(refresh: boolean): Promise<void> {
    if (this.phase === FileDetailPhase.DOWNLOADING) {
      return;
    }
    this.phase = FileDetailPhase.DOWNLOADING;
    this.received = 0;
    this.total = -1;
    this.errorText = '';
    this.previewError = '';
    this.previewUnsupported = false;
    this.pixelMap = undefined;
    const request: FileDownloadRequest = this.request(refresh);
    try {
      const report: FileDownloadReport = await fileRepository().download(request,
        (received: number, total: number): void => {
          this.received = received;
          this.total = total;
        });
      if (!report.outcome.ok) {
        this.errorText = this.describeFailure(report);
        this.phase = FileDetailPhase.ERROR;
        logger.warn('file detail download failed: ' + this.errorText
          + ' rejected=' + report.outcome.rejectedReason
          + ' requiresEnrollment=' + report.requiresEnrollment.toString());
        return;
      }
      const outcome: FileDownloadOutcome = report.outcome;
      this.localPath = outcome.path;
      this.bytes = outcome.bytes;
      this.phase = FileDetailPhase.READY;
      logger.info('file detail ready: path=' + outcome.path + ' bytes=' + outcome.bytes.toString()
        + ' fromCache=' + outcome.fromCache.toString());
      await this.loadPreview();
    } catch (error) {
      this.errorText = (error as Error).message;
      this.phase = FileDetailPhase.ERROR;
      logger.error('file detail download threw: ' + this.errorText);
    }
  }

  /** 失败文案：会话失效要**明确**说"需要重新验证"（验收第 3 条），其余各有各的话。 */
  private describeFailure(report: FileDownloadReport): string {
    const outcome: FileDownloadOutcome = report.outcome;
    if (report.requiresEnrollment || isSessionLossReason(outcome.rejectedReason)) {
      return i18nService.t('loh_session_expired');
    }
    if (outcome.rejectedReason.length > 0) {
      return i18nService.t('ui_file_download_rejected', outcome.rejectedReason);
    }
    if (outcome.error === 'empty file') {
      return i18nService.t('ui_file_download_empty');
    }
    return i18nService.t('loh_file_download_failed');
  }

  /**
   * 应用内预览：
   *   - PDF → `PdfController.loadDocument(path)`（HMS PDFKit），失败时**如实报错**；
   *   - 图片 → `image.createPixelMap(path)` → `Image(pixelMap)`。
   * 两条都不跳第三方应用（有意偏离参考实现的"打开"动作）。
   */
  private async loadPreview(): Promise<void> {
    const kind: FileKind = this.kind();
    if (kind === FileKind.PDF) {
      try {
        const document: pdfService.PdfDocument = new pdfService.PdfDocument();
        const result: pdfService.ParseResult = document.loadDocument(this.localPath);
        if (result !== pdfService.ParseResult.PARSE_SUCCESS) {
          this.previewError = 'PDFKit parse result=' + result.toString();
          logger.error('file detail preview pdf parse failed: result=' + result.toString());
          return;
        }
        this.pdfDocument = document;
        this.pdfPageCount = document.getPageCount();
        this.renderPdfPage(0);
        logger.info('file detail preview pdf ok: pages=' + this.pdfPageCount.toString()
          + ' path=' + this.localPath);
      } catch (error) {
        this.notePreviewFailure(error, 'pdf');
      }
      return;
    }
    if (kind === FileKind.IMAGE) {
      try {
        const source: image.ImageSource = image.createImageSource(this.localPath);
        const decoded: image.PixelMap = await source.createPixelMap();
        this.pixelMap = decoded;
        logger.info('file detail preview image ok: path=' + this.localPath);
      } catch (error) {
        this.notePreviewFailure(error, 'image');
      }
    }
  }

  /**
   * 预览失败的分类：**平台能力缺失**（消息里出现 "of undefined"，即读一个不存在的平台命名空间的成员）
   * 与**文件/解码失败**要分开——前者给 `ui_file_preview_unavailable`，后者给 `ui_file_preview_failed`。
   */
  private notePreviewFailure(error: Object, kind: string): void {
    const message: string = (error as Error).message;
    if (message.includes('of undefined')) {
      this.previewUnsupported = true;
      logger.warn('file detail preview ' + kind + ' unavailable on this platform: ' + message);
      return;
    }
    this.previewError = message;
    logger.error('file detail preview ' + kind + ' failed: ' + message);
  }

  /**
   * 分享用的 UTD（统一类型描述符）。
   *
   * **不用 `getUniformDataTypeByFilenameExtension`**：实测（模拟器，2026-09-12）它在
   * "扩展名 + belongsTo" 这一组合下会让后续的 `SharedData` 构造抛
   * `401 Parameter error.invalid arguments!`（`SharedData` 的构造函数按 BusinessError 401
   * 校验参数）。这里用三个**常量** UTD，语义与参考实现的 `mime.lookup` 三分类一致：
   * 图片 → `general.image`，纯文本 → `general.plain-text`，其余 → `general.file`。
   */
  private shareUtd(): string {
    const kind: FileKind = this.kind();
    if (kind === FileKind.IMAGE) {
      return uniformTypeDescriptor.UniformDataType.IMAGE;
    }
    if (this.params.fileType.trim().toLowerCase() === 'txt') {
      return uniformTypeDescriptor.UniformDataType.PLAIN_TEXT;
    }
    return uniformTypeDescriptor.UniformDataType.FILE;
  }

  /** 分享（systemShare）：URI 由 `fileUri.getUriFromPath` 生成 —— 中文与空格由它负责转义。 */
  private async share(): Promise<void> {
    if (this.localPath.length === 0) {
      return;
    }
    // 逐步打点：平台在这里会抛 401，必须能区分"哪一步的参数不合法"（AGENTS.md 取证口径）。
    let step: string = 'getUriFromPath';
    try {
      const uri: string = fileUri.getUriFromPath(this.localPath);
      logger.info('file detail share uri: ' + uri);
      step = 'utd';
      const utd: string = this.shareUtd();
      logger.info('file detail share utd: ' + utd);
      step = 'SharedData';
      const record: systemShare.SharedRecord = {
        utd: utd,
        uri: uri,
        title: removeTags(this.params.title)
      };
      const data: systemShare.SharedData = new systemShare.SharedData(record);
      const controller: systemShare.ShareController = new systemShare.ShareController(data);
      step = 'hostContext';
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const options: systemShare.ShareControllerOptions = {
        selectionMode: systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DETAIL
      };
      step = 'show';
      logger.info('file detail share: calling show uri=' + uri + ' utd=' + utd
        + ' contextPresent=' + (context === undefined || context === null ? 'false' : 'true'));
      await controller.show(context, options);
      logger.info('file detail share panel dismissed');
    } catch (error) {
      const business: BusinessError = error as BusinessError;
      const code: string = business.code === undefined ? 'none' : business.code.toString();
      logger.error('file detail share failed at step=' + step + ': code=' + code
        + ' message=' + business.message);
      this.errorText = i18nService.t('ui_file_share_failed', 'code=' + code + ' ' + business.message);
    }
  }

  /** 进度百分比；未知总量时返回 -1（界面据此走不确定进度，**不假装**百分比）。 */
  private progressPercent(): number {
    if (this.total <= 0 || this.received <= 0) {
      return -1;
    }
    return Math.min(100, Math.floor(this.received * 100 / this.total));
  }

  private progressText(): string {
    if (this.total > 0) {
      return i18nService.t('ui_file_download_progress', formatSize(this.received), formatSize(this.total));
    }
    return i18nService.t('ui_file_download_received', formatSize(this.received));
  }

  private sizeText(): string {
    if (this.bytes > 0) {
      return formatSize(this.bytes);
    }
    const declared: string | undefined = this.params.size;
    return declared === undefined || declared.length === 0
      ? i18nService.t('loh_no_file_size')
      : declared;
  }

  private infoText(): string {
    const description: string | undefined = this.params.description;
    if (description === undefined || description.trim().length === 0) {
      return i18nService.t('loh_no_file_description');
    }
    return removeTags(description);
  }

  /**
   * 全屏切换：翻转**全局**的"主栏隐藏"标志（AppStorage，取值点在各 tab 页的版式里）。
   *
   * 为什么走 AppStorage 而不是新加两个 @Prop：参考实现的 `showMaster` 就在 `SplitViewProvider`
   * 里、全局一份（`SplitView.tsx:40,106,117`），用 AppStorage 与它同粒度，也不用改
   * 四处 `FileDetailPage(...)` 构造点与它们的测试。日志打在**消费点**（各 tab 页的
   * `masterPaneWidth`）之外的那一行 setter 上，便于把"点了按钮"与"版式真的变了"分开核对。
   */
  private toggleMaster(): void {
    const next: boolean = !this.masterHidden;
    AppStorage.setOrCreate(SPLIT_VIEW_MASTER_HIDDEN_KEY, next);
    logger.info('file detail fullscreen toggle: masterHidden=' + next.toString()
      + ' split=' + this.splitActive.toString());
  }

  /**
   * 顶部工具栏。**不叫 toolbar**：那是 CustomComponent 继承来的属性方法名，重名会编译失败。
   *
   * 四个动作都是图标；点击目标统一是外层 `Stack` 的 **40vp×40vp**（`sizes.controlHeight`）。
   * 换图标**没有缩小点击区**：改动前每个按钮是一行 `labelLarge` 文字（行高约 20–24vp、
   * 宽度随文案），现在每个都是 40vp×40vp 的固定方框；图标本身按 `iconMedium`（24vp）居中。
   * **为什么点击加在 Stack 而不是 IconGlyph 上**：IconGlyph 是本工程的自定义组件，不给它链式挂
   * 通用属性（见 ui/icons/IconGlyph.ets 文件头）；间距仍用 `margin({left: space3})`，与改动前逐点相同。
   *
   * `label` 一律传**可读文案**（不是图标短名）：字体未就绪时 IconGlyph 的回退分支会把这段文案
   * 直接画出来，同时它也是无障碍朗读文案 —— 两种用途共用同一个键。
   */
  @Builder
  topBar() {
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
      Blank()
      // 全屏切换：隐藏左栏、把详情铺满 —— 参考实现 FileDetail.tsx:108-113 的
      // headerRight 首个 IconButton（fullscreen / fullscreen-exit），只在双栏时出现。
      if (this.splitActive) {
        Stack() {
          if (this.masterHidden) {
            IconGlyph({
              icon: AppIcon.FULLSCREEN_EXIT,
              glyphSize: this.theme().sizes.iconMedium,
              color: this.theme().colors.primary,
              label: this.s($r('app.string.loh_exit_fullscreen'))
            })
          } else {
            IconGlyph({
              icon: AppIcon.FULLSCREEN,
              glyphSize: this.theme().sizes.iconMedium,
              color: this.theme().colors.primary,
              label: this.s($r('app.string.loh_fullscreen'))
            })
          }
        }
        .width(this.theme().sizes.controlHeight)
        .height(this.theme().sizes.controlHeight)
        .margin({ left: this.theme().sizes.space3 })
        .onClick(() => {
          this.toggleMaster();
        })
      }
      Stack() {
        IconGlyph({
          icon: AppIcon.REFRESH, glyphSize: this.theme().sizes.iconMedium,
          color: this.theme().colors.primary, label: this.s($r('app.string.loh_refresh'))
        })
      }
      .width(this.theme().sizes.controlHeight)
      .height(this.theme().sizes.controlHeight)
      .margin({ left: this.theme().sizes.space3 })
      .onClick(() => {
        this.startDownload(true);
      })
      Stack() {
        IconGlyph({
          icon: AppIcon.SHARE, glyphSize: this.theme().sizes.iconMedium,
          color: this.localPath.length > 0 ? this.theme().colors.primary : this.theme().colors.outline,
          label: this.s($r('app.string.loh_share'))
        })
      }
      .width(this.theme().sizes.controlHeight)
      .height(this.theme().sizes.controlHeight)
      .margin({ left: this.theme().sizes.space3 })
      .onClick(() => {
        this.share();
      })
      if (this.previewable() && this.localPath.length > 0) {
        // 按钮的图标说的是**按下之后能看到什么**：正在看预览时给"详情"图标、给"预览"文案；
        // 正在看信息面板时反过来。文字按钮改成图标后，两态由图标的语义承载。
        Stack() {
          if (this.showInfo) {
            IconGlyph({
              icon: AppIcon.PREVIEW, glyphSize: this.theme().sizes.iconMedium,
              color: this.theme().colors.primary, label: this.s($r('app.string.ui_file_view_preview'))
            })
          } else {
            IconGlyph({
              icon: AppIcon.INFO, glyphSize: this.theme().sizes.iconMedium,
              color: this.theme().colors.primary, label: this.s($r('app.string.ui_file_view_info'))
            })
          }
        }
        .width(this.theme().sizes.controlHeight)
        .height(this.theme().sizes.controlHeight)
        .margin({ left: this.theme().sizes.space3 })
        .onClick(() => {
          this.showInfo = !this.showInfo;
        })
      }
    }
    .width('100%')
    .padding({
      left: this.theme().sizes.contentPadding,
      right: this.theme().sizes.contentPadding,
      top: this.theme().sizes.space3,
      bottom: this.theme().sizes.space3
    })
  }

  @Builder
  progressBar() {
    Column() {
      Row() {
        Text(this.s($r('app.string.ui_file_downloading')))
          .fontSize(this.theme().typography.labelSmall.fontSize)
          .fontColor(this.theme().colors.onSurfaceVariant)
          .layoutWeight(1)
        Text(this.progressText())
          .fontSize(this.theme().typography.labelSmall.fontSize)
          .fontColor(this.theme().colors.onSurfaceVariant)
      }
      .width('100%')

      if (this.progressPercent() >= 0) {
        Progress({ value: this.progressPercent(), total: 100, type: ProgressType.Linear })
          .color(this.theme().colors.primary)
          .width('100%')
      } else {
        // 没有 Content-Length：只显示"已接收字节"，**不**编一个百分比。
        LoadingProgress()
          .width(this.theme().sizes.iconMedium)
          .height(this.theme().sizes.iconMedium)
          .color(this.theme().colors.primary)
          .margin({ top: this.theme().sizes.space1 })
      }
    }
    .width('100%')
    .padding({
      left: this.theme().sizes.contentPadding,
      right: this.theme().sizes.contentPadding,
      top: this.theme().sizes.space2,
      bottom: this.theme().sizes.space2
    })
    .backgroundColor(this.theme().colors.surfaceVariant)
  }

  @Builder
  infoRow(spec: InfoRowSpec) {
    Row() {
      Text(spec.label)
        .fontSize(this.theme().typography.labelMedium.fontSize)
        .fontColor(this.theme().colors.onSurfaceVariant)
        .width(this.theme().sizes.controlHeight * 2.2)
      Text(spec.value)
        .fontSize(this.theme().typography.bodyMedium.fontSize)
        .fontColor(this.theme().colors.onSurface)
        .layoutWeight(1)
        .maxLines(4)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ top: this.theme().sizes.space1, bottom: this.theme().sizes.space1 })
  }

  @Builder
  infoPanel() {
    Scroll() {
      Column() {
        Text(removeTags(this.params.title))
          .fontSize(this.theme().typography.titleLarge.fontSize)
          .fontColor(this.theme().colors.onSurface)
          .width('100%')
          .margin({ bottom: this.theme().sizes.space3 })
        this.infoRow({
          theme: this.theme(), label: this.s($r('app.string.ui_file_type_label')),
          value: this.params.fileType.toUpperCase()
        })
        this.infoRow({
          theme: this.theme(), label: this.s($r('app.string.ui_file_size_label')), value: this.sizeText()
        })
        if (this.params.uploadTime !== undefined && this.params.uploadTime.length > 0) {
          this.infoRow({
            theme: this.theme(), label: this.s($r('app.string.ui_file_upload_time_label')),
            value: this.params.uploadTime
          })
        }
        this.infoRow({
          theme: this.theme(), label: this.s($r('app.string.loh_courses')), value: this.params.courseName
        })
        Text(this.infoText())
          .fontSize(this.theme().typography.bodyMedium.fontSize)
          .fontColor(this.theme().colors.onSurfaceVariant)
          .width('100%')
          .margin({ top: this.theme().sizes.space3 })
        if (this.localPath.length > 0) {
          Text(i18nService.t('ui_file_saved_at', this.localPath))
            .fontSize(this.theme().typography.labelSmall.fontSize)
            .fontColor(this.theme().colors.onSurfaceVariant)
            .width('100%')
            .margin({ top: this.theme().sizes.space3 })
        }
        if (!this.previewable() || this.previewUnsupported) {
          Text(this.s($r('app.string.ui_file_preview_unavailable')))
            .fontSize(this.theme().typography.bodySmall.fontSize)
            .fontColor(this.theme().colors.onSurfaceVariant)
            .width('100%')
            .margin({ top: this.theme().sizes.space3 })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
    }
    .layoutWeight(1)
    .width('100%')
    .padding(this.theme().sizes.contentPadding)
  }

  /** 渲染 PDF 的第 index 页（同步 API，页数多时只渲染当前页，内存有界）。 */
  private renderPdfPage(index: number): void {
    const document: pdfService.PdfDocument | null = this.pdfDocument;
    if (document === null) {
      return;
    }
    if (index < 0 || index >= this.pdfPageCount) {
      return;
    }
    try {
      const page: pdfService.PdfPage = document.getPage(index);
      this.pdfPage = page.getPagePixelMap();
      this.pdfPageIndex = index;
      logger.info('file detail pdf page rendered: index=' + index.toString()
        + ' of=' + this.pdfPageCount.toString());
    } catch (error) {
      this.previewError = (error as Error).message;
      logger.error('file detail pdf page render failed: ' + this.previewError);
    }
  }

  @Builder
  pdfPageBar() {
    Row() {
      Text(this.s($r('app.string.ui_file_prev_page')))
        .fontSize(this.theme().typography.labelLarge.fontSize)
        .fontColor(this.pdfPageIndex > 0 ? this.theme().colors.primary : this.theme().colors.outline)
        .onClick(() => {
          this.renderPdfPage(this.pdfPageIndex - 1);
        })
      Text(i18nService.t('ui_file_page_of', this.pdfPageIndex + 1, this.pdfPageCount))
        .fontSize(this.theme().typography.labelMedium.fontSize)
        .fontColor(this.theme().colors.onSurfaceVariant)
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
      Text(this.s($r('app.string.ui_file_next_page')))
        .fontSize(this.theme().typography.labelLarge.fontSize)
        .fontColor(this.pdfPageIndex + 1 < this.pdfPageCount
          ? this.theme().colors.primary : this.theme().colors.outline)
        .onClick(() => {
          this.renderPdfPage(this.pdfPageIndex + 1);
        })
    }
    .width('100%')
    .padding({
      left: this.theme().sizes.contentPadding,
      right: this.theme().sizes.contentPadding,
      top: this.theme().sizes.space2,
      bottom: this.theme().sizes.space2
    })
    .backgroundColor(this.theme().colors.surfaceVariant)
  }

  @Builder
  previewBody() {
    if (this.previewError.length > 0) {
      Column() {
        Text(i18nService.t('ui_file_preview_failed', this.previewError))
          .fontSize(this.theme().typography.bodyMedium.fontSize)
          .fontColor(this.theme().colors.error)
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .padding(this.theme().sizes.contentPadding)
    } else if (this.kind() === FileKind.PDF) {
      Column() {
        this.pdfPageBar()
        if (this.pdfPage !== undefined) {
          Scroll() {
            Image(this.pdfPage as image.PixelMap)
              .objectFit(ImageFit.Contain)
              .width('100%')
          }
          .layoutWeight(1)
          .width('100%')
        } else {
          Column() {
            LoadingProgress()
              .width(this.theme().sizes.iconLarge)
              .height(this.theme().sizes.iconLarge)
              .color(this.theme().colors.primary)
          }
          .layoutWeight(1)
          .width('100%')
          .justifyContent(FlexAlign.Center)
        }
      }
      .width('100%')
      .height('100%')
    } else if (this.pixelMap !== undefined) {
      Image(this.pixelMap as image.PixelMap)
        .objectFit(ImageFit.Contain)
        .width('100%')
        .height('100%')
    } else {
      Column() {
        LoadingProgress()
          .width(this.theme().sizes.iconLarge)
          .height(this.theme().sizes.iconLarge)
          .color(this.theme().colors.primary)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    }
  }

  build() {
    Column() {
      this.topBar()
      if (this.phase === FileDetailPhase.DOWNLOADING) {
        this.progressBar()
      }
      if (this.phase === FileDetailPhase.ERROR) {
        Column() {
          Text(this.errorText)
            .fontSize(this.theme().typography.bodyMedium.fontSize)
            .fontColor(this.theme().colors.error)
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .padding(this.theme().sizes.contentPadding)
      } else if (this.phase === FileDetailPhase.READY && this.previewable()
        && !this.showInfo && !this.previewUnsupported) {
        this.previewBody()
      } else if (this.phase === FileDetailPhase.READY) {
        this.infoPanel()
      } else if (this.phase === FileDetailPhase.IDLE) {
        Column() {
          LoadingProgress()
            .width(this.theme().sizes.iconLarge)
            .height(this.theme().sizes.iconLarge)
            .color(this.theme().colors.primary)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme().colors.background)
  }
}
