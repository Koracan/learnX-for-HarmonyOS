/*
 * Copyright (c) 2026 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/**
 * Locale-aware date/time formatting and relative time ("3 days ago" / "3天前").
 *
 * ## Why not the `dayjs` package
 *
 * ohpm *does* carry `dayjs` (1.11.13) -- see
 * `.scratch/foundation/evidence/02-ohpm-dayjs-info.txt` -- but the ohpm registry
 * proxies npm, and that entry is the upstream npm package: no
 * `oh-package.json5`, npm-style CJS entry (`dayjs.min.js`), and locale loading
 * through a dynamic `require('./locale/' + name)`, which ArkTS rejects. The
 * platform already ships a complete, locale-correct implementation, so the
 * choice here is `@ohos.intl` plus a thin adapter.
 *
 * ## Shape
 *
 * Formatting is split from policy:
 *   - `pickRelativeUnit` / `relativeAmount` / `relativeTimeParts` are pure and
 *     are what the unit tests pin down (host unit tests do not load ICU, so
 *     they must not depend on its wording);
 *   - `formatRelativeTimeUsing` takes a `RelativeTimeFormatter`, so the zh/en
 *     wording can be unit-tested with a fake and the real wording verified on
 *     the device (`PlatformRelativeTimeFormatter`).
 */
import { intl } from '@kit.LocalizationKit';

export enum RelativeUnit {
  SECOND = 'second',
  MINUTE = 'minute',
  HOUR = 'hour',
  DAY = 'day',
  WEEK = 'week',
  MONTH = 'month',
  YEAR = 'year'
}

export interface RelativeTimeRule {
  unit: RelativeUnit;
  divisorMs: number;
}

/** Largest-unit-first ladder, mirroring the reference implementation's dayjs usage. */
export const RELATIVE_TIME_LADDER: RelativeTimeRule[] = [
  { unit: RelativeUnit.YEAR, divisorMs: 365 * 24 * 3600 * 1000 },
  { unit: RelativeUnit.MONTH, divisorMs: 30 * 24 * 3600 * 1000 },
  { unit: RelativeUnit.WEEK, divisorMs: 7 * 24 * 3600 * 1000 },
  { unit: RelativeUnit.DAY, divisorMs: 24 * 3600 * 1000 },
  { unit: RelativeUnit.HOUR, divisorMs: 3600 * 1000 },
  { unit: RelativeUnit.MINUTE, divisorMs: 60 * 1000 },
  { unit: RelativeUnit.SECOND, divisorMs: 1000 }
];

/** Pure: the largest unit whose magnitude is at least one. */
export function pickRelativeUnit(diffMs: number): RelativeTimeRule {
  const magnitude: number = Math.abs(diffMs);
  for (const rule of RELATIVE_TIME_LADDER) {
    if (magnitude >= rule.divisorMs) {
      return rule;
    }
  }
  return RELATIVE_TIME_LADDER[RELATIVE_TIME_LADDER.length - 1];
}

/** Pure: signed integer amount for a ladder rule (rounds toward zero). */
export function relativeAmount(diffMs: number, rule: RelativeTimeRule): number {
  const raw: number = diffMs / rule.divisorMs;
  return raw < 0 ? Math.ceil(raw) : Math.floor(raw);
}

export interface RelativeTimeParts {
  unit: RelativeUnit;
  /** Signed amount in `unit`; 0 when `isNow`. */
  amount: number;
  /** True for anything under one second, so the UI can say "刚刚"/"Just now". */
  isNow: boolean;
}

/** Pure: decompose a delta into the unit, the amount and the "now" case. */
export function relativeTimeParts(diffMs: number): RelativeTimeParts {
  const rule: RelativeTimeRule = pickRelativeUnit(diffMs);
  if (rule.unit === RelativeUnit.SECOND && Math.abs(diffMs) < 1000) {
    return { unit: RelativeUnit.SECOND, amount: 0, isNow: true };
  }
  return { unit: rule.unit, amount: relativeAmount(diffMs, rule), isNow: false };
}

/**
 * Pure: a compact, ICU-independent signature of the decomposition, e.g.
 * `now`, `past:day:3`, `future:hour:2`. Used by the unit tests to pin the
 * ladder without depending on platform wording.
 */
export function describeRelativeTime(diffMs: number): string {
  const parts: RelativeTimeParts = relativeTimeParts(diffMs);
  if (parts.isNow) {
    return 'now';
  }
  const direction: string = parts.amount < 0 ? 'past' : 'future';
  return direction + ':' + parts.unit + ':' + Math.abs(parts.amount);
}

export function isChineseLocale(locale: string): boolean {
  return locale.toLowerCase().startsWith('zh');
}

function resolveLocale(locale: string): string {
  return locale.length > 0 ? locale : 'en-US';
}

/** Turns a (amount, unit) pair into words. Swappable so tests need no ICU. */
export interface RelativeTimeFormatter {
  format(amount: number, unit: RelativeUnit): string;
}

/** Real implementation, backed by `Intl.RelativeTimeFormat`. */
export class PlatformRelativeTimeFormatter implements RelativeTimeFormatter {
  private readonly locale: string;
  private readonly rtf: intl.RelativeTimeFormat;

  constructor(locale: string) {
    this.locale = resolveLocale(locale);
    this.rtf = new intl.RelativeTimeFormat(this.locale, { numeric: 'auto' });
  }

