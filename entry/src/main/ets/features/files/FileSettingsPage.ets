/*
 * 文件设置页：两个开关 + 清理缓存。
 *
 * 参考实现是 `screens/FileSettings.tsx`（挂在**设置栈**里）：
 *   - `FileSettings.tsx:57-84` 两个 `TableCell type="switch"`，
 *     文案分别是 `fileUseDocumentDir` / `fileOmitCourseName`，各带一段 caption；
 *   - `FileSettings.tsx:94-100` "清空文件缓存" → `removeFileDir()`（带确认对话框）。
 *
 * ## 归属
 *
 * **值/语义/生效逻辑在本文件**（`data/settings/FileSettings` + `FileDownloader`），
 * 本页是**文件 tab 自己的入口**；**全局设置页的入口与外观归全局设置**。
 * 两边读的是**同一个** `FileSettingsStore` 单例（`fileSettingsStore()`），不各造一套存储。
 *
 * ## 界面上的两行自证
 *
 *   - "当前保存位置" = 实际生效的根目录（`fileRepository().cacheRoot()`）；
 *   - 下面那行是 `describeFileSettings`：**实际生效值 + 覆盖来源**
 *     （脚本覆盖 `--ps lohFileUseDocumentDir` 生效时这里会显出来，
 *     于是"设置没生效"与"没读到设置"能区分）。
 */

import { ConfigurationConstant } from '@kit.AbilityKit';
import { ThemeTokens, resolveTheme } from '../../ui/theme/Tokens';
import { i18nService } from '../../core/i18n/I18n';
import { COLOR_MODE_KEY, LOCALE_VERSION_KEY } from '../../entryability/EntryAbility';
import { Logger } from '../../core/log/Logger';
import { ClearCacheResult } from '../../data/files/FileDownloader';
import {
  FileSettings, FileSettingsKey, describeFileSettings
} from '../../data/settings/FileSettings';
import { fileRepository, fileSettingsStore } from './repository/FileRepositoryProvider';
import { FileSettingsRouteParams } from './FileRoutes';
import { AppIcon } from '../../ui/icons/IconCatalog';
import { IconGlyph } from '../../ui/icons/IconGlyph';

const logger: Logger = new Logger('features.files.settings');

@Component
export struct FileSettingsPage {
  @StorageProp(COLOR_MODE_KEY) colorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageLink(LOCALE_VERSION_KEY) localeVersion: number = 0;

  params: FileSettingsRouteParams = { activeRoot: '' };
  stack: NavPathStack | null = null;

  /** 持久化值（开关显示的就是它；覆盖单独显示在下面一行）。 */
  @State useDocumentDir: boolean = false;
  @State omitCourseName: boolean = false;
  /** 实际生效的根目录。 */
  @State root: string = '';
  /** 实际生效值 + 覆盖来源（自证行）。 */
  @State effectiveSummary: string = '';
  /** 最近一次操作的结果文案（截图证据要看得到）。 */
  @State message: string = '';

  aboutToAppear(): void {
    this.bootstrap();
  }

  private theme(): ThemeTokens {
    return resolveTheme(this.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
  }

  private s(resource: Resource): string {
    return i18nService.tKey(resource);
  }

  private async bootstrap(): Promise<void> {
    const store = fileSettingsStore();
    await store.load();
    const stored: FileSettings = store.stored();
    this.useDocumentDir = stored.useDocumentDir;
    this.omitCourseName = stored.omitCourseName;
    this.root = fileRepository().cacheRoot();
    this.effectiveSummary = describeFileSettings(store.current());
    logger.info('file settings page appear: ' + this.effectiveSummary + ' root=' + this.root);
  }

  private async onToggle(key: FileSettingsKey, value: boolean): Promise<void> {
    const store = fileSettingsStore();
    const persisted: boolean = await store.set(key, value);
    const stored: FileSettings = store.stored();
    this.useDocumentDir = stored.useDocumentDir;
    this.omitCourseName = stored.omitCourseName;
    this.root = fileRepository().cacheRoot();
    this.effectiveSummary = describeFileSettings(store.current());
    // 消费点自证：改完之后**实际生效值**与**落盘根目录**都在下面这一行里。
    logger.info('file settings changed: key=' + key + ' value=' + value.toString()
      + ' persisted=' + persisted.toString() + ' ' + this.effectiveSummary + ' root=' + this.root);
    this.message = persisted
      ? this.effectiveSummary
      : i18nService.t('loh_clear_file_cache_failed') + 'persist failed';
  }

  private handleClearCache(): void {
    AlertDialog.show({
      title: this.s($r('app.string.loh_clear_file_cache')),
      message: this.s($r('app.string.loh_clear_file_cache_confirmation')),
      primaryButton: {
        value: this.s($r('app.string.loh_cancel')),
        action: () => {
        }
      },
      secondaryButton: {
        value: this.s($r('app.string.loh_ok')),
        action: () => {
          this.clearCache();
        }
      },
      cancel: () => {
      }
    });
  }

  private clearCache(): void {
    const result: ClearCacheResult = fileRepository().clearCache();
    this.root = result.root;
    logger.info('file settings clear cache: ok=' + result.ok.toString() + ' root=' + result.root
      + (result.error.length > 0 ? ' error=' + result.error : ''));
    this.message = result.ok
      ? i18nService.t('loh_clear_file_cache_succeeded') + ' ' + result.root
      : i18nService.t('loh_clear_file_cache_failed') + result.error;
  }

  @Builder
  switchRow(title: string, caption: string, isOn: boolean, key: FileSettingsKey) {
    Column() {
      Row() {
        Text(title)
          .fontSize(this.theme().typography.titleMedium.fontSize)
          .fontColor(this.theme().colors.onSurface)
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: isOn })
          .selectedColor(this.theme().colors.primary)
          .onChange((value: boolean) => {
            this.onToggle(key, value);
          })
      }
      .width('100%')
      Text(caption)
        .fontSize(this.theme().typography.bodySmall.fontSize)
        .fontColor(this.theme().colors.onSurfaceVariant)
        .width('100%')
        .margin({ top: this.theme().sizes.space1 })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({
      left: this.theme().sizes.contentPadding,
      right: this.theme().sizes.contentPadding,
      top: this.theme().sizes.space3,
      bottom: this.theme().sizes.space3
    })
  }

