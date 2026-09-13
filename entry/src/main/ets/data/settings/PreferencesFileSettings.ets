/*
 * `FileSettingsPort` 的设备实现：`@ohos.data.preferences`（
 * `@react-native-async-storage/async-storage` → preferences；参考实现用 redux-persist 落这两个布尔）。
 *
 * 与公告快照用 preferences 的理由相同：两个布尔、取一次写一次，不需要文件。
 * **与凭据存储分开**（ADR-0004 只约束 cookie/CSRF 不落盘；设置是普通偏好）。
 *
 * 读不到时返回 null（= "没有保存过"），由 `FileSettingsStore` 用参考实现的默认值兜底；
 * 任何平台失败都不抛到调用方以外。
 */

import { preferences } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { Logger } from '../../core/log/Logger';
import { FileSettings, FileSettingsPort } from './FileSettings';

const logger: Logger = new Logger('data.settings.files');

/** preferences 文件名（应用沙箱内）。 */
export const FILE_SETTINGS_STORE_NAME: string = 'learnoh_file_settings';

/** 两个键（与参考实现的字段名同名）。 */
export const USE_DOCUMENT_DIR_KEY: string = 'useDocumentDir';
export const OMIT_COURSE_NAME_KEY: string = 'omitCourseName';

export class PreferencesFileSettingsPort implements FileSettingsPort {
  private readonly context: common.Context;

  constructor(context: common.Context) {
    this.context = context;
  }

  private async open(): Promise<preferences.Preferences> {
    return await preferences.getPreferences(this.context, FILE_SETTINGS_STORE_NAME);
  }

  async load(): Promise<FileSettings | null> {
    try {
      const store: preferences.Preferences = await this.open();
      const rawUseDocumentDir: preferences.ValueType = await store.get(USE_DOCUMENT_DIR_KEY, '');
      const rawOmitCourseName: preferences.ValueType = await store.get(OMIT_COURSE_NAME_KEY, '');
      if (typeof rawUseDocumentDir !== 'boolean' && typeof rawOmitCourseName !== 'boolean') {
        logger.info('file settings load: absent -> defaults');
        return null;
      }
      const value: FileSettings = {
        useDocumentDir: typeof rawUseDocumentDir === 'boolean' ? rawUseDocumentDir : false,
        omitCourseName: typeof rawOmitCourseName === 'boolean' ? rawOmitCourseName : false
      };
      logger.info('file settings load: useDocumentDir=' + value.useDocumentDir.toString()
        + ' omitCourseName=' + value.omitCourseName.toString());
      return value;
    } catch (error) {
      const business: BusinessError = error as BusinessError;
      logger.warn('file settings load failed: code='
        + (business.code === undefined ? 'none' : business.code.toString())
        + ' message=' + business.message + ' -> defaults');
      return null;
    }
  }

  async save(value: FileSettings): Promise<boolean> {
    try {
      const store: preferences.Preferences = await this.open();
      await store.put(USE_DOCUMENT_DIR_KEY, value.useDocumentDir);
      await store.put(OMIT_COURSE_NAME_KEY, value.omitCourseName);
      await store.flush();
      logger.info('file settings save ok: useDocumentDir=' + value.useDocumentDir.toString()
        + ' omitCourseName=' + value.omitCourseName.toString());
      return true;
    } catch (error) {
      const business: BusinessError = error as BusinessError;
      logger.error('file settings save failed: code='
        + (business.code === undefined ? 'none' : business.code.toString())
        + ' message=' + business.message);
      return false;
    }
  }
}
