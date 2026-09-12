/*
 * `CollectionFlagsPort` 的设备实现：`@ohos.data.preferences`（一个 JSON 键）。
 *
 * 与公告快照 / 文件设置同一处置：preferences 适合"取一次、写一次"的小块文本，
 * 且**与凭据存储分开**（ADR-0004 只约束 cookie/CSRF 不落盘；收藏状态是普通缓存）。
 * 所有平台失败都不抛，读不到就返回 null（= 没保存过）。
 */

import { preferences } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { Logger } from '../../core/log/Logger';
import { CollectionFlagsPort } from './CollectionFlagsStore';

const logger: Logger = new Logger('data.marks.preferences');

/** preferences 文件名（应用沙箱内）。 */
export const COLLECTION_FLAGS_STORE_NAME: string = 'learnoh_collection_flags';

/** 存 JSON 文本的那一个键。 */
export const COLLECTION_FLAGS_KEY: string = 'collectionFlags';

export class PreferencesCollectionFlagsPort implements CollectionFlagsPort {
  private readonly context: common.Context;

  constructor(context: common.Context) {
    this.context = context;
  }

  private async open(): Promise<preferences.Preferences> {
    return await preferences.getPreferences(this.context, COLLECTION_FLAGS_STORE_NAME);
  }

  async load(): Promise<string | null> {
    try {
      const store: preferences.Preferences = await this.open();
      const raw: preferences.ValueType = await store.get(COLLECTION_FLAGS_KEY, '');
      if (typeof raw !== 'string' || (raw as string).length === 0) {
        logger.info('collection flags load: absent');
        return null;
      }
      const payload: string = raw as string;
      logger.info('collection flags load: chars=' + payload.length.toString());
      return payload;
    } catch (error) {
      const business: BusinessError = error as BusinessError;
      logger.warn('collection flags load failed: code='
        + (business.code === undefined ? 'none' : business.code.toString())
        + ' message=' + business.message);
      return null;
    }
  }

  async save(payload: string): Promise<boolean> {
    try {
      const store: preferences.Preferences = await this.open();
      await store.put(COLLECTION_FLAGS_KEY, payload);
      await store.flush();
      logger.info('collection flags save ok: chars=' + payload.length.toString());
      return true;
    } catch (error) {
      const business: BusinessError = error as BusinessError;
      logger.error('collection flags save failed: code='
        + (business.code === undefined ? 'none' : business.code.toString())
        + ' message=' + business.message);
      return false;
    }
  }
}
