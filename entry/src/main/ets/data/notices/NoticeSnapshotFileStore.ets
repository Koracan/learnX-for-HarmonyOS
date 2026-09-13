/*
 * 快照落盘的平台侧（data/notices，ticket 09）：唯一 import `@kit.ArkData` 的文件。
 *
 * 选 preferences 而不是文件：快照是一段 JSON 文本、体量在几十 KB 量级，
 * preferences 的"取一次、写一次"正好；且**与凭据存储分开**——凭据在 asset store
 * （ADR-0004 只约束 cookie/CSRF 不落盘，公告内容是普通缓存，可以落盘）。
 *
 * 所有失败都不抛异常：读不到/写不进只返回结果，由仓储打日志。快照是加速器，
 * 不是数据的唯一来源——它坏了必须只表现为"这次少了一次秒开"，而不是"公告页崩了"。
 *
 * 解码（版本判定、字段校验）走 NoticeSnapshotSerialization 的纯函数：磁盘上的
 * 版本不符或内容损坏只表现为 `decoded.discardReason` 非空，**不抛异常**（验收第 6 条）。
 */

import { preferences } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { Logger } from '../../core/log/Logger';
import { SnapshotDecodeResult, decodeNoticeSnapshot } from './NoticeSnapshotSerialization';
import { NoticeSnapshotPort, SnapshotLoadResult, SnapshotSaveResult } from './NoticeSnapshotStore';

const logger: Logger = new Logger('data.notices.snapshot');

/** preferences 文件名（应用沙箱内）。 */
export const NOTICE_SNAPSHOT_STORE_NAME: string = 'learnoh_notice_snapshot';

/** 存 JSON 文本的那一个键。 */
export const NOTICE_SNAPSHOT_KEY: string = 'snapshot';

/** 空解码结果（"磁盘上没有"）。 */
function absent(): SnapshotDecodeResult {
  return {
    items: [], fetchedAtMillis: 0, readNoticeIds: [], discardReason: 'absent', onDiskVersion: -1
  };
}

/** 基于 @ohos.data.preferences 的快照存储。 */
export class NoticeSnapshotFileStore implements NoticeSnapshotPort {
  private readonly context: common.Context;

  constructor(context: common.Context) {
    this.context = context;
  }

  private async open(): Promise<preferences.Preferences> {
    return await preferences.getPreferences(this.context, NOTICE_SNAPSHOT_STORE_NAME);
  }

  async load(): Promise<SnapshotLoadResult> {
    try {
      const store: preferences.Preferences = await this.open();
      const raw: preferences.ValueType = await store.get(NOTICE_SNAPSHOT_KEY, '');
      if (typeof raw !== 'string' || (raw as string).length === 0) {
        logger.info('snapshot load: absent');
        return { present: false, decoded: absent() };
      }
      const payload: string = raw as string;
      const decoded: SnapshotDecodeResult = decodeNoticeSnapshot(payload);
      logger.info('snapshot load: chars=' + payload.length.toString()
        + ' usable=' + (decoded.discardReason.length === 0).toString()
        + ' discard=' + (decoded.discardReason.length === 0 ? 'none' : decoded.discardReason)
        + ' items=' + decoded.items.length.toString());
      return { present: true, decoded: decoded };
    } catch (error) {
      const business: BusinessError = error as BusinessError;
      logger.warn('snapshot load failed: code=' + (business.code === undefined ? 'none' : business.code.toString())
        + ' message=' + business.message);
      return { present: false, decoded: absent() };
    }
  }

  async save(payload: string): Promise<SnapshotSaveResult> {
    try {
      const store: preferences.Preferences = await this.open();
      await store.put(NOTICE_SNAPSHOT_KEY, payload);
      await store.flush();
      logger.info('snapshot save ok: chars=' + payload.length.toString());
      return { ok: true, diagnostic: 'chars=' + payload.length.toString() };
    } catch (error) {
      const business: BusinessError = error as BusinessError;
      const diagnostic: string = 'code=' + (business.code === undefined ? 'none' : business.code.toString())
        + ' message=' + business.message;
      logger.error('snapshot save failed: ' + diagnostic);
      return { ok: false, diagnostic: diagnostic };
    }
  }
}
