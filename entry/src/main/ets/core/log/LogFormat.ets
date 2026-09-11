/*
 * 日志的格式化与级别定义。此文件**不依赖任何平台 API**，可在 Hypium Local Test 中直接跑。
 */

/** 日志级别，数值越大越严重。 */
export enum LogLevel {
  DEBUG = 0,
  INFO = 1,
  WARN = 2,
  ERROR = 3
}

/** 一条日志记录。 */
export interface LogRecord {
  /** epoch 毫秒。 */
  timestamp: number;
  level: LogLevel;
  /** 模块标签，如 `data.notices`、`ui.index`。 */
  tag: string;
  message: string;
}

const LEVEL_NAMES: string[] = ['DEBUG', 'INFO ', 'WARN ', 'ERROR'];

/** 级别的定宽名称，用于对齐输出。 */
export function logLevelName(level: LogLevel): string {
  return LEVEL_NAMES[level];
}

function pad(value: number, width: number): string {
  let s: string = value.toString();
  while (s.length < width) {
    s = '0' + s;
  }
  return s;
}

/** `YYYY-MM-DD HH:mm:ss.SSS`（本地时区）。 */
export function formatTimestamp(timestamp: number): string {
  const d: Date = new Date(timestamp);
  const date: string = pad(d.getFullYear(), 4) + '-' + pad(d.getMonth() + 1, 2) + '-' + pad(d.getDate(), 2);
  const time: string = pad(d.getHours(), 2) + ':' + pad(d.getMinutes(), 2) + ':' + pad(d.getSeconds(), 2);
  return date + ' ' + time + '.' + pad(d.getMilliseconds(), 3);
}

/** 统一格式：`时间戳 级别 [标签] 消息`。 */
export function formatRecord(record: LogRecord): string {
  return formatTimestamp(record.timestamp) + ' ' + logLevelName(record.level) + ' [' + record.tag + '] ' + record.message;
}

/** 多行日志文本，可附一段头部说明。 */
export function formatRecords(records: LogRecord[], header: string = ''): string {
  const lines: string[] = [];
  if (header.length > 0) {
    lines.push(header);
  }
  for (let i = 0; i < records.length; i++) {
    lines.push(formatRecord(records[i]));
  }
  return lines.join('\n') + '\n';
}
