/*
 * 设置 tab 自己的路由。
 *
 * 沿用既有选型：**每个 tab 一个自己的 NavPathStack**（见 features/shell/ShellTabs.ets 文件头）。
 * 设置 tab 的栈根是设置列表，压在上面的依次是几个子页：
 *   - 沉浸式设置（参考实现 SettingsStackParams.ImmersiveSettings）；
 *   - 学期选择（**复用学期切换页**，参考实现也把它挂在设置栈里）；
 *   - 文件设置（**复用文件设置页**，值/语义/持久化都归那边）；
 *   - 关于 / 帮助（参考实现 SettingsStackParams.About / Help）。
 *
 * 这些路由名与参考实现**逐字相同**（'ImmersiveSettings' / 'SemesterSelection' / 'FileSettings' /
 * 'About' / 'Help'），因为分栏的详情路由白名单（features/shell/SplitView.ets 的 DETAIL_ROUTE_NAMES）
 * 就是按这些名字判定的。
 *
 * 「隐私政策」与「导出日志」**不是子页**：前者是外链（参考实现 `Linking.openURL`），后者是就地动作。
 */

/** 沉浸式设置页。 */
export const ROUTE_IMMERSIVE_SETTINGS: string = 'ImmersiveSettings';

/** 关于页。 */
export const ROUTE_ABOUT: string = 'About';

/** 帮助与反馈页。 */
export const ROUTE_HELP: string = 'Help';

/**
 * 三个"无参数"子页的占位参数。
 *
 * 为什么给一个空壳接口：`NavPathStack.pushPath` 的 `param` 是 `Object`，ArkTS 里原始值
 * 不能当 `Object` 传（`SemesterSelectionRouteParams` 同一处置）。
 */
export interface SettingsPageParams {
  /** 进入来源（只用于日志/诊断）。 */
  source: string;
}
