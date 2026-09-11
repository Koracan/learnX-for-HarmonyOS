/*
 * multipart/form-data 组装——**零平台依赖**（见 scripts/check-domain-purity.mjs）。
 *
 * 移植自参考实现 DataProcessorModule.ts 的 `post`：同样的 CRLF、同样的字段顺序
 * （先按传入顺序的文本字段，再文件，最后结束边界）、同样的 `fileupload` 字段名。
 *
 * 去平台化：参考实现直接 `util.TextEncoder` 编码、`fs` 读文件、`@ohos.net.http` 发送；
 * 这里只做**字节组装**，编码器与文件字节由调用方（data/remote/HttpUploader，core 之外）
 * 注入，因此可在单测里逐字节断言。
 */

/** 文本编码器（把字符串编码为 UTF-8 字节）。 */
export type TextEncoderFn = (text: string) => Uint8Array;

/** 一个待上传的文件。 */
export interface UploadFile {
  /** 表单字段名；参考实现固定为 `fileupload`。 */
  fieldName: string;
  /** 原始文件名（可能含中文）。 */
  fileName: string;
  /** MIME 类型；缺省 `application/octet-stream`。 */
  contentType?: string;
  /** 文件字节。 */
  data: Uint8Array;
}

/** 组装结果：请求体字节 + 供 `Content-Type` 使用的 boundary。 */
export interface MultipartBody {
  boundary: string;
  contentType: string;
  body: Uint8Array;
}

export const DEFAULT_FILE_FIELD: string = 'fileupload';
export const DEFAULT_CONTENT_TYPE: string = 'application/octet-stream';
export const CRLF: string = '\r\n';

const ASCII_TOKEN_PATTERN = /^[A-Za-z0-9!#$%&'*+.^_`|~-]+$/;

/**
 * 表单字段值 / 文件名转义。
 * 不含 CR、LF、双引号或非 ASCII 时原样保留（与参考实现一致，中文名走 filename* 另给），
 * 否则按 RFC 7578/6266 加引号并转义。
 */
export function escapeFormValue(value: string): string {
  if (value.length > 0 && ASCII_TOKEN_PATTERN.test(value)) {
    return value;
  }
  return value.replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\r/g, '%0D').replace(/\n/g, '%0A');
}

/** 文件名是否含非 ASCII 字符（需要额外给出 RFC 5987 的 `filename*`）。 */
export function needsExtendedFileName(fileName: string): boolean {
  for (let i = 0; i < fileName.length; i++) {
    if (fileName.charCodeAt(i) > 0x7f) {
      return true;
    }
  }
  return false;
}

/**
 * RFC 5987 的 `filename*`：`UTF-8''<percent-encoded>`。
 * 非 ASCII 名（如 `作业一.pdf`）必须走这里，否则服务端拿到的文件名是乱码。
 */
export function encodeExtendedFileName(fileName: string): string {
  return "UTF-8''" + encodeURIComponent(fileName)
    .replace(/['()*]/g, (char: string): string => '%' + char.charCodeAt(0).toString(16).toUpperCase());
}

function concat(parts: Uint8Array[]): Uint8Array {
  let total: number = 0;
  for (let i = 0; i < parts.length; i++) {
    total += parts[i].length;
  }
  const merged = new Uint8Array(total);
  let offset: number = 0;
  for (let i = 0; i < parts.length; i++) {
    merged.set(parts[i], offset);
    offset += parts[i].length;
  }
  return merged;
}

/** 组装 multipart 请求体。字段顺序 = 文本字段的传入顺序 → 文件 → 结束边界。 */
export function buildMultipartBody(
  boundary: string,
  params: Record<string, string>,
  file: UploadFile | undefined,
  encoder: TextEncoderFn
): MultipartBody {
  const text = (value: string): Uint8Array => encoder(value);
  const parts: Uint8Array[] = [];

  const keys: string[] = Object.keys(params);
  for (let i = 0; i < keys.length; i++) {
    const key: string = keys[i];
    let head: string = '--' + boundary + CRLF;
    head += 'Content-Disposition: form-data; name="' + escapeFormValue(key) + '"' + CRLF + CRLF;
    parts.push(text(head));
    parts.push(text(params[key]));
    parts.push(text(CRLF));
  }

  if (file !== undefined) {
    const fileName: string = file.fileName.length > 0 ? file.fileName : 'file';
    let head: string = '--' + boundary + CRLF;
    head += 'Content-Disposition: form-data; name="' + escapeFormValue(file.fieldName) + '"; filename="'
      + escapeFormValue(fileName) + '"';
    if (needsExtendedFileName(fileName)) {
      head += "; filename*=" + encodeExtendedFileName(fileName);
    }
    head += CRLF;
    head += 'Content-Type: ' + (file.contentType !== undefined && file.contentType.length > 0
      ? file.contentType : DEFAULT_CONTENT_TYPE) + CRLF + CRLF;
    parts.push(text(head));
    parts.push(file.data);
    parts.push(text(CRLF));
  }

  parts.push(text('--' + boundary + '--' + CRLF));

  return {
    boundary: boundary,
    contentType: 'multipart/form-data; boundary=' + boundary,
    body: concat(parts)
  };
}

/**
 * 生成边界串。参考实现是 `'----WebKitFormBoundary' + Math.random().toString(36).substring(2)`；
 * 这里保留该形状，但接受注入的随机源与短标识，便于单测固定结果。
 */
export function generateBoundary(random: number, salt: string): string {
  return '----WebKitFormBoundary' + Math.floor(Math.abs(random) * 1e16).toString(36) + salt;
}
