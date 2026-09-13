/*
 * 学期切换页（ticket 12）—— 对齐参考实现 `screens/SemesterSelection.tsx`：
 * 列出可选学期（最新在前），当前学期带**与参考实现同源的** check 图标，点一条即切换。
 *
 * 与参考实现的两处差异（都在 ticket Comments 里写明）：
 *   1. **位置**：参考实现把它放在"设置"栈里（`SettingsStackParams.SemesterSelection`），
 *      ticket 12 的交付物把它与课程放在一起（课程 tab 头部点学期名进入）。
 *      行为（列出 + 切换 + 列表随之更新）不变。
 *   2. **脚本入口**：参考实现只能靠界面点；本 ticket 另有
 *      `aa start --ps lohSemester <id>` 与构建期常量（见 data/courses/SemesterOverride.ets），
 *      因为 ticket 10/13 需要在无界面交互的情况下切到 2025-2026 春季学期取真实作业。
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

  private activeSemesterId(): string {
    return this.store === null ? '' : this.store.semesterId;
  }

  private listAvailable(): boolean {
    return this.store === null ? false : this.store.semestersAvailable;
  }

  private semesterText(semesterId: string): string {
    return getSemesterTextFromId(semesterId, i18nService.locale(), i18nService);
  }

  private async select(semesterId: string): Promise<void> {
    const store: CourseListStore | null = this.store;
    logger.info('semester row tapped: ' + semesterId);
    if (store === null) {
      logger.error('semester row tapped but the store is missing');
      return;
    }
    await store.selectSemester(semesterId);
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
