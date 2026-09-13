/*
 * 过滤片（一个视图 + 它的计数）—— 四个列表共用。
 *
 * 参考实现的过滤入口是页头左侧图标弹出的下拉列表（`components/Filter.tsx`，每项
 * "图标 + 名称 + 计数角标"）。本工程把它换成一排**同屏筛选片**（
 * 见交付的偏离说明）：行为（点一下切视图）与计数口径一字未变。
 *
 * 计数用参考实现的角标数字（Filter.tsx:53-61 的 Badge）；这里做成
 * `名称 + 空格 + 数字` 的可读文本，数字逐字可见（截图即可核对）。
 */

import { ThemeTokens, resolveTheme } from '../theme/Tokens';

@Component
export struct FilterChip {
  @Prop label: string = '';
  @Prop count: number = 0;
  @Prop active: boolean = false;
  @Prop isDark: boolean = false;
  onTap: () => void = () => {
  };

  private theme(): ThemeTokens {
    return resolveTheme(this.isDark);
  }

  build() {
    Text(this.label + ' ' + this.count.toString())
      .fontSize(this.theme().typography.labelMedium.fontSize)
      .fontColor(this.active ? this.theme().colors.onPrimaryContainer
        : this.theme().colors.onSurfaceVariant)
      .backgroundColor(this.active ? this.theme().colors.primaryContainer
        : this.theme().colors.surface)
      .borderRadius(this.theme().sizes.controlHeight / 2)
      .padding({
        left: this.theme().sizes.space3,
        right: this.theme().sizes.space3,
        top: this.theme().sizes.space1,
        bottom: this.theme().sizes.space1
      })
      .margin({ right: this.theme().sizes.space2 })
      .onClick(() => {
        this.onTap();
      })
  }
}
