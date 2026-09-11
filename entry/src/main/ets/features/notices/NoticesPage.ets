/*
 * 公告（Notice）tab：Mock/真实数据源之上的列表页。
 *
 * 分工：
 *   - 数据与阶段在 NoticeListStore（@ObservedV2/@Trace），本组件只读；
 *   - 取色一律 resolveTheme()，文案一律走资源；
 *   - 时间用 core/i18n 的 formatRelativeTo（与参考实现 NoticeCard 的
 *     dayjs(publishTime).fromNow() 对齐），拿不到 ICU 措辞时退回绝对时间。
 *
 * 界面只依赖 NoticeRepository 接口（经 createNoticeRepository() 注入），
 * ticket 09 换真实数据源时这里不动。
 */
import { ConfigurationConstant } from '@kit.AbilityKit';
import { ThemeTokens, resolveTheme } from '../../ui/theme/Tokens';
import { i18nService } from '../../core/i18n/I18n';
import {
  DateTimeFormatOptions, PlatformDateTimeFormatter, formatDateTimeUsing, formatDateTimeShort, formatRelativeTo
} from '../../core/i18n/DateTimeUtil';
import { Logger } from '../../core/log/Logger';
import { COLOR_MODE_KEY, LOCALE_VERSION_KEY } from '../../entryability/EntryAbility';
import { EmptyState } from '../../ui/components/EmptyState';
import { isUnread } from './NoticeOrder';
import { NoticeListStore } from './NoticeListStore';
import { NoticeRecord } from './repository/NoticeRepository';
import { createNoticeRepository } from './repository/NoticeRepositoryProvider';

const logger: Logger = new Logger('features.notices');

/** 单行公告的渲染参数；@Builder 按引用传参（见 ticket 01 Comments 的教训）。 */
interface NoticeRowSpec {
  theme: ThemeTokens;
  notice: NoticeRecord;
  timeText: string;
  unreadLabel: string;
}

@Component
export struct NoticesPage {
  /** 系统配色，EntryAbility 写入；变化时本组件重建。 */
  @StorageProp(COLOR_MODE_KEY) colorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  /** 语言版本号；变化时本组件重建并重新取串。 */
  @StorageLink(LOCALE_VERSION_KEY) localeVersion: number = 0;
  /** Refresh 组件自身的两态绑定。 */
  @State refreshing: boolean = false;

  private store: NoticeListStore = new NoticeListStore(createNoticeRepository());
  private listScroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.store.loadOnce();
    logger.info('notices page appear: source=mock, phase=' + this.store.phase);
  }

  private theme(): ThemeTokens {
    return resolveTheme(this.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
  }

  private isDark(): boolean {
    return this.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  }

  /** UI 取串入口：与 $r 同一资源，但走逻辑层门面，便于语言变化后重取。 */
  private s(resource: Resource): string {
    return i18nService.tKey(resource);
  }

  /** 相对时间优先，措辞不可用时退回绝对时间。 */
  private timeTextOf(notice: NoticeRecord): string {
    const locale: string = i18nService.locale();
    const relative: string = formatRelativeTo(notice.publishTimeMillis, Date.now(), locale);
    if (relative.length > 0) {
      return relative;
    }
    return formatDateTimeShort(notice.publishTimeMillis, locale);
  }

  private updatedText(): string {
    if (this.store.fetchedAtMillis <= 0) {
      return '';
    }
    // 精确到秒：下拉刷新后这一行会变，是"刷新有可见反馈"的确定性证据。
    const options: DateTimeFormatOptions = {
      hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false
    };
    const stamp: string = formatDateTimeUsing(this.store.fetchedAtMillis,
      new PlatformDateTimeFormatter(i18nService.locale(), options));
    return i18nService.t('ui_refreshed_at', stamp);
  }

  private unreadText(): string {
    return i18nService.t('loh_unread') + ' ' + this.store.unreadCount().toString();
  }

  private async handlePullRefresh(): Promise<void> {
    this.refreshing = true;
    await this.store.refresh();
    this.refreshing = false;
  }

  @Builder
  header() {
    Column() {
      Text(this.s($r('app.string.ui_tab_notices')))
        .fontSize(this.theme().typography.headlineSmall.fontSize)
        .lineHeight(this.theme().typography.headlineSmall.lineHeight)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.theme().colors.onSurface)
      Row() {
        Text(this.updatedText())
          .fontSize(this.theme().typography.labelSmall.fontSize)
          .fontColor(this.theme().colors.onSurfaceVariant)
          .layoutWeight(1)
        Text(this.unreadText())
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

  @Builder
  noticeRow(spec: NoticeRowSpec) {
    Column() {
      Text(spec.notice.courseName)
        .fontSize(spec.theme.typography.labelMedium.fontSize)
        .lineHeight(spec.theme.typography.labelMedium.lineHeight)
        .fontColor(spec.theme.colors.onSurfaceVariant)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(spec.notice.title)
        .fontSize(spec.theme.typography.titleMedium.fontSize)
        .lineHeight(spec.theme.typography.titleMedium.lineHeight)
        .fontWeight(FontWeight.Medium)
        .fontColor(spec.theme.colors.onSurface)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: spec.theme.sizes.space1 })
      Row() {
        Text(spec.notice.publisher)
          .fontSize(spec.theme.typography.labelSmall.fontSize)
          .fontColor(spec.theme.colors.onSurfaceVariant)
        Text(spec.timeText)
          .fontSize(spec.theme.typography.labelSmall.fontSize)
          .fontColor(spec.theme.colors.onSurfaceVariant)
          .margin({ left: spec.theme.sizes.space2 })
        Blank()
        if (isUnread(spec.notice)) {
          Column()
            .width(spec.theme.sizes.space2)
            .height(spec.theme.sizes.space2)
            .borderRadius(spec.theme.sizes.space2 / 2)
            .backgroundColor(spec.theme.colors.primary)
          Text(spec.unreadLabel)
            .fontSize(spec.theme.typography.labelSmall.fontSize)
            .fontColor(spec.theme.colors.primary)
            .margin({ left: spec.theme.sizes.space1 })
        }
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
  }

  @Builder
  listBody() {
    Stack() {
      List({ space: 0, scroller: this.listScroller }) {
        ForEach(this.store.items, (item: NoticeRecord) => {
          ListItem() {
            this.noticeRow({
              theme: this.theme(),
              notice: item,
              timeText: this.timeTextOf(item),
              unreadLabel: this.s($r('app.string.loh_unread'))
            })
          }
        }, (item: NoticeRecord) => item.id + '|' + (item.hasRead ? 'read' : 'unread'))
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

      // 只有「首次加载且无数据」才盖居中指示器；下拉刷新只用 Refresh 自己的指示器（避免两个 spinner 同转）
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
      } else if (this.store.isEmpty()) {
        EmptyState({
          message: this.s($r('app.string.ui_empty_notices')),
          isDark: this.isDark()
        })
      }
    }
    .width('100%')
    .height('100%')
  }

  build() {
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
      // 把 Refresh 的状态机打进 hilog：Inactive/Drag/OverDrag/Refresh/Done。
      // 这是"下拉刷新确实被触发并进入刷新态"的确定性证据（截图只能尽力抓时机）。
      .onStateChange((state: RefreshStatus) => {
        logger.info('pull refresh state: ' + state.toString());
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme().colors.background)
  }
}
