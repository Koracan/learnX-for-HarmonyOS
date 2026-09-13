/*
 * 公告列表状态的组装点（features/notices）。
 *
 * **必须是进程内单例**：学期切换的编排（features/courses/SemesterSwitch）要在
 * 公告页可能还没被打开的情况下也驱动一次公告重取；而页面自己 new 一份 store 时，
 * 编排拿不到那份 store，公告列表就永远停在旧学期的数据上。
 *
 * 与 courseListStore / fileListStore 同一模式：界面只依赖 NoticeListStore 的接口，
 * 取数实现（真实 / mock）只在 repository provider 里被选定一次。
 */

import { Logger } from '../../core/log/Logger';
import { NoticeListStore } from './NoticeListStore';
import { createNoticeRepository } from './repository/NoticeRepositoryProvider';

const logger: Logger = new Logger('features.notices.provider');

let store: NoticeListStore | null = null;

/** 当前生效的公告列表 store（进程内单例）。 */
export function noticeListStore(): NoticeListStore {
  if (store === null) {
    store = new NoticeListStore(createNoticeRepository());
    logger.info('notice list store wired: process singleton (semester switch drives it)');
  }
  return store;
}
