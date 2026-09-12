/*
 * 页头的"相对更新时间"（ticket 11.5，Part B）：`刚刚更新` / `N 分钟前更新` / `N 小时前更新` / `N 天前更新`。
 *
 * 数据源是快照的 `fetchedAtMillis`（`snapshot.fetchedAt`），**不**每秒重算：
 * 页面在构建 spec 时取一次（进入页面 / 下拉刷新时重取），与参考实现的"渲染时取一次"同口径。
 *
 * 分档是**纯函数**（`updatedTimeParts`），单测不需要 ICU / 资源即可钉住边界；
 * 措辞走 i18n 键（`ui_updated_*`），中英各一份。边界见 docs/accepted-deviations.md 第 24 条。
 */
import { i18nService } from '../../core/i18n/I18n';
import { I18nKey } from '../../core/i18n/I18nKeys';

/** 相对时间的四档。 */
export enum UpdateAgeUnit {
  /** < 1 分钟（含"未来时间戳"这种异常输入）。 */
  JUST_NOW = 'just-now',
  MINUTES = 'minutes',
  HOURS = 'hours',
  DAYS = 'days'
}

export interface UpdateAgeParts {
  unit: UpdateAgeUnit;
  /** 档内整数（JUST_NOW 时为 0）。 */
  amount: number;
}

/** 一分钟的毫秒数（不用数字分隔符，保持 ArkTS 最保守的写法）。 */
const MINUTE_MS: number = 60000;
const HOUR_MS: number = 3600000;
const DAY_MS: number = 86400000;

/**
 * 纯函数：把"距更新已过去多少毫秒"分成四档。
 * 边界：<60s → JUST_NOW；60s–59min59s → MINUTES(1..59)；1h–23h59m → HOURS(1..23)；≥24h → DAYS。
 */
export function updatedTimeParts(elapsedMillis: number): UpdateAgeParts {
  if (!Number.isFinite(elapsedMillis) || elapsedMillis < MINUTE_MS) {
    return { unit: UpdateAgeUnit.JUST_NOW, amount: 0 };
  }
  if (elapsedMillis < HOUR_MS) {
    return { unit: UpdateAgeUnit.MINUTES, amount: Math.floor(elapsedMillis / MINUTE_MS) };
  }
  if (elapsedMillis < DAY_MS) {
    return { unit: UpdateAgeUnit.HOURS, amount: Math.floor(elapsedMillis / HOUR_MS) };
  }
  return { unit: UpdateAgeUnit.DAYS, amount: Math.floor(elapsedMillis / DAY_MS) };
}

/** 分档 → 文案（本地化）。 */
export function updateAgeText(parts: UpdateAgeParts): string {
  switch (parts.unit) {
    case UpdateAgeUnit.MINUTES:
      return i18nService.t('ui_updated_minutes_ago', parts.amount);
    case UpdateAgeUnit.HOURS:
      return i18nService.t('ui_updated_hours_ago', parts.amount);
    case UpdateAgeUnit.DAYS:
      return i18nService.t('ui_updated_days_ago', parts.amount);
    default:
      return i18nService.t('ui_updated_just_now');
  }
}

/**
 * 页头那一行。`fetchedAtMillis <= 0`（还没有快照）时返回空串 ⇒ 调用方不渲染这一行。
 */
export function updatedTimeText(fetchedAtMillis: number, nowMillis: number): string {
  if (fetchedAtMillis <= 0) {
    return '';
  }
  return updateAgeText(updatedTimeParts(nowMillis - fetchedAtMillis));
}
