/*
 * 秘密存储端口（core）：凭据落盘的**唯一**抽象，零平台依赖，可在 host 单测里注入假实现。
 *
 * 为什么是一个端口：凭据要进 asset store（DEVICE_UNLOCKED，无额外开关），
 * 但"asset store 到底能不能用"要等设备才能验；把平台调用收敛在 core/asset/AssetSecretStore
 * （唯一 import @kit.AssetStoreKit 的文件）之后，凭据的编解码、完整性判定、降级策略
 * 都能在 host 上逐条测。
 *
 * 硬约束（ADR-0004）：这里只放**凭据**，会话 cookie / CSRF 绝不落盘。
 */

/** 一个按别名寻址的秘密存储。 */
export interface SecretStore {
  /** 读：不存在（或读失败）返回 null，不抛异常。 */
  read(alias: string): Promise<string | null>;
  /** 写：成功 true；任何失败 false（调用方据此决定是否降级，不吞掉结果）。 */
  write(alias: string, value: string): Promise<boolean>;
  /** 删：成功 true；本来就不存在也算 true（幂等）。 */
  remove(alias: string): Promise<boolean>;
}
