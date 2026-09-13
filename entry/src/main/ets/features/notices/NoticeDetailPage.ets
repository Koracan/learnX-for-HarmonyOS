/*
 * 公告详情页（ticket 04）—— 逐项对齐参考实现
 * `reference/learnOH-old/src/screens/NoticeDetail.tsx`。
 *
 * ## 页面结构（对应参考实现行号）
 *
 * | 元素 | 参考实现 | 这里 |
 * | --- | --- | --- |
 * | 标题 = `removeTags(title)` | NoticeDetail.tsx:81 | `removeTags(this.notice.title)`（ticket 09 补齐） |
 * | 副标题 = 发布者 + **绝对时间** | :84-92 | 同（模式走 i18n 资源，见 domain/render/NoticeDateText） |
 * | 正文上方独立一行的附件 | :95-109 `List.Item` | 同（下方 attachmentRow） |
 * | 空正文兜底 `content \|\| "<p>" + t('noNoticeContent') + "</p>"` | :54 | HtmlWebView 内做（传 emptyText） |
 * | Web 容器渲染正文 | :111 `AutoHeightWebView` | ui/components/HtmlWebView |
 * | 重型组件延迟（InteractionManager） | :26-32,110-116 | **不移植**，见下 |
 *
 * ## 三处必须说明的判断
 *
 * 1. **不显示课程名**：ticket 04 的验收第 1 条写的是"课程名 + 发布者"，但参考实现
 *    详情页**只显示发布者与时间**；`courseName` 只作为附件跳转 FileDetail 的参数（:65）。
 *    按本仓规则（移植完成定义 = 与参考实现行为一致），这里**不显示课程名**，
 *    并在 ticket Comments 里请统筹决定是否作为增强单独登记。
 *
 * 2. **不移植 InteractionManager 延迟**：参考实现先显示 `ActivityIndicator`、
 *    等导航动画结束后才挂 WebView（:26-32）。ArkUI 的 Navigation 转场由框架负责，
 *    没有等价的 interaction 队列；而公告详情是"点进去立刻要看正文"的页面，
 *    这里直接渲染（RenderService 已把 Web 引擎初始化提前到 aboutToAppear）。
 *    这条写进 ticket Comments 的有意差异。
 *
 * 3. **正文不做实体解码**：正文是 HTML，
 *    交给 Web 容器渲染即可；参考实现的 `removeTags`（去标签 + he.decode 全实体集）
 *    只用在**标题**上。ticket 09 已把 `removeTags` 等价物实现在
 *    `domain/render/WebViewTemplate.ets`（标题用它，卡片正文预览也用它）。
 */
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { PLAIN_PALETTE, ThemeTokens, resolveTheme } from '../../ui/theme/Tokens';
import { i18nService } from '../../core/i18n/I18n';
import { COLOR_MODE_KEY } from '../../entryability/EntryAbility';
import { Logger } from '../../core/log/Logger';
import { buildNoticeContent, removeTags } from '../../domain/render/WebViewTemplate';
import { formatNoticeDate, NoticeDateText } from '../../domain/render/NoticeDateText';
import { getExtension, stripExtension } from '../../domain/render/FileNames';
import { Attachment } from '../../domain/model/ContentItem';
import { HtmlWebView } from '../../ui/components/HtmlWebView';
import { AppIcon } from '../../ui/icons/IconCatalog';
import { IconGlyph } from '../../ui/icons/IconGlyph';
import { SessionHeaderProvider } from '../../core/web/SessionHeaderProvider';
import { FileDetailRouteParams, ROUTE_FILE_DETAIL } from './NoticeRoutes';
import { NoticeRecord } from '../../data/notices/NoticeRepository';
import {
  EVIDENCE_DARK_TOGGLE, evidenceContentOr, logEvidenceContentState
} from './NoticeDetailEvidence';

const logger: Logger = new Logger('features.notices.detail');

@Component
export struct NoticeDetailPage {
  @StorageProp(COLOR_MODE_KEY) colorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  /** 进入详情时的公告（NavPathStack 的参数，就是列表项本身）。 */
  notice: NoticeRecord = {
    id: '', title: '', content: '', publisher: '', courseId: '', courseName: '',
    courseTeacherName: '', publishTimeMillis: 0, hasRead: true, markedImportant: false, url: ''
  };
  /** 公告 tab 自己的导航栈（由 NoticesPage 注入）。 */
  stack: NavPathStack | null = null;
  /** 会话注入端口（Mock 阶段为空实现）。 */
  session: SessionHeaderProvider | null = null;
  aboutToAppear(): void {
    logEvidenceContentState();
    logger.info('detail evidence dark toggle: enabled=' + EVIDENCE_DARK_TOGGLE.toString()
      + ' effectiveDark=' + this.isDark().toString());
    logger.info('notice detail appear: id=' + this.notice.id
      + ' attachment=' + (this.notice.attachment === undefined ? 'none' : 'yes')
      + ' contentChars=' + this.notice.content.length.toString()
      + ' dark=' + (this.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK).toString());
  }

