/*
 * i18n 单测（foundation/02）
 *
 * 覆盖三块：
 *   1. 取串门面 `core/i18n`：类型化键、插值、缺失键回显、语言变化通知；
 *   2. 相对时间的**策略层**：单位阶梯、取整、`now` 判定、以及中英两套措辞
 *      （措辞通过可替换的 RelativeTimeFormatter 注入，因为本机 local 单测
 *      环境不加载 ICU —— 实测 `formatRelativeTime` 在本机返回空串，真实 ICU
 *      输出在模拟器上以截图与 hilog 取证）；
 *   3. 学期文案：移植参考实现 helpers/parse.ts 的 getSemesterTextFromId。
 *
 * 键总量的守卫用常量断言：键数变化时本测试失败，提醒同步更新
 * .scratch/foundation/i18n-key-map.md 与 scripts/gen-i18n-keys.mjs 的输出。
 */

import { describe, it, expect } from '@ohos/hypium';
import { I18nKey, I18N_KEY_COUNT, isI18nKey } from '../main/ets/core/i18n/I18nKeys';
import { I18nService, formatMessage } from '../main/ets/core/i18n/I18n';
import { StringProvider, KeyEchoStringProvider } from '../main/ets/core/i18n/StringProvider';
import {
  DateTimeFormatter, RELATIVE_TIME_LADDER, RelativeTimeFormatter, RelativeTimeParts, RelativeTimeRule, RelativeUnit,
  SemesterTextSource, describeRelativeTime, formatDateTimeUsing, formatFileSize,
  formatRelativeTimeUsing, formatRelativeTo, getSemesterTextFromId, isChineseLocale, pickRelativeUnit,
  relativeAmount, relativeTimeParts
} from '../main/ets/core/i18n/DateTimeUtil';

/** 参考实现的中英字典：180 个键（两本字典键集与顺序完全一致）。 */
const REFERENCE_KEY_COUNT: number = 180;
/** 本工程新增：学期季节词 3 个（loh_ 命名空间）。 */
const LOCAL_ADDITION_COUNT: number = 3;
/**
 * 本工程新增：原生重写 UI 文案 48 个（ui_ 命名空间）。
 * ticket 03 加了 4 个（tab/空态/刷新）；ticket 04 加了 20 个
 * （公告详情的日期模式 + 星期词表 + 月份词表，见 scripts/i18n-ui-strings.mjs）。
 */
const UI_STRING_COUNT: number = 48;
/** 迁移后的资源键总数（也是 I18N_KEY_COUNT 的期望值）。 */
const TOTAL_KEY_COUNT: number = 231;

const REFERENCE_SAMPLE: string[] = ['loh_back', 'loh_notices', 'loh_assignments', 'loh_files', 'loh_courses'];
const LOCAL_ADDITIONS: string[] = ['loh_fall', 'loh_spring', 'loh_summer'];
const UI_SAMPLES: string[] = [
  'ui_app_name', 'ui_language', 'ui_export_logs', 'ui_exported',
  'ui_notice_publish_time', 'ui_weekday_thursday', 'ui_month_sep'
];

const SECOND: number = 1000;
const MINUTE: number = 60 * SECOND;
const HOUR: number = 60 * MINUTE;
const DAY: number = 24 * HOUR;
const WEEK: number = 7 * DAY;
const MONTH: number = 30 * DAY;
const YEAR: number = 365 * DAY;

/** 假 provider：可切换语言，返回表内文案；用来验证门面而不依赖设备。 */
class FakeProvider implements StringProvider, SemesterTextSource {
  private current: string;
  private readonly table: Map<string, string>;

  constructor(locale: string, table: Map<string, string>) {
    this.current = locale;
    this.table = table;
  }

  get(key: string): string {
    const hit: string | undefined = this.table.get(key);
    return hit === undefined ? '' : hit;
  }

  locale(): string {
    return this.current;
  }

