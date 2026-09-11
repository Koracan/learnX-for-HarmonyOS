/*
 * core.LogFormat 单测：统一日志格式（时间戳 + 级别 + 标签 + 消息）。
 * LogFormat 不依赖任何平台 API，故可在 Local Test 中直接跑。
 */

import { describe, it, expect } from '@ohos/hypium';
import { LogLevel, LogRecord, formatRecord, formatRecords, formatTimestamp, logLevelName } from '../main/ets/core/log/LogFormat';

const SAMPLE_TIMESTAMP: number = new Date(2026, 1, 3, 4, 5, 6, 7).getTime();

export default function logFormatTest() {
  describe('core.LogFormat', () => {
    it('formats the timestamp as YYYY-MM-DD HH:mm:ss.SSS', 0, () => {
      expect(formatTimestamp(SAMPLE_TIMESTAMP)).assertEqual('2026-02-03 04:05:06.007');
    });

    it('pads level names to a fixed width', 0, () => {
      expect(logLevelName(LogLevel.DEBUG)).assertEqual('DEBUG');
      expect(logLevelName(LogLevel.INFO)).assertEqual('INFO ');
      expect(logLevelName(LogLevel.WARN)).assertEqual('WARN ');
      expect(logLevelName(LogLevel.ERROR)).assertEqual('ERROR');
    });

    it('uses the unified record format with a module tag', 0, () => {
      const record: LogRecord = {
        timestamp: SAMPLE_TIMESTAMP,
        level: LogLevel.INFO,
        tag: 'data.notices',
        message: '抓取成功'
      };
      expect(formatRecord(record)).assertEqual('2026-02-03 04:05:06.007 INFO  [data.notices] 抓取成功');
    });

    it('joins records with a trailing newline', 0, () => {
      const records: LogRecord[] = [
        { timestamp: SAMPLE_TIMESTAMP, level: LogLevel.WARN, tag: 'ui.index', message: 'a' },
        { timestamp: SAMPLE_TIMESTAMP, level: LogLevel.ERROR, tag: 'ui.index', message: 'b' }
      ];
      const text: string = formatRecords(records, 'HEADER');
      expect(text.endsWith('\n')).assertTrue();
      const lines: string[] = text.split('\n');
      expect(lines.length).assertEqual(4);
      expect(lines[0]).assertEqual('HEADER');
      expect(lines[1].indexOf('WARN  [ui.index] a') > 0).assertTrue();
      expect(lines[2].indexOf('ERROR [ui.index] b') > 0).assertTrue();
      expect(lines[3]).assertEqual('');
      expect(formatRecords(records).split('\n').length).assertEqual(3);
    });
  });
}
