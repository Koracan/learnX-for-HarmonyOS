/*
 * 日志导出的**设备侧编排**：拉起系统文件选择器 → 按纯逻辑选定的目标写盘 → 量真实字节数。
 *
 * 决策全部在 LogExportTarget.ets（纯逻辑，离线可测）；这里只做三件只有设备上才成立的事，
 * 并且每一件都把**实际生效值**打进 hilog：
 *   1. 选择：`picker.DocumentViewPicker.save()` 的返回 URI（或空列表 = 用户取消）与平台错误码；
 *   2. 落盘：写完之后 statSync 量到的**真实字节数** —— 它就是外部 ls -l 会看到的那个数，
 *      也是界面文案里那个字节数的唯一出处（两者必然逐字一致）；
 *   3. 写盘失败时带着平台原话重新决策一次（降级到私有目录），不把失败报成成功。
 *
 * **不申请任何权限**：位置是用户在系统选择器里自己挑的，应用侧不需要 `READ_WRITE_*_DIRECTORY`
 * 这类受限权限（它们要 ACL 放行，发布 Profile 里没有，AGC 上传会报 ACL permission consistency）。
 *
 * 降级是显式的：选择器不可用 / 用户没选成 / 选中的位置写不进去时落回应用私有目录，
 * 但结局类别与文案都会说明「外部拿不到」，绝不假装导出到了用户拿得到的地方。
 */

import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { LogBuffer, logBuffer } from './LogBuffer';
import { Logger } from './Logger';
import {
  LogExportDestination, LogExportMessage, LogExportPickResult, LogExportPickState, LogExportPlan,
  classifyPickError, classifyPickedUris, describeLogExportPlan, logExportFileName,
  logExportMessage, logExportPickStateName, planLogExport
} from './LogExportTarget';

const logger: Logger = new Logger('core.log.export');

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
 * 拉起系统「保存到…」，把用户挑的位置变成一次决策输入。
 *
 * 三件实测事实都从这里出来：返回的 URI、空列表（用户取消）、以及平台错误码 ——
 * 码到结局的映射在纯逻辑里（`classifyPickError` / `classifyPickedUris`），这里只负责量。
 */
export async function pickLogExportTarget(context: common.Context, fileName: string): Promise<LogExportPickResult> {
  try {
    const options: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
    options.newFileNames = [fileName];
    const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
    const uris: Array<string> | undefined = await documentPicker.save(options);
    const state: LogExportPickState = classifyPickedUris(uris);
    const shown: string = uris === undefined ? '[]' : JSON.stringify(uris);
    logger.info('log export pick: state=' + logExportPickStateName(state) + ' uris=' + shown);
    if (state === LogExportPickState.PICKED && uris !== undefined) {
      return { state: state, uri: uris[0], error: '' };
    }
    // 取消是用户的选择：不给它配错误文本，文案里也不能出现「失败」。
    return { state: state, uri: '', error: state === LogExportPickState.CANCELLED ? '' : 'no uri returned' };
  } catch (error) {
    const failure: BusinessError = error as BusinessError;
    const text: string = errorText(failure);
    const state: LogExportPickState = classifyPickError(failure.code);
    logger.error('log export pick failed: state=' + logExportPickStateName(state)
      + ' code=' + String(failure.code) + ' error=' + text);
    return { state: state, uri: '', error: text };
  }
}

/** 私有兜底目录不存在就建（filesDir/logs 首次导出时并不存在）。 */
function ensureDirectory(dir: string): void {
  if (!fs.accessSync(dir)) {
    fs.mkdirSync(dir, true);
  }
}

/** 落盘后的真实字节数（stat 失败时退回 writeSync 的返回值）＋ 一条自证日志。 */
function reportWritten(path: string, text: string, written: number): number {
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
 * 写**用户选中的位置**（选择器给的 URI）：URI 由系统授权，既不需要建目录也不需要权限。
 * 任何失败都抛给调用方 —— 由它带着平台原话重新决策（降级），不许吞掉。
 */
function writeLogFileAtUri(uri: string, text: string): number {
  const file: fs.File = fs.openSync(uri, fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
  let written: number = 0;
  try {
    // 字符串进来由平台按 UTF-8 编码写出，writeSync 返回的是**字节数**（不是字符串长度）。
    written = fs.writeSync(file.fd, text);
  } finally {
    fs.closeSync(file);
  }
  return reportWritten(uri, text, written);
}

/** 写私有兜底路径（先建目录再写），返回磁盘上的真实字节数；任何失败都抛给调用方。 */
function writeLogFile(path: string, text: string): number {
  ensureDirectory(path.substring(0, path.lastIndexOf('/')));
  const file: fs.File = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
  let written: number = 0;
  try {
    written = fs.writeSync(file.fd, text);
  } finally {
    fs.closeSync(file);
  }
  return reportWritten(path, text, written);
}

/**
 * 导出日志：把内存缓冲写到**用户在系统选择器里挑的位置**。
 *
 * 依次是：拉起选择器 → 决策（planLogExport）→ 写盘；写不进去就带原因重新决策一次落回私有目录。
 * 用户取消既不写盘也不报错；降级必须显式 —— 不许把一次写失败报成「已导出到你选的位置」。
 */
export async function exportLogs(context: common.Context, buffer: LogBuffer = logBuffer): Promise<LogExportReport> {
  const text: string = buffer.toText();
  const recordCount: number = buffer.size();
  const timestamp: number = Date.now();

  const pick: LogExportPickResult = await pickLogExportTarget(context, logExportFileName(timestamp));
  let plan: LogExportPlan = planLogExport({
    pick: pick,
    writeError: '',
    privateDir: context.filesDir,
    timestamp: timestamp
  });
  logger.info('log export plan: ' + describeLogExportPlan(plan));

  let byteLength: number = 0;
  if (plan.destination === LogExportDestination.PICKED) {
    try {
      byteLength = writeLogFileAtUri(plan.path, text);
    } catch (error) {
      const detail: string = 'picked=' + plan.path + ' write=' + errorText(error as BusinessError);
      logger.error('log export picked-target write failed, re-planning to the private fallback: ' + detail);
      plan = planLogExport({
        pick: pick,
        writeError: detail,
        privateDir: context.filesDir,
        timestamp: timestamp
      });
      logger.info('log export re-plan: ' + describeLogExportPlan(plan));
      if (plan.destination === LogExportDestination.PRIVATE) {
        byteLength = writeLogFile(plan.path, text);
      }
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