  switchTo(locale: string): void {
    this.current = locale;
  }
}

function fakeTable(): Map<string, string> {
  return new Map<string, string>([
    ['loh_ok', '确定'],
    ['loh_cancel', '取消'],
    ['loh_settings', '设置'],
    ['loh_submit_assignment', '提交作业'],
    ['loh_semester_selection', '学期切换'],
    ['loh_about', '关于'],
    ['loh_login_failed', '登录失败，请检查网络连接并确保用户电子身份服务系统的登录依旧有效'],
    ['loh_fall', '秋季学期'],
    ['loh_spring', '春季学期'],
    ['loh_summer', '夏季学期'],
    ['loh_file_pick_failed', '选取文件失败']
  ]);
}

/** 记录调用的假措辞器：证明策略层把正确的 (amount, unit) 交给了措辞层。 */
class RecordingRelativeFormatter implements RelativeTimeFormatter {
  private readonly language: string;
  readonly calls: string[] = [];

  constructor(language: string) {
    this.language = language;
  }

  format(amount: number, unit: RelativeUnit): string {
    this.calls.push(String(amount) + ':' + unit);
    const zh: boolean = this.language === 'zh';
    if (amount === 0 && unit === RelativeUnit.SECOND) {
      return zh ? '刚刚' : 'just now';
    }
    const day: boolean = unit === RelativeUnit.DAY;
    if (zh) {
      if (day && amount === -1) {
        return '昨天';
      }
      return String(Math.abs(amount)) + (day ? '天前' : '小时前');
    }
    if (day && amount === -1) {
      return 'yesterday';
    }
    return String(Math.abs(amount)) + (day ? ' days ago' : ' hours ago');
  }
}

/** 记录调用的假日期格式器。 */
class RecordingDateFormatter implements DateTimeFormatter {
  private readonly language: string;
  readonly stamps: number[] = [];

  constructor(language: string) {
    this.language = language;
  }

  format(millis: number): string {
    this.stamps.push(millis);
    return (this.language === 'zh' ? '2026/03/04 15:30' : '03/04/2026, 15:30') + '|' + String(millis);
  }
}

