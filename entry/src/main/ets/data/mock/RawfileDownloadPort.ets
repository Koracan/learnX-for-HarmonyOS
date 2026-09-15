/*
 * Rawfile 下载端口（data/mock）：实现 data/remote/DownloadPort，从**包内资产**喂字节。
 *
 * ## 它在整条链路上的位置
 *
 * features/files 的详情页进页即下载，走的是**真实的** FileDownloader
 * （data/files，缓存命中 / 路径规则 / 落盘前判定 / fileSize 收尾校验都在那里）。
 * mock 模式唯一换掉的就是那条链路的**最末端**：把 HttpDownloadPort（@ohos.net.http 的
 * requestInStream）换成这个端口。于是"预览 / 分享 / 交给系统打开 / 缓存命中"全部照旧，
 * 而**一行网络请求都不发**（NetworkAudit 的计数不变）。
 *
 * ## 为什么分块交付（而不是一次性 onChunk）
 *
 * 详情页的进度条读的是 sink.onChunk 累积出来的字节数。一次交付 = 进度条从 0 直接跳到 100%，
 * "进度真的走起来"这件事就无法观察。所以按固定上限切块，且**保证至少 2 块**
 * （样例只有几 KB，上限大于文件时就对半分）。
 *
 * ## Content-Type 与状态码这两件事怎么给
 *
 * 与真实端口同一口径（见 data/remote/DownloadPort 的文件头）：Content-Type 在**第一个字节
 * 之前**由 onHeaders 给出（落盘前判定据此拦截 HTML/JSON）；状态码在流结束后由返回值给出。
 * 这里两者都是 200 与样例自己的类型，所以真实编排的每一条判定都会照走一遍。
 *
 * ## 失败形态（显式，不静默）
 *
 *   - 地址里没有已知的 mock id：**不发 onHeaders、不写一个字节**，返回 ok=false + 明确 error；
 *   - rawfile 读失败 / 读到 0 字节：同样显式失败（error 里带资产路径）。
 * 绝不"成功返回 0 字节" —— 那会让详情页拿一个空文件去预览。
 */

import { resourceManager } from '@kit.LocalizationKit';
import { Logger } from '../../core/log/Logger';
import { networkAttemptCount } from '../remote/NetworkAudit';
import { DownloadHeaders, DownloadPort, DownloadSink, DownloadStreamResult } from '../remote/DownloadPort';
import { Session } from '../remote/Requests';
import { MockBlobSource, MockFileBlob, mockBlobForUrl } from './MockFileBlobs';

/**
 * 每块的目标字节数上限（32 KB）。
 *
 * 为什么是 32 KB：与 HttpDownloadPort 那块平台给的块量级相当，进度粒度够用，
 * 又不会让几 KB 的样例被切成上百次回调。
 */
const CHUNK_TARGET_BYTES: number = 32768;

/** 分块大小：内容大于 1 字节时**至少 2 块**，至多 CHUNK_TARGET_BYTES 一块。 */
function chunkSizeFor(length: number): number {
  if (length <= 1) {
    return length;
  }
  return Math.max(1, Math.min(CHUNK_TARGET_BYTES, Math.floor((length + 1) / 2)));
}

/**
 * 复制一段字节成**独立的** ArrayBuffer。
 *
 * 为什么不用 subarray：subarray 是共享底层缓冲的视图，sink 若把 ArrayBuffer 存起来
 * （真实实现里 fs.writeSync 是同步写，但这是契约之外的假设），后续块会互相覆盖。
 * 复制一份是这个端口唯一"多花一点内存"的地方，代价明确、语义干净。
 */
function copyRange(source: Uint8Array, start: number, end: number): ArrayBuffer {
  // 先建 ArrayBuffer 再在它上面开视图（而不是先建 Uint8Array 再取 .buffer）：
  // 这样返回值的类型就是 ArrayBuffer，不依赖 typed array 的 buffer 属性的类型别名。
  const buffer: ArrayBuffer = new ArrayBuffer(end - start);
  const view: Uint8Array = new Uint8Array(buffer);
  for (let i = start; i < end; i++) {
    view[i - start] = source[i];
  }
  return buffer;
}