  private theme(): ThemeTokens {
    return resolveTheme(this.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
  }

  private isDark(): boolean {
    return this.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  }

  /** UI 取串入口（与 $r 同一资源，走逻辑层门面）。 */
  private s(resource: Resource): string {
    return i18nService.tKey(resource);
  }

  /** 详情页时间文案：模式与词表全部来自 i18n 资源（见 domain/render/NoticeDateText）。 */
  private timeText(): string {
    const text: NoticeDateText = {
      pattern: this.s($r('app.string.ui_notice_publish_time')),
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
      // 参考实现两种语言都用 24 小时制（HH:mm），模式里没有 A 记号；
      // 参考字典里也没有 am/pm 键，故留空（domain/render/NoticeDateText 允许空词表）。
      am: '',
      pm: ''
    };
    return formatNoticeDate(this.notice.publishTimeMillis, text);
  }

  /**
   * 交给 Web 容器的正文：**空正文兜底后**的 HTML（参考实现 NoticeDetail.tsx:54）。
   * 取证开关开启时整段换成夹具正文（见 NoticeDetailEvidence.ets，提交态关闭）。
   */
  private preparedContent(): string {
    const real: string = evidenceContentOr(this.notice.content);
    return buildNoticeContent(real, this.s($r('app.string.loh_no_notice_content')));
  }

  /**
   * 附件跳转参数，逐项对齐参考实现 NoticeDetail.tsx:63-71：
   * `title: stripExtension(name)`、`fileType: getExtension(name) ?? ''`，
   * 另带 `id` / `courseName` / `courseTeacherName` / `downloadUrl`。
   */
  private fileParams(attachment: Attachment): FileDetailRouteParams {
    const extension: string | undefined = getExtension(attachment.name);
    return {
      noticeId: this.notice.id,
      courseName: this.notice.courseName,
      courseTeacherName: this.notice.courseTeacherName,
      title: stripExtension(attachment.name),
      attachmentName: attachment.name,
      downloadUrl: attachment.downloadUrl,
      fileType: extension === undefined ? '' : extension
    };
  }

  private openAttachment(attachment: Attachment): void {
    const params: FileDetailRouteParams = this.fileParams(attachment);
    logger.info('attachment tapped: name=' + params.attachmentName
      + ' title=' + params.title + ' fileType=' + params.fileType);
    if (this.stack === null) {
      logger.error('attachment tapped but no NavPathStack');
      return;
    }
    // 参考实现是 navigation.push（把 FileDetail 压在同一栈上）。
    this.stack.pushPath({ name: ROUTE_FILE_DETAIL, param: params });
  }

  /**
   * 取证态才渲染的控制条（提交态 `EVIDENCE_DARK_TOGGLE=false`，整段是死分支）。
   *
   * 它**不翻转本地标志**，而是调用应用级 `setColorMode`（与 ticket 03 同一办法，只作用于
   * 本应用、不动设备全局设置）—— 于是这条控制条走的是**生产同一条链路**：
   * `setColorMode` → `onConfigurationUpdate` → `COLOR_MODE_KEY` → 本组件的 `@StorageProp`
   * → `isDark()` → `@Prop isDark` → HtmlWebView 的 `@Watch` → 重送模板。
   *
   * 为什么不在组件里自己翻一个 `@State`：早先就是这么做的，结果只翻了 WebView 的 dark 标志、
   * 没翻 surface 色，DarkReader 拿到浅色底 → 深色文字配浅色底不可读；而且控制条显示的
   * `dark=` 是那个本地标志、不是真实生效值，直接造成了"截图说 dark=true、画面却是浅色"的
   * 证据错位。现在 `dark=` 读的就是 `isDark()` 本身。
   */
  /** 取证实录：切换**应用级**深浅色（不改设备全局设置），走生产同一条链路。 */
  private toggleAppColorMode(): void {
    const next: number = this.isDark()
      ? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
      : ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    try {
      const context: common.UIAbilityContext = getContext() as common.UIAbilityContext;
      context.getApplicationContext().setColorMode(next);
      logger.info('evidence colorMode -> ' + (next === ConfigurationConstant.ColorMode.COLOR_MODE_DARK
        ? 'DARK' : 'LIGHT'));
    } catch (error) {
      logger.error('evidence setColorMode failed: ' + (error as Error).message);
    }
  }

  @Builder
  evidenceControls() {
    Row() {
      Text('dark=' + this.isDark().toString())
        .fontSize(this.theme().typography.labelSmall.fontSize)
        .fontColor(this.theme().colors.onSurfaceVariant)
      Button('toggle')
        .fontSize(this.theme().typography.labelSmall.fontSize)
        .height(this.theme().sizes.controlHeight)
        .backgroundColor(this.theme().colors.primaryContainer)
        .fontColor(this.theme().colors.onPrimaryContainer)
        .margin({ left: this.theme().sizes.space2 })
        .onClick(() => {
          this.toggleAppColorMode();
        })
    }
    .width('100%')
    .padding({ left: this.theme().sizes.contentPadding, right: this.theme().sizes.contentPadding })
  }

  @Builder
  headerRow() {
    Row() {
      // 返回：参考实现的详情页是导航栈默认的 MaterialIcons `arrow-back`（ticket 11.5 前这里是
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
      Text(this.s($r('app.string.ui_tab_notices')))
        .fontSize(this.theme().typography.titleMedium.fontSize)
        .fontColor(this.theme().colors.onSurfaceVariant)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  titleSection() {
    Column() {
      // 标题过 removeTags（参考实现 NoticeDetail.tsx:81 就是 removeTags(title)）：
      // 解析层刻意不解码实体，解码在渲染层。
      Text(removeTags(this.notice.title))
        .fontSize(this.theme().typography.headlineSmall.fontSize)
        .lineHeight(this.theme().typography.headlineSmall.lineHeight)
        .fontColor(this.theme().colors.onSurface)
        .width('100%')
        .margin({ bottom: this.theme().sizes.space2 })
      Row() {
        Text(this.notice.publisher)
          .fontSize(this.theme().typography.labelSmall.fontSize)
          .fontColor(this.theme().colors.onSurfaceVariant)
        Text(this.timeText())
          .fontSize(this.theme().typography.labelSmall.fontSize)
          .fontColor(this.theme().colors.onSurfaceVariant)
          .margin({ left: this.theme().sizes.space2 })
      }
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(this.theme().sizes.contentPadding)
  }

  /** 正文**上方**的独立一行附件（参考实现 NoticeDetail.tsx:95-109）。 */
  @Builder
  attachmentRow(attachment: Attachment) {
    Row() {
      // 参考实现 NoticeDetail.tsx:100-107：MaterialIcons `insert-drive-file`（橙色）。
      IconGlyph({
        icon: AppIcon.INSERT_DRIVE_FILE, glyphSize: this.theme().sizes.iconMedium,
        color: PLAIN_PALETTE.orange500, label: this.s($r('app.string.ui_attachment_label'))
      })
      Text(attachment.name)
        .fontSize(this.theme().typography.bodyLarge.fontSize)
        .fontColor(this.theme().colors.onSurface)
        .layoutWeight(1)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ left: this.theme().sizes.space4 })
    }
    .width('100%')
    .constraintSize({ minHeight: this.theme().sizes.listItemMinHeight })
    .alignItems(VerticalAlign.Center)
    .padding({
      left: this.theme().sizes.contentPadding,
      right: this.theme().sizes.contentPadding
    })
    .onClick(() => {
      this.openAttachment(attachment);
    })
  }

  build() {
    Column() {
      this.headerRow()
      if (EVIDENCE_DARK_TOGGLE) {
        this.evidenceControls()
      }
      Scroll() {
        Column() {
          this.titleSection()
          Divider()
            .strokeWidth(this.theme().sizes.borderWidth)
            .color(this.theme().colors.outlineVariant)
          if (this.notice.attachment !== undefined) {
            this.attachmentRow(this.notice.attachment)
            Divider()
              .strokeWidth(this.theme().sizes.borderWidth)
              .color(this.theme().colors.outlineVariant)
          }
          HtmlWebView({
            content: this.preparedContent(),
            emptyText: this.s($r('app.string.loh_no_notice_content')),
            // 唯一来源就是 isDark()（= 应用 colorMode）；取证控制条改的也是它，
            // 所以不存在"界面显示的标志"与"模板实际用的标志"不一致的余地。
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
      // 外层是唯一滚动容器，且没有内部滚动条（验收第 2 条）。
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme().colors.background)
  }
}
