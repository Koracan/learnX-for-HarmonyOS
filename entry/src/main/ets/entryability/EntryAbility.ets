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
import {
  SEMESTER_WANT_PARAM, describeSemesterOverride, setRuntimeSemesterOverride
} from '../data/courses/SemesterOverride';
import {
  FILE_OMIT_COURSE_NAME_WANT_PARAM, FILE_USE_DOCUMENT_DIR_WANT_PARAM,
  describeFileSettingsOverride, setRuntimeFileSettingsOverride
} from '../data/settings/FileSettings';

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

    // 学期覆盖的**脚本入口**（ticket 12 硬约束 2）：ticket 10/13 要切到
    // 2025-2026 学年春季学期才能取到真实作业，而不允许靠界面交互。
    //   hdc shell aa start -a EntryAbility -b com.koracan.learnOH --ps lohSemester 2025-2026-2
    this.applySemesterOverride(want);
    // 文件设置的两个开关（ticket 11 验收第 5 条要"两个设置均生效"的可复现取证）：
    //   hdc shell aa start -a EntryAbility -b com.koracan.learnOH \
    //     --ps lohFileUseDocumentDir 1 --ps lohFileOmitCourseName 1
    this.applyFileSettingsOverride(want);

    logger.info('Ability onCreate: colorMode=' + this.context.config.colorMode
      + ' language=' + this.context.config.language
      + ' locale=' + i18nService.locale()
      + ' hilogDomain=' + LOG_DOMAIN);
  }

  /**
   * 从 want 参数里读学期覆盖并**自证生效**（AGENTS.md：开关必须把实际生效值打进 hilog）。
   *
   * 冷启动走 onCreate；应用已在运行时再次被拉起走 onNewWant。
   * 覆盖只在**内存**里，进程重启即失效——所以取证脚本的正确用法是
   * `aa force-stop` 后再 `aa start --ps ...`（见 data/courses/SemesterOverride.ets 的文件头）。
   */
  private applySemesterOverride(want: Want): void {
    const params: Record<string, Object> | undefined = want.parameters;
    if (params === undefined) {
      logger.info('semester override: no want parameters; ' + describeSemesterOverride());
      return;
    }
    const raw: Object = params[SEMESTER_WANT_PARAM];
    if (raw === undefined || raw === null) {
      logger.info('semester override: want parameter "' + SEMESTER_WANT_PARAM
        + '" absent; ' + describeSemesterOverride());
      return;
    }
    const accepted: boolean = setRuntimeSemesterOverride(String(raw));
    logger.info('semester override: want parameter "' + SEMESTER_WANT_PARAM + '"="'
      + String(raw) + '" accepted=' + accepted.toString() + '; ' + describeSemesterOverride());
  }

  /**
   * 文件设置的运行期覆盖（`--ps lohFileUseDocumentDir` / `lohFileOmitCourseName`）。
   *
   * 与学期覆盖同一口径：**实际生效值进 hilog**（AGENTS.md：开关必须自证生效）。
   * 真正的**消费点**自证在下载器（`data.files.downloader` 的 file download plan 一行，
   * 含 root / dir / path）与文件设置页（`file settings page appear`）——只有那两行能证明
   * "覆盖真的到达了数据路径"。
   */
  private applyFileSettingsOverride(want: Want): void {
    const params: Record<string, Object> | undefined = want.parameters;
    const useDocumentDir: string = params === undefined || params[FILE_USE_DOCUMENT_DIR_WANT_PARAM] === undefined
      ? '' : String(params[FILE_USE_DOCUMENT_DIR_WANT_PARAM]);
    const omitCourseName: string = params === undefined || params[FILE_OMIT_COURSE_NAME_WANT_PARAM] === undefined
      ? '' : String(params[FILE_OMIT_COURSE_NAME_WANT_PARAM]);
    if (useDocumentDir.length === 0 && omitCourseName.length === 0) {
      logger.info('file settings override: want parameters absent; ' + describeFileSettingsOverride());
      return;
    }
    const accepted: boolean = setRuntimeFileSettingsOverride(useDocumentDir, omitCourseName);
    logger.info('file settings override: "' + FILE_USE_DOCUMENT_DIR_WANT_PARAM + '"="' + useDocumentDir
      + '" "' + FILE_OMIT_COURSE_NAME_WANT_PARAM + '"="' + omitCourseName
      + '" accepted=' + accepted.toString() + '; ' + describeFileSettingsOverride());
  }

  /** 已经在前台时再次被 `aa start --ps`：同样要读参数并自证。 */
  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    logger.info('Ability onNewWant');
    this.applySemesterOverride(want);
    this.applyFileSettingsOverride(want);
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