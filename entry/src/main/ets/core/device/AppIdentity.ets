/*
 * 应用与设备自述信息（core）：versionName 与 productModel，deviceName 的取值来源。
 *
 * spec 第 5 节：deviceName = HarmonyOS,learnOH/{versionName} ({productModel})，
 * **仅登记时上报**（HTTP 重登不带它，故不参与信任绑定）。
 *
 * 参考实现的对应物是 packageJson.version（src/screens/SSO.tsx:52，且没有型号段）
 * 与 react-native-device-info 的 getModel()（src/constants/DeviceInfo.ts）。移植后：
 *   - versionName 取**应用自身信息**（bundleManager，即 AppScope/app.json5 的 versionName），
 *     不再从源码里的 package.json 读——那样打包后可能与实际安装包不一致；
 *   - productModel 取 @ohos.deviceInfo。
 *
 * 两个函数都容错：取不到返回空串，由 domain 的 composeDeviceName 退化成 (unknown)，
 * 而不是让登记因为一个自述字段失败。
 */

import { bundleManager } from '@kit.AbilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { Logger } from '../log/Logger';

const logger: Logger = new Logger('core.device');

/** 应用自身的 versionName（AppScope/app.json5）。取不到返回空串。 */
export function appVersionName(): string {
  try {
    const info: bundleManager.BundleInfo =
      bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
    const version: string = info.versionName;
    return version === undefined || version === null ? '' : version;
  } catch (error) {
    logger.warn('appVersionName failed: ' + (error as Error).message);
    return '';
  }
}

/** 设备型号（productModel）。取不到返回空串。 */
export function deviceProductModel(): string {
  try {
    const model: string = deviceInfo.productModel;
    return model === undefined || model === null ? '' : model;
  } catch (error) {
    logger.warn('deviceProductModel failed: ' + (error as Error).message);
    return '';
  }
}
