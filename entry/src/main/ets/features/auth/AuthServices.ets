/*
 * 认证的装配点（features/auth）：把"平台能力"与"领域规则"接到一起。
 *
 * 为什么放在 features 而不是 core：这里要同时 import core（asset / crypto / http / web）与
 * domain（指纹格式、凭据记录），只有 features 允许两个方向都依赖（spec 第 2 节的分层）。
 * 也正因为如此，**它不会被任何单测 import**——单测只碰 domain 与 data 的注入式接缝。
 *
 * ticket 08 新增的装配（全部是把 06 的零件 + 07 的凭据库接到一起，没有新机制）：
 *   - `loginClient`：纯 HTTP 7 步登录，cookie jar 就用 `session` 的那一个；
 *   - `loginAction`：从凭据库读 → 登录 → **成功才 adopt 会话**（内存），并且是 re-auth 的唯一出口；
 *   - `restorer`：冷启动静默重登（单飞 + 整体超时 + 失败分类）；
 *   - `runner`：数据路径入口（先确保会话 → SessionGate 包任务），ticket 09 的三域仓储用它。
 *
 * 会话 cookie 只在内存（ADR-0004）：本文件没有任何 preferences / 文件写入。
 */

import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { AssetSecretStore } from '../../core/asset/AssetSecretStore';
import { appVersionName, deviceProductModel } from '../../core/device/AppIdentity';
import { Logger } from '../../core/log/Logger';
import { updateWebSessionHeader } from '../../core/web/SessionHeaderProvider';
import { AuthSession } from '../../data/auth/AuthSession';
import { CredentialStore } from '../../data/auth/CredentialStore';
import { EnrollmentSession } from '../../data/auth/EnrollmentSession';
import { LoginClient } from '../../data/auth/LoginClient';
import { ReAuthCoordinator, SessionGate } from '../../data/auth/ReAuth';
import { LoginResult, FailReason, CredentialEncryptor, EncryptorResult } from '../../data/auth/AuthTypes';
import {
  AuthedTaskRunner, SessionRestorer, credentialsFor
} from '../../data/auth/SessionRestore';
import { HttpFetchPort } from '../../data/remote/HttpFetchPort';
import { Session } from '../../data/remote/Requests';
import { encryptPasswordWithSm2 } from '../../core/crypto/Sm2Cipher';
import { CredentialRecord } from '../../domain/auth/CredentialRecord';
import { composeDeviceName, formatUuidV4, redactSecret } from '../../domain/auth/DeviceIdentity';

const logger: Logger = new Logger('features.auth.services');

/** 平台 SM2 加密器 → 登录流要的注入签名（形状相同，做一次显式适配，避免隐式结构化类型）。 */
function sm2Encryptor(): CredentialEncryptor {
  return (password: string, publicKeyHex: string): EncryptorResult => {
    const encrypted = encryptPasswordWithSm2(password, publicKeyHex);
    const result: EncryptorResult = { ok: encrypted.ok, cipherText: encrypted.cipherText };
    if (encrypted.error !== undefined) {
      result.error = encrypted.error;
    }
    return result;
  };
}

export class AuthServices {
  /** 内存会话（cookie jar + Session + 凭据缓存）；ADR-0004：绝不落盘。 */
  readonly session: AuthSession = new AuthSession();
  /** 凭据库：设备侧实现是 asset store（DEVICE_UNLOCKED，无额外开关）。 */
  readonly credentials: CredentialStore = new CredentialStore(new AssetSecretStore());
  /** 登记会话收割（把浏览器的 cookie 交给 HTTP 客户端）。 */
  readonly enrollment: EnrollmentSession;
  /** 纯 HTTP 登录客户端（重登用；登录路径零 WebView）。 */
  readonly loginClient: LoginClient;
  /** 冷启动静默重登（单飞 + 超时 + 分类）。 */
  readonly restorer: SessionRestorer;
  /** 数据路径入口（ticket 09 用）。 */
  readonly runner: AuthedTaskRunner;

