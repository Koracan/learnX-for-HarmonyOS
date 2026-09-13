/*
 * 帮助与反馈页（settings）—— 参考实现 `screens/Help.tsx`（64 行）的移植。
 *
 * 三节，顺序与文案逐条照抄（`loh_github_recommended` / `loh_email_not_recommended` / `loh_issue_template`）：
 *   1. GitHub（推荐）→ `https://github.com/Koracan/learnX-for-HarmonyOS/issues/new/choose`；
 *   2. 邮件（不推荐）→ `mailto:koracan@163.com`；
 *   3. 问题反馈与帮助（一段说明文字 + 议题模板正文，都是**迁移键**的原文）。
 *
 * 外链走 `ui/components/ExternalLink.openExternalUrl`（参考实现是 `Linking.openURL`）；
 * `mailto:` 走同一个 want，系统没有邮件应用时 startAbility 会失败并落日志（不假装打开成功）。
 */

import { ConfigurationConstant } from '@kit.AbilityKit';
import { ThemeTokens, resolveTheme } from '../../ui/theme/Tokens';
import { i18nService } from '../../core/i18n/I18n';
import { COLOR_MODE_KEY, LOCALE_VERSION_KEY } from '../../entryability/EntryAbility';
import { openExternalUrl } from '../../ui/components/ExternalLink';
import { AppIcon } from '../../ui/icons/IconCatalog';
import { IconGlyph } from '../../ui/icons/IconGlyph';

const NEW_ISSUE_URL: string = 'https://github.com/Koracan/learnX-for-HarmonyOS/issues/new/choose';
const SUPPORT_EMAIL: string = 'koracan@163.com';

@Component
export struct HelpPage {
  @StorageProp(COLOR_MODE_KEY) colorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageLink(LOCALE_VERSION_KEY) localeVersion: number = 0;

  stack: NavPathStack | null = null;

  private theme(): ThemeTokens {
    return resolveTheme(this.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
  }

  private s(resource: Resource): string {
    return i18nService.tKey(resource);
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

  build() {
    Column() {
      // 页头：返回图标与标题**同一行**。图标是闭集里的既有字形，label 负责无障碍朗读，
      // 外框固定 40vp×40vp（点击区不小于改动前那行 labelLarge 文字）。
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
        Text(this.s($r('app.string.loh_help_and_feedback')))
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
          this.sectionTitle(this.s($r('app.string.loh_github_recommended')))
          this.linkText(this.s($r('app.string.loh_create_new_git_hub_issue')), NEW_ISSUE_URL)

          this.sectionTitle(this.s($r('app.string.loh_email_not_recommended')))
          this.linkText(SUPPORT_EMAIL, 'mailto:' + SUPPORT_EMAIL)

          this.sectionTitle(this.s($r('app.string.loh_issue_template')))
          this.bodyText(this.s($r('app.string.loh_issue_template_description')))
          this.bodyText(this.s($r('app.string.loh_issue_template_content')))
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
      // 内容比视口短时停在顶部：Scroll 默认会把子内容居中，页面看起来"浮在半空"。
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme().colors.background)
  }
}
