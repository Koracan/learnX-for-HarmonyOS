/*
 * 列表行的**滑动操作按钮** —— 内容三域（收藏 / 归档）与课程（屏蔽）两套。
 *
 * 逐项对齐参考实现 reference/learnOH-old/src/components/CardWrapper.tsx：
 *
 * | 项 | 参考实现 | 出处 |
 * | --- | --- | --- |
 * | 按钮宽 | `buttonWidth = 80` | :11 |
 * | 收藏 | MCI `heart` / 已收藏 `heart-off`，32，`Colors.red500`，底 `rgba(255,59,48,0.2)` | :86-98 |
 * | 归档 | MCI `archive-arrow-down` / 已归档 `archive-arrow-up`，32，`Colors.blue500`，底 `rgba(33,150,243,0.2)` | :100-115 |
 * | **已归档时收藏按钮不渲染** | `{archived ? null : (…fav button…)}` | :82 |
 * | 屏蔽课程 | MaterialIcons `visibility-off` / 已屏蔽 `visibility`，32，`Colors.yellow500`，底 `rgba(255,204,0,0.2)` | :63-79 |
 *
 * 颜色取本工程的 `PLAIN_PALETTE`（与参考实现 `constants/Colors` 同值）。
 * 图标形状来自同一份 TTF（该决定见 ui/icons/IconCatalog.ets 文件头）。
 *
 * 参考实现还有"长按卡片 = 打开右侧操作"（CardWrapper.tsx:161-166）。本工程用同一排按钮
 * 承载同样的两个动作（长按弹菜单，见各列表页的 `.bindContextMenu`），所以动作集不变。
 */

import { PLAIN_PALETTE } from '../theme/Tokens';
import { AppIcon } from '../icons/IconCatalog';
import { IconGlyph } from '../icons/IconGlyph';

/** 单个按钮的宽度（参考实现 CardWrapper.tsx:11）。 */
export const SWIPE_ACTION_WIDTH: number = 80;

/** 图标字号（参考实现固定 32）。 */
const SWIPE_ICON_SIZE: number = 32;

/** 收藏 / 归档两个按钮（公告 / 作业 / 文件三域共用）。 */
@Component
export struct ContentSwipeActions {
  /** 该行是否已收藏（传**原始收藏集合**的成员判断，见 features/marks/FilteredContent）。 */
  @Prop fav: boolean = false;
  /** 该行是否已归档。 */
  @Prop archived: boolean = false;
  /** 两个按钮的无障碍文案（界面无文字，按钮语义靠它）。 */
  @Prop favLabel: string = '';
  @Prop archiveLabel: string = '';
  onFav: () => void = () => {
  };
  onArchive: () => void = () => {
  };

  build() {
    Row() {
      // 参考实现：已归档的行不渲染收藏按钮（CardWrapper.tsx:82）。
      if (!this.archived) {
        Column() {
          IconGlyph({
            icon: this.fav ? AppIcon.HEART_OFF : AppIcon.HEART,
            glyphSize: SWIPE_ICON_SIZE,
            color: PLAIN_PALETTE.red500,
            label: this.favLabel
          })
        }
        .width(SWIPE_ACTION_WIDTH)
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('rgba(255,59,48,0.2)')
        .onClick(() => {
          this.onFav();
        })
      }
      Column() {
        IconGlyph({
          icon: this.archived ? AppIcon.ARCHIVE_ARROW_UP : AppIcon.ARCHIVE_ARROW_DOWN,
          glyphSize: SWIPE_ICON_SIZE,
          color: PLAIN_PALETTE.blue500,
          label: this.archiveLabel
        })
      }
      .width(SWIPE_ACTION_WIDTH)
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .backgroundColor('rgba(33,150,243,0.2)')
      .onClick(() => {
        this.onArchive();
      })
    }
    .height('100%')
  }
}

/** 课程行的屏蔽 / 取消屏蔽（参考实现 CardWrapper.tsx:63-79 的 onHide 那一支）。 */
@Component
export struct CourseHideAction {
  @Prop hidden: boolean = false;
  @Prop label: string = '';
  onHide: () => void = () => {
  };

  build() {
    Row() {
      Column() {
        IconGlyph({
          icon: this.hidden ? AppIcon.VISIBILITY : AppIcon.VISIBILITY_OFF,
          glyphSize: SWIPE_ICON_SIZE,
          color: PLAIN_PALETTE.yellow500,
          label: this.label
        })
      }
      .width(SWIPE_ACTION_WIDTH)
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .backgroundColor('rgba(255,204,0,0.2)')
      .onClick(() => {
        this.onHide();
      })
    }
    .height('100%')
  }
}