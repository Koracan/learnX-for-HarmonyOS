/*
 * 断点分栏（ticket 16）单测：钉的是**判据**与**迁移计划**这两件纯逻辑。
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
  SplitMigrationPlan, isSplitDetailRoute, resolveSplitViewActive, splitMigrationPlan
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

    it('recognises exactly the nine detail routes of the reference whitelist', 0, () => {
      const expected: string[] = [
        'NoticeDetail', 'AssignmentDetail', 'FileDetail', 'CourseDetail',
        'AssignmentSubmission', 'SemesterSelection', 'FileSettings', 'About', 'Help'
      ];
      expect(DETAIL_ROUTE_NAMES.length).assertEqual(9);
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
  });
}
