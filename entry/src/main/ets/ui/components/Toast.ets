/*
 * 应用内 Toast（Snackbar）—— 支持一枚**撤销**动作。
 *
 * 参考实现用 react-native-paper 的 `Snackbar`（reference/learnOH-old/src/components/Toast.tsx）：
 * 文案 + 可选动作（`action.label` / `action.onPress`），success 档的消失时长是
 * **3000 ms**（Toast.tsx:51-54）。收藏 / 归档 / 屏蔽三处的提示与撤销都走它
 * （components/FilterList.tsx:119-171）。
 *
 * 为什么不用 `promptAction.showToast`：平台 toast **没有动作按钮**，而本工程的
 * 要求"撤销可恢复" —— 撤销入口必须在界面上、且能截到图。
 *
 * 结构：`ToastController`（@ObservedV2，状态 + 定时器） + `ToastOverlay`（视图）。
 * 页面把它放进自己的 `Stack` 里做底部浮层。
 */

import { Logger } from '../../core/log/Logger';
import { ThemeTokens, resolveTheme } from '../theme/Tokens';

const logger: Logger = new Logger('ui.toast');

/**
 * success 档的消失时长。**逐字取自参考实现**（Toast.tsx:51-54：`type === 'success' ? 3000`）。
 * 收藏 / 归档 / 屏蔽三处的提示都是 success 档，所以撤销窗口就是 3 秒。
 */
export const TOAST_SUCCESS_MILLIS: number = 3000;

/**
 * 【取证开关】**只服务取证**：> 0 时把成功档的时长整体换成这个值。
 * 提交态必须是 0（= 不覆盖，用参考实现的 3000ms）—— 单测
 * `evidenceToastDurationOverrideIsOffAtCommit` 在守这一条。
 *
 * 为什么需要它：本仓库的取证动作（`devecocli ui screenshot/click`）单次要 15–35s，
 * 3 秒的窗口**必然抓不到**（AGENTS.md：时间敏感的证据不要赌手速，要把延迟直接改大）。
 * 取证构建用 60000ms；**实际生效值会由 `show()` 打进 hilog**（消费点自证）。
 */
export const TOAST_MILLIS_FOR_EVIDENCE: number = 0;

/** 实际生效的 Toast 时长（唯一读取点 = show()，日志与界面用的是同一个值）。 */
export function effectiveToastMillis(): number {
  return TOAST_MILLIS_FOR_EVIDENCE > 0 ? TOAST_MILLIS_FOR_EVIDENCE : TOAST_SUCCESS_MILLIS;
}

/** Toast 状态 + 定时器（视图只读它）。 */
@ObservedV2
export class ToastController {
  @Trace text: string = '';
  /** 动作按钮文案；空串 = 没有动作（参考实现 `toast(text)` 那一支）。 */
  @Trace actionLabel: string = '';
  @Trace visible: boolean = false;

  private action: (() => void) | null = null;
  private timerId: number = -1;

  /**
   * 弹一条；`onAction` 为 null 时只显示文案（参考实现 `toast(t('undoArchive'))` 那一支：
   * 有文案、**没有**撤销按钮）。
   *
   * 时长不走参数：四个调用点都是 success 档，时长只有一个来源 `effectiveToastMillis()` ——
   * 这样"实际生效的时长"只有一个读取点，取证构建的覆盖值必然反映到界面上。
   */
  show(text: string, actionLabel: string, onAction: (() => void) | null): void {
    const millis: number = effectiveToastMillis();
    // 消费点自证（AGENTS.md）：**实际生效**的时长进 hilog，避免"以为开关生效了"。
    logger.info('toast shown: millis=' + millis.toString()
      + ' hasAction=' + (actionLabel.length > 0).toString() + ' text=' + text);
    this.cancelTimer();
    this.text = text;
    this.actionLabel = actionLabel;
    this.action = onAction;
    this.visible = true;
    this.timerId = setTimeout(() => {
      this.dismiss();
    }, millis);
  }

  /** 点动作按钮：先收起，再执行（参考实现 Snackbar 的 onPress 语义）。 */
  invokeAction(): void {
    const action: (() => void) | null = this.action;
    this.dismiss();
    if (action !== null) {
      action();
    }
  }

  /** 收起（超时或被点掉）。 */
  dismiss(): void {
    this.cancelTimer();
    this.visible = false;
    this.action = null;
    this.actionLabel = '';
  }

  private cancelTimer(): void {
    if (this.timerId !== -1) {
      clearTimeout(this.timerId);
      this.timerId = -1;
    }
  }
}

/** 底部浮层。放进页面的 Stack 里；没有 Toast 时什么都不画。 */
@Component
export struct ToastOverlay {
  controller: ToastController = new ToastController();
  @Prop isDark: boolean = false;

  private theme(): ThemeTokens {
    return resolveTheme(this.isDark);
  }

  build() {
    Column() {
      if (this.controller.visible) {
        Row() {
          Text(this.controller.text)
            .fontSize(this.theme().typography.bodyMedium.fontSize)
            .fontColor(this.theme().colors.inverseOnSurface)
            .layoutWeight(1)
            // 上限给 4 行：导出日志那条提示要带**完整路径**（两行起步），
            // 2 行会把路径截在中间；短文案本来也只占一行。
            .maxLines(4)
          if (this.controller.actionLabel.length > 0) {
            Text(this.controller.actionLabel)
              .fontSize(this.theme().typography.labelLarge.fontSize)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.theme().colors.inversePrimary)
              .margin({ left: this.theme().sizes.space3 })
              .onClick(() => {
                this.controller.invokeAction();
              })
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .padding({
          left: this.theme().sizes.contentPadding,
          right: this.theme().sizes.contentPadding,
          top: this.theme().sizes.space3,
          bottom: this.theme().sizes.space3
        })
        .backgroundColor(this.theme().colors.inverseSurface)
        .borderRadius(this.theme().sizes.space1)
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.End)
    .padding({
      left: this.theme().sizes.space3,
      right: this.theme().sizes.space3,
      bottom: this.theme().sizes.space3
    })
    // 空白处不吃触摸：列表照常可点可滑（只有 Snackbar 自己那一块拦事件）。
    .hitTestBehavior(HitTestMode.Transparent)
  }
}