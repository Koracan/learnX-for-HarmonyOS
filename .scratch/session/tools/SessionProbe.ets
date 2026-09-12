/*
 * ticket 08 证据探针（**仅取证用，绝不入库**；由 .scratch/session/tools/run-session-probe.ps1
 * 临时拷贝到 entry/src/main/ets/core/codec/ 并在 finally 里删除 + 复原 EntryAbility）。
 *
 * 为什么需要它：验收第 1/3/4/5 条都需要"应用手里**有**一份凭据，于是冷启动会走纯 HTTP 静默重登"。
 * 真实凭据要用户手动完成短信登记（本 ticket 不做、也不经手），所以在拿到真实登记之前，用
 * **合成凭据**走一遍真实代码路径（AssetSecretStore → CredentialStore → AuthStore.start →
 * SessionRestorer → LoginClient.login），从而在设备上真实地：
 *   - 让应用向 id.tsinghua.edu.cn 发一次真请求（于是**内存 jar 里会有一个真实的 JSESSIONID**）；
 *   - 观察到重登失败时的**显式降级**（回登录页 + "需要重新验证" + 重试入口）；
 *   - 在**杀进程之后**扫描应用存储，证明那份会话 cookie 没有落盘（ADR-0004）。
 *
 * 它写进去的是明显的占位值（probe-user / probe-not-a-real-password / 0f0f…），
 * **不是任何真实账号、口令或指纹**；跑完由 clear 动作删除。
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

const logger: Logger = new Logger('session.probe');
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
  // 自证：这一行让日志能区分"探针生效"与"探针没跑"
  logger.info('session probe: action=' + action + ' syntheticCredentials=1 (NOT a real account)');
  if (action === 'seed') {
    const record = createCredentialRecord(PROBE_USERNAME, PROBE_PASSWORD, PROBE_FINGERPRINT, '', '');
    const saved: boolean = await store.save(record);
    const back = await store.load();
    logger.info('session probe seed: saved=' + saved.toString()
      + ' readBack=' + (back !== undefined).toString()
      + ' ' + describeCredentialRecord(back === undefined ? record : back));
  } else if (action === 'verify') {
    const back = await store.load();
    logger.info('session probe verify: found=' + (back !== undefined).toString()
      + (back === undefined ? '' : ' ' + describeCredentialRecord(back)));
  } else if (action === 'clear') {
    const cleared: boolean = await store.clear();
    const back = await store.load();
    logger.info('session probe clear: cleared=' + cleared.toString()
      + ' foundAfterClear=' + (back !== undefined).toString());
  } else {
    logger.info('session probe unknown action: ' + action);
  }
}

/** EntryAbility.onCreate 里调用（仅取证构建）。 */
export function runSessionEvidenceProbe(want: Want): void {
  const action: string = readAction(want);
  if (action.length === 0) {
    logger.info('session probe skipped: no ' + ACTION_KEY + ' parameter');
    return;
  }
  runAction(action);
}
