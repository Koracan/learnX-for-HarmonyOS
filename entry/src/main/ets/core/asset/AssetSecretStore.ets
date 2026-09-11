/*
 * asset store 实现（core）：凭据落盘的平台侧，唯一 import @kit.AssetStoreKit 的文件。
 *
 * spec 第 4 节：凭据（账号/密码/设备指纹）→ asset store，**DEVICE_UNLOCKED**，**无额外开关**。
 * 即：设备解锁后应用可直接读，不弹生物识别/口令框——与参考实现
 * （react-native-secure-key-store，reference/learnOH-old/src/helpers/secureStorage.ts）的
 * 用户可见行为一致：登记一次之后冷启动不再要求任何输入。
 *
 * 边界：
 *   - **只放凭据**。会话 cookie / CSRF 不在这里（ADR-0004），本文件没有任何 cookie 概念；
 *   - 失败不抛异常：读失败 → null，写/删失败 → false，全部落 hilog 供排查
 *     （错误码是 asset 的定义域，照原样记录，便于对照官方错误表）。
 *
 * 与 domain 的关系：这里 import `domain/parse/Utf8` 的**纯叶子工具**做文本 ↔ 字节，
 * 属于 spec 第 2 节明确允许的例外（core 允许引用受纯度保护的纯叶子工具）。
 */

import { asset } from '@kit.AssetStoreKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { encodeUtf8, decodeUtf8 } from '../../domain/parse/Utf8';
import { Logger } from '../log/Logger';
import { SecretStore } from './SecretStorePort';

const logger: Logger = new Logger('core.asset');

/** asset 的别名长度上限（256 字节，见 asset 官方文档）。 */
const ALIAS_MAX_BYTES: number = 256;

/** 平台错误码 → 文本（不认识的码原样给数字，便于日后比对官方错误表）。 */
function describeError(error: BusinessError | Error): string {
  const code: number | undefined = (error as BusinessError).code;
  const name: string = (error as Error).name;
  const message: string = (error as Error).message;
  return 'code=' + (code === undefined ? 'none' : code.toString())
    + ' name=' + name + ' message=' + message;
}

/** 基于 @ohos.security.asset 的凭据存储。 */
export class AssetSecretStore implements SecretStore {
  async write(alias: string, value: string): Promise<boolean> {
    const attributes: asset.AssetMap = this.attributesFor(alias, encodeUtf8(value));
    try {
      await asset.add(attributes);
      logger.info('asset write ok: aliasChars=' + alias.length.toString() + ' valueChars=' + value.length.toString());
      return true;
    } catch (error) {
      const businessError: BusinessError = error as BusinessError;
      // 同名已存在：先删再写（asset 没有 upsert）。这条是**正常路径**：重新登记会走到。
      if (businessError.code === asset.ErrorCode.DUPLICATED) {
        logger.info('asset write: duplicated, replacing');
        const removed: boolean = await this.remove(alias);
        if (!removed) {
          return false;
        }
        try {
          await asset.add(attributes);
          logger.info('asset write ok after replace: aliasChars=' + alias.length.toString());
          return true;
        } catch (retryError) {
          logger.error('asset write failed after replace: ' + describeError(retryError as BusinessError));
          return false;
        }
      }
      logger.error('asset write failed: ' + describeError(businessError));
      return false;
    }
  }

  async read(alias: string): Promise<string | null> {
    const query: asset.AssetMap = new Map<asset.Tag, asset.Value>();
    query.set(asset.Tag.ALIAS, encodeUtf8(alias));
    query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
    try {
      const results: Array<asset.AssetMap> = await asset.query(query);
      if (results.length === 0) {
        logger.info('asset read: not found');
        return null;
      }
      const secret: asset.Value | undefined = results[0].get(asset.Tag.SECRET);
      if (secret === undefined || secret === null) {
        logger.warn('asset read: result without SECRET');
        return null;
      }
      const text: string = decodeUtf8(secret as Uint8Array);
      logger.info('asset read ok: aliasChars=' + alias.length.toString() + ' valueChars=' + text.length.toString());
      return text;
    } catch (error) {
      const businessError: BusinessError = error as BusinessError;
      // NOT_FOUND 是正常路径（首次安装 / 已登出），只记 info。
      if (businessError.code === asset.ErrorCode.NOT_FOUND) {
        logger.info('asset read: not found');
        return null;
      }
      logger.error('asset read failed: ' + describeError(businessError));
      return null;
    }
  }

  async remove(alias: string): Promise<boolean> {
    const query: asset.AssetMap = new Map<asset.Tag, asset.Value>();
    query.set(asset.Tag.ALIAS, encodeUtf8(alias));
    try {
      await asset.remove(query);
      logger.info('asset remove ok: aliasChars=' + alias.length.toString());
      return true;
    } catch (error) {
      const businessError: BusinessError = error as BusinessError;
      if (businessError.code === asset.ErrorCode.NOT_FOUND) {
        logger.info('asset remove: nothing to remove');
        return true;
      }
      logger.error('asset remove failed: ' + describeError(businessError));
      return false;
    }
  }

  private attributesFor(alias: string, secret: Uint8Array): asset.AssetMap {
    const aliasBytes: Uint8Array = encodeUtf8(alias);
    if (aliasBytes.length > ALIAS_MAX_BYTES) {
      // 别名的长度上限是平台约束（256 字节）。调用方用的是常量别名，这里只做一次自证式记录，
      // 不改变行为：真正的失败仍由 asset 的错误码回来（日志里能看到 code=401）。
      logger.error('asset alias too long: bytes=' + aliasBytes.length.toString());
    }
    const attributes: asset.AssetMap = new Map<asset.Tag, asset.Value>();
    attributes.set(asset.Tag.ALIAS, aliasBytes);
    attributes.set(asset.Tag.SECRET, secret);
    attributes.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_UNLOCKED);
    return attributes;
  }
}
