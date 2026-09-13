/*
 * 把"应用底色"刷到**系统栏**（状态栏 / 导航栏）以及**栏下的窗口底**——core/window。
 *
 * ## 为什么需要它
 *
 * 本工程此前从不设置系统栏配色，两个栏就用平台默认色。深色模式下平台默认给的是**纯黑**，
 * 而应用底色令牌是 `#1C1C1C` ⇒ 屏幕顶部与底部各留一条更黑的带子（设备实测：状态栏
 * y=0..135 为 `#000000`、应用内容 y=136 起为 `#1C1C1C`；底部导航条区 y≥2758 亦为 `#000000`）。
 * 浅色模式下平台默认恰好是白、与应用底色相同，所以**只有深色模式看得出来**。
 *
 * ## 两个平台调用，缺一不可
 *
 * 1. `setWindowSystemBarProperties(...)` 设四个值：
 *    - `statusBarColor` / `navigationBarColor`：两个栏的**底色**（要等于应用底色）；
 *    - `statusBarContentColor` / `navigationBarContentColor`：栏内图标与文字的颜色
 *      （要等于底色之上的**前景色**，否则深色底配深色图标 = 看不见）。
 * 2. `setWindowBackgroundColor(...)`：设**窗口底色**。
 *
 * 第 2 条是设备实测逼出来的：手势导航下底部那条"导航条"是 SystemUI 的**独立且透明**的窗口
 * （WMS 实测 `SCBGestureNavBar [0,2758,1320,98]`，而应用窗口本身已经是整屏 `[0,0,1320,2856]`），
 * 露出来的其实是**应用窗口自己的底色**——它默认是深色模式的纯黑。只设 `navigationBarColor`
 * 动不了它（平台文档：该属性配的是**三键导航栏**），底部那条带子只有靠窗口底色才填得上。
 *
 * ## 与沉浸式的分工
 *
 * `setWindowLayoutFullScreen` / `setWindowSystemBarEnable` 管"栏在不在、内容铺不铺到栏下"，
 * 本文件管"栏与窗口的底色是什么"。沉浸式开启时栏被隐藏，配色无从谈起；
 * **关闭沉浸式（栏重新出现）时必须重放一次**，否则栏会带着平台默认色回来——这条落在
 * `ImmersiveWindow.applyImmersiveToWindow` 里。
 *
 * ## 配色从哪来
 *
 * 不在这里硬编码：调用方从主题令牌取（`ui/theme/Tokens.systemBarColors`，栏底色 = 应用
 * `background`、栏内容色 = `onBackground`）。core 层只负责"把它交给平台"。
 *
 * ## 自证
 *
 * 与 `ImmersiveWindow` 同一口径：每一次应用都把请求值、两个平台调用的结果与累计次数打进
 * hilog，于是"没生效"与"没调用"能区分开。
 */

import { window } from '@kit.ArkUI';
import { Logger } from '../log/Logger';

const logger: Logger = new Logger('core.window.systembar');

/**
 * 最近一次**请求**应用的栏配色（沉浸式关闭后重放要用）。
 *
 * 成功与否都记：某一次调用可能只成功一半（实测 `setWindowBackgroundColor` 在
 * `loadContent` 完成前会报 "This window state is abnormal"），但"重放"要放的仍是
 * **最近一次请求的那份配色**，否则沉浸式一关就没人管这两个栏了。
 */
let lastBarColor: string = '';
let lastContentColor: string = '';
/** 两个平台调用**都成功**的累计次数（只用于自证）。 */
let applyCount: number = 0;

/** 自证串（打进 hilog）。 */
export function describeSystemBarTheme(): string {
  return 'system bar theme: requestedBar=' + (lastBarColor.length > 0 ? lastBarColor : '<unset>')
    + ' requestedContent=' + (lastContentColor.length > 0 ? lastContentColor : '<unset>')
    + ' fullyAppliedCount=' + applyCount.toString();
}

/** 是否至少请求过一次配色（决定"重放"值不值得做）。 */
export function hasSystemBarTheme(): boolean {
  return lastBarColor.length > 0;
}

/**
 * 把配色应用到给定窗口。**失败不抛**：返回两个平台调用是否都成功。
 *
 * 两个栏共用同一份配色：本工程两个栏都直接接应用底色（右侧内容区 / 底栏的底色也是它），
 * 没有"导航栏比状态栏更浅一档"这回事。
 */
export async function applySystemBarColors(target: window.Window, barColor: string,
  contentColor: string): Promise<boolean> {
  let barsOk: boolean = false;
  try {
    await target.setWindowSystemBarProperties({
      statusBarColor: barColor,
      statusBarContentColor: contentColor,
      navigationBarColor: barColor,
      navigationBarContentColor: contentColor
    });
    barsOk = true;
  } catch (error) {
    logger.error('setWindowSystemBarProperties failed: bar=' + barColor + ' content=' + contentColor
      + ' error=' + (error as Error).message);
  }
  let windowBackgroundOk: boolean = false;
  try {
    // 栏下露出来的那一条是窗口底色（手势导航条窗口是透明的，见文件头）。
    target.setWindowBackgroundColor(barColor);
    windowBackgroundOk = true;
  } catch (error) {
    logger.error('setWindowBackgroundColor failed: color=' + barColor
      + ' error=' + (error as Error).message);
  }
  lastBarColor = barColor;
  lastContentColor = contentColor;
  if (barsOk && windowBackgroundOk) {
    applyCount++;
  }
  // **消费点自证**：请求值 + 两个平台调用的结果 + 累计次数，一行打完。
  logger.info('apply system bar colors: bar=' + barColor + ' content=' + contentColor
    + ' barPropertiesOk=' + barsOk.toString() + ' windowBackgroundOk=' + windowBackgroundOk.toString()
    + ' ' + describeSystemBarTheme());
  return barsOk && windowBackgroundOk;
}

/**
 * 用最近一次**请求**的配色重放一次（系统栏重新出现后调用）。
 * 从来没请求过就什么都不做——不假装生效。
 */
export async function reapplySystemBarColors(target: window.Window): Promise<boolean> {
  if (!hasSystemBarTheme()) {
    logger.info('reapply system bar colors skipped: nothing applied yet; ' + describeSystemBarTheme());
    return false;
  }
  return await applySystemBarColors(target, lastBarColor, lastContentColor);
}
