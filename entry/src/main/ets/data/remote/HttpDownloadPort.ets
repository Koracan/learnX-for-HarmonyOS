/*
 * `DownloadPort` 的设备实现：`@ohos.net.http` 的 `requestInStream`。
 *
 * 逐条对应（**HTTP 层解决，不搬 <5000 字节 + 含 <html> 的启发式**）：
 *   - 响应头到达即把 `Content-Type` / `Content-Length` 交给 sink 判定；
 *   - sink 拒绝时立刻 `destroy()`，**一个字节都不落盘**；
 *   - 状态码在流结束后由调用方（FileDownloader）判定。
 *
 * 本文件是继 `HttpFetchPort` 之后**第二个**直接 import 平台 http 的文件；业务判断
 * （什么算"下载失败"）在 `domain/files/FileDownloadPolicy`，这里只做搬运。
 */

import http from '@ohos.net.http';
import { Logger } from '../../core/log/Logger';
import { parseContentLength } from '../../domain/files/FileDownloadPolicy';
import { DownloadPort, DownloadSink, DownloadStreamResult } from './DownloadPort';
import { noteNetworkAttempt } from './NetworkAudit';
import { Session, USER_AGENT } from './Requests';

/** 连接超时（毫秒），与 HttpClient 一致。 */
const CONNECT_TIMEOUT_MS: number = 15000;

/** 读超时（毫秒）：下载可能比普通请求慢，给得更宽（参考实现没有这一层，平台默认 60s）。 */
const READ_TIMEOUT_MS: number = 120000;

/** 把平台的头对象摊平成**小写键**的字符串表。 */
function flattenLowercaseHeaders(raw: Object): Record<string, string> {
  const flat: Record<string, string> = {};
  if (raw === undefined || raw === null) {
    return flat;
  }
  try {
    const record: Record<string, Object> = raw as Record<string, Object>;
    const keys: string[] = Object.keys(record);
    for (let i = 0; i < keys.length; i++) {
      const value: Object = record[keys[i]];
      flat[keys[i].toLowerCase()] = typeof value === 'string' ? value : JSON.stringify(value);
    }
  } catch (error) {
    flat['error'] = (error as Error).message;
  }
  return flat;
}

/** 从摊平后的头里取值（缺省空串）。 */
function headerValue(flat: Record<string, string>, name: string): string {
  const value: string | undefined = flat[name];
  return value === undefined ? '' : value;
}

export class HttpDownloadPort implements DownloadPort {
  private readonly logger: Logger;

  constructor(logger: Logger) {
    this.logger = logger;
  }

  async download(session: Session, url: string, sink: DownloadSink): Promise<DownloadStreamResult> {
    // **消费点自证**：流式下载是第二个真实出口。
    noteNetworkAttempt('download', url);
    const request = http.createHttp();
    let contentType: string = '';
    let contentLength: number = -1;
    let receivedBytes: number = 0;
    let accepted: boolean = false;
    let rejected: boolean = false;
    let headersSeen: boolean = false;
    let writeError: string = '';

    const headers: Record<string, string> = {};
    headers['Cookie'] = session.cookie;
    headers['User-Agent'] = USER_AGENT;

    request.on('headersReceive', (raw: Object): void => {
      headersSeen = true;
      const flat: Record<string, string> = flattenLowercaseHeaders(raw);
      contentType = headerValue(flat, 'content-type');
      contentLength = parseContentLength(headerValue(flat, 'content-length'));
      accepted = sink.onHeaders({ contentType: contentType, contentLength: contentLength });
      if (!accepted) {
        rejected = true;
        // 会话失效时不要把那整张登录页拖下来：头一到就中止。
        try {
          request.destroy();
        } catch (error) {
          this.logger.warn('download abort failed: ' + (error as Error).message);
        }
      }
    });

    request.on('dataReceive', (chunk: ArrayBuffer): void => {
      receivedBytes += chunk.byteLength;
      if (!accepted || writeError.length > 0) {
        return;
      }
      try {
        sink.onChunk(chunk);
      } catch (error) {
        writeError = (error as Error).message;
      }
    });

    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      header: headers,
      connectTimeout: CONNECT_TIMEOUT_MS,
      readTimeout: READ_TIMEOUT_MS
    };

    let status: number = 0;
    let transportError: string = '';
    try {
      status = await request.requestInStream(url, options);
    } catch (error) {
      transportError = (error as Error).message;
    } finally {
      try {
        request.off('headersReceive');
        request.off('dataReceive');
        request.destroy();
      } catch (error) {
        // destroy 可能已经在上面的拒绝分支被调用过；这里再调一次是幂等的。
      }
    }

    const result: DownloadStreamResult = {
      ok: status === 200 && !rejected && writeError.length === 0 && transportError.length === 0,
      status: status,
      contentType: contentType,
      contentLength: contentLength,
      receivedBytes: receivedBytes,
      rejected: rejected
    };
    if (writeError.length > 0) {
      result.error = 'write failed: ' + writeError;
    } else if (transportError.length > 0 && !rejected) {
      result.error = transportError;
    }
    this.logger.info('download stream done: status=' + status.toString()
      + ' contentType="' + contentType + '" contentLength=' + contentLength.toString()
      + ' received=' + receivedBytes.toString()
      + ' headersSeen=' + headersSeen.toString()
      + ' rejected=' + rejected.toString()
      + (result.error === undefined ? '' : ' error=' + result.error));
    return result;
  }
}
