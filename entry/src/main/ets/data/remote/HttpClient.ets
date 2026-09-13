/*
 * HTTP 适配层（平台调用集中在这里）：@ohos.net.http + 注入的会话 Cookie。
 *
 * 参考实现把 http 调用与解析混在 DataProcessorModule.ts 里；移植后 http 只做
 * "发出去、把响应体拿回来"，失败不抛异常而是返回 `ok: false` 的 outcome，
 * 让上层（data/remote/*Fetcher）能照参考实现那样逐请求容错并继续。
 *
 * 每次请求后调用 `destroy()` 释放句柄——参考实现没有释放，批量抓取会攒下句柄。
 */

import http from '@ohos.net.http';
import { HttpMethod, HttpOutcome, RequestSpec, Session } from './Requests';
import { noteNetworkAttempt } from './NetworkAudit';

/** 单次请求超时（毫秒）。 */
const CONNECT_TIMEOUT_MS: number = 15000;
const READ_TIMEOUT_MS: number = 30000;

export class HttpResponse {
  readonly statusCode: number;
  readonly body: string;
  readonly ok: boolean;
  readonly error?: string;
  /** 响应头原样（诊断用）。 */
  readonly headers: Record<string, string>;
  /** 服务端下发的 Set-Cookie 原始串（平台在 response.cookies 里给出）。 */
  readonly setCookie: string;

  private constructor(statusCode: number, body: string, ok: boolean, error: string | undefined,
    headers: Record<string, string>, setCookie: string) {
    this.statusCode = statusCode;
    this.body = body;
    this.ok = ok;
    this.error = error;
    this.headers = headers;
    this.setCookie = setCookie;
  }

  static success(statusCode: number, body: string, headers: Record<string, string>,
    setCookie: string): HttpResponse {
    return new HttpResponse(statusCode, body, true, undefined, headers, setCookie);
  }

  static failure(message: string): HttpResponse {
    const empty: Record<string, string> = {};
    return new HttpResponse(0, '', false, message, empty, '');
  }

  /** 折算成上层使用的 outcome（只有 HTTP 200 算成功，与参考实现一致）。 */
  toOutcome(): HttpOutcome {
    if (!this.ok) {
      const failed: HttpOutcome = { ok: false, status: this.statusCode, body: '' };
      failed.error = this.error;
      return failed;
    }
    const outcome: HttpOutcome = { ok: this.statusCode === 200, status: this.statusCode, body: this.body };
    if (!outcome.ok) {
      outcome.body = '';
      outcome.error = 'HTTP ' + this.statusCode.toString();
    }
    return outcome;
  }
}

/** 把平台给的头对象摊平成字符串表（只用于诊断与 Set-Cookie 之外的展示）。 */
function flatHeaders(raw: Object): Record<string, string> {
  const flat: Record<string, string> = {};
  if (raw === undefined || raw === null) {
    return flat;
  }
  try {
    const record: Record<string, Object> = raw as Record<string, Object>;
    const keys: string[] = Object.keys(record);
    for (let i = 0; i < keys.length; i++) {
      const value: Object = record[keys[i]];
      flat[keys[i]] = typeof value === 'string' ? value : JSON.stringify(value);
    }
  } catch (error) {
    flat['error'] = (error as Error).message;
  }
  return flat;
}

/** HTTP 客户端：把 `RequestSpec` 发出去，返回响应。 */
export class HttpClient {
  private readonly session: Session;

  constructor(session: Session) {
    this.session = session;
  }

  getSession(): Session {
    return this.session;
  }

  /** 发送请求；任何失败都折算为 `HttpResponse.failure`，不抛异常。 */
  async send(spec: RequestSpec): Promise<HttpResponse> {
    return this.request(spec.url, spec.method, spec.headers, spec.body, undefined, undefined);
  }

  /** 发送二进制体（multipart）；失败语义同 `send`。 */
  async sendBinary(spec: RequestSpec, binaryBody: Uint8Array): Promise<HttpResponse> {
    return this.request(spec.url, spec.method, spec.headers, undefined, binaryBody.buffer as ArrayBuffer, undefined);
  }

  /**
   * 发送 multipart 体。
   * @param onProgress 上传进度回调（参考实现通过 RN 设备事件 `LearnOHUploadProgress` 上报，
   *   移植后改成普通回调，由调用方决定怎么呈现）。
   */
  async sendMultipart(
    url: string,
    headers: Record<string, string>,
    body: Uint8Array,
    onProgress?: (sent: number, total: number) => void
  ): Promise<HttpResponse> {
    return this.request(url, HttpMethod.POST, headers, undefined, body.buffer as ArrayBuffer, onProgress);
  }

  private async request(
    url: string,
    method: HttpMethod,
    headers: Record<string, string>,
    body: string | undefined,
    binaryBody: ArrayBuffer | undefined,
    onProgress?: (sent: number, total: number) => void
  ): Promise<HttpResponse> {
    // **消费点自证**：任何一条真实请求都在这里被计数。
    noteNetworkAttempt(method === HttpMethod.POST ? 'post' : 'get', url);
    const request = http.createHttp();
    let cookiePresent: boolean = false;
    const keys: string[] = Object.keys(headers);
    for (let i = 0; i < keys.length; i++) {
      if (keys[i].toLowerCase() === 'cookie') {
        cookiePresent = true;
      }
    }
    if (!cookiePresent && this.session.cookie.length > 0) {
      headers['Cookie'] = this.session.cookie;
    }

    const options: http.HttpRequestOptions = {
      method: method === HttpMethod.POST ? http.RequestMethod.POST : http.RequestMethod.GET,
      header: headers,
      connectTimeout: CONNECT_TIMEOUT_MS,
      readTimeout: READ_TIMEOUT_MS,
      expectDataType: http.HttpDataType.STRING
    };
    if (body !== undefined) {
      options.extraData = body;
    } else if (binaryBody !== undefined) {
      options.extraData = binaryBody;
    }

    request.on('dataSendProgress', (data: http.DataSendProgressInfo): void => {
      if (onProgress !== undefined) {
        onProgress(data.sendSize, data.totalSize);
      }
    });

    try {
      const response: http.HttpResponse = await request.request(url, options);
      const result: string | Object | ArrayBuffer = response.result;
      const text: string = typeof result === 'string' ? result : JSON.stringify(result);
      return HttpResponse.success(response.responseCode, text, flatHeaders(response.header),
        response.cookies === undefined || response.cookies === null ? '' : response.cookies);
    } catch (error) {
      return HttpResponse.failure((error as Error).message);
    } finally {
      request.off('dataSendProgress');
      request.destroy();
    }
  }
}