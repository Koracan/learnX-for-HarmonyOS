/*
 * 登记的装配点（features/auth）：把"平台能力"与"领域规则"接到一起。
 *
 * 为什么放在 features 而不是 core：这里要同时 import core（asset / http / crypto）与
 * domain（指纹格式、凭据记录），只有 features 允许两个方向都依赖（spec 第 2 节的分层）。
 * 也正因为如此，**它不会被任何单测 import**——单测只碰 domain 与 data 的注入式接缝。
 */

import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { AssetSecretStore } from '../../core/asset/AssetSecretStore';
import { appVersionName, deviceProductModel } from '../../core/device/AppIdentity';
import { Logger } from '../../core/log/Logger';
import { AuthSession } from '../../data/auth/AuthSession';
import { CredentialStore } from '../../data/auth/CredentialStore';
import { EnrollmentSession } from '../../data/auth/EnrollmentSession';
import { HttpFetchPort } from '../../data/remote/HttpFetchPort';
import { composeDeviceName, formatUuidV4, redactSecret } from '../../domain/auth/DeviceIdentity';

const logger: Logger = new Logger('features.auth.services');

export class AuthServices {
  /** 内存会话（cookie jar + Session + 凭据缓存）；ADR-0004：绝不落盘。 */
  readonly session: AuthSession = new AuthSession();
  /** 凭据库：设备侧实现是 asset store（DEVICE_UNLOCKED，无额外开关）。 */
  readonly credentials: CredentialStore = new CredentialStore(new AssetSecretStore());
  /** 登记会话收割（把浏览器的 cookie 交给 HTTP 客户端）。 */
  readonly enrollment: EnrollmentSession;

  constructor() {
    this.enrollment = new EnrollmentSession(this.session.getJar(), new HttpFetchPort(),
      new Logger('data.auth.enrollment'));
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
