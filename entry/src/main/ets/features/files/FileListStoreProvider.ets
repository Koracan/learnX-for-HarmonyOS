/*
 * 文件列表状态的组装点（features/files）。
 *
 * **必须是进程内单例**：学期切换的编排（features/courses/SemesterSwitch）要在
 * 文件页可能还没被打开的情况下也驱动一次文件重取；而页面自己 new 一份 store 时，
 * 编排拿不到那份 store，文件列表就永远停在旧学期的数据上。
 *
 * 与 courseListStore / noticeListStore 同一模式。
 */

import { Logger } from '../../core/log/Logger';
import { FileListStore } from './FileListStore';
import { fileRepository } from './repository/FileRepositoryProvider';

const logger: Logger = new Logger('features.files.provider');

let store: FileListStore | null = null;

/** 当前生效的文件列表 store（进程内单例）。 */
export function fileListStore(): FileListStore {
  if (store === null) {
    store = new FileListStore(fileRepository());
    logger.info('file list store wired: process singleton (semester switch drives it)');
  }
  return store;
}
