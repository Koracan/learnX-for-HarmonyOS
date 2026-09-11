/*
 * learnOH 首屏（foundation/01 + foundation/02）。
 *
 * 这张页面是分层、主题令牌与 i18n 资源化的最小验证载体：
 *   - 颜色 / 排版 / 尺寸一律取 `resolveTheme()` 的令牌，页面内无硬编码色值；
 *   - 主题随系统深浅色实时切换（EntryAbility 把系统 colorMode 写入 AppStorage）；
 *   - **界面文案零硬编码**：全部走资源（UI 层 `$r('app.string.*')`，逻辑层 `core/i18n` 的 `t()`）；
 *   - 语言随系统切换，无需重启：EntryAbility 在 onConfigurationUpdate 里写 AppStorage 的
 *     `learnOHLocaleVersion`，本页 `@StorageLink` 订阅后立即重建并重新取串；
 *   - 启动打一条 info 日志（带 `ui.index` 标签），并可把内存日志导出为文本文件；
 *   - 展示一条来自 domain 的纯逻辑结果，证明 ui → domain 的分层已通。
 *
 * 后续 shell ticket 会用真正的导航壳替换本页面。
 */

import { ConfigurationConstant, common } from '@kit.AbilityKit';
import { Logger } from '../core/log/Logger';
import { logBuffer, exportLogs, LogExportResult } from '../core/log/LogBuffer';
import { ThemeTokens, resolveTheme, PLAIN_PALETTE, PlainPalette } from '../ui/theme/Tokens';
import { Semester } from '../domain/model/Semester';
import { i18nService } from '../core/i18n/I18n';
import { formatDateTimeShort, formatRelativeTo, getSemesterTextFromId } from '../core/i18n/DateTimeUtil';
import { LOCALE_VERSION_KEY } from '../entryability/EntryAbility';

const logger: Logger = new Logger('ui.index');

/** 一个色块样本。 */
interface Swatch {
  name: string;
  color: string;
}

/** 一行「标签 — 值」；label/value 都已是解析好的本地化字符串。 */
interface InfoRow {
  label: string;
  value: string;
}

/** \`infoCard\` 的参数：单对象以便按引用传递（见 \`infoCard\` 注释）。 */
interface CardSpec {
  theme: ThemeTokens;
  title: string;
  rows: InfoRow[];
}

@Entry
@Component
struct Index {
  /** 系统配色，由 EntryAbility 写入；变化时本页自动重建。 */
  @StorageProp('learnOHColorMode') colorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  /** 语言版本号，由 EntryAbility 在语言变化时写入；变化时本页自动重建并重新取资源。 */
  @StorageLink(LOCALE_VERSION_KEY) localeVersion: number = 0;
  @State private exportPath: string = '';
  @State private exportNote: string = '';

