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
 * Locale identity helpers. Backed by `@ohos.i18n` so the answer follows the
 * system (or, when the app overrides it, the application) language.
 */
import { i18n, intl } from '@kit.LocalizationKit';

/** `zh-Hans-CN`, `en-US`, ... -- the language tag currently in effect. */
export function getLocaleTag(): string {
  const language = i18n.System.getSystemLanguage();
  let region = '';
  try {
    region = i18n.System.getSystemRegion();
  } catch (err) {
    region = '';
  }
  if (region.length > 0) {
    return language + '-' + region;
  }
  return language;
}

/** System language only, e.g. `zh-Hans`. */
export function getLanguage(): string {
  return i18n.System.getSystemLanguage();
}

/** Port of the reference `isLocaleChinese` (`helpers/i18n.ts`). */
export function isChinese(): boolean {
  return getLanguage().toLowerCase().startsWith('zh');
}

/** True for right-to-left locales; ArkUI needs it for mirroring decisions. */
export function isRtl(locale: string): boolean {
  return i18n.isRTL(locale);
}

/** Locale-aware collator, for sorting course/file names. */
export function createCollator(locale: string): intl.Collator {
  return new intl.Collator(locale);
}

/** Locale-aware line breaker, so long CJK titles wrap correctly. */
export function getLineInstance(locale: string): i18n.BreakIterator {
  return i18n.getLineInstance(locale);
}
