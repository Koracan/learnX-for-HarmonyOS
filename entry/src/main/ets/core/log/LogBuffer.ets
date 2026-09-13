/*
 * 内存环形缓冲（Logger 写入，设置页导出）。
 *
 * 缓冲只负责把记录变成文本；**落到哪个目录**（公共目录 / 私有兜底）与权限申请
 * 都在同目录的 LogExport.ets（编排）与 LogExportTarget.ets（纯决策）里 ——
 * 本文件不碰文件系统，也就不需要 Context。
 */

import { LogRecord, formatRecords, formatTimestamp } from './LogFormat';

/** 默认保留的日志条数。 */
export const DEFAULT_LOG_CAPACITY: number = 500;

/** 固定容量环形缓冲，满时覆盖最旧记录。 */
export class LogBuffer {
  private readonly capacity: number;
  private readonly entries: Array<LogRecord | null>;
  private start: number = 0;
  private count: number = 0;

  constructor(capacity: number = DEFAULT_LOG_CAPACITY) {
    this.capacity = capacity > 0 ? capacity : 1;
    this.entries = new Array<LogRecord | null>(this.capacity).fill(null);
  }

  /** 追加一条记录；超出容量时丢弃最旧的一条。 */
  append(record: LogRecord): void {
    const index: number = (this.start + this.count) % this.capacity;
    this.entries[index] = record;
    if (this.count === this.capacity) {
      this.start = (this.start + 1) % this.capacity;
    } else {
      this.count++;
    }
  }

  size(): number {
    return this.count;
  }

  getCapacity(): number {
    return this.capacity;
  }

  clear(): void {
    this.entries.fill(null);
    this.start = 0;
    this.count = 0;
  }

  /** 按时间顺序（旧 → 新）返回快照。 */
  snapshot(): LogRecord[] {
    const result: LogRecord[] = [];
    for (let i = 0; i < this.count; i++) {
      const record: LogRecord | null = this.entries[(this.start + i) % this.capacity];
      if (record !== null) {
        result.push(record);
      }
    }
    return result;
  }

  /** 导出为文本。 */
  toText(): string {
    const records: LogRecord[] = this.snapshot();
    const header: string =
      'learnOH 日志导出\n' +
      '导出时间: ' + formatTimestamp(Date.now()) + '\n' +
      '记录数: ' + records.length + '/' + this.capacity + '\n' +
      '------------------------------------------------------------';
    return formatRecords(records, header);
  }
}

/** 全局日志缓冲：Logger 写入，设置页导出。 */
export const logBuffer: LogBuffer = new LogBuffer();

