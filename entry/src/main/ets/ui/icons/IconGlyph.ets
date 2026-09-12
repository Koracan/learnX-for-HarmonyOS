/*
 * 图标组件（ticket 11.5）：全应用**唯一**的字形渲染入口。
 *
 * 形状与来源：内嵌的 MaterialCommunityIcons / MaterialIcons（与参考实现同一份 TTF、同一批码位），
 * 颜色与尺寸仍由调用方用主题令牌给出（`colors.*` / `PLAIN_PALETTE.*` / `sizes.icon*`）。
 *
 * 失败回退：字体未就绪时渲染**可读文本**（有 `label` 用 `label`，否则用目录里的短名），
 * 并已在 `IconFont` 里落过 error hilog —— 不会出现"豆腐块且无日志"。
 */
import { AppIcon, IconSpec, iconGlyph, iconSpec } from './IconCatalog';
import { iconFontFamily, iconFontReady } from './IconFont';

@Component
export struct IconGlyph {
  /** 闭集里的图标。 */
  icon: AppIcon = AppIcon.CHECK;
  /**
   * 字号 = 图标边长（vp）。调用方传既有尺寸令牌。
   *
   * 名字**不能叫 `size`**：`CustomComponent` 上已有通用属性方法 `size(value: SizeOptions)`，
   * 同名会编译失败（`Property 'size' in type 'IconGlyph' is not assignable to the same property
   * in base type 'CustomComponent'`）—— 这是实打实踩到过的坑。
   */
  @Prop glyphSize: number = 16;
  /** 颜色（令牌）。 */
  @Prop color: string = '#000000';
  /** 无障碍文案；回退时也当作可见文本（所以它是"可读"的）。 */
  @Prop label: string = '';
  /**
   * 左侧外边距。放在组件**内部**是有意的：卡片右上角那几个标记原本就是"每个图标自带
   * `margin({left: space1})`"，这样调用点不必给自定义组件链式加通用属性（那会引入
   * "自定义组件是否支持通用属性"的额外不确定性），间距值与改动前逐点相同。
   */
  @Prop marginLeft: number = 0;

  build() {
    if (iconFontReady()) {
      Text(iconGlyph(this.icon))
        .fontFamily(iconFontFamily(iconSpec(this.icon).family))
        .fontSize(this.glyphSize)
        .fontColor(this.color)
        .textAlign(TextAlign.Center)
        .accessibilityText(this.label)
        .margin({ left: this.marginLeft })
    } else {
      // 回退路径：可读文本。字号按比例收一点，避免比图标宽出太多。
      Text(this.label.length > 0 ? this.label : iconSpec(this.icon).fallback)
        .fontSize(this.glyphSize * 0.75)
        .fontColor(this.color)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .accessibilityText(this.label)
        .margin({ left: this.marginLeft })
    }
  }
}
