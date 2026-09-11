/*
 * 上传请求组装（data 层的装配，不含平台调用）。
 *
 * 参考实现的 `post` 把三件事揉在一起：读文件、拼 multipart、发请求。
 * 移植后拆成：
 *   - `domain/parse/Multipart.ets`：纯字节组装（可单测）；
 *   - 本类：把"参数 + 文件字节 + 边界"装配成一次可发送的请求；
 *   - `HttpClient.sendMultipart`：真正发出去。
 */

import { buildMultipartBody, generateBoundary, MultipartBody, TextEncoderFn, UploadFile, DEFAULT_FILE_FIELD } from
  '../../domain/parse/Multipart';
import { USER_AGENT } from '../remote/Requests';

/** 一次组装好的上传请求。 */
export interface UploadRequest {
  url: string;
  headers: Record<string, string>;
  body: Uint8Array;
  boundary: string;
  contentType: string;
}

/** 组装上传请求（边界可注入，便于单测固定字节）。 */
export function buildUploadRequest(
  url: string,
  params: Record<string, string>,
  file: UploadFile | undefined,
  encoder: TextEncoderFn,
  cookieHeader: string,
  boundary: string
): UploadRequest {
  const assembled: MultipartBody = buildMultipartBody(boundary, params, file, encoder);
  return {
    url: url,
    headers: {
      'Content-Type': assembled.contentType,
      'Cookie': cookieHeader,
      'User-Agent': USER_AGENT
    },
    body: assembled.body,
    boundary: assembled.boundary,
    contentType: assembled.contentType
  };
}

/** 生成默认边界（照参考实现 `----WebKitFormBoundary` + 随机串）。 */
export function newBoundary(): string {
  return generateBoundary(Math.random(), Math.random().toString(36).substring(2));
}

/** 文件字段名固定为 `fileupload`（参考实现如此，站点据此取文件）。 */
export function makeUploadFile(
  fileName: string,
  contentType: string,
  data: Uint8Array,
  fieldName?: string
): UploadFile {
  const file: UploadFile = {
    fieldName: fieldName === undefined ? DEFAULT_FILE_FIELD : fieldName,
    fileName: fileName,
    data: data
  };
  if (contentType.length > 0) {
    file.contentType = contentType;
  }
  return file;
}
