/*
 * 收藏 / 归档 / 隐藏状态的**组装点**（composition root，features/marks）。
 *
 * 与 features/notices/repository/NoticeRepositoryProvider、features/files/repository/
 * FileRepositoryProvider 同一模式：界面只依赖 `CollectionFlagsStore` 的接口，
 * 设备实现（preferences）只在这里被选定一次。
 *
 * **必须是进程内单例**：课程页屏蔽一门课要立刻影响公告 / 作业 / 文件三个列表
 * （参考实现里它们共用同一份 redux state），四个页面各持一份就做不到。
 *
 * Context 拿不到时降级到内存实现（状态仍然生效，只是不落盘），并把这件事打进 hilog ——
 * 不静默。
 */

import { common } from '@kit.AbilityKit';
import { Logger } from '../../core/log/Logger';
import {
  CollectionFlagsPort, CollectionFlagsStore, InMemoryCollectionFlagsPort
} from '../../data/marks/CollectionFlagsStore';
import { PreferencesCollectionFlagsPort } from '../../data/marks/PreferencesCollectionFlags';

const logger: Logger = new Logger('features.marks.provider');

/** 取宿主 Context：与两个既有 provider 同一处置（拿不到时显式降级 + 日志）。 */
function hostContext(): common.Context | null {
  try {
    return getContext() as common.Context;
  } catch (error) {
    logger.error('no host context for the collection flags store: ' + (error as Error).message);
    return null;
  }
}

let store: CollectionFlagsStore | null = null;

/** 当前生效的收藏 / 归档 / 屏蔽状态 store（进程内单例）。 */
export function collectionFlagsStore(): CollectionFlagsStore {
  if (store === null) {
    const context: common.Context | null = hostContext();
    const port: CollectionFlagsPort = context === null
      ? new InMemoryCollectionFlagsPort()
      : new PreferencesCollectionFlagsPort(context);
    store = new CollectionFlagsStore(port);
    logger.info('collection flags store wired: persistence='
      + (context === null ? 'memory' : 'preferences'));
  }
  return store;
}