  build() {
    Column() {
      // 页头：返回图标与标题**同一行**（标题不再另占一行）。
      // 图标放在固定 40vp×40vp 的 Stack 里：a11y 文案就是 label，点击区不缩。
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
        Text(this.s($r('app.string.ui_file_settings_title')))
          .fontSize(this.theme().typography.headlineSmall.fontSize)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.theme().colors.onSurface)
          .layoutWeight(1)
          .margin({ left: this.theme().sizes.space3 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({
        left: this.theme().sizes.contentPadding,
        right: this.theme().sizes.contentPadding,
        top: this.theme().sizes.space3,
        bottom: this.theme().sizes.space2
      })

      Scroll() {
        Column() {
          this.switchRow(
            this.s($r('app.string.loh_file_use_document_dir')),
            this.useDocumentDir
              ? this.s($r('app.string.ui_file_use_document_dir_on'))
              : this.s($r('app.string.ui_file_use_document_dir_off')),
            this.useDocumentDir,
            FileSettingsKey.USE_DOCUMENT_DIR)
          Divider()
            .color(this.theme().colors.outlineVariant)
          this.switchRow(
            this.s($r('app.string.loh_file_omit_course_name')),
            this.omitCourseName
              ? this.s($r('app.string.ui_file_omit_course_name_on'))
              : this.s($r('app.string.ui_file_omit_course_name_off')),
            this.omitCourseName,
            FileSettingsKey.OMIT_COURSE_NAME)
          Divider()
            .color(this.theme().colors.outlineVariant)

          Row() {
            Text(this.s($r('app.string.loh_clear_file_cache')))
              .fontSize(this.theme().typography.titleMedium.fontSize)
              .fontColor(this.theme().colors.onSurface)
              .layoutWeight(1)
          }
          .width('100%')
          .padding({
            left: this.theme().sizes.contentPadding,
            right: this.theme().sizes.contentPadding,
            top: this.theme().sizes.space4,
            bottom: this.theme().sizes.space4
          })
          .onClick(() => {
            this.handleClearCache();
          })

          Text(i18nService.t('ui_file_settings_root', this.root))
            .fontSize(this.theme().typography.bodySmall.fontSize)
            .fontColor(this.theme().colors.onSurfaceVariant)
            .width('100%')
            .padding({ left: this.theme().sizes.contentPadding, right: this.theme().sizes.contentPadding })
          Text(this.effectiveSummary)
            .fontSize(this.theme().typography.labelSmall.fontSize)
            .fontColor(this.theme().colors.onSurfaceVariant)
            .width('100%')
            .margin({ top: this.theme().sizes.space2 })
            .padding({ left: this.theme().sizes.contentPadding, right: this.theme().sizes.contentPadding })
          if (this.message.length > 0) {
            Text(this.message)
              .fontSize(this.theme().typography.bodySmall.fontSize)
              .fontColor(this.theme().colors.primary)
              .width('100%')
              .margin({ top: this.theme().sizes.space3 })
              .padding({ left: this.theme().sizes.contentPadding, right: this.theme().sizes.contentPadding })
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
      // 内容比视口短时停在顶部：Scroll 默认会把子内容居中，页面看起来"浮在半空"。
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme().colors.background)
  }
}
