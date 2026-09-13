/*
 * Mock 公告数据源（data/mock）。
 *
 * 参考实现是把整个 redux state 换成 `data/mock.ts`（`reducers/root.ts:138-139` 的 SET_MOCK_STORE），
 * 本工程没有那层 state，于是把 Mock 落在**仓储**这一层：mock 模式下 provider 返回本类，
 * 界面与 store 一行都不用改。
 *
 * 两条纪律：
 *   - **不发任何请求**：本类不 import 任何 http 端口，只有样例数据；
 *   - 每次都打一行**消费点自证**，把当时的网络请求计数写出来（要求可证明）。
 */

import { Logger } from '../../core/log/Logger';
import { networkAttemptCount } from '../remote/NetworkAudit';
import {
  NOTICE_SNAPSHOT_SCHEMA_VERSION, NoticeRepository, NoticeSnapshot, mergeNoticeReadState
} from '../notices/NoticeRepository';
import { mockNotices } from './MockData';

const logger: Logger = new Logger('data.mock.notices');

export class MockNoticeRepository implements NoticeRepository {
  /**
   * 样例数据不落盘（没有"上次快照"这回事），但**已读集合留在内存里**：
   * 一次会话内打开过的公告仍会立刻变成已读，与真实数据源的行为一致；杀掉进程即重置。
   */
  private readIds: string[] = [];

  /** Mock 数据不落盘：没有"上次快照"这回事（参考实现的 mock store 也只有一份内存态）。 */
  async loadSnapshot(): Promise<NoticeSnapshot | null> {
    return null;
  }

  async refresh(): Promise<NoticeSnapshot> {
    const items = mergeNoticeReadState(mockNotices(), this.readIds);
    const snapshot: NoticeSnapshot = {
      items: items,
      fetchedAtMillis: Date.now(),
      schemaVersion: NOTICE_SNAPSHOT_SCHEMA_VERSION,
      fromSnapshot: false
    };
    logger.info('mock notices served: items=' + items.length.toString()
      + ' readIds=' + this.readIds.length.toString()
      + ' networkAttempts=' + networkAttemptCount().toString());
    return snapshot;
  }

  async markRead(noticeId: string): Promise<void> {
    if (noticeId.length > 0 && !this.readIds.includes(noticeId)) {
      this.readIds.push(noticeId);
    }
  }
}
