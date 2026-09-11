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

import {
  AbilityConstant,
  ConfigurationConstant,
  Configuration,
  EnvironmentCallback,
  UIAbility,
  Want
} from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { Logger, LOG_DOMAIN } from '../core/log/Logger';
import { i18nService } from '../core/i18n/I18n';

const logger: Logger = new Logger('entry.ability');

/** AppStorage 键：系统配色，供页面用 @StorageProp 订阅（见 pages/Index.ets）。 */
export const COLOR_MODE_KEY: string = 'learnOHColorMode';

/** AppStorage 键：语言版本号，语言变化时自增，页面据此重建（无需重启）。 */
export const LOCALE_VERSION_KEY: string = 'learnOHLocaleVersion';

/**
 * 应用级环境回调：系统语言变化时由 AbilityKit 触发（`ApplicationContext.on('environment')`）。
 * 与 `UIAbility.onConfigurationUpdate` 是两条并行的通知路径，这里都接上，见 ticket 02 Comments。
 */
class LearnOhEnvironmentCallback extends EnvironmentCallback {
  onConfigurationUpdated(config: Configuration): void {
    logger.info('environment updated: language=' + config.language);
    i18nService.refresh();
    AppStorage.setOrCreate(LOCALE_VERSION_KEY, Date.now());
  }

  onMemoryLevel(level: AbilityConstant.MemoryLevel): void {
    logger.info('memory level changed: level=' + level);
  }
}

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      // COLOR_MODE_NOT_SET = 跟随系统深浅色。
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      logger.error('setColorMode failed: ' + (err as Error).message);
    }
    AppStorage.setOrCreate(COLOR_MODE_KEY, this.context.config.colorMode);

    // 逻辑层取串入口：绑定应用资源管理器（ArkTS 中 $r 只能用于 UI 上下文）。
    i18nService.bindResourceManager(this.context.resourceManager, this.context.config.language);

    // 语言变化通知：注册应用级环境回调，系统语言变化时无需重启即可刷新。
    try {
      this.context.getApplicationContext().on('environment', new LearnOhEnvironmentCallback());
    } catch (err) {
      logger.error('register environment callback failed: ' + (err as Error).message);
    }
    AppStorage.setOrCreate(LOCALE_VERSION_KEY, Date.now());

    logger.info('Ability onCreate: colorMode=' + this.context.config.colorMode
      + ' language=' + this.context.config.language
      + ' locale=' + i18nService.locale()
      + ' hilogDomain=' + LOG_DOMAIN);
  }

  /**
   * 系统深浅色切换时触发（无需重启 Ability）。
   * 写入 AppStorage 后，订阅该键的页面立即重建。
   */
  onConfigurationUpdate(newConfig: Configuration): void {
    AppStorage.setOrCreate(COLOR_MODE_KEY, newConfig.colorMode);
    // 语言可能随配置变化：重新绑定资源管理器（同一对象即可，取值按调用时的配置解析），
    // 再自增语言版本号，订阅它的页面会立即重建并重新取串。
    i18nService.bindResourceManager(this.context.resourceManager, this.context.config.language);
    i18nService.refresh();
    AppStorage.setOrCreate(LOCALE_VERSION_KEY, Date.now());
    logger.info('configuration updated: colorMode=' + newConfig.colorMode
      + ' language=' + newConfig.language + ' locale=' + i18nService.locale());
  }

  onDestroy(): void {
    logger.info('Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    logger.info('Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        logger.error('loadContent failed: ' + JSON.stringify(err));
        return;
      }
      logger.info('pages/Index loaded');
    });
  }

  onWindowStageDestroy(): void {
    logger.info('Ability onWindowStageDestroy');
  }

  onForeground(): void {
    logger.info('Ability onForeground');
  }

  onBackground(): void {
    logger.info('Ability onBackground');
  }
}
