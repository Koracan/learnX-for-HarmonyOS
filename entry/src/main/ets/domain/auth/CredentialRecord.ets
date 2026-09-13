/*
 * 凭据记录（domain，纯逻辑）：加密落盘的那一份 payload 的形状、编解码与脱敏。
 *
 * 参考实现把这几项放进 redux-persist 的 `auth` 切片、用 react-native-secure-key-store 落盘
 * （reference/learnOH-old/src/data/reducers/root.ts:46-56 的 whitelist：
 *  username / password / fingerPrint / fingerGenPrint / fingerGenPrint3）。
 * 本工程的对应物是 **asset store（DEVICE_UNLOCKED，无额外开关）**；
 * 这里只负责"记录 ↔ 文本"，不碰任何平台 API，因此可在 host 单测里逐条断言。
 *
 * **会话 cookie / CSRF 绝不在这里**（ADR-0004）：那是内存态，本文件没有它们的字段，
 * 新增字段前请先读 ADR-0004。
 */

import { describeFingerprints } from './DeviceIdentity';

/** payload 版本号；将来改字段时递增，读到不认识的高版本一律当作"没有凭据"。 */
export const CREDENTIAL_SCHEMA_VERSION: number = 1;

/** 落盘的凭据记录。 */
export interface CredentialRecord {
  schemaVersion: number;
  username: string;
  password: string;
  /** **我们生成的**设备指纹：它必须与 saveFinger 上报给服务端的值逐字相同。 */
  fingerPrint: string;
  /** 站点自己写在页面里的两个指纹（来自 localStorage），我们只如实保存与回放。 */
  fingerGenPrint: string;
  fingerGenPrint3: string;
}

/** 组装（只做形状，不校验非空——空值也允许写，由调用方决定是否降级）。 */
export function createCredentialRecord(username: string, password: string, fingerPrint: string,
  fingerGenPrint: string, fingerGenPrint3: string): CredentialRecord {
  return {
    schemaVersion: CREDENTIAL_SCHEMA_VERSION,
    username: username,
    password: password,
    fingerPrint: fingerPrint,
    fingerGenPrint: fingerGenPrint,
    fingerGenPrint3: fingerGenPrint3
  };
}

/**
 * 判断记录是否"可用于重登"：账号、口令、我们生成的指纹三者缺一不可。
 *
 * 与参考实现对齐：`login()` 的判定是 `username && password && fingerPrint` 三者齐全
 * （reference/learnOH-old/src/data/actions/auth.ts:51,89-96），
 * `fingerGenPrint`/`fingerGenPrint3` 缺省可以为空串（同 auth.ts:32-33 的默认值）。
 */
export function isCredentialRecordComplete(record: CredentialRecord): boolean {
  return record.username.length > 0 && record.password.length > 0 && record.fingerPrint.length > 0;
}

/** 记录 → 落盘文本。 */
export function encodeCredentialRecord(record: CredentialRecord): string {
  return JSON.stringify(record);
}

/**
 * 落盘文本 → 记录。
 *
 * 失败一律返回 undefined（不抛异常）：JSON 损坏、版本不认识、字段缺失或类型不对，
 * 都按"没有凭据"处理——要求显式降级回 Enrollment，而不是拿半条记录去重登。
 */
export function decodeCredentialRecord(text: string): CredentialRecord | undefined {
  if (text.length === 0) {
    return undefined;
  }
  let parsed: Object;
  try {
    parsed = JSON.parse(text) as Object;
  } catch (error) {
    return undefined;
  }
  const root: Record<string, Object> = parsed as Record<string, Object>;
  if (root === null || root === undefined) {
    return undefined;
  }
  // 版本必须是**数字**：字符串 "1" 会被 Number() 悄悄接受，而"字段类型不对"意味着这份
  // payload 不是我们写的（或被人改过），应当按"没有凭据"处理而不是猜测。
  const versionValue: Object | undefined = root['schemaVersion'];
  if (versionValue === undefined || versionValue === null || typeof versionValue !== 'number') {
    return undefined;
  }
  const version: number = versionValue as number;
  if (version !== CREDENTIAL_SCHEMA_VERSION) {
    return undefined;
  }
  const username: string = readString(root, 'username');
  const password: string = readString(root, 'password');
  const fingerPrint: string = readString(root, 'fingerPrint');
  const fingerGenPrint: string = readString(root, 'fingerGenPrint');
  const fingerGenPrint3: string = readString(root, 'fingerGenPrint3');
  if (username.length === 0 || password.length === 0 || fingerPrint.length === 0) {
    return undefined;
  }
  return {
    schemaVersion: version,
    username: username,
    password: password,
    fingerPrint: fingerPrint,
    fingerGenPrint: fingerGenPrint,
    fingerGenPrint3: fingerGenPrint3
  };
}

function readString(root: Record<string, Object>, key: string): string {
  const value: Object | undefined = root[key];
  if (value === undefined || value === null) {
    return '';
  }
  const text: string = String(value);
  return text === 'undefined' || text === 'null' ? '' : text;
}

/**
 * 诊断串（**脱敏**，可安全进日志/导出文件）：
 * 只给字段长度、账号长度、以及三个指纹的 4 字符前缀，绝不给口令或完整指纹。
 */
export function describeCredentialRecord(record: CredentialRecord): string {
  return 'schema=' + record.schemaVersion.toString()
    + ' usernameChars=' + record.username.length.toString()
    + ' passwordChars=' + record.password.length.toString()
    + ' ' + describeFingerprints(record.fingerPrint, record.fingerGenPrint, record.fingerGenPrint3);
}
