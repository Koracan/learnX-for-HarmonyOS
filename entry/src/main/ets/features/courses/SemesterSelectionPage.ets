/*
 * 学期切换页 —— 对齐参考实现 `screens/SemesterSelection.tsx`：
 * 列出可选学期（最新在前），当前学期带**与参考实现同源的** check 图标，点一条即切换。
 *
 * 与参考实现的两处差异（都已写明）：
 *   1. **位置**：参考实现把它放在"设置"栈里（`SettingsStackParams.SemesterSelection`），
 *      本工程的交付物把它与课程放在一起（课程 tab 头部点学期名进入）。
 *      行为（列出 + 切换 + 列表随之更新）不变。
 *   2. **脚本入口**：参考实现只能靠界面点；本工程另有
 *      `aa start --ps lohSemester <id>` 与构建期常量（见 data/courses/SemesterOverride.ets），
 *      因为作业与提交需要在无界面交互的情况下切到 2025-2026 春季学期取真实作业。
 *
 * 学期集合接口不可用时（`semestersAvailable=false`）**不假装完整**：页面顶部显式说明，
 * 列表退化为"站点当前学期 + 实际生效学期"。
 */
import { ConfigurationConstant } from '@kit.AbilityKit';
import { ThemeTokens, resolveTheme } from '../../ui/theme/Tokens';
import { i18nService } from '../../core/i18n/I18n';
import { getSemesterTextFromId } from '../../core/i18n/DateTimeUtil';
import { COLOR_MODE_KEY, LOCALE_VERSION_KEY } from '../../entryability/EntryAbility';
import { Logger } from '../../core/log/Logger';
import { CourseListStore } from './CourseListStore';
import { AppIcon } from '../../ui/icons/IconCatalog';
import { IconGlyph } from '../../ui/icons/IconGlyph';

const logger: Logger = new Logger('features.courses.semesters');

@Component
export struct SemesterSelectionPage {
  @StorageProp(COLOR_MODE_KEY) colorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageLink(LOCALE_VERSION_KEY) localeVersion: number = 0;
  @State refreshing: boolean = false;

  store: CourseListStore | null = null;
  stack: NavPathStack | null = null;

  private theme(): ThemeTokens {
    return resolveTheme(this.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
  }

  private isDark(): boolean {
    return this.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  }

  private s(resource: Resource): string {
    return i18nService.tKey(resource);
  }

  private semesterIds(): string[] {
    return this.store === null ? [] : this.store.semesters;
  }

  /**
   * 哪一行打勾：切换在途时以**正在应用的选择**为准，否则用快照里的实际生效值。
   * 直接读两个 @Trace 字段（不绕包装函数），保证勾选标记随选择同步移动，
   * 而不是等整轮取数跑完才动。
   */
  private activeSemesterId(): string {
    const store: CourseListStore | null = this.store;
    if (store === null) {
      return '';
    }
    return store.pendingSemesterId.length > 0 ? store.pendingSemesterId : store.semesterId;
  }

  private listAvailable(): boolean {
    return this.store === null ? false : this.store.semestersAvailable;
  }

  private semesterText(semesterId: string): string {
    return getSemesterTextFromId(semesterId, i18nService.locale(), i18nService);
  }

  /**
   * 点一行 = 纯状态写入 + 立即返回。
   *
   * 这里**不 await 取数**：一轮 refresh 要串行取"学期集合 + 课程列表 + 三域内容"，
   * 以秒计；等它跑完再更新勾选、再 pop，用户看到的就是"点一下卡住"。选择记下后
   * 由共享 store 的 @Trace 推给所有读它的页面（课程 tab 的列表会在后台刷新时更新）。
   */
  private select(semesterId: string): void {
    const store: CourseListStore | null = this.store;
    logger.info('semester row tapped: ' + semesterId);
    if (store === null) {
      logger.error('semester row tapped but the store is missing');
      return;
    }
    store.selectSemester(semesterId);
    logger.info('semester selection dismissed: ' + semesterId);
    if (this.stack !== null) {
      this.stack.pop();
    }
  }

  private async handlePullRefresh(): Promise<void> {
    const store: CourseListStore | null = this.store;
    if (store === null) {
      return;
    }
    this.refreshing = true;
    await store.refresh();
    this.refreshing = false;
  }

  @Builder
  header() {
    Column() {
      Row() {
        Text(this.s($r('app.string.loh_back')))
          .fontSize(this.theme().typography.labelLarge.fontSize)
          .fontColor(this.theme().colors.primary)
          .onClick(() => {
            if (this.stack !== null) {
              this.stack.pop();
            }
          })
      }
      .width('100%')
      .margin({ bottom: this.theme().sizes.space2 })

      Text(this.s($r('app.string.loh_semester_selection')))
        .fontSize(this.theme().typography.headlineSmall.fontSize)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.theme().colors.onSurface)
        .width('100%')

      if (!this.listAvailable()) {
        Text(this.s($r('app.string.ui_course_semester_list_unavailable')))
          .fontSize(this.theme().typography.labelSmall.fontSize)
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
      top: this.theme().sizes.space4,
      bottom: this.theme().sizes.space3
    })
  }

  @Builder
  semesterRow(semesterId: string) {
    Row() {
      Text(this.semesterText(semesterId))
        .fontSize(this.theme().typography.bodyLarge.fontSize)
        .fontColor(this.theme().colors.onSurface)
        .layoutWeight(1)
      if (semesterId === this.activeSemesterId()) {
        // 参考实现 SemesterSelection.tsx:60,69：选中项 `iconName='check'`（MCI `check`）。
        // 语义挪进图标的 accessibilityText，行本身的无障碍文本不再拼 U+2713 字符。
        IconGlyph({
          icon: AppIcon.CHECK, glyphSize: this.theme().sizes.iconSmall,
          color: this.theme().colors.primary,
          label: this.s($r('app.string.ui_courses_semester_label'))
        })
      }
    }
    .width('100%')
    .height(this.theme().sizes.listItemMinHeight)
    .padding({ left: this.theme().sizes.contentPadding, right: this.theme().sizes.contentPadding })
    .backgroundColor(this.theme().colors.surface)
    .accessibilityText(this.semesterText(semesterId))
    .onClick(() => {
      this.select(semesterId);
    })
  }

  build() {
    Column() {
      this.header()
      Refresh({ refreshing: $$this.refreshing, promptText: this.s($r('app.string.loh_refresh')) }) {
        List({ space: 0 }) {
          ForEach(this.semesterIds(), (semesterId: string) => {
            ListItem() {
              this.semesterRow(semesterId)
            }
          }, (semesterId: string) => semesterId + '|' + this.activeSemesterId())
        }
        .width('100%')
        .height('100%')
        .divider({
          strokeWidth: this.theme().sizes.borderWidth,
          color: this.theme().colors.outlineVariant,
          startMargin: this.theme().sizes.contentPadding,
          endMargin: this.theme().sizes.contentPadding
        })
      }
      .layoutWeight(1)
      .width('100%')
      .onRefreshing(() => {
        this.handlePullRefresh();
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme().colors.background)
  }
}
