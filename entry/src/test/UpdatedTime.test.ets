/*
 * 相对更新时间（ticket 11.5，Part B）的四档边界与文案映射。
 *
 * 分档是纯函数（`updatedTimeParts`），所以边界可以在 host 单测里逐条钉住，不需要 ICU；
 * 文案映射在**未绑定 provider** 的全局 `i18nService` 上跑，`KeyEchoStringProvider` 会把键原样返回，
 * 于是"哪一档用哪一个键"也被钉住了（设备上的实际措辞由 ticket 11.5 的截图承担）。
 */

import { describe, it, expect } from '@ohos/hypium';
import {
  UpdateAgeParts, UpdateAgeUnit, updateAgeText, updatedTimeParts, updatedTimeText
} from '../main/ets/ui/components/UpdatedTime';

const SECOND: number = 1000;
const MINUTE: number = 60000;
const HOUR: number = 3600000;
const DAY: number = 86400000;

function unitOf(elapsed: number): string {
  return updatedTimeParts(elapsed).unit;
}

function amountOf(elapsed: number): number {
  return updatedTimeParts(elapsed).amount;
}

export default function updatedTimeTest() {
  describe('ui.components.UpdatedTime', () => {
    it('buckets the four ranges at their exact boundaries', 0, () => {
      // < 1 分钟 → JUST_NOW（含 0 与 59.999s）
      expect(unitOf(0)).assertEqual(UpdateAgeUnit.JUST_NOW);
      expect(unitOf(59 * SECOND)).assertEqual(UpdateAgeUnit.JUST_NOW);
      expect(unitOf(MINUTE - 1)).assertEqual(UpdateAgeUnit.JUST_NOW);
      // 恰好 1 分钟 → 分钟档
      expect(unitOf(MINUTE)).assertEqual(UpdateAgeUnit.MINUTES);
      expect(amountOf(MINUTE)).assertEqual(1);
      expect(unitOf(59 * MINUTE + 59 * SECOND)).assertEqual(UpdateAgeUnit.MINUTES);
      expect(amountOf(59 * MINUTE + 59 * SECOND)).assertEqual(59);
      // 恰好 1 小时 → 小时档
      expect(unitOf(HOUR)).assertEqual(UpdateAgeUnit.HOURS);
      expect(amountOf(HOUR)).assertEqual(1);
      expect(unitOf(23 * HOUR + 59 * MINUTE)).assertEqual(UpdateAgeUnit.HOURS);
      expect(amountOf(23 * HOUR + 59 * MINUTE)).assertEqual(23);
      // 恰好 24 小时 → 天档
      expect(unitOf(DAY)).assertEqual(UpdateAgeUnit.DAYS);
      expect(amountOf(DAY)).assertEqual(1);
      expect(amountOf(3 * DAY + 5 * HOUR)).assertEqual(3);
    });

    it('treats an unusable or future timestamp as just-now', 0, () => {
      // 快照时间戳还没落（0 / 负数）或时钟回拨（负数 elapsed）：不显示"N 分钟后更新"这种怪话。
      expect(unitOf(-1)).assertEqual(UpdateAgeUnit.JUST_NOW);
      expect(unitOf(-5 * MINUTE)).assertEqual(UpdateAgeUnit.JUST_NOW);
      expect(unitOf(Number.NaN)).assertEqual(UpdateAgeUnit.JUST_NOW);
    });

    it('maps each bucket to its own i18n key', 0, () => {
      const justNow: UpdateAgeParts = updatedTimeParts(30 * SECOND);
      const minutes: UpdateAgeParts = updatedTimeParts(5 * MINUTE);
      const hours: UpdateAgeParts = updatedTimeParts(3 * HOUR);
      const days: UpdateAgeParts = updatedTimeParts(2 * DAY);
      expect(updateAgeText(justNow)).assertEqual('ui_updated_just_now');
      expect(updateAgeText(minutes)).assertEqual('ui_updated_minutes_ago');
      expect(updateAgeText(hours)).assertEqual('ui_updated_hours_ago');
      expect(updateAgeText(days)).assertEqual('ui_updated_days_ago');
    });

    it('renders the header line from a snapshot timestamp', 0, () => {
      const now: number = 1789192225900;
      // 还没有快照 → 空串（调用方据此不渲染这一行）。
      expect(updatedTimeText(0, now)).assertEqual('');
      expect(updatedTimeText(-1, now)).assertEqual('');
      // 30 秒前更新 → "刚刚更新"那一档的键。
      expect(updatedTimeText(now - 30 * SECOND, now)).assertEqual('ui_updated_just_now');
      // 2 分钟前 → 分钟档。
      expect(updatedTimeText(now - 2 * MINUTE, now)).assertEqual('ui_updated_minutes_ago');
      // 5 小时前 → 小时档。
      expect(updatedTimeText(now - 5 * HOUR, now)).assertEqual('ui_updated_hours_ago');
      // 3 天前 → 天档。
      expect(updatedTimeText(now - 3 * DAY, now)).assertEqual('ui_updated_days_ago');
    });
  });
}