/** 设备侧的 MockBlobSource：读 rawfile（**只有本类**碰平台资源 API）。 */
export class RawfileMockBlobSource implements MockBlobSource {
  private readonly manager: resourceManager.ResourceManager;

  constructor(manager: resourceManager.ResourceManager) {
    this.manager = manager;
  }

  read(rawfilePath: string): Uint8Array {
    return this.manager.getRawFileContentSync(rawfilePath);
  }
}

/** 用包内样例实现的下载端口（零网络）。 */
export class RawfileDownloadPort implements DownloadPort {
  private readonly blobs: MockBlobSource;
  private readonly logger: Logger;

  constructor(blobs: MockBlobSource, logger: Logger) {
    this.blobs = blobs;
    this.logger = logger;
  }

  async download(session: Session, url: string, sink: DownloadSink): Promise<DownloadStreamResult> {
    const blob: MockFileBlob | null = mockBlobForUrl(url);
    if (blob === null) {
      const error: string = 'mock mode: no bundled sample blob for url=' + url;
      this.logger.warn('mock download refused: ' + error);
      return {
        ok: false, status: 0, contentType: '', contentLength: -1,
        receivedBytes: 0, rejected: false, error: error
      };
    }
    let bytes: Uint8Array;
    try {
      bytes = this.blobs.read(blob.rawfilePath);
    } catch (error) {
      const message: string = 'mock mode: cannot read bundled asset ' + blob.rawfilePath
        + ': ' + (error as Error).message;
      this.logger.error('mock download failed: ' + message);
      return {
        ok: false, status: 0, contentType: blob.contentType, contentLength: -1,
        receivedBytes: 0, rejected: false, error: message
      };
    }
    if (bytes.length === 0) {
      const message: string = 'mock mode: bundled asset is empty: ' + blob.rawfilePath;
      this.logger.error('mock download failed: ' + message);
      return {
        ok: false, status: 0, contentType: blob.contentType, contentLength: -1,
        receivedBytes: 0, rejected: false, error: message
      };
    }

    // onHeaders 是同步返回布尔值的：返回 false = 落盘前判定拒绝（真实端口在此不再交付字节）。
    const headers: DownloadHeaders = {
      contentType: blob.contentType, contentLength: bytes.length
    };
    const accepted: boolean = sink.onHeaders(headers);
    if (!accepted) {
      this.logger.warn('mock download rejected by sink before any byte: url=' + url);
      return {
        ok: false, status: 200, contentType: blob.contentType, contentLength: bytes.length,
        receivedBytes: 0, rejected: true
      };
    }

    const chunkSize: number = chunkSizeFor(bytes.length);
    let offset: number = 0;
    let delivered: number = 0;
    let chunks: number = 0;
    while (offset < bytes.length) {
      const end: number = Math.min(bytes.length, offset + chunkSize);
      const chunk: ArrayBuffer = copyRange(bytes, offset, end);
      sink.onChunk(chunk);
      delivered += chunk.byteLength;
      chunks++;
      offset = end;
    }
    // 消费点自证：networkAttempts 一直是 0 —— 这条下载链路一个请求都没发。
    this.logger.info('mock download served from bundled asset: asset=' + blob.rawfilePath
      + ' contentType=' + blob.contentType + ' bytes=' + delivered.toString()
      + ' chunks=' + chunks.toString()
      + ' sessionCsrfPresent=' + (session.csrfToken.length > 0).toString()
      + ' networkAttempts=' + networkAttemptCount().toString());
    return {
      ok: true, status: 200, contentType: blob.contentType, contentLength: bytes.length,
      receivedBytes: delivered, rejected: false
    };
  }
}
