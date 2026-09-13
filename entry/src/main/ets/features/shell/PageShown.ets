/*
 * 「页面被显示」这个动作，以及页头相对时间的重算口径。
 *
 * ## 要解决的问题
 *
 * 四个列表页的页头那一行是 `updatedTimeText(fetchedAtMillis, Date.now())`，只在页面**构建那一刻**
 * 求值过一次。ArkUI 的部分更新只重跑"读了变了的那个状态变量"的更新函数，而 `Date.now()` 不是状态：
 * 切走再切回、或从后台回到前台，这一行都停在旧文本上（隔夜回来还写着"刚刚更新"）。
 *
 * 两个容易看错的点（先踩过）：
 *   - `onPageShow` 是 `@Entry` 页面级生命周期，而这四个页面是 shell 里的子组件
 *     （`TabContent(){ NoticesPage() }`），没有这个回调 —— 信号只能**从上往下**发。
 *   - 壳层自己重绘 ≠ 子页面重绘：给 `ShellTabs.activeIndex` 赋值只重绘壳层；
 *     `TabContent` 的子组件实例是持久的，它的 `build()` 不会因为切 tab 而重跑。
 *
 * ## 契约（**只有一处实现**，四个列表页共用）
 *
 *   - `PAGE_SHOWN_AT_KEY`：AppStorage 键，值是**最近一次"页面被显示"的时刻**（毫秒）。
 *   - `markPageShown(source)`：这个动作的唯一实现（也是唯一写这个键的地方）。
 *     两个触发源都汇进它：切 tab（`ShellTabs` 的底栏点击与 `Tabs.onChange`）、
 *     回到前台（`EntryAbility.onForeground`）。
 *   - `pageHeaderUpdatedText(fetchedAtMillis, pageShownAtMillis)`：页头那一行文本的唯一实现。
 *     四个页面各自只订阅同一个键、把两个数传进来，不各写一套。
 *
 * ## 为什么页面的时间基准取"显示时刻"而不是求值那一刻
 *
 * 这一行回答的是"我进这个页面时，数据是多久以前更新的"，所以基准就是页面被显示的那一刻；
 * 键一变，订阅它的页面就用新基准重算这一行。这**不是**定时器：没有心跳，
 * 只在被显示时算一次 —— 要的是"页面被显示时重算"，不是"持续刷新"。
 *
 * 下拉刷新会把 `fetchedAtMillis` 推到当下 ⇒ 差值 0 或负数 ⇒ 仍落在"刚刚更新"一档，
 * 观感与改动前一致。
 */
import { Logger } from '../../core/log/Logger';
import { updatedTimeText } from '../../ui/components/UpdatedTime';

const logger: Logger = new Logger('features.shell.pageshown');

/** AppStorage：最近一次「页面被显示」的时刻（毫秒）。 */
export const PAGE_SHOWN_AT_KEY: string = 'lohPageShownAtMillis';

/** 最近一次「页面被显示」的时刻；从没有过时为 0。 */
export function pageShownAt(): number {
  const current: number | undefined = AppStorage.get<number>(PAGE_SHOWN_AT_KEY);
  return current === undefined ? 0 : current;
}

/**
 * 动作：**页面被显示**。
 *
 * 写一次时间戳就够 —— 订阅 `PAGE_SHOWN_AT_KEY` 的页面会据此重算自己页头的那一行。
 * 重复调用无害（底栏点击与 `Tabs.onChange` 可能都会走到），只是多一次重算。
 *
 * `previousAt` 进日志是为了让取证能分辨"动作没被触发"与"触发了但界面没重算"。
 */
export function markPageShown(source: string): void {
  const previous: number = pageShownAt();
  const at: number = Date.now();
  AppStorage.setOrCreate(PAGE_SHOWN_AT_KEY, at);
  logger.info('page shown: source=' + source
    + ' at=' + at.toString()
    + ' previousAt=' + previous.toString());
}

/**
 * 页头相对时间的**时间基准**：页面被显示的那一刻；还没有过任何"显示"时退回当下。
 *
 * 退回分支覆盖预览器 / host 单测这类不会走 `markPageShown` 的环境。
 */
export function pageShownTimeBasis(shownAtMillis: number): number {
  return shownAtMillis > 0 ? shownAtMillis : Date.now();
}

/**
 * 页头那一行时间文本 —— **四个列表页唯一的实现**。
 *
 * 页面侧只剩一行：`pageHeaderUpdatedText(this.store.fetchedAtMillis, this.pageShownAtMillis)`。
 * 对 `this.pageShownAtMillis` 的读取必须发生在**产出这一行文本的表达式里**（不能挪进
 * `@Watch` 回调、也不能挪进 build 里的 `if`）：ArkUI 按"更新函数执行时读了哪些状态变量"
 * 登记依赖，读在别处这一行就不会跟着重算 —— 这正是改动前时间会冻住的原因。
 */
export function pageHeaderUpdatedText(fetchedAtMillis: number, pageShownAtMillis: number): string {
  return updatedTimeText(fetchedAtMillis, pageShownTimeBasis(pageShownAtMillis));
}
