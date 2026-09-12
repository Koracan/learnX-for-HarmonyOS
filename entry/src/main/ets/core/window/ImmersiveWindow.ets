/*
 * 把"沉浸式模式"落到**平台窗口**（core/window）。
 *
 * ## 参考实现的对应物
 *
 * 参考实现是 `App.tsx:682-690` 的 `ImmersiveModeController`：
 * ```ts
 * React.useEffect(() => { Immersive.setImmersive(immersiveMode); }, [immersiveMode]);
 * ```
 * 即"开关一变就应用一次"，`react-native-immersive` 在 Android 上做的是隐藏状态栏 / 导航栏。
 *
 * ## 平台侧的两个调用
 *
 *   - `setWindowLayoutFullScreen(enabled)`：窗口内容铺满整屏（是否**绘制到**系统栏之下）；
 *   - `setWindowSystemBarEnable(enabled ? [] : ['status','navigation'])`：**真正隐藏 / 恢复**状态栏与导航栏。
 *
 * 两个都调：只调前者会得到"内容铺到栏下、栏还在"的观感，只调后者则布局仍按安全区收边。
 *
 * ## 为什么要一个"实际生效值"日志
 *
 * AGENTS.md：取证开关必须**自证生效**，且要打在**消费点**。本文件的消费点就是这两个平台调用
 * 的返回值 —— `applyImmersive(...)` 每一次都会把「请求值 / 平台是否接受 / 当时的窗口状态」
 * 打进 hilog，于是"没生效"与"没调用"能区分开。
 */

import { window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { Logger } from '../log/Logger';

const logger: Logger = new Logger('core.window.immersive');

/** 应用级"最近一次实际应用的沉浸式状态"（只用于日志与自证，不参与判定）。 */
let lastApplied: boolean = false;
let applyCount: number = 0;

/** 最近一次成功应用的沉浸式状态。 */
export function lastAppliedImmersive(): boolean {
  return lastApplied;
}

/** 自证串（打进 hilog）。 */
export function describeImmersiveWindow(): string {
  return 'immersive window: lastApplied=' + lastApplied.toString()
    + ' applyCount=' + applyCount.toString();
}

/**
 * 把沉浸式状态应用到给定窗口。**失败不抛**：返回平台是否两个调用都成功。
 *
 * `setWindowSystemBarEnable` 的参数是"要**显示**的系统栏列表"，所以隐藏时传空数组。
 */
export async function applyImmersiveToWindow(target: window.Window, enabled: boolean): Promise<boolean> {
  let layoutOk: boolean = false;
  let barsOk: boolean = false;
  try {
    await target.setWindowLayoutFullScreen(enabled);
    layoutOk = true;
  } catch (error) {
    logger.error('setWindowLayoutFullScreen(' + enabled.toString() + ') failed: ' + (error as Error).message);
  }
  try {
    const bars: Array<'status' | 'navigation'> = enabled ? [] : ['status', 'navigation'];
    await target.setWindowSystemBarEnable(bars);
    barsOk = true;
  } catch (error) {
    logger.error('setWindowSystemBarEnable(' + (enabled ? 'hidden' : 'shown') + ') failed: '
      + (error as Error).message);
  }
  applyCount++;
  lastApplied = enabled;
  // **消费点自证**：请求值 + 两个平台调用的结果 + 累计次数，一行打完。
  logger.info('apply immersive: requested=' + enabled.toString()
    + ' layoutFullScreenOk=' + layoutOk.toString()
    + ' systemBarEnableOk=' + barsOk.toString()
    + ' ' + describeImmersiveWindow());
  return layoutOk && barsOk;
}

/**
 * 取当前窗口并应用沉浸式状态（界面开关与启动恢复都走这一个入口）。
 *
 * `window.getLastWindow` 需要宿主 Context；取不到窗口时**不假装生效**：落 error 日志并返回 false。
 */
export async function applyImmersiveMode(context: common.Context, enabled: boolean): Promise<boolean> {
  try {
    const target: window.Window = await window.getLastWindow(context);
    return await applyImmersiveToWindow(target, enabled);
  } catch (error) {
    logger.error('getLastWindow failed, immersive NOT applied: ' + (error as Error).message);
    return false;
  }
}