  constructor() {
    this.enrollment = new EnrollmentSession(this.session.getJar(), new HttpFetchPort(),
      new Logger('data.auth.enrollment'));
    this.loginClient = new LoginClient({
      jar: this.session.getJar(),
      port: new HttpFetchPort(),
      encrypt: sm2Encryptor(),
      logger: new Logger('data.auth.login')
    });
    const coordinator: ReAuthCoordinator = new ReAuthCoordinator(
      (): Promise<LoginResult> => this.loginFromStoredCredentials(),
      new Logger('data.auth.reauth'));
    this.restorer = new SessionRestorer({
      coordinator: coordinator,
      currentSession: (): Session | null => this.session.current(),
      logger: new Logger('data.auth.restore')
    });
    const gate: SessionGate = new SessionGate(coordinator, new Logger('data.auth.gate'));
    this.runner = new AuthedTaskRunner(this.restorer, gate,
      (): Session | null => this.session.current(), new Logger('data.auth.runner'));
  }

  /**
   * re-auth 的**唯一出口**：读凭据 → 纯 HTTP 登录 → **成功才把会话放进内存**。
   *
   * 为什么放在这里而不是 data 层：读盘（asset）是平台能力，只有 features 能同时看到
   * 凭据库与登录客户端；data 层的 SessionRestorer 只接收"登录动作"这个函数。
   * 失败时**不 adopt**：宁可不留会话，也不要让界面以为登上了（验收第 3 条）。
   */
  private async loginFromStoredCredentials(): Promise<LoginResult> {
    const record: CredentialRecord | undefined = await this.credentials.load();
    if (record === undefined) {
      return LoginResult.failure(FailReason.NO_CREDENTIAL, 'no usable persisted credentials');
    }
    this.session.setCredentials(record);
    const result: LoginResult = await this.loginClient.login(credentialsFor(record));
    if (result.ok && result.session !== undefined) {
      this.session.adopt(result.session);
      // Web 容器与模板的会话注入点（ticket 04 预留、07 接上）：这里让它随重登一起轮换。
      updateWebSessionHeader(result.session.cookie, result.session.csrfToken);
      logger.info('re-auth session adopted: language=' + result.language
        + ' ' + this.session.getJar().describe());
    } else {
      logger.warn('re-auth session NOT adopted: reason=' + result.reason + ' diag=' + result.diagnostic);
    }
    return result;
  }

  /** deviceName（spec 第 5 节）：仅登记时上报，HTTP 重登不带它。 */
  deviceName(): string {
    const name: string = composeDeviceName(appVersionName(), deviceProductModel());
    logger.info('device name resolved: ' + name);
    return name;
  }

  /**
   * 生成本机设备指纹：16 字节平台安全随机 → UUID v4 文本。
   *
   * 随机源用 cryptoFramework（参考实现是 react-native-securerandom，helpers/fingerprint.ts:9），
   * 格式规则在 domain/auth/DeviceIdentity。**这个值只在日志里以脱敏形式出现**（验收第 5 条）。
   */
  newFingerprint(): string {
    try {
      const random: cryptoFramework.Random = cryptoFramework.createRandom();
      const blob: cryptoFramework.DataBlob = random.generateRandomSync(16);
      const bytes: number[] = [];
      for (let i = 0; i < blob.data.length; i++) {
        bytes.push(blob.data[i]);
      }
      const value: string = formatUuidV4(bytes);
      logger.info('device fingerprint generated: ' + redactSecret(value));
      return value;
    } catch (error) {
      // 取不到平台随机就不要继续：一条可预测的指纹比"登记失败"更糟。
      logger.error('cryptoFramework random failed: ' + (error as Error).message);
      return '';
    }
  }
}

/** 进程内单例（装配点由 UI 持有；测试不碰这里）。 */
export const authServices: AuthServices = new AuthServices();
