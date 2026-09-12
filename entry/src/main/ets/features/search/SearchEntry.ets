/*
 * 搜索页的**根栈入口**（ticket 15）。
 *
 * 参考实现里页头右侧那颗 search 图标做的是 `navigation.navigate('SearchStack')`
 * （`src/App.tsx:149-155`）—— 从**任何一个** tab 页的页头都能进，且搜索页是**盖在整个
 * 主壳之上**的一个根级屏幕（不是第六个 tab，底栏在它下面被盖住）。
 *
 * 本工程的对应物：ShellTabs 的根 Navigation（`features/shell/ShellTabs.ets`）+ 这里这份
 * **进程内单例**的根栈引用。为什么用模块单例：四个 tab 页都是 ShellTabs 的子组件，
 * ArkUI 没有"把祖先的 NavPathStack 通过 context 传下去"的等价物（参考实现用的是
 * `navigation.navigate` 的那个 navigation 对象）。与 `collectionFlagsStore()` 同一处置。
 */

import { Logger } from '../../core/log/Logger';
import { ROUTE_SEARCH, SearchRouteParams } from './SearchRoutes';

const logger: Logger = new Logger('features.search.entry');

let rootStack: NavPathStack | null = null;

/** ShellTabs 在 aboutToAppear 里绑定根导航栈（应用里唯一一份）。 */
export function bindSearchRootStack(stack: NavPathStack): void {
  rootStack = stack;
  logger.info('search root stack bound');
}

/** 页头右侧的 search 图标 → 打开搜索页（对应参考实现的 navigation.navigate('SearchStack')）。 */
export function openSearch(query: string): void {
  const stack: NavPathStack | null = rootStack;
  if (stack === null) {
    // 不静默：拿不到根栈时搜索页打不开，日志里必须能看见。
    logger.error('openSearch ignored: root stack not bound yet');
    return;
  }
  const params: SearchRouteParams = { query: query };
  stack.pushPath({ name: ROUTE_SEARCH, param: params });
  logger.info('search opened: query="' + query + '"');
}

/**
 * 关闭搜索页：**弹根栈**。
 *
 * 实测踩到的坑（模拟器 Pura 90，2026-09-13）：搜索页内部还有一个自己的 NavPathStack
 * （承载单栏时的详情），所以页头那颗关闭按钮**不能**弹它 —— 详情已返回时那个栈是空的，
 * pop() 什么也不做，搜索页关不掉（日志表现为 search closed 之后界面仍是搜索页），
 * 而搜索页整屏盖住了底栏，用户就出不去了。关闭动作属于**根栈**，因此放在这里。
 */
export function closeSearch(): void {
  const stack: NavPathStack | null = rootStack;
  if (stack === null) {
    logger.error('closeSearch ignored: root stack not bound yet');
    return;
  }
  stack.pop();
  logger.info('search closed');
}
