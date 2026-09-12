/*
 * 沉浸式设置页（settings，ticket 17）—— 参考实现 `screens/ImmersiveSettings.tsx`（74 行）的移植。
 *
 * ## 逐项对齐
 *
 * | 项 | 参考实现 | 这里 |
 * | --- | --- | --- |
 * | 开关 1 | `fullscreen` 图标 + `immersiveMode`，值 = `immersiveMode` | 同（`AppIcon.FULLSCREEN`） |
 * | 开关 1 说明 | `immersiveModeDescription`，12px / opacity 0.6 | 同 |
 * | 开关 2 | `center-focus-strong` + `avoidFrontCamera`，值 = `immersiveMode && immersiveAvoidFrontCamera` | 同（`effectiveAvoidFrontCamera`） |
 * | 开关 2 禁用 | `switchDisabled={!immersiveMode}` | 同（`avoidFrontCameraEnabled`） |
 * | 开关 2 说明 | `avoidFrontCameraDescription`，12px / opacity 0.6，块间距 24 | 同 |
 * | 联动 | 关掉开关 1 时若开关 2 为真则置假（`:24-29`） | 同（`ImmersiveSettingsStore.setImmersiveMode`，纯函数 `applyImmersiveToggle`） |
 *
 * ## 与参考实现的一处**行为差异（工单要求）**
 *
 * 参考实现的说明文字写着"需要重启应用"（`immersiveModeDescription` 的原文），而本 ticket 的验收
 * 第 3 条要求"**即时生效**，重启后保持"。本工程按验收做：切换后立刻调
 * `core/window/ImmersiveWindow.applyImmersiveMode`（隐藏 / 恢复状态栏与导航栏）并写 preferences。
 * **那句说明文字仍按参考实现原样显示**——它是**迁移键**（由 reference 的词典生成），
 * 改它会让 `check-generated-fresh` 失败，且会偏离参考实现的文案。这处"文案与行为不完全一致"
 * 已在 ticket 17 的交付节里如实登记。
 */

import { ConfigurationConstant, common } from '@kit.AbilityKit';
import { ThemeTokens, resolveTheme } from '../../ui/theme/Tokens';
import { i18nService } from '../../core/i18n/I18n';
import { COLOR_MODE_KEY, LOCALE_VERSION_KEY } from '../../entryability/EntryAbility';
import { Logger } from '../../core/log/Logger';
import { TableCell, TableCellType } from '../../ui/components/TableCell';
import { AppIcon } from '../../ui/icons/IconCatalog';
import {
  ImmersiveSettingsKey, ImmersiveSettingsStore, describeImmersiveSettings, effectiveAvoidFrontCamera
} from '../../data/settings/ImmersiveSettings';
import { applyImmersiveMode } from '../../core/window/ImmersiveWindow';
import { immersiveSettingsStore } from './repository/ImmersiveSettingsProvider';

const logger: Logger = new Logger('features.settings.immersive.page');

@Component
export struct ImmersiveSettingsPage {
  @StorageProp(COLOR_MODE_KEY) colorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageLink(LOCALE_VERSION_KEY) localeVersion: number = 0;

  /** 返回按钮要弹的栈（由导航目标传入；null = 拿不到，按钮点了也不做事）。 */
  stack: NavPathStack | null = null;

  /** 持久化值（开关 1 直接显示它）。 */
  @State immersiveMode: boolean = false;
  /** 持久化值（开关 2 的**显示值**还要与开关 1 相与，见 effectiveAvoidFrontCamera）。 */
  @State avoidFrontCamera: boolean = false;
  /** 最近一次操作的结果（自证行，截图可见）。 */
  @State message: string = '';

