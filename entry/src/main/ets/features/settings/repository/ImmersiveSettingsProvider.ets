/*
 * 沉浸式设置的组装点（features/settings）：进程内单例。
 *
 * 与 `features/files/repository/FileRepositoryProvider` 的 `fileSettingsStore()` 同一模式：
 * 值/语义在 `data/settings/ImmersiveSettings`，持久化在 `data/settings/PreferencesImmersiveSettings`，
 * **界面与启动恢复读的是同一个 store 实例**（否则"开关改过、重启又变回去"这类问题会被掩盖）。
 *
 * Context 拿不到时退回内存端口：值仍按默认值生效，界面照常可操作，只是不跨进程保留
 * （与文件设置同一降级口径 —— 不假装持久化成功）。
 */

import { common } from '@kit.AbilityKit';
import { Logger } from '../../../core/log/Logger';
import {
  ImmersiveSettingsStore, ImmersiveSettingsPort, InMemoryImmersiveSettingsPort
} from '../../../data/settings/ImmersiveSettings';
import { PreferencesImmersiveSettingsPort } from '../../../data/settings/PreferencesImmersiveSettings';
import { applyImmersiveMode } from '../../../core/window/ImmersiveWindow';

const logger: Logger = new Logger('features.settings.immersive');

let store: ImmersiveSettingsStore | null = null;

/** 取宿主 Context（与文件设置 provider 同一套退路）。 */
function hostContext(): common.Context | null {
  try {
    return getContext() as common.Context;
  } catch (error) {
    logger.error('no host context for the immersive settings store: ' + (error as Error).message);
    return null;
  }
}

/** 当前生效的沉浸式设置 store（进程内单例）。 */
export function immersiveSettingsStore(): ImmersiveSettingsStore {
  if (store === null) {
    const context: common.Context | null = hostContext();
    const port: ImmersiveSettingsPort = context === null
      ? new InMemoryImmersiveSettingsPort()
      : new PreferencesImmersiveSettingsPort(context);
    store = new ImmersiveSettingsStore(port);
    logger.info('immersive settings store wired: persistence='
      + (context === null ? 'memory' : 'preferences'));
  }
  return store;
}

/**
 * 启动时恢复沉浸式状态（`pages/Index` 在 aboutToAppear 里调用）。
 *
 * **"重启后保持"这条验收的落点**：参考实现的 `ImmersiveModeController`（`App.tsx:682-690`）
 * 在挂载时就会 `Immersive.setImmersive(immersiveMode)`，值来自持久化的 redux state；
 * 这里读 preferences 再调平台窗口接口，语义相同。**实际生效值进 hilog**（消费点自证口径）。
 */
export async function restoreImmersiveMode(context: common.Context): Promise<boolean> {
  const settings: ImmersiveSettingsStore = immersiveSettingsStore();
  await settings.load();
  const enabled: boolean = settings.current().immersiveMode;
  const applied: boolean = await applyImmersiveMode(context, enabled);
  logger.info('immersive restored on startup: persisted=' + enabled.toString()
    + ' applied=' + applied.toString());
  return applied;
}
