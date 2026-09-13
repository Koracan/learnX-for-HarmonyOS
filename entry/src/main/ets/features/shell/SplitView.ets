/*
 * 断点分栏（ticket 16）：常量、**纯判据**、路由迁移计划，以及三处共享的迁移助手。
 *
 * ## 与参考实现的对应关系（逐条给行号，便于复核）
 *
 * | 项 | 参考实现 | 这里 |
 * | --- | --- | --- |
 * | 断点判据 | `showDetail = showMain && effectiveWidth >= 750 && isLandscape`（`src/App.tsx:873`） | `resolveSplitViewActive()`；`showMain`（登录态）在本工程由"ShellTabs 只在登录后渲染"承担 |
 * | 尺寸来源 | 根布局 `onLayout` 实测，`measuredWidth > 0` 才信实测、否则退回 window/frame（`App.tsx:864-872`） | ShellTabs 的 `onAreaChange` 实测 + `display` 退路，判据在同一函数里 |
 * | 主栏宽度 | `splitViewMasterWidth = 393`（`src/constants/Numbers.ts:2`，`SplitView.tsx:149` 用它） | `SPLIT_VIEW_MASTER_WIDTH` |
 * | 分隔线 | `Divider` 1px、100% 高（`SplitView.tsx:123,157-160`） | `SPLIT_VIEW_DIVIDER_WIDTH` + `Divider().vertical(true)` |
 * | 迁移延迟 | 进分栏时把详情路由迁到右栏，`setTimeout(…, 100)`（`SplitView.tsx:69-76`） | `SPLIT_VIEW_MIGRATION_DELAY_MS` |
 * | 详情路由白名单 | 9 条（`SplitView.tsx:55-65`） | `DETAIL_ROUTE_NAMES` |
 * | 主栏隐藏开关 | `showMaster`（`SplitView.tsx:40,106,117`），由文件详情的全屏按钮翻转（`FileDetail.tsx:108-113`） | `SPLIT_VIEW_MASTER_HIDDEN_KEY`（AppStorage，全局一份，与参考实现的 Provider 同粒度） |
 *
 * ## 为什么是"两个 NavPathStack"而不是 ArkUI 的 Navigation Split 模式
 *
 * 参考实现是**两个独立的导航容器**（`App.tsx:885-896`：主 `NavigationContainer` 与
 * `NavigationIndependentTree` 里的详情 `NavigationContainer`），不是某个现成的主从组件。
 * 本工程每个 tab 已经各有一个 `Navigation + NavPathStack`（选型见 `features/shell/ShellTabs.ets`
 * 文件头），所以同构的翻法是**每个 tab 再加一个详情栈**：左=列表栈，右=详情栈。
 *
 * ## 有意偏离参考实现的一处
 *
 * 参考实现只在**进分栏**时迁移（`!lastSplitEnabled.current`），**退出分栏时把详情留在右栏、
 * 左栏停在列表** ⇒ 竖屏回退会把正在看的详情丢掉。本 ticket 验收第 3 条要求
 * "旋转 / 缩放窗口时正在浏览的详情不丢、不重复请求"，所以这里补上**对称的回迁**
 * （`migrateDetailRoutesBack`），并把迁移粒度从"栈顶一条"放宽到"栈顶连续的详情段"，
 * 以免回迁后右侧返回落到空白。理由与替代验收标准见该条。
 */
import { Logger } from '../../core/log/Logger';

const logger: Logger = new Logger('features.shell.split');

/** 断点：**≥750vp 且横向**才进双栏。出处 `spec.md:149`；参考实现 `App.tsx:873`。 */
export const SPLIT_VIEW_BREAKPOINT_VP: number = 750;

/** 主栏定宽 393vp。出处 参考实现 `src/constants/Numbers.ts:2` 的 `splitViewMasterWidth`。 */
export const SPLIT_VIEW_MASTER_WIDTH: number = 393;

/** 主栏与详情之间的分隔线宽度。出处 `SplitView.tsx:157-160`（`width: 1`）。 */
export const SPLIT_VIEW_DIVIDER_WIDTH: number = 1;

/** 进分栏时等右栏导航容器挂载的延迟。出处 `SplitView.tsx:69-76`（100ms）。 */
export const SPLIT_VIEW_MIGRATION_DELAY_MS: number = 100;

/** AppStorage：最近一次实测的渲染区尺寸（vp），只用于日志/诊断。 */
export const SPLIT_VIEW_WIDTH_KEY: string = 'lohSplitViewWidthVp';
export const SPLIT_VIEW_HEIGHT_KEY: string = 'lohSplitViewHeightVp';

