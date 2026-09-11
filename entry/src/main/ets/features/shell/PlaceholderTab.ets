/*
 * 尚未实现的 tab 的占位页（作业 / 文件 / 课程 / 设置）。
 *
 * 本 ticket 只交付导航骨架与公告列表；其余四页在各自切片（10/11/12/17）落地，
 * 这里明确说明“后续迭代实现”，而不是留白或写死假内容。
 */
import { ThemeTokens, resolveTheme } from '../../ui/theme/Tokens';

@Component
export struct PlaceholderTab {
  /** 已本地化的 tab 名（由调用方取串）。 */
  @Prop title: string = '';
  /** 已本地化的占位说明（由调用方取串）。 */
  @Prop message: string = '';
  @Prop isDark: boolean = false;

  private theme(): ThemeTokens {
    return resolveTheme(this.isDark);
  }

  build() {
    Column() {
      Text(this.title)
        .fontSize(this.theme().typography.headlineSmall.fontSize)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.theme().colors.onSurface)
      Text(this.message)
        .fontSize(this.theme().typography.bodyMedium.fontSize)
        .fontColor(this.theme().colors.onSurfaceVariant)
        .textAlign(TextAlign.Center)
        .margin({ top: this.theme().sizes.space3 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding(this.theme().sizes.contentPadding)
    .backgroundColor(this.theme().colors.background)
  }
}
