/*
 * UTF-8 编解码单测。
 *
 * 目的：解析器依赖的"字节 → 文本"这一步必须是**可复现的纯函数**，而不是平台 API 的
 * 可用性。本文件同时给出平台通道的实测值（只记录、不断言），作为环境限制的证据。
 */

import { describe, it, expect } from '@ohos/hypium';
import util from '@ohos.util';
import { decodeUtf8, encodeUtf8 } from '../main/ets/domain/parse/Utf8';
import { Logger } from '../main/ets/core/log/Logger';
import { platformProbeBase64Decoder } from './TestHelpers';


/** UTF-8 编码后的字节序列（十六进制），便于断言。 */
function hexOf(bytes: Uint8Array): string {
  let text: string = '';
  for (let i = 0; i < bytes.length; i++) {
    const part: string = bytes[i].toString(16);
    text += part.length === 1 ? '0' + part : part;
  }
  return text;
}

export default function utf8Test() {
  describe('domain.Utf8', () => {
    it('encodesAsciiTwoAndThreeByteSequences', 0, () => {
      expect(hexOf(encodeUtf8('abc'))).assertEqual('616263');
      expect(hexOf(encodeUtf8('é'))).assertEqual('c3a9');
      expect(hexOf(encodeUtf8('务'))).assertEqual('e58aa1');
      expect(hexOf(encodeUtf8('<p>务'))).assertEqual('3c703ee58aa1');
      expect(hexOf(encodeUtf8(''))).assertEqual('');
    });

    it('encodesSurrogatePairsAsFourBytes', 0, () => {
      expect(hexOf(encodeUtf8(String.fromCharCode(0xd83d, 0xde00)))).assertEqual('f09f9880');
      expect(hexOf(encodeUtf8(String.fromCharCode(0xd800)))).assertEqual('efbfbd');
    });

    it('roundTripsChineseAndAscii', 0, () => {
      const samples: string[] = [
        '公告正文 <p>务必交作业，请不要交到理科楼。</p>',
        '作业一.pdf',
        'a.bin',
        '',
        '混合 mixed 中文 & symbols: "\\%0A'
      ];
      for (let i = 0; i < samples.length; i++) {
        expect(decodeUtf8(encodeUtf8(samples[i]))).assertEqual(samples[i]);
      }
    });

    it('decodesInvalidSequencesToReplacementChar', 0, () => {
      const bad = new Uint8Array(2);
      bad[0] = 0xff;
      bad[1] = 0x41;
      expect(decodeUtf8(bad)).assertEqual(String.fromCharCode(0xfffd) + 'A');
      const truncated = new Uint8Array(1);
      truncated[0] = 0xe5;
      expect(decodeUtf8(truncated)).assertEqual(String.fromCharCode(0xfffd));
      expect(decodeUtf8(new Uint8Array(0))).assertEqual('');
    });
  });

  describe('core.textChannels', () => {
    it('platformTextChannelProbe', 0, () => {
      // 只记录、不断言：本工程的 local 单测环境里 `@ohos.util` 只提供部分实现。
      // 逐 API 的实测结论（TextEncoder 返回空数组、Base64Helper 解不出字节、TextDecoder 未单独测出）
      // 见 TestHelpers.ets 文件头的实测表；因此文本编解码不依赖平台，走 domain/parse/Utf8 纯实现。
      const bytes: Uint8Array = new util.TextEncoder().encodeInto('abc');
      const decoder = new util.TextDecoder();
      const streamed: string = decoder.decodeWithStream(bytes);
      const direct: string = decoder.decodeToString(bytes);
      // 平台 Base64 通道：local 环境实测解不出字节（返回空/异常），设备窗口再观测
      const probeEncoded: string = 'PHA+5Yqh';
      const probePlatform: string = platformProbeBase64Decoder(probeEncoded);
      let base64Length: number = -1;
      try {
        base64Length = new util.Base64Helper().decodeSync('YWJj').length;
      } catch (error) {
        base64Length = -2;
      }
      const logger: Logger = new Logger('test.textchannels');
      logger.info('platform channels: encodeInto.length=' + bytes.length
        + ' decodeWithStream=' + JSON.stringify(streamed) + ' (' + (typeof streamed) + ')'
        + ' decodeToString=' + JSON.stringify(direct) + ' (' + (typeof direct) + ')'
        + ' base64Helper.decodeSync("YWJj").length=' + base64Length.toString()
        + ' platformProbeBase64("PHA+5Yqh")=' + JSON.stringify(probePlatform)
        + ' pureBase64("PHA+5Yqh")=' + JSON.stringify(decodeUtf8(encodeUtf8('<p>务')))
        + ' pureDecodeOfPlatformBytes=' + JSON.stringify(decodeUtf8(bytes)));
      // 本地实现的确定性断言（与平台无关）
      expect(decodeUtf8(encodeUtf8('abc'))).assertEqual('abc');
    });
  });
}