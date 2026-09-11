/*
 * 分级日志门面：带模块标签，统一格式（时间戳 + 级别 + 标签 + 消息），
 * 同时写 hilog 与内存环形缓冲（缓冲可由设置页导出为文本文件）。
 *
 * 用法：`const logger = new Logger('data.notices'); logger.info('抓取成功');`
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import { LogLevel, LogRecord, formatRecord } from './LogFormat';
import { logBuffer, LogBuffer } from './LogBuffer';

/** hilog 业务域，取 'LO' 的 ASCII 便于在 hilog 中辨认。 */
export const LOG_DOMAIN: number = 0x4C4F;

export class Logger {
  private static minLevel: LogLevel = LogLevel.DEBUG;
  private readonly tag: string;

  /** 全局最低输出级别，低于该级别的调用被直接丢弃。 */
  static setMinLevel(level: LogLevel): void {
    Logger.minLevel = level;
  }

  static getMinLevel(): LogLevel {
    return Logger.minLevel;
  }

  /**
   * @param tag 模块标签，建议用分层路径命名，如 `data.notices`、`core.http`、`ui.index`。
   */
  constructor(tag: string) {
    this.tag = tag;
  }

  getTag(): string {
    return this.tag;
  }

  debug(message: string): void {
    this.write(LogLevel.DEBUG, message);
  }

  info(message: string): void {
    this.write(LogLevel.INFO, message);
  }

  warn(message: string): void {
    this.write(LogLevel.WARN, message);
  }

  error(message: string): void {
    this.write(LogLevel.ERROR, message);
  }

  /** 追加到指定缓冲（默认全局缓冲）。 */
  write(level: LogLevel, message: string, buffer: LogBuffer = logBuffer): void {
    if (level < Logger.minLevel) {
      return;
    }
    const record: LogRecord = { timestamp: Date.now(), level: level, tag: this.tag, message: message };
    buffer.append(record);
    const line: string = formatRecord(record);
    switch (level) {
      case LogLevel.DEBUG:
        hilog.debug(LOG_DOMAIN, this.tag, '%{public}s', line);
        break;
      case LogLevel.INFO:
        hilog.info(LOG_DOMAIN, this.tag, '%{public}s', line);
        break;
      case LogLevel.WARN:
        hilog.warn(LOG_DOMAIN, this.tag, '%{public}s', line);
        break;
      default:
        hilog.error(LOG_DOMAIN, this.tag, '%{public}s', line);
        break;
    }
  }
}
