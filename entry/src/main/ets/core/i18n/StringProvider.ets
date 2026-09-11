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
 * Where localised strings come from.
 *
 * The UI layer can use `$r('app.string.loh_xxx')` directly (it has a UI
 * context); pure logic cannot, because `$r` is only valid inside a component
 * build. This interface is the seam for that boundary: the logic layer asks
 * for a string by name and does not care where it came from.
 */
export interface StringProvider {
  /** Returns the localised value, or the empty string when the key is absent. */
  get(key: string): string;
  /** Locale tag currently used for resource resolution, e.g. `zh-Hans-CN`. */
  locale(): string;
}

/**
 * Fallback provider used before the ability binds the real resource manager.
 * Returning the key itself makes a missing binding loud instead of silently
 * rendering an empty label.
 */
export class KeyEchoStringProvider implements StringProvider {
  get(key: string): string {
    return key;
  }

  locale(): string {
    return 'und';
  }
}
