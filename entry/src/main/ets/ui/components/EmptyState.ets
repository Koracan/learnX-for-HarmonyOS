/*
 * 通用空态组件（ui/ 放通用组件）。
 *
 * 参考实现 components/Empty.tsx:13-18 用 MaterialIcons 的 check-circle（outline 取色）。
 * 图标字体已随包内嵌，这里直接用**同一个字形**（`AppIcon.CHECK_CIRCLE`），
 * 不再画替代圆环。尺寸仍取既有令牌 `sizes.iconLarge`（参考实现是硬编码 56）。
 */
import { ThemeTokens, resolveTheme } from '../theme/Tokens';
import { AppIcon } from '../icons/IconCatalog';
import { IconGlyph } from '../icons/IconGlyph';

@Component
export struct EmptyState {
  /** 已经本地化好的空态文案（由调用方用资源取串）。 */
  @Prop message: string = '';
  @Prop isDark: boolean = false;

  private theme(): ThemeTokens {
    return resolveTheme(this.isDark);
  }

  build() {
    Column() {
      IconGlyph({
        icon: AppIcon.CHECK_CIRCLE,
        glyphSize: this.theme().sizes.iconLarge,
        color: this.theme().colors.outline
      })
      Text(this.message)
        .fontSize(this.theme().typography.bodyLarge.fontSize)
        .lineHeight(this.theme().typography.bodyLarge.lineHeight)
        .fontColor(this.theme().colors.onSurfaceVariant)
        .textAlign(TextAlign.Center)
        .margin({ top: this.theme().sizes.space4 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding(this.theme().sizes.contentPadding)
  }
}
