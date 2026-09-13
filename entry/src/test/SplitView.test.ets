/*
 * 断点分栏（ticket 16）单测：钉的是**判据**、**底栏宽度**与**迁移计划**这几件纯逻辑。
 *
 * 为什么这两件能上单测：它们与 ArkUI 无关（只有数字与字符串数组进、布尔/计划出），
 * 所以"750 边界""实测为 0 时退回退路尺寸""栈顶连续详情段怎么切"都能在 host 里逐条钉死；
 * 设备侧只承担"版式真的排成两栏"与"迁移真的发生在运行期"（见 `.scratch/splitview/evidence/`）。
 *
 * 期望值全部来自参考实现：`src/App.tsx:864-873`（判据）与 `src/components/SplitView.tsx:55-65,77-84`（白名单与迁移）。
 */

import { describe, it, expect } from '@ohos/hypium';
import {
  DETAIL_ROUTE_NAMES, SPLIT_VIEW_BREAKPOINT_VP, SPLIT_VIEW_MASTER_WIDTH,
  SplitMigrationPlan, bottomBarWidth, isSplitDetailRoute, resolveSplitViewActive,
  shouldReplaceDetailTop, splitMigrationPlan
} from '../main/ets/features/shell/SplitView';

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

    it('narrows the bottom tab bar to the master column only in split view', 0, () => {
      // 分栏态：底栏与主栏同宽 —— 底栏只挂在左栏下方，右栏的详情不被它割断。
      // 期望值就是主栏那个既有常量（393vp），不新造宽度。
      expect(bottomBarWidth(true)).assertEqual(SPLIT_VIEW_MASTER_WIDTH);
      expect(bottomBarWidth(true)).assertEqual(393);
      // 单栏态：仍横跨整屏（形态与改动前一致）。
      expect(bottomBarWidth(false)).assertEqual('100%');
      // 两个分支必须不同，否则"只在分栏态收敛"这条要求会静默失效。
      expect(bottomBarWidth(true) === bottomBarWidth(false)).assertFalse();
    });

    it('recognises the reference whitelist plus the immersive settings page', 0, () => {
      // 参考实现 SplitView.tsx:55-65 是九条；**ticket 17 补了第十条** ImmersiveSettings
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
