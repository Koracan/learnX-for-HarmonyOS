/*
 * 「页面被显示 → 页头相对时间重算」里**可以单测的部分**。
 *
 * 钉的是外部行为：给定 (快照抓取时刻, 页面显示时刻) → 页头那一行落在哪一档；
 * 以及动作真的把"显示时刻"写进了 AppStorage。**不**断言"UI 重绘了" —— 那只有设备能给答案。
 * 四档边界本身仍由 UpdatedTime.test.ets 钉住，这里不重复那些边界，只钉**新的时间基准入口**。
 *
 * 文案断言走的是**未绑定 provider** 的全局 i18nService（KeyEchoStringProvider 原样回键），
 * 与 UpdatedTime.test.ets 同一口径。
 */
import { describe, it, expect } from '@ohos/hypium';
import {
  markPageShown, pageHeaderUpdatedText, pageShownAt, pageShownTimeBasis
} from '../main/ets/features/shell/PageShown';

const SECOND: number = 1000;
const MINUTE: number = 60000;
const HOUR: number = 3600000;
const DAY: number = 86400000;

export default function pageShownTest() {
  describe('features.shell.PageShown', () => {
    it('uses the shown moment as the time basis, and now when there is none', 0, () => {
      const shownAt: number = 1789192225900;
      expect(pageShownTimeBasis(shownAt)).assertEqual(shownAt);
      // 还没有过任何"显示"（预览器 / 首次求值之前）：退回当下，绝不能算出"未来时间"。
      expect(pageShownTimeBasis(0) > 0).assertTrue();
    });

    it('recomputes the header line against the shown moment', 0, () => {
      const fetchedAt: number = 1789192225900;
      // 进页面时数据是 30 秒前抓的 → 刚刚；同一份数据在两分钟后重新显示 → 分钟档。
      const firstShow: number = fetchedAt + 30 * SECOND;
      const secondShow: number = fetchedAt + 2 * MINUTE;
      expect(pageHeaderUpdatedText(fetchedAt, firstShow)).assertEqual('ui_updated_just_now');
      expect(pageHeaderUpdatedText(fetchedAt, secondShow)).assertEqual('ui_updated_minutes_ago');
      // 同一份快照 + 不同的时间基准 ⇒ 文本必须不同。这就是"不再冻结"的可单测形式。
      expect(pageHeaderUpdatedText(fetchedAt, secondShow)
        === pageHeaderUpdatedText(fetchedAt, firstShow)).assertFalse();
      // 四档措辞仍走既有键（这里钉"页面入口也走同一套"）。
      expect(pageHeaderUpdatedText(fetchedAt, fetchedAt + 5 * HOUR)).assertEqual('ui_updated_hours_ago');
      expect(pageHeaderUpdatedText(fetchedAt, fetchedAt + 3 * DAY)).assertEqual('ui_updated_days_ago');
      // 还没有快照 → 空串（调用方据此不渲染这一行）。
      expect(pageHeaderUpdatedText(0, secondShow)).assertEqual('');
      // 下拉刷新把抓取时刻推到当下 ⇒ 差值为 0 / 负数，仍落在"刚刚更新"一档。
      expect(pageHeaderUpdatedText(secondShow, secondShow)).assertEqual('ui_updated_just_now');
      expect(pageHeaderUpdatedText(secondShow + MINUTE, secondShow)).assertEqual('ui_updated_just_now');
    });

    it('advances the stored page-shown moment', 0, () => {
      const before: number = pageShownAt();
      markPageShown('unit-test');
      const after: number = pageShownAt();
      expect(after > 0).assertTrue();
      expect(after >= before).assertTrue();
    });
  });
}
