/*
 * `FetchPort` 的设备实现：把端口调用翻译成 `@ohos.net.http` 请求。
 *
 * 唯一真正碰平台的地方就是本文件与 `HttpClient`。请求体编码、接口路径、字段名
 * 全部来自 data/remote/Requests 与 domain 层，本文件不做任何业务判断。
 */

import { HttpClient as NetClient, HttpResponse } from './HttpClient';
import {
  FetchPort, FetchOutcome, GetSpec, PostFormSpec, UploadSpec, UploadProgressSink,
  RawFetchPort, RawRequest, RawResponse
} from './Port';
import { HttpOutcome, HttpMethod, RequestSpec, Session, defaultHeaders, formHeaders } from './Requests';
import { buildUploadRequest, newBoundary, UploadRequest } from '../upload/UploadForm';
import { encodeUtf8 } from '../../core/codec/TextCodec';

/**
 * 表单体编码，与参考实现逐字节一致：
 *   - `aoData=encodeURIComponent('[{"name":"wlkcid","value":"<courseId>"}]')`（列表接口）；
 *   - `id=<encodeURIComponent(zyid)>`（作业描述接口）。
 */
function formBody(spec: PostFormSpec): string {
  if (spec.courseId !== undefined) {
    return 'aoData=' + encodeURIComponent(JSON.stringify([{ name: 'wlkcid', value: spec.courseId }]));
  }
  if (spec.id !== undefined) {
    return 'id=' + encodeURIComponent(spec.id);
  }
  return '';
}

function toOutcome(response: HttpResponse): FetchOutcome {
  if (!response.ok) {
    return { ok: false, status: response.statusCode, body: '',
      error: response.error === undefined ? 'HTTP ' + response.statusCode.toString() : response.error };
  }
  if (response.statusCode !== 200) {
    return { ok: false, status: response.statusCode, body: '',
      error: 'HTTP ' + response.statusCode.toString() };
  }
  return { ok: true, status: response.statusCode, body: response.body };
}

/** 原始请求通道用的空会话：它意味着「不要自动注入 Cookie」，Cookie 由调用方按 jar 自己给。 */
const NO_SESSION: Session = { cookie: '', csrfToken: '' };

export class HttpFetchPort implements FetchPort, RawFetchPort {
  private readonly client: (session: Session) => NetClient;

  constructor(client?: (session: Session) => NetClient) {
    this.client = client === undefined ? (session: Session): NetClient => new NetClient(session) : client;
  }

  /**
   * 原始请求（登录流用）。
   *
   * 与 `postForm`/`get` 的区别：**不自动注入会话 Cookie**（登录时还没有会话，
   * 且 cookie jar 的重置/拼接必须显式可见），并把响应头与 Set-Cookie 原样带回。
   */
  async sendRaw(spec: RawRequest): Promise<RawResponse> {
    const request: RequestSpec = {
      url: spec.url,
      method: spec.method,
      headers: spec.headers
    };
    if (spec.body !== undefined) {
      request.body = spec.body;
    }
    const client: NetClient = this.client(NO_SESSION);
    const response: HttpResponse = spec.binaryBody === undefined
      ? await client.send(request)
      : await client.sendBinary(request, spec.binaryBody);
    const result: RawResponse = {
      ok: response.ok,
      status: response.statusCode,
      body: response.body,
      setCookie: response.setCookie,
      headers: response.headers,
      requestUrl: spec.url
    };
    if (response.error !== undefined) {
      result.error = response.error;
    }
    return result;
  }

  async postForm(session: Session, spec: PostFormSpec): Promise<FetchOutcome> {
    const request: RequestSpec = {
      url: spec.url,
      method: HttpMethod.POST,
      headers: formHeaders(session),
      body: formBody(spec)
    };
    return toOutcome(await this.client(session).send(request));
  }

  async get(session: Session, spec: GetSpec): Promise<FetchOutcome> {
    const request: RequestSpec = {
      url: spec.url,
      method: HttpMethod.GET,
      headers: defaultHeaders(session)
    };
    return toOutcome(await this.client(session).send(request));
  }

  async upload(session: Session, spec: UploadSpec, onProgress?: UploadProgressSink): Promise<HttpOutcome> {
    const params: Record<string, string> = {};
    params['id'] = spec.params.id;
    params['xszyid'] = spec.params.xszyid;
    const assembled: UploadRequest = buildUploadRequest(
      spec.url,
      params,
      {
        fieldName: 'fileupload',
        fileName: spec.fileName,
        contentType: spec.contentType,
        data: spec.data
      },
      encodeUtf8,
      session.cookie,
      newBoundary()
    );
    const response: HttpResponse = await this.client(session).sendMultipart(
      assembled.url, assembled.headers, assembled.body,
      (sent: number, total: number): void => {
        if (onProgress !== undefined) {
          onProgress({ requestId: spec.requestId === undefined ? '' : spec.requestId, sent: sent, total: total });
        }
      });
    const result: HttpOutcome = {
      ok: response.ok && response.statusCode === 200,
      status: response.statusCode,
      body: response.body
    };
    if (!result.ok) {
      result.error = response.error === undefined ? 'HTTP ' + response.statusCode.toString() : response.error;
    }
    return result;
  }
}