/*
 * 关于页（settings）—— 参考实现 `screens/About.tsx`（105 行）的移植。
 *
 * ## 分节与顺序（逐条照抄）
 *
 * 1. 「版本信息」（`loh_version_information`）→ `v{versionName} (build {versionCode})`
 *    + `© 2026 Han Wong` + 备案号（**外链** `https://beian.miit.gov.cn/`）；
 * 2. 「维护者」（`loh_maintainers`）→ `Han Wong (Koracan)`（外链 `https://github.com/Koracan`）
 *    + "开源地址" 一行（`loh_opensource_at` + 外链 `https://github.com/Koracan/learnX-for-HarmonyOS`）；
 * 3. 「特别感谢」（`loh_special_thanks`）→ `robertying/learnX` 与 `Harry-Chen/thu-learn-lib`
 *    （各带外链，前缀文案 `loh_rui_ying` / `loh_harry_chen`）；
 * 4. 「开源依赖」（`loh_opensource_dependencies`）。
 *
 * ## 版本号与构建号的取值（与参考实现不同，已登记）
 *
 * 参考实现取 `package.json.version` 与 `DeviceInfo.buildNo()`（react-native-device-info 的
 * `getBuildNumber()`）。本工程取 **应用自身信息**（`bundleManager`）：`versionName` 与 `versionCode`
 * （`AppScope/app.json5` 的 `1.1.0` / `1000042`）。理由与 `core/device/AppIdentity.ets` 里
 * `deviceName` 那条一致：**从安装包读**比从源码里的 package.json 读更接近真相。
 *
 * ## 「开源依赖」一节：**不照抄参考实现的名单**
 *
 * 参考实现是 `Object.keys(packageJson.dependencies)` 动态列，本工程根 `oh-package.json5` 的
 * `dependencies` **是空的**（只有 `@ohos/hypium` / `@ohos/hamock` 两个 devDependency，跑单测用，
 * 不进 hap）。照抄那份名单会列出一堆本工程根本没用的包，所以这里**如实说明没有第三方运行时依赖**。
 */

import { ConfigurationConstant } from '@kit.AbilityKit';
import { ThemeTokens, resolveTheme } from '../../ui/theme/Tokens';
import { i18nService } from '../../core/i18n/I18n';
import { COLOR_MODE_KEY, LOCALE_VERSION_KEY } from '../../entryability/EntryAbility';
import { appVersionCode, appVersionName } from '../../core/device/AppIdentity';
import { openExternalUrl } from '../../ui/components/ExternalLink';

const BEIAN_URL: string = 'https://beian.miit.gov.cn/';
const MAINTAINER_URL: string = 'https://github.com/Koracan';
const REPO_URL: string = 'https://github.com/Koracan/learnX-for-HarmonyOS';
const LEARN_X_URL: string = 'https://github.com/robertying/learnX';
const THU_LEARN_LIB_URL: string = 'https://github.com/Harry-Chen/thu-learn-lib';

@Component
export struct AboutPage {
  @StorageProp(COLOR_MODE_KEY) colorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageLink(LOCALE_VERSION_KEY) localeVersion: number = 0;

  stack: NavPathStack | null = null;

  private theme(): ThemeTokens {
    return resolveTheme(this.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
  }

  private s(resource: Resource): string {
    return i18nService.tKey(resource);
  }

  /** `v{versionName} (build {versionCode})`（参考实现 About.tsx:27 的模板，逐字）。 */
  private versionText(): string {
    const version: string = appVersionName();
    const build: string = appVersionCode();
    return 'v' + (version.length > 0 ? version : '?')
      + ' (build ' + (build.length > 0 ? build : '?') + ')';
  }

  @Builder
  sectionTitle(text: string) {
    Text(text)
      .fontSize(20)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.theme().colors.onSurface)
      .width('100%')
      .margin({ top: this.theme().sizes.space5 })
  }

  @Builder
  bodyText(text: string) {
    Text(text)
      .fontSize(this.theme().typography.bodyMedium.fontSize)
      .fontColor(this.theme().colors.onSurface)
      .width('100%')
      .margin({ top: this.theme().sizes.space2 })
  }

  @Builder
  linkText(text: string, url: string) {
    Text(text)
      .fontSize(this.theme().typography.bodyMedium.fontSize)
      .fontColor(this.theme().colors.primary)
      .width('100%')
      .margin({ top: this.theme().sizes.space2 })
      .onClick(() => {
        openExternalUrl(url);
      })
  }

  /**
   * 一行"前缀文案 + 链接"（参考实现 `About.tsx:43-53` 的 `{t('opensourceAt')}{' '}<Text link>…</Text>`）。
   * 用 `Flex(wrap)` 排：前缀与链接在同一段文字流里，窄屏放不下时链接整体换行，不会把链接截断。
   */
  @Builder
  inlineLink(prefix: string, label: string, url: string) {
    Flex({ wrap: FlexWrap.Wrap }) {
      Text(prefix + ' ')
        .fontSize(this.theme().typography.bodyMedium.fontSize)
        .fontColor(this.theme().colors.onSurface)
      Text(label)
        .fontSize(this.theme().typography.bodyMedium.fontSize)
        .fontColor(this.theme().colors.primary)
        .onClick(() => {
          openExternalUrl(url);
        })
    }
    .width('100%')
    .margin({ top: this.theme().sizes.space2 })
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

      Text(this.s($r('app.string.loh_about')))
        .fontSize(this.theme().typography.headlineSmall.fontSize)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.theme().colors.onSurface)
        .width('100%')
        .padding({ left: this.theme().sizes.contentPadding, right: this.theme().sizes.contentPadding })

      Scroll() {
        Column() {
          // --- 1. 版本信息 ---
          this.sectionTitle(this.s($r('app.string.loh_version_information')))
          this.bodyText(this.versionText())
          this.bodyText('© 2026 Han Wong')
          this.linkText('京ICP备2026001019号-1A', BEIAN_URL)

          // --- 2. 维护者 ---
          this.sectionTitle(this.s($r('app.string.loh_maintainers')))
          this.linkText('Han Wong (Koracan)', MAINTAINER_URL)
          this.inlineLink(this.s($r('app.string.loh_opensource_at')),
            'Koracan/learnX-for-HarmonyOS', REPO_URL)

          // --- 3. 特别感谢 ---
          this.sectionTitle(this.s($r('app.string.loh_special_thanks')))
          this.inlineLink(this.s($r('app.string.loh_rui_ying')), 'robertying/learnX', LEARN_X_URL)
          this.inlineLink(this.s($r('app.string.loh_harry_chen')), 'Harry-Chen/thu-learn-lib',
            THU_LEARN_LIB_URL)

          // --- 4. 开源依赖（**如实说明**：本工程没有第三方运行时依赖）---
          this.sectionTitle(this.s($r('app.string.loh_opensource_dependencies')))
          this.bodyText(this.s($r('app.string.ui_opensource_dependencies_none')))
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({
          left: this.theme().sizes.space5,
          right: this.theme().sizes.space5,
          top: 16,
          bottom: 32
        })
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme().colors.background)
  }
}