  format(amount: number, unit: RelativeUnit): string {
    return this.rtf.format(amount, unit);
  }
}

/** Relative time using an explicit formatter (unit-tested with a fake). */
export function formatRelativeTimeUsing(diffMs: number, formatter: RelativeTimeFormatter): string {
  const parts: RelativeTimeParts = relativeTimeParts(diffMs);
  return formatter.format(parts.amount, parts.unit);
}

/**
 * Relative time between two instants. Prefer this over `formatRelativeTime`
 * when you hold absolute timestamps -- passing a timestamp where a delta is
 * expected silently yields "in 56 years".
 */
export function formatRelativeTo(targetMillis: number, nowMillis: number, locale: string): string {
  return formatRelativeTime(targetMillis - nowMillis, locale);
}

/** Locale-aware relative time, e.g. `3 days ago` / `3天前`. */
export function formatRelativeTime(diffMs: number, locale: string): string {
  return formatRelativeTimeUsing(diffMs, new PlatformRelativeTimeFormatter(locale));
}

export interface DateTimeFormatOptions {
  year?: string;
  month?: string;
  day?: string;
  hour?: string;
  minute?: string;
  second?: string;
  hour12?: boolean;
}

/** Turns an instant into a string. Swappable so tests need no ICU. */
export interface DateTimeFormatter {
  format(millis: number): string;
}

/** Real implementation, backed by `Intl.DateTimeFormat`. */
export class PlatformDateTimeFormatter implements DateTimeFormatter {
  private readonly fmt: intl.DateTimeFormat;

  constructor(locale: string, options: DateTimeFormatOptions) {
    this.fmt = new intl.DateTimeFormat(resolveLocale(locale), options);
  }

  format(millis: number): string {
    return this.fmt.format(new Date(millis));
  }
}

/** Absolute date/time using an explicit formatter. */
export function formatDateTimeUsing(millis: number, formatter: DateTimeFormatter): string {
  return formatter.format(millis);
}

/** `2026/03/04 15:30`-style timestamp used by list rows. */
export function formatDateTimeShort(millis: number, locale: string): string {
  const options: DateTimeFormatOptions = {
    year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', hour12: false
  };
  return formatDateTimeUsing(millis, new PlatformDateTimeFormatter(locale, options));
}

/** Date only. */
export function formatDate(millis: number, locale: string): string {
  const options: DateTimeFormatOptions = { year: 'numeric', month: '2-digit', day: '2-digit' };
  return formatDateTimeUsing(millis, new PlatformDateTimeFormatter(locale, options));
}

export interface SemesterTextSource {
  /** Returns a translated string for a resource name (`loh_*` / `ui_*`). */
  get(key: string): string;
  /** `zh-Hans-CN`, `en-US`, ... */
  locale(): string;
}

const SEASON_KEYS: string[] = ['loh_fall', 'loh_spring', 'loh_summer'];
const SEASON_ZH: string[] = ['秋季学期', '春季学期', '夏季学期'];
const SEASON_EN: string[] = ['Fall', 'Spring', 'Summer'];

function seasonLabel(season: string, chinese: boolean, source: SemesterTextSource | null): string {
  const index: number = Number(season) - 1;
  const inRange: boolean = index >= 0 && index < SEASON_KEYS.length;
  if (inRange && source !== null) {
    const key: string = SEASON_KEYS[index];
    const translated: string = source.get(key);
    if (translated.length > 0 && translated !== key) {
      return translated;
    }
  }
  if (inRange) {
    return chinese ? SEASON_ZH[index] : SEASON_EN[index];
  }
  return season;
}

/**
 * Port of the reference `getSemesterTextFromId`
 * (`reference/learnOH-old/src/helpers/parse.ts`).
 *
 * zh: `2025-2026 学年秋季学期`    en: `Fall 2025-2026`
 *
 * Season words come from the resources (`loh_fall`/`loh_spring`/`loh_summer`)
 * when a provider is supplied; the built-in table keeps the function pure and
 * unit-testable without a device.
 */
export function getSemesterTextFromId(semesterId: string, locale: string, source?: SemesterTextSource | null): string {
  const provider: SemesterTextSource | null = source === undefined ? null : source;
  const parts: string[] = semesterId.split('-');
  const yearFrom: string = parts.length > 0 ? parts[0] : '';
  const yearTo: string = parts.length > 1 ? parts[1] : '';
  const season: string = parts.length > 2 ? parts[2] : '';
  const chinese: boolean = isChineseLocale(locale);
  const label: string = seasonLabel(season, chinese, provider);
  if (chinese) {
    return yearFrom + '-' + yearTo + ' 学年' + label;
  }
  return label + ' ' + yearFrom + '-' + yearTo;
}

/** `1.5 MB` / `900 B`. Unit names are ASCII, so this needs no locale. */
export function formatFileSize(bytes: number): string {
  if (bytes < 0 || !Number.isFinite(bytes)) {
    return '';
  }
  const units: string[] = ['B', 'KB', 'MB', 'GB', 'TB'];
  let value: number = bytes;
  let unit: number = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value = value / 1024;
    unit++;
  }
  const rounded: string = unit === 0 ? String(Math.round(value)) : value.toFixed(value >= 100 ? 0 : 1);
  return rounded + ' ' + units[unit];
}
