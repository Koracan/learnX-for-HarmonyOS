/*
 * 凭据库（data）：把 domain 的 CredentialRecord 存进注入的 SecretStore（设备侧是 asset store）。
 *
 * 归属（ticket 07 Comments 的接口约束）：**凭据落盘归本 ticket**；ticket 06 的 LoginClient
 * 只接收入参、自己不读盘；ticket 08 的重登从这里取凭据。
 *
 * spec 第 4 节：asset store，DEVICE_UNLOCKED，**无额外开关**——没有"记住密码"这类开关要读，
 * 因此本文件里也**不该出现**任何 preferences / 设置项。
 *
 * 日志纪律（验收第 5 条）：记录数与长度、脱敏后的指纹前缀，绝不记录口令或完整指纹。
 */

import { SecretStore } from '../../core/asset/SecretStorePort';
import { Logger } from '../../core/log/Logger';
import {
  CredentialRecord, decodeCredentialRecord, describeCredentialRecord, encodeCredentialRecord,
  isCredentialRecordComplete
} from '../../domain/auth/CredentialRecord';

/** asset 别名（常量：改它等于让老用户"掉登录"，不要随手改）。 */
export const CREDENTIAL_ALIAS: string = 'learnOH.credentials';

export class CredentialStore {
  private readonly secrets: SecretStore;
  private readonly alias: string;
  private readonly logger: Logger = new Logger('data.auth.credentials');

  constructor(secrets: SecretStore, alias: string = CREDENTIAL_ALIAS) {
    this.secrets = secrets;
    this.alias = alias;
  }

  /**
   * 写入凭据。**不完整的记录一律不写**（宁可不登记，也不要留一条半凭据让重登去试）——
   * 对应验收第 4 条"不残留半登记状态"。
   */
  async save(record: CredentialRecord): Promise<boolean> {
    if (!isCredentialRecordComplete(record)) {
      this.logger.error('refusing to persist incomplete credentials: ' + describeCredentialRecord(record));
      return false;
    }
    const saved: boolean = await this.secrets.write(this.alias, encodeCredentialRecord(record));
    this.logger.info('credentials saved: ok=' + saved.toString() + ' ' + describeCredentialRecord(record));
    return saved;
  }

  /**
   * 读凭据。没有 / 损坏 / 版本不认识 / 不完整，一律返回 undefined（= 需要重新登记），
   * 不抛异常：spec 第 5 节要求任何非预期情况都显式降级到 Enrollment。
   */
  async load(): Promise<CredentialRecord | undefined> {
    const text: string | null = await this.secrets.read(this.alias);
    if (text === null) {
      this.logger.info('no persisted credentials');
      return undefined;
    }
    const record: CredentialRecord | undefined = decodeCredentialRecord(text);
    if (record === undefined) {
      this.logger.error('persisted credentials unusable (corrupt or unknown schema): chars=' + text.length.toString());
      return undefined;
    }
    if (!isCredentialRecordComplete(record)) {
      this.logger.error('persisted credentials incomplete: ' + describeCredentialRecord(record));
      return undefined;
    }
    this.logger.info('credentials loaded: ' + describeCredentialRecord(record));
    return record;
  }

  /** 清除（登出 / 重新登记前）。 */
  async clear(): Promise<boolean> {
    const cleared: boolean = await this.secrets.remove(this.alias);
    this.logger.info('credentials cleared: ok=' + cleared.toString());
    return cleared;
  }
}
