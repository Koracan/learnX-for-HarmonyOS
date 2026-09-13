/*
 * 断点分栏单测：钉的是**判据**、**底栏宽度**与**迁移计划**这几件纯逻辑。
 *
 * 为什么这两件能上单测：它们与 ArkUI 无关（只有数字与字符串数组进、布尔/计划出），
 * 所以"750 边界""实测为 0 时退回退路尺寸""栈顶连续详情段怎么切"都能在 host 里逐条钉死；
 * 设备侧只承担"版式真的排成两栏"与"迁移真的发生在运行期"（见 `.scratch/splitview/evidence/`）。
 *
 * 期望值全部来自参考实现：`src/App.tsx:864-873`（判据）与 `src/components/SplitView.tsx:55-65,77-84`（白名单与迁移）。
 */

import { describe, it, expect } from '@ohos/hypium';
import {
  BottomBarLayout, DETAIL_ROUTE_NAMES, SPLIT_VIEW_BREAKPOINT_VP, SPLIT_VIEW_MASTER_WIDTH,
  SplitHeightBudget, SplitMigrationPlan, bottomBarHeight, bottomBarLayout, isSplitDetailRoute,
  masterPaneBottomReserve, resolveSplitViewActive, shouldReplaceDetailTop, splitHeightBudget,
  splitMigrationPlan
} from '../main/ets/features/shell/SplitView';
import { LIGHT_THEME } from '../main/ets/ui/theme/Tokens';

