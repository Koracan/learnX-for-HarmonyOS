/*
 * `ImmersiveSettingsPort` 的设备实现：`@ohos.data.preferences`。
 *
 * 与 `PreferencesFileSettings.ets` 逐行同构，只是**另一个 preferences 文件**
 * （`learnoh_immersive_settings`）：两套设置互不影响，任何一边读失败都不会波及另一边。
 * 参考实现是 redux-persist 把整个 `settings` 存进 AsyncStorage（`reducers/root.ts:61-65`）；
 * 移植后按设置域分文件，与文件设置同一处置。
 *
 * 读不到时返回 null（= "没有保存过"），由 `ImmersiveSettingsStore` 用参考实现的默认值兜底；
 * 任何平台失败都不抛到调用方以外。
 *
 * ## 旧沙箱里残留的 `immersiveAvoidFrontCamera`
 *
 * 这个键在移除"避让前置摄像头"开关之前会被写进同一个 preferences 文件。已经存过它的设备/沙箱
 * 上，本文件**既不读它、也不删它**：
 *
 *   - 不读：读路径只看 `immersiveMode`，缺键时 `get` 返回默认值，不可能因此抛异常；
 *   - 不删：删它要为一次纯粹的清理去写同一个 preferences 文件（`delete` + `flush`），
 *     而 preferences 是按键存取，多出来的一个键**是惰性的**，不会影响任何取值。
 *
 * 于是"旧数据不许炸"的判据落在：老沙箱启动后 `load` 正常返回（hilog 有 `immersive settings load`
 * 一行），`immersiveMode` 的旧值照旧生效。
 */

import { preferences } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { Logger } from '../../core/log/Logger';
import { ImmersiveSettings, ImmersiveSettingsPort } from './ImmersiveSettings';

const logger: Logger = new Logger('data.settings.immersive');

/** preferences 文件名（应用沙箱内）。 */
export const IMMERSIVE_SETTINGS_STORE_NAME: string = 'learnoh_immersive_settings';

/** 唯一的键（与参考实现的字段名同名）。 */
export const IMMERSIVE_MODE_KEY: string = 'immersiveMode';

export class PreferencesImmersiveSettingsPort implements ImmersiveSettingsPort {
  private readonly context: common.Context;

  constructor(context: common.Context) {
    this.context = context;
  }

  private async open(): Promise<preferences.Preferences> {
    return await preferences.getPreferences(this.context, IMMERSIVE_SETTINGS_STORE_NAME);
  }

  async load(): Promise<ImmersiveSettings | null> {
    try {
      const store: preferences.Preferences = await this.open();
      const rawImmersiveMode: preferences.ValueType = await store.get(IMMERSIVE_MODE_KEY, '');
      if (typeof rawImmersiveMode !== 'boolean') {
        logger.info('immersive settings load: absent -> defaults');
        return null;
      }
      const value: ImmersiveSettings = { immersiveMode: rawImmersiveMode };
      logger.info('immersive settings load: immersiveMode=' + value.immersiveMode.toString());
      return value;
    } catch (error) {
      const business: BusinessError = error as BusinessError;
      logger.warn('immersive settings load failed: code='
        + (business.code === undefined ? 'none' : business.code.toString())
        + ' message=' + business.message + ' -> defaults');
      return null;
    }
  }

  async save(value: ImmersiveSettings): Promise<boolean> {
    try {
      const store: preferences.Preferences = await this.open();
      await store.put(IMMERSIVE_MODE_KEY, value.immersiveMode);
      await store.flush();
      logger.info('immersive settings save ok: immersiveMode=' + value.immersiveMode.toString());
      return true;
    } catch (error) {
      const business: BusinessError = error as BusinessError;
      logger.error('immersive settings save failed: code='
        + (business.code === undefined ? 'none' : business.code.toString())
        + ' message=' + business.message);
      return false;
    }
  }
}
