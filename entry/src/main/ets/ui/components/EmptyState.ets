/*
 * 通用空态组件（spec.md 第 2 节：ui/ 放通用组件）。
 *
 * 参考实现 components/Empty.tsx 用 MaterialIcons 的 check-circle；图标字体
 * （MCI TTF）要到后续切片才打包，这里用一个纯主题令牌画的中性圆环代替，
 * 视觉效果一致（居中、outline 取色），且不引入任何硬编码色值。
 */
import { ThemeTokens, resolveTheme } from '../theme/Tokens';

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
      Column()
        .width(this.theme().sizes.iconLarge)
        .height(this.theme().sizes.iconLarge)
        .borderRadius(this.theme().sizes.iconLarge / 2)
        .border({ width: this.theme().sizes.borderWidth * 2, color: this.theme().colors.outline })
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
