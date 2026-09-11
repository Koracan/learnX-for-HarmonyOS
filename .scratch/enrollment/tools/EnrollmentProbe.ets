/*
 * ticket 07 证据探针（**仅取证用，绝不入库**）。
 *
 * 为什么需要它：验收第 3 条要求"凭据加密落盘；重启应用后仍处于已登记状态"，而"完整登记"
 * 需要用户本人完成短信验证。在没有真实凭据的前提下，唯一能证明**落盘路径与启动判定**
 * 可用的办法，是用**合成凭据**走一遍真实代码（AssetSecretStore → CredentialStore →
 * AuthStore.loadPersisted），并在**杀进程重启**后读回来。
 *
 * 它写进去的是合成值（probe-user / probe-not-a-real-password），不是任何真实账号或口令；
 * 跑完由 `clear` 动作删除，并在复原探针后重新构建一次确认"未登记 → 登录页"。
 *
 * 驱动方式（EntryAbility.onCreate 里注入一行调用，want 参数区分动作）：
 *   hdc shell aa start -b com.koracan.learnOH -a EntryAbility --ps learnohProbe seed
 *   hdc shell aa start -b com.koracan.learnOH -a EntryAbility --ps learnohProbe verify
 *   hdc shell aa start -b com.koracan.learnOH -a EntryAbility --ps learnohProbe clear
 */

import { Want } from '@kit.AbilityKit';
import { AssetSecretStore } from '../asset/AssetSecretStore';
import { Logger } from '../log/Logger';
import { CREDENTIAL_ALIAS, CredentialStore } from '../../data/auth/CredentialStore';
import { createCredentialRecord, describeCredentialRecord } from '../../domain/auth/CredentialRecord';

const logger: Logger = new Logger('enrollment.probe');
const ACTION_KEY: string = 'learnohProbe';

/** 合成凭据（明显的占位值，避免与任何真实账号混淆）。 */
const PROBE_USERNAME: string = 'probe-user';
const PROBE_PASSWORD: string = 'probe-not-a-real-password';
const PROBE_FINGERPRINT: string = '0f0f0f0f-1a1a-4b4b-8c8c-2d2d2d2d2d2d';

function readAction(want: Want): string {
  try {
    const parameters: Record<string, Object> | undefined = want.parameters;
    if (parameters === undefined || parameters === null) {
      return '';
    }
    const value: Object | undefined = parameters[ACTION_KEY];
    if (value === undefined || value === null) {
      return '';
    }
    return String(value);
  } catch (error) {
    return '';
  }
}

async function runAction(action: string): Promise<void> {
  const store: CredentialStore = new CredentialStore(new AssetSecretStore(), CREDENTIAL_ALIAS);
  logger.info('probe start: action=' + action);
  if (action === 'seed') {
    const record = createCredentialRecord(PROBE_USERNAME, PROBE_PASSWORD, PROBE_FINGERPRINT, '', '');
    const saved: boolean = await store.save(record);
    const back = await store.load();
    logger.info('probe seed: saved=' + saved.toString()
      + ' readBack=' + (back !== undefined).toString()
      + ' ' + describeCredentialRecord(back === undefined ? record : back));
  } else if (action === 'verify') {
    const back = await store.load();
    logger.info('probe verify: found=' + (back !== undefined).toString()
      + (back === undefined ? '' : ' ' + describeCredentialRecord(back)));
  } else if (action === 'clear') {
    const cleared: boolean = await store.clear();
    const back = await store.load();
    logger.info('probe clear: cleared=' + cleared.toString()
      + ' foundAfterClear=' + (back !== undefined).toString());
  } else {
    logger.info('probe unknown action: ' + action);
  }
}

/** EntryAbility.onCreate 里调用（仅取证构建）。 */
export function runEnrollmentEvidenceProbe(want: Want): void {
  const action: string = readAction(want);
  if (action.length === 0) {
    logger.info('probe skipped: no ' + ACTION_KEY + ' parameter');
    return;
  }
  runAction(action);
}
