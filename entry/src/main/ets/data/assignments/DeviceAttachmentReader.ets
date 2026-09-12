/*
 * 本地附件字节读取（data 层，平台实现）。
 *
 * picker 给的是平台 URI（`file://docs/…` 或 `file://media/…`），"把它读成字节"这一步
 * 只有平台能做，所以它是 `AttachmentBytesSource` 这个端口在设备侧的实现；
 * 单测注入替身，于是提交链路的组装可以在 host 上跑完。
 *
 * 参考实现的对应物在原生处理器里（`LearnOHDataProcessor.post` 内部读文件），
 * 移植后拆成"读字节（本文件）→ 组装（data/upload）→ 发送（HttpClient）"三段。
 */

import fs from '@ohos.file.fs';
import { Logger } from '../../core/log/Logger';
import { AttachmentBytesSource } from './SubmitAssignment';

export class DeviceAttachmentReader implements AttachmentBytesSource {
  private readonly logger: Logger;

  constructor(logger: Logger) {
    this.logger = logger;
  }

  async read(uri: string): Promise<Uint8Array> {
    const file: fs.File = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    try {
      const info: fs.Stat = fs.statSync(file.fd);
      const declared: number = info.size;
      if (declared <= 0) {
        this.logger.warn('attachment read: empty file uri=' + uri);
        return new Uint8Array(0);
      }
      const buffer: ArrayBuffer = new ArrayBuffer(declared);
      const readBytes: number = fs.readSync(file.fd, buffer);
      const all: Uint8Array = new Uint8Array(buffer);
      const bytes: Uint8Array = readBytes === declared ? all : all.slice(0, readBytes);
      this.logger.info('attachment read: bytes=' + bytes.length.toString()
        + ' declared=' + declared.toString());
      return bytes;
    } finally {
      fs.closeSync(file);
    }
  }
}