  aboutToAppear(): void {
    this.bootstrap();
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

  private hostContext(): common.Context | null {
    try {
      return this.getUIContext().getHostContext() as common.Context;
    } catch (error) {
      logger.error('immersive page: no host context (' + (error as Error).message + ')');
      return null;
    }
  }

  private async bootstrap(): Promise<void> {
    const store: ImmersiveSettingsStore = immersiveSettingsStore();
    await store.load();
    this.immersiveMode = store.stored().immersiveMode;
    this.avoidFrontCamera = store.stored().immersiveAvoidFrontCamera;
    this.message = describeImmersiveSettings(store.current());
    logger.info('immersive settings page appear: ' + this.message);
  }

  /** 开关 1：联动 + 持久化 + **立刻应用到窗口**（验收第 3 条的"即时生效"）。 */
  private async onImmersiveToggle(value: boolean): Promise<void> {
    const store: ImmersiveSettingsStore = immersiveSettingsStore();
    const persisted: boolean = await store.setImmersiveMode(value);
    this.immersiveMode = store.stored().immersiveMode;
    this.avoidFrontCamera = store.stored().immersiveAvoidFrontCamera;
    const context: common.Context | null = this.hostContext();
    let applied: boolean = false;
    if (context !== null) {
      applied = await applyImmersiveMode(context, this.immersiveMode);
    }
    // **消费点自证**：持久化结果 + 平台调用结果 + 实际生效值（含联动后的开关 2）。
    logger.info('immersive toggled: requested=' + value.toString()
      + ' persisted=' + persisted.toString()
      + ' appliedToWindow=' + applied.toString()
      + ' ' + describeImmersiveSettings(store.current()));
    this.message = describeImmersiveSettings(store.current());
  }

  /** 开关 2：参考实现只写 state（它的消费点是 RN 的安全区回退），这里只持久化。 */
  private async onAvoidFrontCameraToggle(value: boolean): Promise<void> {
    const store: ImmersiveSettingsStore = immersiveSettingsStore();
    const persisted: boolean = await store.set(ImmersiveSettingsKey.AVOID_FRONT_CAMERA, value);
    this.avoidFrontCamera = store.stored().immersiveAvoidFrontCamera;
    logger.info('immersive avoid-front-camera toggled: requested=' + value.toString()
      + ' persisted=' + persisted.toString()
      + ' ' + describeImmersiveSettings(store.current()));
    this.message = describeImmersiveSettings(store.current());
  }

  @Builder
  caption(text: string) {
    Text(text)
      .fontSize(12)
      .fontColor(this.theme().colors.onSurface)
      .opacity(0.6)
      .width('100%')
      .margin({ top: 4 })
      .padding({ left: this.theme().sizes.contentPadding, right: this.theme().sizes.contentPadding })
  }

  build() {
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
      .padding({
        left: this.theme().sizes.contentPadding,
        top: this.theme().sizes.space3,
        bottom: this.theme().sizes.space2
      })

      Text(this.s($r('app.string.loh_immersive_mode')))
        .fontSize(this.theme().typography.headlineSmall.fontSize)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.theme().colors.onSurface)
        .width('100%')
        .padding({ left: this.theme().sizes.contentPadding, right: this.theme().sizes.contentPadding })

      Scroll() {
        Column() {
          TableCell({
            icon: AppIcon.FULLSCREEN,
            primaryText: this.s($r('app.string.loh_immersive_mode')),
            cellType: TableCellType.SWITCH,
            switchValue: this.immersiveMode,
            switchLabel: this.s($r('app.string.loh_immersive_mode')),
            isDark: this.isDark(),
            onSwitchChange: (value: boolean): void => {
              this.onImmersiveToggle(value);
            }
          })
          this.caption(this.s($r('app.string.loh_immersive_mode_description')))

          TableCell({
            icon: AppIcon.CENTER_FOCUS_STRONG,
            primaryText: this.s($r('app.string.loh_avoid_front_camera')),
            cellType: TableCellType.SWITCH,
            switchValue: effectiveAvoidFrontCamera({
              immersiveMode: this.immersiveMode,
              immersiveAvoidFrontCamera: this.avoidFrontCamera
            }),
            switchDisabled: !this.immersiveMode,
            switchLabel: this.s($r('app.string.loh_avoid_front_camera')),
            isDark: this.isDark(),
            marginTop: 24,
            onSwitchChange: (value: boolean): void => {
              this.onAvoidFrontCameraToggle(value);
            }
          })
          this.caption(this.s($r('app.string.loh_avoid_front_camera_description')))

          if (this.message.length > 0) {
            Text(this.message)
              .fontSize(this.theme().typography.labelSmall.fontSize)
              .fontColor(this.theme().colors.onSurfaceVariant)
              .width('100%')
              .margin({ top: this.theme().sizes.space4 })
              .padding({
                left: this.theme().sizes.contentPadding,
                right: this.theme().sizes.contentPadding
              })
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ top: 16, bottom: 16 })
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme().colors.background)
  }
}