export default function i18nTest() {
  describe('core.i18n', () => {
    it('has a stable resource key count', 0, () => {
      expect(I18N_KEY_COUNT).assertEqual(TOTAL_KEY_COUNT);
      expect(REFERENCE_KEY_COUNT + LOCAL_ADDITION_COUNT + UI_STRING_COUNT).assertEqual(TOTAL_KEY_COUNT);
    });

    it('namespaces every migrated key with loh_ or ui_', 0, () => {
      const keys: string[] = REFERENCE_SAMPLE.concat(LOCAL_ADDITIONS, UI_SAMPLES);
      for (let i = 0; i < keys.length; i++) {
        const key: string = keys[i];
        expect(isI18nKey(key)).assertTrue();
        expect(key.startsWith('loh_') || key.startsWith('ui_')).assertTrue();
        expect(/^[a-z][a-z0-9_]*$/.test(key)).assertTrue();
      }
    });

    it('rejects unknown keys at runtime', 0, () => {
      expect(isI18nKey('loh_does_not_exist')).assertFalse();
      expect(isI18nKey('back')).assertFalse();
      expect(isI18nKey('')).assertFalse();
    });

    it('returns the key itself before a provider is bound', 0, () => {
      const service: I18nService = new I18nService();
      expect(service.isBound()).assertFalse();
      const key: I18nKey = 'loh_ok';
      expect(service.t(key)).assertEqual('loh_ok');
    });

    it('resolves typed keys through a bound provider', 0, () => {
      const service: I18nService = new I18nService();
      service.bindProvider(new FakeProvider('zh-Hans-CN', fakeTable()));
      expect(service.isBound()).assertTrue();
      expect(service.t('loh_ok')).assertEqual('确定');
      expect(service.t('loh_cancel')).assertEqual('取消');
      expect(service.t('loh_submit_assignment')).assertEqual('提交作业');
      expect(service.t('loh_file_pick_failed')).assertEqual('选取文件失败');
      expect(service.isChinese()).assertTrue();
    });

    it('returns an empty string for a missing resource via get()', 0, () => {
      const service: I18nService = new I18nService();
      service.bindProvider(new FakeProvider('en-US', fakeTable()));
      expect(service.get('loh_nope')).assertEqual('');
      expect(service.isChinese()).assertFalse();
    });

    it('notifies listeners on refresh and on rebind', 0, () => {
      const service: I18nService = new I18nService();
      const fake: FakeProvider = new FakeProvider('zh-Hans-CN', fakeTable());
      const seen: string[] = [];
      service.onLocaleChange((locale: string) => {
        seen.push(locale);
      });
      service.bindProvider(fake);
      expect(seen.length).assertEqual(1);
      expect(seen[0]).assertEqual('zh-Hans-CN');
      fake.switchTo('en-US');
      service.refresh();
      expect(seen.length).assertEqual(2);
      expect(seen[1]).assertEqual('en-US');
      service.offLocaleChange(() => {
      });
    });

    it('substitutes positional and plain placeholders', 0, () => {
      expect(formatMessage('较晚 = %1$s', ['2025-2026-2'])).assertEqual('较晚 = 2025-2026-2');
      expect(formatMessage('已导出 %1$s 条 / %2$s 字节', [12, 3456])).assertEqual('已导出 12 条 / 3456 字节');
      expect(formatMessage('later = %1$s', ['2025-2026-2'])).assertEqual('later = 2025-2026-2');
      expect(formatMessage('%s / %s', ['a', 'b'])).assertEqual('a / b');
      expect(formatMessage('no placeholder', ['x'])).assertEqual('no placeholder');
    });

    it('applies placeholders when a typed key is translated', 0, () => {
      const service: I18nService = new I18nService();
      const table: Map<string, string> = new Map<string, string>([['ui_exported', '已导出 %1$s 条 / %2$s 字节']]);
      service.bindProvider(new FakeProvider('zh-Hans-CN', table));
      expect(service.t('ui_exported', 7, 1024)).assertEqual('已导出 7 条 / 1024 字节');
    });

    it('keeps the key-echo provider honest', 0, () => {
      const echo: StringProvider = new KeyEchoStringProvider();
      expect(echo.get('loh_ok')).assertEqual('loh_ok');
      expect(echo.locale()).assertEqual('und');
    });
  });

  describe('core.i18n.DateTimeUtil', () => {
    it('exposes a largest-first unit ladder', 0, () => {
      expect(RELATIVE_TIME_LADDER.length).assertEqual(7);
      expect(RELATIVE_TIME_LADDER[0].unit).assertEqual(RelativeUnit.YEAR);
      expect(RELATIVE_TIME_LADDER[6].unit).assertEqual(RelativeUnit.SECOND);
      for (let i = 1; i < RELATIVE_TIME_LADDER.length; i++) {
        expect(RELATIVE_TIME_LADDER[i].divisorMs < RELATIVE_TIME_LADDER[i - 1].divisorMs).assertTrue();
      }
    });

    it('picks the largest unit that fits', 0, () => {
      expect(pickRelativeUnit(500).unit).assertEqual(RelativeUnit.SECOND);
      expect(pickRelativeUnit(SECOND).unit).assertEqual(RelativeUnit.SECOND);
      expect(pickRelativeUnit(MINUTE).unit).assertEqual(RelativeUnit.MINUTE);
      expect(pickRelativeUnit(HOUR).unit).assertEqual(RelativeUnit.HOUR);
      expect(pickRelativeUnit(DAY).unit).assertEqual(RelativeUnit.DAY);
      expect(pickRelativeUnit(WEEK).unit).assertEqual(RelativeUnit.WEEK);
      expect(pickRelativeUnit(MONTH).unit).assertEqual(RelativeUnit.MONTH);
      expect(pickRelativeUnit(YEAR).unit).assertEqual(RelativeUnit.YEAR);
    });

    it('rounds toward zero and keeps the sign', 0, () => {
      const rule: RelativeTimeRule = pickRelativeUnit(3 * DAY);
      expect(rule.unit).assertEqual(RelativeUnit.DAY);
      expect(relativeAmount(3 * DAY, rule)).assertEqual(3);
      expect(relativeAmount(3.9 * DAY, rule)).assertEqual(3);
      expect(relativeAmount(-3 * DAY, rule)).assertEqual(-3);
      expect(relativeAmount(-3.9 * DAY, rule)).assertEqual(-3);
    });

    it('decomposes into unit, amount and the now case', 0, () => {
      const now: RelativeTimeParts = relativeTimeParts(500);
      expect(now.isNow).assertTrue();
      expect(now.amount).assertEqual(0);
      expect(now.unit).assertEqual(RelativeUnit.SECOND);
      const past: RelativeTimeParts = relativeTimeParts(-3 * DAY);
      expect(past.isNow).assertFalse();
      expect(past.unit).assertEqual(RelativeUnit.DAY);
      expect(past.amount).assertEqual(-3);
      const future: RelativeTimeParts = relativeTimeParts(2 * HOUR);
      expect(future.amount).assertEqual(2);
      expect(future.unit).assertEqual(RelativeUnit.HOUR);
    });

    it('describes the ladder without ICU wording', 0, () => {
      expect(describeRelativeTime(500)).assertEqual('now');
      expect(describeRelativeTime(5 * SECOND)).assertEqual('future:second:5');
      expect(describeRelativeTime(-3 * DAY)).assertEqual('past:day:3');
      expect(describeRelativeTime(2 * HOUR)).assertEqual('future:hour:2');
    });

    it('hands the right amount and unit to the wording layer', 0, () => {
      const formatter: RecordingRelativeFormatter = new RecordingRelativeFormatter('en');
      formatRelativeTimeUsing(-3 * DAY, formatter);
      formatRelativeTimeUsing(2 * HOUR, formatter);
      formatRelativeTimeUsing(500, formatter);
      expect(formatter.calls.length).assertEqual(3);
      expect(formatter.calls[0]).assertEqual('-3:day');
      expect(formatter.calls[1]).assertEqual('2:hour');
      expect(formatter.calls[2]).assertEqual('0:second');
    });

    it('converts absolute timestamps to a delta before wording', 0, () => {
      const now: number = 1770000000000;
      const formatter: RecordingRelativeFormatter = new RecordingRelativeFormatter('zh');
      expect(formatRelativeTo(now - 3 * DAY, now, 'zh-Hans-CN')).assertEqual('');
      expect(formatter.calls.length).assertEqual(0);
      const zh: RecordingRelativeFormatter = new RecordingRelativeFormatter('zh');
      expect(formatRelativeTo(now - 3 * DAY, now, 'zh-Hans-CN') === '').assertTrue();
      // The platform formatter is what turns the delta into words; assert the
      // delta reached it through formatRelativeTimeUsing.
      expect(formatRelativeTimeUsing((now - 3 * DAY) - now, zh)).assertEqual('3天前');
      expect(zh.calls[0]).assertEqual('-3:day');
    });

    it('renders Chinese and English relative wording', 0, () => {
      const zh: RecordingRelativeFormatter = new RecordingRelativeFormatter('zh');
      const en: RecordingRelativeFormatter = new RecordingRelativeFormatter('en');
      expect(formatRelativeTimeUsing(-3 * DAY, zh)).assertEqual('3天前');
      expect(formatRelativeTimeUsing(-1 * DAY, zh)).assertEqual('昨天');
      expect(formatRelativeTimeUsing(500, zh)).assertEqual('刚刚');
      expect(formatRelativeTimeUsing(-3 * DAY, en)).assertEqual('3 days ago');
      expect(formatRelativeTimeUsing(-1 * DAY, en)).assertEqual('yesterday');
      expect(formatRelativeTimeUsing(500, en)).assertEqual('just now');
    });

    it('renders Chinese and English absolute date/time wording', 0, () => {
      const stamp: number = new Date(2026, 2, 4, 15, 30, 0).getTime();
      const zh: RecordingDateFormatter = new RecordingDateFormatter('zh');
      const en: RecordingDateFormatter = new RecordingDateFormatter('en');
      const zhText: string = formatDateTimeUsing(stamp, zh);
      const enText: string = formatDateTimeUsing(stamp, en);
      expect(zhText.startsWith('2026/03/04 15:30')).assertTrue();
      expect(enText.startsWith('03/04/2026, 15:30')).assertTrue();
      expect(zhText !== enText).assertTrue();
      expect(zh.stamps[0]).assertEqual(stamp);
    });

    it('recognises Chinese locale tags', 0, () => {
      expect(isChineseLocale('zh')).assertTrue();
      expect(isChineseLocale('zh-Hans')).assertTrue();
      expect(isChineseLocale('zh-Hans-CN')).assertTrue();
      expect(isChineseLocale('en-US')).assertFalse();
      expect(isChineseLocale('')).assertFalse();
    });

    it('falls back to a built-in table without a provider', 0, () => {
      expect(getSemesterTextFromId('2025-2026-1', 'zh-Hans-CN', null)).assertEqual('2025-2026 学年秋季学期');
      expect(getSemesterTextFromId('2025-2026-2', 'zh-Hans-CN', null)).assertEqual('2025-2026 学年春季学期');
      expect(getSemesterTextFromId('2025-2026-3', 'zh-Hans-CN', null)).assertEqual('2025-2026 学年夏季学期');
      expect(getSemesterTextFromId('2025-2026-1', 'en-US', null)).assertEqual('Fall 2025-2026');
      expect(getSemesterTextFromId('2025-2026-2', 'en-US', null)).assertEqual('Spring 2025-2026');
      expect(getSemesterTextFromId('2025-2026-3', 'en-US', null)).assertEqual('Summer 2025-2026');
    });

    it('prefers translated season words when a provider is supplied', 0, () => {
      const provider: FakeProvider = new FakeProvider('zh-Hans-CN', fakeTable());
      expect(getSemesterTextFromId('2025-2026-1', 'zh-Hans-CN', provider)).assertEqual('2025-2026 学年秋季学期');
      const english: FakeProvider = new FakeProvider('en-US', fakeTable());
      expect(getSemesterTextFromId('2025-2026-1', 'en-US', english)).assertEqual('秋季学期 2025-2026');
    });

    it('handles malformed or truncated semester ids', 0, () => {
      expect(getSemesterTextFromId('', 'zh-Hans-CN', null)).assertEqual('- 学年');
      expect(getSemesterTextFromId('2025', 'en-US', null)).assertEqual(' 2025-');
      expect(getSemesterTextFromId('2025-2026', 'zh-Hans-CN', null)).assertEqual('2025-2026 学年');
      expect(getSemesterTextFromId('2025-2026-9', 'zh-Hans-CN', null)).assertEqual('2025-2026 学年9');
    });

    it('formats file sizes', 0, () => {
      expect(formatFileSize(0)).assertEqual('0 B');
      expect(formatFileSize(900)).assertEqual('900 B');
      expect(formatFileSize(1024)).assertEqual('1.0 KB');
      expect(formatFileSize(1536)).assertEqual('1.5 KB');
      expect(formatFileSize(1024 * 1024)).assertEqual('1.0 MB');
      expect(formatFileSize(-1)).assertEqual('');
      expect(formatFileSize(Number.NaN)).assertEqual('');
    });
  });
}
