/*
 * 设置项的一行（ui/components）—— 参考实现 `components/TableCell.tsx` 的移植。
 *
 * ## 逐项对齐（参考实现 → 这里）
 *
 * | 项 | 参考实现（`TableCell.tsx`） | 这里 |
 * | --- | --- | --- |
 * | 容器 | `Touchable`（整行可点）+ row / alignItems:center | `Row` + `.onClick` |
 * | 内边距 | `paddingHorizontal:16`、`paddingVertical:2`（有头像时 16）、`minHeight:52` | 同 |
 * | 图标 | `MaterialIcons size={21} color={theme.colors.onSurface}`，`marginRight:8` | `IconGlyph` + 同一尺寸与间距 |
 * | 头像 | `Avatar.Icon size={48} icon="account" color={theme.colors.background}` | 48vp 圆形底（`primary`）+ `account` 字形（`background`） |
 * | 主文案 | `fontSize:17`；有头像时 `19` 且 600 粗 | 同（`fontWeight(FontWeight.Bold)` ≈ 600） |
 * | 副文案 | `fontSize:14`、`grey`、`marginTop:2` | `bodySmall/bodyMedium` 尺寸取令牌；颜色取 `colors.outline`（令牌里最接近 RN 的 `grey`） |
 * | 行尾 | `type==='arrow'` → MaterialIcons `keyboard-arrow-right` 21 `grey`；`type==='switch'` → paper 的 `Switch` | `IconGlyph(KEYBOARD_ARROW_RIGHT)` 21 `outline`；`Toggle({type: Switch})` |
 *
 * **两处不移植**：`type==='input'`（数字输入框）与 `loading` 指示器 —— 参考实现里
 * `input` 只被日历/提醒那套设置用，`loading` 只被推送通知 token 那一屏用，两者都在
 * ticket 17 的范围之外（参考实现的 `Settings.tsx` 一件都没用到）。**不写死空实现**，
 * 而是不声明这两个属性，免得后来者以为"故意留白"。
 */

import { ThemeTokens, resolveTheme } from '../theme/Tokens';
import { AppIcon } from '../icons/IconCatalog';
import { IconGlyph } from '../icons/IconGlyph';

/** 一行的类型（参考实现 `TableCell.tsx:15` 的联合里本工程用到的三支）。 */
export enum TableCellType {
  NONE = 'none',
  ARROW = 'arrow',
  SWITCH = 'switch'
}

/** 图标边长 21（参考实现 `TableCell.tsx:84` 的 `size={21}`）。 */
const CELL_ICON_SIZE: number = 21;

/** 头像直径 48（参考实现 `TableCell.tsx:73` 的 `size={48}`）。 */
const CELL_AVATAR_SIZE: number = 48;

@Component
export struct TableCell {
  /** 主文案（必填）。 */
  @Prop primaryText: string = '';
  /** 副文案；空串 = 不渲染（参考实现 `secondaryText ? … : null`）。 */
  @Prop secondaryText: string = '';
  /** 左侧图标。 */
  @Prop icon: AppIcon = AppIcon.CHECK;
  /** false = 不渲染左侧图标。 */
  @Prop showIcon: boolean = true;
  /** true = 左侧渲染头像（参考实现 `imageAlt` 那一支）。 */
  @Prop showAvatar: boolean = false;
  @Prop cellType: TableCellType = TableCellType.NONE;
  @Prop switchValue: boolean = false;
  /** 开关是否禁用（沉浸式设置的第二项用它）。 */
  @Prop switchDisabled: boolean = false;
  /** 开关的无障碍文案（图标 / 文案已经说明语义，这里只补"这是一个开关"）。 */
  @Prop switchLabel: string = '';
  @Prop isDark: boolean = false;
  /** 与上一行的间距（参考实现用 `styles.marginTop = 16` 分组）。 */
  @Prop marginTop: number = 0;
  onPress: () => void = () => {
  };
  onSwitchChange: (value: boolean) => void = () => {
  };

  private theme(): ThemeTokens {
    return resolveTheme(this.isDark);
  }

  @Builder
  avatar() {
    Stack() {
      IconGlyph({
        icon: AppIcon.ACCOUNT,
        glyphSize: CELL_AVATAR_SIZE * 0.62,
        color: this.theme().colors.background,
        label: this.primaryText
      })
    }
    .width(CELL_AVATAR_SIZE)
    .height(CELL_AVATAR_SIZE)
    .borderRadius(CELL_AVATAR_SIZE / 2)
    .backgroundColor(this.theme().colors.primary)
    .margin({ right: this.theme().sizes.space2 })
  }

  build() {
    Row() {
      if (this.showAvatar) {
        this.avatar()
      } else if (this.showIcon) {
        // **不在自定义组件上链式加通用属性**（IconGlyph.ets 的文件头说明过这个不确定性）：
        // 图标与文字之间的间距改由下面那个 Column 的左边距承担，数值与参考实现等价
        // （参考实现是 iconContainer.marginRight:8 + textContainer.marginLeft:8 = 16）。
        IconGlyph({
          icon: this.icon,
          glyphSize: CELL_ICON_SIZE,
          color: this.theme().colors.onSurface,
          label: this.primaryText
        })
      }

      Column() {
        Text(this.primaryText)
          .fontSize(this.showAvatar ? 19 : 17)
          .fontWeight(this.showAvatar ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(this.theme().colors.onSurface)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        if (this.secondaryText.length > 0) {
          Text(this.secondaryText)
            .fontSize(this.theme().typography.bodyMedium.fontSize)
            .fontColor(this.theme().colors.outline)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .margin({ top: 2 })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: this.showIcon ? this.theme().sizes.space4 : this.theme().sizes.space2,
        right: this.theme().sizes.space2 })

      if (this.cellType === TableCellType.SWITCH) {
        Toggle({ type: ToggleType.Switch, isOn: this.switchValue })
          .enabled(!this.switchDisabled)
          .selectedColor(this.theme().colors.primary)
          .accessibilityText(this.switchLabel)
          .onChange((value: boolean) => {
            this.onSwitchChange(value);
          })
      } else if (this.cellType === TableCellType.ARROW) {
        IconGlyph({
          icon: AppIcon.KEYBOARD_ARROW_RIGHT,
          glyphSize: CELL_ICON_SIZE,
          color: this.theme().colors.outline,
          label: ''
        })
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .constraintSize({ minHeight: 52 })
    .padding({
      left: this.theme().sizes.contentPadding,
      right: this.theme().sizes.contentPadding,
      top: this.showAvatar ? 16 : 2,
      bottom: this.showAvatar ? 16 : 2
    })
    .backgroundColor(this.theme().colors.surface)
    .margin({ top: this.marginTop })
    .onClick(() => {
      this.onPress();
    })
  }
}