/** AppStorage：**双栏开关**（判据的唯一产物；每个 tab 页订阅它决定版式）。 */
export const SPLIT_VIEW_ACTIVE_KEY: string = 'lohSplitViewActive';

/**
 * AppStorage：主栏是否被隐藏（参考实现的 `showMaster` 取反）。
 * 全局一份，与参考实现放在 `SplitViewProvider` 里的粒度一致（`SplitView.tsx:40`）。
 */
export const SPLIT_VIEW_MASTER_HIDDEN_KEY: string = 'lohSplitViewMasterHidden';

/**
 * 详情路由白名单（**逐字**抄参考实现 `SplitView.tsx:55-65` 的九条 + **本工程补的第 10 条**）。
 *
 * 它的用途只有一个：判断主栈栈顶那段是不是"详情"，从而决定要不要迁到右栏。
 * 本工程的路由名与参考实现同名同义（见各 tab 目录下的 `*Routes.ets`）。
 *
 * **补的那一条：`ImmersiveSettings`**（ticket 17）。参考实现的白名单里有其余四个设置子页
 * （`SemesterSelection` / `FileSettings` / `About` / `Help`），唯独漏了沉浸式设置页 ——
 * 后果是"平板横屏下从设置页点进沉浸式 → 再旋转一次 → 该页被留在 393vp 的左栏"。
 * 本工程把这一条补齐。
 */
export const DETAIL_ROUTE_NAMES: string[] = [
  'NoticeDetail',
  'AssignmentDetail',
  'FileDetail',
  'CourseDetail',
  'AssignmentSubmission',
  'SemesterSelection',
  'FileSettings',
  'About',
  'Help',
  'ImmersiveSettings'
];

/** 这条路由名是不是"详情"（白名单判定）。 */
export function isSplitDetailRoute(name: string): boolean {
  return DETAIL_ROUTE_NAMES.includes(name);
}

/**
 * 双栏判据 —— **`App.tsx:864-873` 的逐行翻译**。
 *
 * `measuredWidth > 0` 才信实测尺寸（旋转时实测跟真实渲染区），否则退回窗口/屏幕尺寸；
 * 横竖比对同样优先用实测的两个分量。**不**在这里做"是否登录"的判断：
 * 本工程的 ShellTabs 只在登录后渲染（`showMain` 那一项由结构承担）。
 */
export function resolveSplitViewActive(measuredWidth: number, measuredHeight: number,
  fallbackWidth: number, fallbackHeight: number): boolean {
  const hasMeasuredWidth: boolean = measuredWidth > 0;
  const effectiveWidth: number = hasMeasuredWidth ? measuredWidth : fallbackWidth;
  const isLandscape: boolean = (measuredWidth > 0 && measuredHeight > 0)
    ? measuredWidth > measuredHeight
    : fallbackWidth > fallbackHeight;
  return effectiveWidth >= SPLIT_VIEW_BREAKPOINT_VP && isLandscape;
}

/**
 * 底栏宽度：**分栏态取主栏宽度**（"底栏只占主栏"），**单栏态铺满整屏**（`'100%'`）。
 *
 * 判据复用既有的分栏开关（`SPLIT_VIEW_ACTIVE_KEY` 那一个布尔），**不新造断点**：
 * 底栏与主栏同宽，右栏的详情就不会被一条横跨整屏的底栏割断。
 *
 * 抽成纯函数（而不是把三元写在组件里）是为了把两个分支钉进单测：本机模拟器不能旋转、
 * 不能缩放窗口，平板恒为横屏 ⇒ **单栏态在平板上排不出来**，只能靠单测覆盖。
 * 返回 `string | number`（`'100%'` 或 vp 数）而不引 ArkUI 的 `Length`，是为了让它
 * 在 host 侧单测里也能编译（本模块的其它纯函数同样不依赖 ArkUI 类型）。
 */
export function bottomBarWidth(splitActive: boolean): string | number {
  return splitActive ? SPLIT_VIEW_MASTER_WIDTH : '100%';
}

/** 迁移计划：主栈里"栈顶连续的详情段"要从第几条开始搬。 */
export interface SplitMigrationPlan {
  /** 主栈里**保留**的路由条数（详情段之前的那些）。 */
  keepCount: number;
  /** 要搬到右栏的详情路由名，**自底向顶**排列。 */
  detailNames: string[];
}