  /** 唯一的取色入口。 */
  private theme(): ThemeTokens {
    return resolveTheme(this.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
  }

  private weightOf(weight: number): FontWeight {
    if (weight >= 700) {
      return FontWeight.Bold;
    }
    if (weight >= 500) {
      return FontWeight.Medium;
    }
    return FontWeight.Regular;
  }

  /**
   * 逻辑层取串的等价入口：`$r` 只能在 UI 上下文里用，这里把 Resource 交给
   * `i18nService.tKey()`，走 `ResourceManager.getStringByNameSync` 取同一资源，
   * 于是 build() 里对 LocaleVersion 的订阅能真正驱动重取串。
   */
  private s(resource: Resource): string {
    return i18nService.tKey(resource);
  }

  private swatches(): Swatch[] {
    const palette: PlainPalette = PLAIN_PALETTE;
    return [
      { name: 'plainTheme', color: palette.plainTheme },
      { name: 'red500', color: palette.red500 },
      { name: 'blue500', color: palette.blue500 },
      { name: 'green500', color: palette.green500 },
      { name: 'orange500', color: palette.orange500 },
      { name: 'yellow500', color: palette.yellow500 },
      { name: 'grey500', color: palette.grey500 }
    ];
  }

  /** 领域纯逻辑的现场调用：解析与比较学期标识。 */
  private semesterRows(): InfoRow[] {
    const first: Semester | null = Semester.tryParse('2025-2026-1');
    const second: Semester | null = Semester.tryParse('2025-2026-2');
    const failed: string = this.s($r('app.string.ui_semester_parse_failed'));
    let parseValue: string = failed;
    if (first !== null) {
      parseValue = first.academicYear + ' / ' + first.season;
    }
    let compareValue: string = failed;
    if (first !== null && second !== null) {
      const later: string = first.isBefore(second) ? second.id : first.id;
      compareValue = i18nService.t('ui_semester_later', later);
    }
    return [
      { label: this.s($r('app.string.ui_semester_parse')), value: parseValue },
      { label: this.s($r('app.string.ui_semester_compare')), value: compareValue }
    ];
  }

  private infoRows(): InfoRow[] {
    const dark: boolean = this.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    const rows: InfoRow[] = [
      {
        label: this.s($r('app.string.ui_system_color_mode')),
        value: this.s(dark ? $r('app.string.ui_dark') : $r('app.string.ui_light'))
      },
      {
        label: this.s($r('app.string.ui_color_tokens')),
        value: dark ? 'DARK_COLORS' : 'LIGHT_COLORS'
      },
      {
        label: this.s($r('app.string.ui_recent_log_count')),
        value: logBuffer.size().toString() + ' / ' + logBuffer.getCapacity().toString()
      }
    ];
    const semesters: InfoRow[] = this.semesterRows();
    for (let i = 0; i < semesters.length; i++) {
      rows.push(semesters[i]);
    }
    return rows;
  }

  aboutToAppear(): void {
    const theme: ThemeTokens = this.theme();
    // 日志文案刻意不走 i18n：诊断输出必须与设备语言无关、可稳定 grep。
    logger.info('first-screen: theme=' + (theme.dark ? 'dark' : 'light')
      + ' primary=' + theme.colors.primary
      + ' locale=' + i18nService.locale()
      + ' tokenSource=reference-md3');
  }

  private onExport(): void {
    try {
      const context = this.getUIContext().getHostContext() as common.Context;
      const result: LogExportResult = exportLogs(context);
      this.exportPath = result.path;
      this.exportNote = i18nService.t('ui_exported', result.recordCount, result.byteLength);
      logger.info('log exported: ' + result.path);
    } catch (error) {
      const message: string = (error as Error).message;
      this.exportNote = i18nService.t('ui_export_failed', message);
      this.exportPath = '';
      logger.error('log export failed: ' + message);
    }
  }

  /**
   * 语言切换（无需重启）：`ApplicationContext.setLanguage()` 更新应用语言配置，
   * 随即重新绑定资源管理器并刷新，界面在同一进程内重取资源。
   */
  private switchLanguage(language: string): void {
    const context = this.getUIContext().getHostContext() as common.Context;
    try {
      context.getApplicationContext().setLanguage(language);
    } catch (error) {
      logger.error('set language failed: ' + (error as Error).message);
    }
    i18nService.bindResourceManager(context.resourceManager, language);
    i18nService.refresh();
    this.localeVersion = Date.now();
    logger.info('language switched: requested=' + language + ' effective=' + i18nService.locale());
  }

  private localeSampleRows(): InfoRow[] {
    const locale: string = i18nService.locale();
    const now: number = Date.now();
    return [
      { label: this.s($r('app.string.ui_current_locale')), value: locale },
      {
        label: this.s($r('app.string.ui_relative_time_sample')),
        value: formatRelativeTo(now - 3 * 24 * 3600 * 1000, now, locale)
      },
      {
        label: this.s($r('app.string.ui_date_time_sample')),
        value: formatDateTimeShort(now, locale)
      },
      {
        label: this.s($r('app.string.ui_semester_sample')),
        value: getSemesterTextFromId('2025-2026-1', locale, i18nService)
      }
    ];
  }

  /**
   * 卡片。
   *
   * 注意参数形态：@Builder 只有**按引用**传递（调用点传对象字面量、方法只收一个对象参数）时，
   * 参数变化才会驱动 builder 内的 UI 刷新。早先写成 `infoCard(theme, title, rows)` 三个按值参数，
   * 结果切换系统深浅色时卡片整块保持旧主题（2026-09-12 真机截图发现），故改成单对象参数。
   */
  @Builder
  infoCard(spec: CardSpec) {
    Column() {
      Text(spec.title)
        .fontSize(spec.theme.typography.titleMedium.fontSize)
        .lineHeight(spec.theme.typography.titleMedium.lineHeight)
        .fontWeight(this.weightOf(spec.theme.typography.titleMedium.fontWeight))
        .fontColor(spec.theme.colors.onSurface)
      ForEach(spec.rows, (row: InfoRow) => {
        Row() {
          Text(row.label)
            .fontSize(spec.theme.typography.bodyMedium.fontSize)
            .lineHeight(spec.theme.typography.bodyMedium.lineHeight)
            .fontColor(spec.theme.colors.onSurfaceVariant)
            .layoutWeight(1)
          Text(row.value)
            .fontSize(spec.theme.typography.bodyMedium.fontSize)
            .lineHeight(spec.theme.typography.bodyMedium.lineHeight)
            .fontColor(spec.theme.colors.onSurface)
            .textAlign(TextAlign.End)
            .layoutWeight(1)
        }
        .width('100%')
        .margin({ top: spec.theme.sizes.space2 })
      }, (row: InfoRow) => row.label)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(spec.theme.sizes.contentPadding)
    .backgroundColor(spec.theme.colors.surfaceVariant)
    .borderRadius(spec.theme.sizes.radiusMedium)
  }

  build() {
    Column() {
      Scroll() {
        Column() {
          Text(this.s($r('app.string.ui_app_name')))
            .fontSize(this.theme().typography.headlineMedium.fontSize)
            .lineHeight(this.theme().typography.headlineMedium.lineHeight)
            .fontWeight(this.weightOf(this.theme().typography.headlineMedium.fontWeight))
            .fontColor(PLAIN_PALETTE.plainTheme)
          Text(this.s($r('app.string.ui_app_tagline')))
            .fontSize(this.theme().typography.bodyMedium.fontSize)
            .fontColor(this.theme().colors.onSurfaceVariant)
            .margin({ top: this.theme().sizes.space1 })

          Column() {
            this.infoCard({ theme: this.theme(), title: this.s($r('app.string.ui_self_check_card_title')), rows: this.infoRows() });
          }
          .margin({ top: this.theme().sizes.space4 })
          Column() {
            this.infoCard({ theme: this.theme(), title: this.s($r('app.string.ui_language')), rows: this.localeSampleRows() });
          }
          .margin({ top: this.theme().sizes.space4 })

          Text(this.s($r('app.string.ui_locale_live_demo')))
            .fontSize(this.theme().typography.titleMedium.fontSize)
            .fontWeight(this.weightOf(this.theme().typography.titleMedium.fontWeight))
            .fontColor(this.theme().colors.onSurface)
            .margin({ top: this.theme().sizes.space5 })

          Row() {
            Button(this.s($r('app.string.ui_switch_chinese')))
              .layoutWeight(1)
              .height(this.theme().sizes.controlHeight)
              .backgroundColor(this.theme().colors.primary)
              .fontColor(this.theme().colors.onPrimary)
              .onClick(() => this.switchLanguage('zh-Hans'))
            Button(this.s($r('app.string.ui_switch_english')))
              .layoutWeight(1)
              .height(this.theme().sizes.controlHeight)
              .backgroundColor(this.theme().colors.secondaryContainer)
              .fontColor(this.theme().colors.onSecondaryContainer)
              .margin({ left: this.theme().sizes.space2 })
              .onClick(() => this.switchLanguage('en-Latn-US'))
          }
          .width('100%')
          .margin({ top: this.theme().sizes.space2 })

          Text(this.s($r('app.string.ui_reference_palette')))
            .fontSize(this.theme().typography.titleMedium.fontSize)
            .fontWeight(this.weightOf(this.theme().typography.titleMedium.fontWeight))
            .fontColor(this.theme().colors.onSurface)
            .margin({ top: this.theme().sizes.space5 })

          Row() {
            ForEach(this.swatches(), (item: Swatch) => {
              Column() {
                Column()
                  .width(this.theme().sizes.iconLarge)
                  .height(this.theme().sizes.iconLarge)
                  .backgroundColor(item.color)
                  .borderRadius(this.theme().sizes.radiusSmall)
                  .border({ width: this.theme().sizes.borderWidth, color: this.theme().colors.outlineVariant })
                Text(item.name)
                  .fontSize(this.theme().typography.labelSmall.fontSize)
                  .fontColor(this.theme().colors.onSurfaceVariant)
                  .margin({ top: this.theme().sizes.space1 })
              }
              .layoutWeight(1)
            }, (item: Swatch) => item.name)
          }
          .width('100%')
          .margin({ top: this.theme().sizes.space2 })

          Button(this.s($r('app.string.ui_export_logs')))
            .width('100%')
            .height(this.theme().sizes.controlHeight)
            .backgroundColor(this.theme().colors.primary)
            .fontColor(this.theme().colors.onPrimary)
            .margin({ top: this.theme().sizes.space5 })
            .onClick(() => this.onExport())

          if (this.exportPath.length > 0) {
            Text(this.exportNote + '\n' + this.exportPath)
              .fontSize(this.theme().typography.bodySmall.fontSize)
              .fontColor(this.theme().colors.onSurfaceVariant)
              .margin({ top: this.theme().sizes.space2 })
              .width('100%')
          }
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding(this.theme().sizes.contentPadding)
      }
      .layoutWeight(1)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme().colors.background)
  }
}
