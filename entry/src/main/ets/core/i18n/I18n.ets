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
 * i18n access facade for the logic layer.
 *
 * Boundary: `$r('app.string.xxx')` is only legal inside a component build, so
 * `data/`, `domain/` and other pure logic cannot use it. This facade is the
 * equivalent there: it resolves the same element resources by name through
 * `ResourceManager.getStringByNameSync`.
 *
 * Live switching: the resource manager owned by `Context` re-resolves against
 * the configuration in force at call time, so nothing is cached here and no
 * restart is involved. `bindResourceManager()` is re-run from
 * `UIAbility.onConfigurationUpdate` (system or app language change) and from
 * in-app language switches, and listeners are then notified so the UI can
 * re-read strings already captured in state (see pages/Index.ets).
 */
import { resourceManager } from '@kit.LocalizationKit';
import { I18nKey, isI18nKey } from './I18nKeys';
import { StringProvider, KeyEchoStringProvider } from './StringProvider';
import { getLocaleTag } from './Locale';
import { SemesterTextSource } from './DateTimeUtil';
import { Logger } from '../log/Logger';

const logger: Logger = new Logger('core.i18n');

export type LocaleChangeListener = (locale: string) => void;

/** Adapter: an application `ResourceManager`, addressed by resource name. */
export class ResourceManagerStringProvider implements StringProvider {
  private readonly rm: resourceManager.ResourceManager;

  constructor(rm: resourceManager.ResourceManager) {
    this.rm = rm;
  }

  get(key: string): string {
    try {
      return this.rm.getStringByNameSync(key);
    } catch (err) {
      logger.warn('取不到字符串资源：' + key + '（' + (err as Error).message + '）');
      return '';
    }
  }

  locale(): string {
    try {
      const locales: string[] = this.rm.getLocales();
      if (locales.length > 0) {
        return locales[0];
      }
    } catch (err) {
      logger.warn('getLocales() 失败，回退到 @ohos.i18n：' + (err as Error).message);
    }
    return getLocaleTag();
  }
}

export class I18nService implements SemesterTextSource {
  private provider: StringProvider = new KeyEchoStringProvider();
  private rm: resourceManager.ResourceManager | null = null;
  /** App language from UIAbility context.config, e.g. `zh-Hans`. Authoritative. */
  private appLanguage: string = '';
  private bound: boolean = false;
  private listeners: LocaleChangeListener[] = [];

  /** Binds the application resource manager. Safe to call repeatedly. */
  bindResourceManager(rm: resourceManager.ResourceManager, appLanguage?: string): void {
    this.provider = new ResourceManagerStringProvider(rm);
    this.rm = rm;
    if (appLanguage !== undefined && appLanguage.length > 0) {
      this.appLanguage = appLanguage;
    }
    this.bound = true;
    const locale: string = this.locale();
    logger.info('资源管理器已绑定：locale=' + locale);
    this.notify(locale);
  }

  /** For unit tests and for layers that already own a provider. */
  bindProvider(provider: StringProvider): void {
    this.provider = provider;
    this.bound = true;
    this.notify(this.locale());
  }

  /** True once `bindResourceManager` / `bindProvider` has run. */
  isBound(): boolean {
    return this.bound;
  }

  /**
   * Re-reads the locale after a configuration change and notifies listeners.
   * The provider is stateless with respect to language, so no rebinding is
   * strictly required; this exists so the UI gets an explicit refresh signal.
   */
  refresh(): void {
    const locale: string = this.locale();
    logger.info('语言已刷新：locale=' + locale);
    this.notify(locale);
  }

  onLocaleChange(listener: LocaleChangeListener): void {
    if (!this.listeners.includes(listener)) {
      this.listeners.push(listener);
    }
  }

  offLocaleChange(listener: LocaleChangeListener): void {
    const index: number = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  private notify(locale: string): void {
    for (const listener of this.listeners) {
      listener(locale);
    }
  }

  /** Language tag currently used for resource resolution. */
  locale(): string {
    // 1) The app language the ability last reported (authoritative).
    // 2) `ResourceManager.getLocales()` is NOT used as the primary source: on
    //    the emulator it reported `en-US` while resource resolution used
    //    zh-Hans, which is exactly the mismatch that produced an English date
    //    next to Chinese labels.
    if (this.appLanguage.length > 0) {
      return this.appLanguage;
    }
    const fromProvider: string = this.provider.locale();
    if (fromProvider.length > 0 && fromProvider !== 'und') {
      return fromProvider;
    }
    return getLocaleTag();
  }

  /** Port of the reference `isLocaleChinese` (helpers/i18n.ts). */
  isChinese(): boolean {
    return this.locale().toLowerCase().startsWith('zh');
  }

  /**
   * Untyped lookup by resource name. Returns `''` when the resource is absent.
   * Callers that must not show a blank label should use `t()`, which echoes the
   * key so the gap is visible.
   */
  get(key: string): string {
    return this.provider.get(key);
  }

  /** Typed translation lookup; `key` is one of the generated resource names. */
  t(key: I18nKey, ...args: Array<string | number>): string {
    const value: string = this.provider.get(key);
    if (value.length === 0) {
      return key;
    }
    if (args.length === 0) {
      return value;
    }
    return formatMessage(value, args);
  }

  /** Untyped variant for keys that arrive as plain strings. */
  tName(key: string, ...args: Array<string | number>): string {
    if (!isI18nKey(key)) {
      return key;
    }
    return this.t(key as I18nKey, ...args);
  }

  /**
   * The logic-layer twin of `$r('app.string.x')`: takes the same `Resource`
   * object the UI layer would, so a component can hand its `$r`-derived key to
   * the logic layer without duplicating the name as a literal.
   */
  tKey(resource: Resource, ...args: Array<string | number>): string {
    if (this.rm === null) {
      return '';
    }
    try {
      return this.rm.getStringSync(resource.id, ...args);
    } catch (err) {
      logger.warn('tKey 取串失败，id=' + resource.id + '（' + (err as Error).message + '）');
      return '';
    }
  }
}



/**
 * Substitutes `%(N+1)$s`, `%s` and `%d` placeholders, mirroring what
 * `$r('app.string.x', a, b)` does for the UI layer.
 */
export function formatMessage(template: string, args: Array<string | number>): string {
  let out: string = template;
  for (let index = 0; index < args.length; index++) {
    out = out.split('%' + (index + 1) + '$s').join(String(args[index]));
  }
  for (const arg of args) {
    const plain: number = out.indexOf('%s');
    if (plain < 0) {
      break;
    }
    out = out.substring(0, plain) + String(arg) + out.substring(plain + 2);
  }
  return out;
}

/** Process-wide instance. */
export const i18nService: I18nService = new I18nService();

export function t(key: I18nKey, ...args: Array<string | number>): string {
  return i18nService.t(key, ...args);
}

export function getLocale(): string {
  return i18nService.locale();
}

export function isLocaleChinese(): boolean {
  return i18nService.isChinese();
}