/**
 * 从栈底到栈顶的路由名 → 迁移计划。
 *
 * `getAllPathName()` 只含 `pushPath` 进去的路由（根内容不在里面），所以正常情形下
 * 主栈要么是空的、要么整段都是详情：`keepCount` 因此通常是 0。
 * 写成"从栈顶往下数连续详情段"是为了同时覆盖"列表也是一条路由"的未来情形。
 */
export function splitMigrationPlan(pathNames: string[]): SplitMigrationPlan {
  let keepCount: number = pathNames.length;
  while (keepCount > 0 && isSplitDetailRoute(pathNames[keepCount - 1])) {
    keepCount--;
  }
  const detailNames: string[] = [];
  for (let i = keepCount; i < pathNames.length; i++) {
    detailNames.push(pathNames[i]);
  }
  return { keepCount: keepCount, detailNames: detailNames };
}

/**
 * 进分栏：把主栈上的详情段搬到右栏，左栏逐级回到列表根（`SplitView.tsx:77-84` 的等价物）。
 *
 * 左栏的 `pop` 是**同步**的（主栏导航一直在树上）；右栏的 `push` 延后
 * `SPLIT_VIEW_MIGRATION_DELAY_MS`，因为右栏的 `Navigation` 是这一刻才挂上去的。
 * 返回搬走的条数（0 = 本来就在列表页，无需迁移）。
 */
export function migrateDetailRoutesInto(master: NavPathStack, detail: NavPathStack): number {
  const names: string[] = master.getAllPathName();
  const plan: SplitMigrationPlan = splitMigrationPlan(names);
  if (plan.detailNames.length === 0) {
    return 0;
  }
  const params: Object[] = [];
  for (let i = plan.keepCount; i < names.length; i++) {
    params.push(master.getParamByIndex(i) as Object);
  }
  if (plan.keepCount === 0) {
    master.clear(false);
  } else {
    master.popToIndex(plan.keepCount - 1, false);
  }
  const pendingNames: string[] = plan.detailNames;
  setTimeout(() => {
    for (let i = 0; i < pendingNames.length; i++) {
      detail.pushPath({ name: pendingNames[i], param: params[i] }, false);
    }
  }, SPLIT_VIEW_MIGRATION_DELAY_MS);
  return pendingNames.length;
}

/**
 * 退出分栏：把右栏的详情整段搬回主栈（本工程对参考实现的**补做**）。
 *
 * 主栏导航一直在树上，所以这里可以同步做完；不这样做的话，竖屏（单栏）会只剩列表，
 * 正在浏览的详情就丢了（参考实现 `splitEnabled=false` 时只渲染 masterChild，正是这个后果）。
 */
export function migrateDetailRoutesBack(detail: NavPathStack, master: NavPathStack): number {
  const names: string[] = detail.getAllPathName();
  if (names.length === 0) {
    return 0;
  }
  const params: Object[] = [];
  for (let i = 0; i < names.length; i++) {
    params.push(detail.getParamByIndex(i) as Object);
  }
  detail.clear(false);
  for (let i = 0; i < names.length; i++) {
    master.pushPath({ name: names[i], param: params[i] }, false);
  }
  return names.length;
}

/**
 * 列表项点击 → 打开详情。
 *
 * 单栏：照 ticket 03/04 的做法压到本 tab 的**主栈**上（行为一字未改）。
 * 分栏：压到**右栏**的详情栈；若右栏栈顶已是**同名**路由，则用 `replacePath` **原子替换**
 * （参考实现是 `detailNavigatorRef.current.navigate(name, params)`，react-navigation 对栈顶同名路由
 * 是“换参数、不再压栈”——这里对齐这个可观察行为）。
 *
 * 【2026-09-13 修一个真机+模拟器共有的缺陷】原实现是 `pop(false)` 之后紧接着 `pushPath`
 * —— 两步在**同一个同步块**里，ArkUI 把两次栈变更合并处理，弹出通知被吞掉，
 * `pushPath` 之后栈内容与原来等价 ⇒ **已有的 `NavDestination` 不会重建**
 * ⇒ 详情页的 `aboutToAppear` 不再执行、页面持有的是**第一次**的 `param`。
 * 可观察表现（ticket 18 真机复验发现，统筹在模拟器平板上独立复现）：
 *   第 1 次点列表项 → `tapped` + `detail appear`，右栏正确；
 *   第 2 次点**另一条** → **只有 `tapped`、没有 `detail appear`**，右栏仍显示第一条；
 *   连带后果：右栏页面持有的陈旧对象会让**提交入口按上一条作业的截止时间**判定。
/**
 * 右栏栈顶已是同名路由时，应当**替换**而不是“先弹再压”。
 *
 * 抽成纯函数的目的：把“用哪个导航调用”这个**决策**钉进单测（`SplitView.test.ets`），
 * 因为踩过的那个坑正是“决策看起来对、实现却静默失效”：
 * `pop(false)` 紧跟 `pushPath()` 在同一个同步块里会被 ArkUI 合并处理，目的地不重建（详见下面 `pushDetailFromMaster` 的说明）。
 *
 * 参考实现对应物：react-navigation 的 `navigate(name, params)` 对栈顶同名路由是“换参数、不再压栈”。
 */