export default function splitViewTest() {
  describe('features.shell.SplitView', () => {
    it('keeps the reference constants: 750vp breakpoint and a 393vp master column', 0, () => {
      // 断点 750：spec.md:149；主栏 393：参考实现 constants/Numbers.ts:2。
      expect(SPLIT_VIEW_BREAKPOINT_VP).assertEqual(750);
      expect(SPLIT_VIEW_MASTER_WIDTH).assertEqual(393);
    });

    it('enters split view only at >=750vp in landscape (measured size wins)', 0, () => {
      // 达断点 + 横向 → 双栏
      expect(resolveSplitViewActive(1440, 960, 1440, 960)).assertTrue();
      // 恰好 750 是**含**的（参考实现是 >=750）
      expect(resolveSplitViewActive(750, 400, 0, 0)).assertTrue();
      // 差 1vp → 单栏
      expect(resolveSplitViewActive(749, 400, 0, 0)).assertFalse();
      // 够宽但竖屏 → 单栏（MatePad 竖屏 960x1440 走这一支）
      expect(resolveSplitViewActive(960, 1440, 0, 0)).assertFalse();
      // 电话竖屏 → 单栏
      expect(resolveSplitViewActive(440, 952, 0, 0)).assertFalse();
    });

    it('falls back to window size when the root layout has not been measured', 0, () => {
      // 未测到尺寸（0x0）→ 用退路比对横竖与断点
      expect(resolveSplitViewActive(0, 0, 1440, 960)).assertTrue();
      expect(resolveSplitViewActive(0, 0, 960, 1440)).assertFalse();
      // 只测到宽度、没测到高度 → 高度那一半退回退路（App.tsx:869-872 的三元）
      expect(resolveSplitViewActive(1440, 0, 1440, 960)).assertTrue();
      expect(resolveSplitViewActive(1440, 0, 1440, 1600)).assertFalse();
      // 退路自己也小于断点 → 单栏
      expect(resolveSplitViewActive(0, 0, 440, 952)).assertFalse();
    });

    it('lays out the bottom tab bar per split view and master visibility', 0, () => {
      // ① 单栏态：**显示**且横跨整屏（形态与改动前一致）。
      const single: BottomBarLayout = bottomBarLayout(false, false);
      expect(single.visible).assertTrue();
      expect(single.width).assertEqual('100%');
      // 边界：单栏态 + 残留的 masterHidden ⇒ 底栏**仍然可见**。
      // 隐藏的判据是 splitActive && masterHidden；只判 masterHidden 会让底栏凭空消失。
      const singleWithStaleFlag: BottomBarLayout = bottomBarLayout(false, true);
      expect(singleWithStaleFlag.visible).assertTrue();
      expect(singleWithStaleFlag.width).assertEqual('100%');
      // ② 分栏 + 主栏可见：**显示**，宽度 = 主栏宽度（底栏只挂在左栏下方；
      // 期望值就是那个既有常量 393vp，不新造宽度）。
      const split: BottomBarLayout = bottomBarLayout(true, false);
      expect(split.visible).assertTrue();
      expect(split.width).assertEqual(SPLIT_VIEW_MASTER_WIDTH);
      expect(split.width).assertEqual(393);
      // ③ 分栏 + 主栏隐藏（文件详情全屏）：**整条隐藏**（不占位），而不是横跨整屏。
      const fullscreen: BottomBarLayout = bottomBarLayout(true, true);
      expect(fullscreen.visible).assertFalse();
      // ② 与 ① 的宽度必须不同，否则"只在分栏态收敛"会静默失效。
      expect(split.width === single.width).assertFalse();
      // ③ 与 ① 的可见性必须不同，否则"全屏时隐藏底栏"会静默失效。
      expect(fullscreen.visible === single.visible).assertFalse();
    });

    it('splits the height budget so the right pane gets the whole screen', 0, () => {
      // barH 的**唯一**来源：主题令牌 controlHeight(40) + space4(16)，原先藏在 ShellTabs 的私有方法里。
      const barH: number = bottomBarHeight(LIGHT_THEME);
      expect(barH).assertEqual(56);

      // 平板横屏实测 2880x1920px @密度2 ⇒ 960vp 高（应用渲染区更矮，这里只钉算术）。
      const screenH: number = 960;

      // ① 单栏：底栏在壳层流内 ⇒ 壳层内容区底部留 barH、页面主栏不再预留。
      const single: SplitHeightBudget = splitHeightBudget(false, false, screenH, barH);
      expect(single.barVisible).assertTrue();
      expect(single.barWidth).assertEqual('100%');
      expect(single.shellContentBottomInset).assertEqual(barH);
      expect(single.barMarginTop).assertEqual(0);
      expect(single.masterPaneBottomInset).assertEqual(0);
      expect(single.masterContentHeight).assertEqual(screenH - barH);
      // 单栏不渲染右栏，详情高度取与主栏相同（不出现「右栏比主栏高」这种无意义的数）。
      expect(single.detailContentHeight).assertEqual(screenH - barH);

      // ①' 单栏 + 残留 masterHidden ⇒ 与单栏逐值相同（底栏不会凭空消失，也不会凭空浮起）。
      const singleStale: SplitHeightBudget = splitHeightBudget(false, true, screenH, barH);
      expect(singleStale.barVisible).assertTrue();
      expect(singleStale.shellContentBottomInset).assertEqual(single.shellContentBottomInset);
      expect(singleStale.barMarginTop).assertEqual(0);
      expect(singleStale.masterPaneBottomInset).assertEqual(0);
      expect(singleStale.masterContentHeight).assertEqual(single.masterContentHeight);

      // ② 分栏 + 主栏可见：壳层内容区拿满整屏（shellContentBottomInset=0，底栏浮起 −barH），
      //    主栏自己让出 barH ⇒ **详情拿到整屏高**（这就是本 ticket 的要害）。
      const split: SplitHeightBudget = splitHeightBudget(true, false, screenH, barH);
      expect(split.barVisible).assertTrue();
      expect(split.barWidth).assertEqual(SPLIT_VIEW_MASTER_WIDTH);
      expect(split.shellContentBottomInset).assertEqual(0);
      expect(split.barMarginTop).assertEqual(-barH);
      expect(split.masterPaneBottomInset).assertEqual(barH);
      // 主栏内容仍只到 屏高 − barH（底栏可见时两条路必须走到同一个数：不被底栏遮）。
      expect(split.masterContentHeight).assertEqual(screenH - barH);
      expect(split.detailContentHeight).assertEqual(screenH);
      // 改动前的旧行为对照：右栏只有 屏高 − barH（下方那条 barH 高的带子是空的）。
      expect(split.detailContentHeight > screenH - barH).assertTrue();

      // ③ 分栏 + 主栏隐藏（文件详情全屏）：底栏不占位，两个 inset 都是 0，整屏让给详情。
      const fullscreen: SplitHeightBudget = splitHeightBudget(true, true, screenH, barH);
      expect(fullscreen.barVisible).assertFalse();
      expect(fullscreen.shellContentBottomInset).assertEqual(0);
      expect(fullscreen.masterPaneBottomInset).assertEqual(0);
      expect(fullscreen.masterContentHeight).assertEqual(screenH);
      expect(fullscreen.detailContentHeight).assertEqual(screenH);

      // 边界：屏高比 barH 还小 ⇒ 两个高度夹到 0，不出现负高度。
      const tiny: SplitHeightBudget = splitHeightBudget(false, false, 40, barH);
      expect(tiny.masterContentHeight).assertEqual(0);
      const tinySplit: SplitHeightBudget = splitHeightBudget(true, false, 40, barH);
      expect(tinySplit.masterContentHeight).assertEqual(0);
      expect(tinySplit.detailContentHeight).assertEqual(40);
      // 恰好等于 barH：内容区高 0，不是负数。
      expect(splitHeightBudget(false, false, barH, barH).masterContentHeight).assertEqual(0);
      // 屏高为 0（首帧还没量到尺寸）⇒ 夹到 0，不炸。
      const unmeasured: SplitHeightBudget = splitHeightBudget(true, false, 0, barH);
      expect(unmeasured.masterContentHeight).assertEqual(0);
      expect(unmeasured.detailContentHeight).assertEqual(0);

      // 不变量（跨三档）：两个 inset 互补，且底栏可见时主栏内容高度恒为 屏高 − barH。
      const all: SplitHeightBudget[] = [single, singleStale, split, fullscreen];
      for (let i = 0; i < all.length; i++) {
        const b: SplitHeightBudget = all[i];
        const reserved: number = b.barVisible ? barH : 0;
        expect(b.masterPaneBottomInset + b.shellContentBottomInset).assertEqual(reserved);
        expect(b.barMarginTop).assertEqual(b.shellContentBottomInset - barH);
        expect(b.masterContentHeight).assertEqual(Math.max(0, screenH - reserved));
      }
    });

    it('has one source for the master pane reserve: pages and shell agree', 0, () => {
      // C.2 的钉法：五个页面各自调用 masterPaneBottomReserve(theme, split, hidden)，
      // 壳层调用 splitHeightBudget(...).masterPaneBottomInset —— 两者必须同值。
      // 谁把 barH 或预留量另算一遍（或只改了一边），这条会先失败。
      const barH: number = bottomBarHeight(LIGHT_THEME);
      const cases: boolean[][] = [[false, false], [false, true], [true, false], [true, true]];
      for (let i = 0; i < cases.length; i++) {
        const split: boolean = cases[i][0];
        const hidden: boolean = cases[i][1];
        const fromShell: number =
          splitHeightBudget(split, hidden, 960, barH).masterPaneBottomInset;
        const fromPage: number = masterPaneBottomReserve(LIGHT_THEME, split, hidden);
        expect(fromPage).assertEqual(fromShell);
      }
      // 只有「分栏 + 底栏可见」这一档要留，其余三档一律 0。
      expect(masterPaneBottomReserve(LIGHT_THEME, true, false)).assertEqual(barH);
      expect(masterPaneBottomReserve(LIGHT_THEME, true, true)).assertEqual(0);
      expect(masterPaneBottomReserve(LIGHT_THEME, false, false)).assertEqual(0);
      expect(masterPaneBottomReserve(LIGHT_THEME, false, true)).assertEqual(0);
    });
    it('recognises the reference whitelist plus the immersive settings page', 0, () => {
      // 参考实现 SplitView.tsx:55-65 是九条；**后来补了第十条** ImmersiveSettings
      // （白名单里其余四个设置子页都在、唯独漏了它）。
      const expected: string[] = [
        'NoticeDetail', 'AssignmentDetail', 'FileDetail', 'CourseDetail',
        'AssignmentSubmission', 'SemesterSelection', 'FileSettings', 'About', 'Help',
        'ImmersiveSettings'
      ];
      expect(DETAIL_ROUTE_NAMES.length).assertEqual(10);
      for (let i = 0; i < expected.length; i++) {
        expect(isSplitDetailRoute(expected[i])).assertTrue();
        expect(DETAIL_ROUTE_NAMES[i]).assertEqual(expected[i]);
      }
      // 列表页路由名不是详情
      expect(isSplitDetailRoute('Notices')).assertFalse();
      expect(isSplitDetailRoute('MainTab')).assertFalse();
      expect(isSplitDetailRoute('')).assertFalse();
    });

    it('migrates the consecutive detail segment on top of the master stack', 0, () => {
      // 空栈（停在列表页）→ 没有可迁的
      const empty: SplitMigrationPlan = splitMigrationPlan([]);
      expect(empty.keepCount).assertEqual(0);
      expect(empty.detailNames.length).assertEqual(0);

      // 栈顶一条详情
      const one: SplitMigrationPlan = splitMigrationPlan(['NoticeDetail']);
      expect(one.keepCount).assertEqual(0);
      expect(one.detailNames.length).assertEqual(1);
      expect(one.detailNames[0]).assertEqual('NoticeDetail');

      // 课程详情 → 文件详情：整段都迁，且**自底向顶**保序（否则右栏的返回会乱）
      const chain: SplitMigrationPlan = splitMigrationPlan(['CourseDetail', 'FileDetail']);
      expect(chain.keepCount).assertEqual(0);
      expect(chain.detailNames.length).assertEqual(2);
      expect(chain.detailNames[0]).assertEqual('CourseDetail');
      expect(chain.detailNames[1]).assertEqual('FileDetail');

      // 非详情路由之下有详情：只迁栈顶连续的那一段，下面那条留在主栈
      const mixed: SplitMigrationPlan = splitMigrationPlan(['Notices', 'NoticeDetail']);
      expect(mixed.keepCount).assertEqual(1);
      expect(mixed.detailNames.length).assertEqual(1);
      expect(mixed.detailNames[0]).assertEqual('NoticeDetail');

      // 栈顶不是详情 → 一条都不迁
      const none: SplitMigrationPlan = splitMigrationPlan(['Notices']);
      expect(none.keepCount).assertEqual(1);
      expect(none.detailNames.length).assertEqual(0);
    });

    it('replaces the detail top instead of popping and pushing a duplicate', 0, () => {
      // 回归保护（2026-09-13）：分栏下点另一条列表项时，右栏栈顶仍是**同名**详情路由。
      // 当时用 `pop(false)` + `pushPath()` 两步实现 —— 同一次同步块里 ArkUI 会把两次栈变更合并，
      // 目的地不重建（详情页 `aboutToAppear` 不再执行）⇒ 右栏停在**第一条**的陈旧内容。
      // 现在改为单次原子 `replacePath`；这里钉住"什么时候该替换"这个决策，
      // 将来若有人改回 pop+push 的写法，这条断言会先失败。
      expect(shouldReplaceDetailTop(['AssignmentDetail'], 'AssignmentDetail')).assertTrue();
      // 栈空 → 没有可替换的，走 push
      expect(shouldReplaceDetailTop([], 'AssignmentDetail')).assertFalse();
      // 栈顶是**别的**路由 → 走 push（保留上一级详情）
      expect(shouldReplaceDetailTop(['AssignmentDetail'], 'FileDetail')).assertFalse();
      // 只有**栈顶**同名才算：同名的那条在下面时仍然走 push
      expect(shouldReplaceDetailTop(['CourseDetail', 'FileDetail'], 'CourseDetail')).assertFalse();
      // 多级详情链：栈顶同名 → 替换栈顶，不动下面几级
      expect(shouldReplaceDetailTop(['CourseDetail', 'FileDetail'], 'FileDetail')).assertTrue();
    });
  });
}
