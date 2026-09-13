/*
 * 日志导出的**设备侧编排**：探测公共目录 → 申请运行时权限 → 按纯逻辑选定的目标写盘。
 *
 * 决策全部在 LogExportTarget.ets（纯逻辑，离线可测）；这里只做三件只有设备上才成立的事，
 * 并且每一件都把**实际生效值**打进 hilog：
 *   1. 探测：Environment.getUserDownloadDir() 的返回路径或平台错误码；
 *   2. 权限：requestPermissionsFromUser 的 authResults 与 dialogShownResults
 *      （弹窗没出现 + 被拒 = 永久拒绝，文案要告诉用户去系统设置里开）；
 *   3. 落盘：写完之后 statSync 量到的**真实字节数** —— 它就是外部 ls -l 会看到的那个数，
 *      也是界面文案里那个字节数的唯一出处（两者必然逐字一致）。
 *
 * 降级是显式的：公共目录不可用（权限被拒 / 平台不支持 / 写不进去）时落回应用私有目录，
 * 但结局类别与文案都会说明"外部拿不到"，绝不假装导出到了用户拿得到的地方。
 */

import { Environment, fileIo as fs } from '@kit.CoreFileKit';
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { LogBuffer, logBuffer } from './LogBuffer';
import { Logger } from './Logger';
import {
  LogExportDestination, LogExportDirState, LogExportMessage, LogExportPermission, LogExportPlan,
  LogExportPublicDir, describeLogExportPlan, logExportDirStateName, logExportFileName,
  logExportMessage, logExportPermissionName, planLogExport
} from './LogExportTarget';

const logger: Logger = new Logger('core.log.export');

/** 公共「下载」目录所需的运行时权限（module.json5 里已声明）。 */
const DOWNLOAD_DIRECTORY_PERMISSION: Permissions = 'ohos.permission.READ_WRITE_DOWNLOAD_DIRECTORY';

/** 平台错误码：能力不支持 / 权限未授予。 */
const ERR_NOT_SUPPORTED: number = 801;
const ERR_PERMISSION_DENIED: number = 201;

/** authResults 的三个取值：0 已授予 / -1 未授予 / 2 请求无效（平台没受理这次申请）。 */
const AUTH_GRANTED: number = 0;
const AUTH_DENIED: number = -1;
const AUTH_INVALID: number = 2;

/** 一次导出的完整结果（界面只消费 message 与 plan.path）。 */
export interface LogExportReport {
  plan: LogExportPlan;
  message: LogExportMessage;
  recordCount: number;
  /** 落盘后的真实字节数（statSync），与外部 ls -l 一致。 */
  byteLength: number;
}

/** 平台错误 → 一行可读文本（错误码可能不存在，所以整段兜住）。 */
function errorText(error: BusinessError): string {
  try {
    return '[' + String(error.code) + '] ' + String(error.message);
  } catch (inner) {
    return String(error);
  }
}

/**
 * 探测公共「下载」目录。
 *
 * 这里**不**申请权限：权限弹窗只该在确实需要时弹一次，调用方（exportLogs）拿到
 * NEEDS_PERMISSION 之后才去申请，再回来重探一次。
 */
export function probePublicDownloadDir(): LogExportPublicDir {
  try {
    const dir: string = Environment.getUserDownloadDir();
    if (dir.length === 0) {
      return { state: LogExportDirState.UNWRITABLE, path: '', error: 'getUserDownloadDir() returned an empty path' };
    }
    if (!fs.accessSync(dir)) {
      return { state: LogExportDirState.UNWRITABLE, path: dir, error: 'directory does not exist: ' + dir };
    }
    return { state: LogExportDirState.AVAILABLE, path: dir, error: '' };
  } catch (error) {
    const failure: BusinessError = error as BusinessError;
    const text: string = errorText(failure);
    if (failure.code === ERR_NOT_SUPPORTED) {
      return { state: LogExportDirState.UNSUPPORTED, path: '', error: text };
    }
    if (failure.code === ERR_PERMISSION_DENIED) {
      return { state: LogExportDirState.NEEDS_PERMISSION, path: '', error: text };
    }
    return { state: LogExportDirState.UNWRITABLE, path: '', error: text };
  }
}

/**
 * 申请公共目录权限，返回**实际生效**的授予状态。
 *
 * dialogShownResults 缺失时按"弹窗出现过"处理（保守：宁可说"被拒绝，可重试"，
 * 也不要把一次普通拒绝说成"永久拒绝，去系统设置里开"）。
 */
export async function requestDownloadDirectoryPermission(context: common.Context): Promise<LogExportPermission> {
  try {
    const manager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
    const result = await manager.requestPermissionsFromUser(context, [DOWNLOAD_DIRECTORY_PERMISSION]);
    const results: Array<number> = result.authResults;
    const first: number = results.length > 0 ? results[0] : AUTH_DENIED;
    let shown: boolean = true;
    const shownResults: Array<boolean> | undefined = result.dialogShownResults;
    if (shownResults !== undefined && shownResults.length > 0) {
      shown = shownResults[0];
    }
    const reasons: Array<number> | undefined = result.errorReasons;
    const reasonText: string = reasons === undefined ? 'n/a' : JSON.stringify(reasons);
    logger.info('log export permission: name=' + DOWNLOAD_DIRECTORY_PERMISSION
      + ' authResults=' + JSON.stringify(results)
      + ' dialogShown=' + shown.toString()
      + ' errorReasons=' + reasonText
      + ' effective=' + permissionNameFor(first, shown));
    if (first === AUTH_GRANTED) {
      return LogExportPermission.GRANTED;
    }
    if (first === AUTH_DENIED) {
      // 用户的选择：尊重它，不再往公共目录写。
      return shown ? LogExportPermission.DENIED : LogExportPermission.BLOCKED;
    }
    // 其余（含 2 = 请求无效）：平台没受理，这让"能不能写"成为一个实测问题。
    return LogExportPermission.NOT_REQUESTABLE;
  } catch (error) {
    logger.error('log export permission request failed: ' + errorText(error as BusinessError));
    return LogExportPermission.NOT_REQUESTABLE;
  }
}