export function shouldReplaceDetailTop(detailNames: string[], name: string): boolean {
  return detailNames.length > 0 && detailNames[detailNames.length - 1] === name;
}

/**
 * 列表项点击 → 打开详情。
 *
 * 单栏：照 ticket 03/04 的做法压到本 tab 的**主栈**上（行为一字未改）。
 * 分栏：压到**右栏**的详情栈；若右栏栈顶已是**同名**路由，则用 `replacePath` **原子替换**。
 *
 * 【2026-09-13 修一个真机+模拟器共有的缺陷】原实现是 `pop(false)` 之后紧接着 `pushPath` ——
 * 两步在**同一个同步块**里，ArkUI 把两次栈变更合并处理，弹出通知被吞掉，
 * `pushPath` 之后栈内容与原来等价 ⇒ **已有的 `NavDestination` 不会重建**
 * ⇒ 详情页的 `aboutToAppear` 不再执行、页面持有的是**第一次**的 `param`。
 * 可观察表现（ticket 18 真机复验发现，统筹在模拟器平板上独立复现）：
 *   第 1 次点列表项 → `tapped` + `detail appear`，右栏正确；
 *   第 2 次点**另一条** → **只有 `tapped`、没有 `detail appear`**，右栏仍显示第一条；
 *   连带后果：右栏页面持有的陈旧对象会让**提交入口按上一条作业的截止时间**判定。
 * 修法：栈顶同名时改用单次 `replacePath`（API 23 已有，见 `navigation.d.ts:1229`），
 * 它是一次原子替换 ⇒ 旧 `NavDestination` 被销毁、新页面重建并拿到新 `param`。
 */
export function pushDetailFromMaster(master: NavPathStack, detail: NavPathStack,
  split: boolean, name: string, param: Object, animated: boolean = true): void {
  if (!split) {
    master.pushPath({ name: name, param: param });
    return;
  }
  const names: string[] = detail.getAllPathName();
  if (shouldReplaceDetailTop(names, name)) {
    // 原子替换：**不要**写成 pop + pushPath（那个组合不重建目的地，见上面说明）。
    // animated 默认 true（四个 tab 页的行为一字未改）。搜索页传 false，对应参考实现
    // `Search.tsx:54-63` 给进右栏的那次 navigate 补 `disableAnimation: true`（单栏的 push 不补）。
    detail.replacePath({ name: name, param: param }, animated);
    return;
  }
  detail.pushPath({ name: name, param: param }, animated);
}
/**
 * 把判据结果写进 AppStorage（**消费点在各个 tab 页**：它们订阅 `SPLIT_VIEW_ACTIVE_KEY` 决定版式）。
 * 这里同时打一行"实际生效值"日志，取证时按消费点核对（AGENTS.md 的开关自证口径）。
 */
export function publishSplitViewDecision(measuredWidth: number, measuredHeight: number,
  fallbackWidth: number, fallbackHeight: number): boolean {
  const active: boolean = resolveSplitViewActive(measuredWidth, measuredHeight,
    fallbackWidth, fallbackHeight);
  AppStorage.setOrCreate(SPLIT_VIEW_WIDTH_KEY, Math.round(measuredWidth));
  AppStorage.setOrCreate(SPLIT_VIEW_HEIGHT_KEY, Math.round(measuredHeight));
  AppStorage.setOrCreate(SPLIT_VIEW_ACTIVE_KEY, active);
  logger.info('split view decision: active=' + active.toString()
    + ' measured=' + measuredWidth.toString() + 'x' + measuredHeight.toString()
    + ' fallback=' + fallbackWidth.toString() + 'x' + fallbackHeight.toString()
    + ' breakpoint=' + SPLIT_VIEW_BREAKPOINT_VP.toString()
    + ' masterWidth=' + SPLIT_VIEW_MASTER_WIDTH.toString());
  return active;
}
