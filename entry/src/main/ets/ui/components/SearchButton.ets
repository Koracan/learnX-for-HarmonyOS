/*
 * 页头右侧的搜索入口（ticket 15）—— 四个内容 tab 的 `header()` 共用同一个按钮。
 *
 * 参考实现是导航栏的 `headerRight`：`App.tsx:137-158` 的 `getScreenOptions(title, hideSearch)`，
 * 默认给每个页头加一颗 MaterialIcons `search` 图标，点它 `navigation.navigate('SearchStack')`；
 * **设置页显式传 `hideSearch = true`**（`App.tsx:558`），详情页走另一套 options 函数、也没有。
 * 本工程的页头是自绘的，所以这颗按钮由各页自己放进 `header()` 的 Row 末尾。
 *
 * 组件只负责"长什么样 + 点一下"，**打开搜索的动作**由调用方传进来（`onTap`）：
 * ui/ 不反向依赖 features/（分层约束，见 scripts/check-domain-purity.mjs 的同类口径）。
 */

import { ThemeTokens, resolveTheme } from '../theme/Tokens';
import { AppIcon } from '../icons/IconCatalog';
import { IconGlyph } from '../icons/IconGlyph';

@Component
export struct SearchButton {
  @Prop isDark: boolean = false;
  /** 无障碍文案（调用方取 `loh_search`）。 */
  @Prop label: string = '';
  onTap: () => void = () => {
  };

  private theme(): ThemeTokens {
    return resolveTheme(this.isDark);
  }

  build() {
    Row() {
      IconGlyph({
        icon: AppIcon.SEARCH,
        glyphSize: this.theme().sizes.iconMedium,
        color: this.theme().colors.onSurface,
        label: this.label
      })
    }
    // 点击热区：图标本身 24vp，加一圈 padding 才够得着（参考实现的 IconButton 自带热区）。
    .padding(this.theme().sizes.space2)
    .onClick(() => {
      this.onTap();
    })
  }
}