/** 权限结果的三种结局名（只给 hilog 用）。 */
function permissionNameFor(authResult: number, dialogShown: boolean): string {
  if (authResult === AUTH_GRANTED) {
    return 'granted';
  }
  if (authResult === AUTH_DENIED) {
    return dialogShown ? 'denied' : 'blocked';
  }
  return 'not-requestable';
}

/** 目录不存在就建（私有兜底目录 filesDir/logs 首次导出时并不存在）。 */
function ensureDirectory(dir: string): void {
  if (!fs.accessSync(dir)) {
    fs.mkdirSync(dir, true);
  }
}

/** 写文件并返回**磁盘上的真实字节数**；任何失败都抛给调用方。 */
function writeLogFile(path: string, text: string): number {
  ensureDirectory(path.substring(0, path.lastIndexOf('/')));
  const file: fs.File = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
  let written: number = 0;
  try {
    // 字符串进来由平台按 UTF-8 编码写出，writeSync 返回的是**字节数**（不是字符串长度）。
    written = fs.writeSync(file.fd, text);
  } finally {
    fs.closeSync(file);
  }
  let bytes: number = written;
  try {
    bytes = fs.statSync(path).size;
  } catch (error) {
    logger.warn('log export stat failed, falling back to writeSync count: ' + errorText(error as BusinessError));
  }
  // 消费点自证：写出的字节数（writeSync）与文件系统报的字节数（statSync）都必须在这里出现。
  logger.info('log export wrote file: path=' + path
    + ' textLength=' + text.length.toString()
    + ' writeSync=' + written.toString()
    + ' statSize=' + bytes.toString());
  return bytes;
}

/**
 * 导出日志：把内存缓冲写到一个**用户拿得到**的位置。
 *
 * 依次是：探测公共目录 → 必要时申请权限并重探 → 决策（planLogExport）→ 写盘。
 * 公共目录"列得出来但写不进去"时重新决策一次落回私有目录 —— 降级必须显式，
 * 不许把一次写失败报成"已导出到公共目录"。
 */
export async function exportLogs(context: common.Context, buffer: LogBuffer = logBuffer): Promise<LogExportReport> {
  const text: string = buffer.toText();
  const recordCount: number = buffer.size();
  const timestamp: number = Date.now();

  let publicDir: LogExportPublicDir = probePublicDownloadDir();
  logger.info('log export probe: state=' + logExportDirStateName(publicDir.state)
    + ' path=' + publicDir.path + ' error=' + publicDir.error);

  let permission: LogExportPermission = LogExportPermission.GRANTED;
  const supported: boolean = publicDir.state === LogExportDirState.AVAILABLE
    || publicDir.state === LogExportDirState.NEEDS_PERMISSION;
  if (supported) {
    permission = await requestDownloadDirectoryPermission(context);
    if (permission === LogExportPermission.GRANTED) {
      // API 11 那条重载在未授权时直接抛 201、拿不到路径，所以授权之后必须重探。
      publicDir = probePublicDownloadDir();
    }
    logger.info('log export after permission: permission=' + logExportPermissionName(permission)
      + ' state=' + logExportDirStateName(publicDir.state)
      + ' path=' + publicDir.path + ' error=' + publicDir.error);
  }

  let plan: LogExportPlan = planLogExport({
    publicDir: publicDir,
    permission: permission,
    privateDir: context.filesDir,
    timestamp: timestamp,
    cancelled: false
  });
  logger.info('log export plan: ' + describeLogExportPlan(plan));

  let byteLength: number = 0;
  if (plan.destination === LogExportDestination.PUBLIC) {
    try {
      byteLength = writeLogFile(plan.path, text);
    } catch (error) {
      const detail: string = 'permission=' + logExportPermissionName(permission)
        + ' write=' + errorText(error as BusinessError);
      logger.error('log export public write failed, re-planning to the private fallback: ' + detail);
      plan = planLogExport({
        publicDir: { state: LogExportDirState.UNWRITABLE, path: publicDir.path, error: detail },
        permission: permission,
        privateDir: context.filesDir,
        timestamp: timestamp,
        cancelled: false
      });
      logger.info('log export re-plan: ' + describeLogExportPlan(plan));
      byteLength = writeLogFile(plan.path, text);
    }
  } else if (plan.destination === LogExportDestination.PRIVATE) {
    byteLength = writeLogFile(plan.path, text);
  }

  const message: LogExportMessage = logExportMessage(plan, recordCount, byteLength);
  logger.info('log export done: ' + describeLogExportPlan(plan)
    + ' records=' + recordCount.toString()
    + ' bytes=' + byteLength.toString());
  return { plan: plan, message: message, recordCount: recordCount, byteLength: byteLength };
}
