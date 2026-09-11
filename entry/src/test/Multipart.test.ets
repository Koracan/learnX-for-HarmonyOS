/*
 * multipart/form-data 组装单测（ticket 05 验收项 5）。
 *
 * 断言到**字节**级别：CRLF、字段顺序、`fileupload` 字段名、文件名编码
 * （ASCII 名走 `filename`，非 ASCII 名在 `filename` 之外再给 RFC 5987 的 `filename*`），
 * 以及"结束边界后必有一个 CRLF"。
 *
 * 与参考实现的一致性：参考实现 `post` 的字段顺序 = 文本参数（对象插入序）→ 文件 → `--boundary--`；
 * 本文件逐条锁定该顺序。
 */

import { describe, it, expect } from '@ohos/hypium';
import {
  buildMultipartBody, generateBoundary, escapeFormValue, needsExtendedFileName,
  encodeExtendedFileName, MultipartBody, UploadFile, DEFAULT_FILE_FIELD
} from '../main/ets/data/upload/Multipart';
import { decodeUtf8, deviceUtf8Encoder } from './TestHelpers';

const BOUNDARY: string = '----WebKitFormBoundaryTEST';

/** 文本字段容器：ArkTS 不支持结构化类型，禁止用匿名对象字面量当参数。 */
interface Params {
  id: string;
  xszyid: string;
}

interface SingleParam {
  only: string;
}

interface WeirdParam {
  weird: string;
}

interface EscapedParam {
  quoted: string;
}

function bytesOf(text: string): number {
  return deviceUtf8Encoder(text).length;
}

function uploadFile(name: string, bytes: number[], contentType?: string): UploadFile {
  const data = new Uint8Array(bytes.length);
  for (let i = 0; i < bytes.length; i++) {
    data[i] = bytes[i];
  }
  const file: UploadFile = { fieldName: DEFAULT_FILE_FIELD, fileName: name, data: data };
  if (contentType !== undefined) {
    file.contentType = contentType;
  }
  return file;
}

/** 把命名接口摊平成 `Record`（组装的入参形态）。 */
function recordOf(params: Params): Record<string, string> {
  const record: Record<string, string> = {};
  record['id'] = params.id;
  record['xszyid'] = params.xszyid;
  return record;
}

export default function multipartTest() {
  describe('data.Multipart', () => {
    it('assemblesFieldsAndFileInReferenceOrder', 0, () => {
      const assembled: MultipartBody = buildMultipartBody(
        BOUNDARY,
        recordOf({ id: '12345', xszyid: 'abc' }),
        uploadFile('a.pdf', [1, 2, 3], 'application/pdf'),
        deviceUtf8Encoder);
      const text: string = decodeUtf8(assembled.body);
      const idIndex: number = text.indexOf('name="id"');
      const xszyidIndex: number = text.indexOf('name="xszyid"');
      const fileIndex: number = text.indexOf('name="fileupload"');
      const endIndex: number = text.indexOf('--' + BOUNDARY + '--');
      expect(idIndex > 0).assertTrue();
      expect(idIndex < xszyidIndex).assertTrue();
      expect(xszyidIndex < fileIndex).assertTrue();
      expect(fileIndex < endIndex).assertTrue();
      expect(assembled.contentType).assertEqual('multipart/form-data; boundary=' + BOUNDARY);
      expect(assembled.boundary).assertEqual(BOUNDARY);
      expect(text.endsWith('--' + BOUNDARY + '--\r\n')).assertTrue();
      expect(text.includes('Content-Type: application/pdf')).assertTrue();
      expect(text.includes('\r\n\r\n12345\r\n')).assertTrue();
      expect(assembled.body.length).assertEqual(bytesOf(text));
    });

    it('keepsBinaryFileBytesIntact', 0, () => {
      const file: UploadFile = uploadFile('a.bin', [0, 1, 255, 254], 'application/octet-stream');
      const empty: Record<string, string> = {};
      const assembled: MultipartBody = buildMultipartBody(BOUNDARY, empty, file, deviceUtf8Encoder);
      const header: string = '--' + BOUNDARY + '\r\n'
        + 'Content-Disposition: form-data; name="fileupload"; filename="a.bin"\r\n'
        + 'Content-Type: application/octet-stream\r\n\r\n';
      const headerBytes: number = bytesOf(header);
      expect(assembled.body[headerBytes]).assertEqual(0);
      expect(assembled.body[headerBytes + 1]).assertEqual(1);
      expect(assembled.body[headerBytes + 2]).assertEqual(255);
      expect(assembled.body[headerBytes + 3]).assertEqual(254);
      const tail: string = '\r\n--' + BOUNDARY + '--\r\n';
      expect(assembled.body.length).assertEqual(headerBytes + 4 + bytesOf(tail));
    });

    it('encodesChineseFileNameWithRfc5987', 0, () => {
      const file: UploadFile = uploadFile('作业一.pdf', [9], 'application/pdf');
      expect(needsExtendedFileName('作业一.pdf')).assertTrue();
      expect(needsExtendedFileName('a.pdf')).assertFalse();
      const empty: Record<string, string> = {};
      const assembled: MultipartBody = buildMultipartBody(BOUNDARY, empty, file, deviceUtf8Encoder);
      const text: string = decodeUtf8(assembled.body);
      expect(text.includes('filename="作业一.pdf"')).assertTrue();
      expect(text.includes("filename*=UTF-8''%E4%BD%9C%E4%B8%9A%E4%B8%80.pdf")).assertTrue();
      expect(encodeExtendedFileName('a b.pdf')).assertEqual("UTF-8''a%20b.pdf");
      expect(encodeExtendedFileName('a(1).pdf')).assertEqual("UTF-8''a%281%29.pdf");
    });

    it('worksWithoutFile', 0, () => {
      const only: Record<string, string> = {};
      only['only'] = 'x';
      const assembled: MultipartBody = buildMultipartBody(BOUNDARY, only, undefined, deviceUtf8Encoder);
      const text: string = decodeUtf8(assembled.body);
      expect(text.indexOf('filename=')).assertEqual(-1);
      expect(text).assertEqual('--' + BOUNDARY + '\r\n'
        + 'Content-Disposition: form-data; name="only"\r\n\r\n'
        + 'x\r\n'
        + '--' + BOUNDARY + '--\r\n');
    });

    it('escapesFieldNamesAndValues', 0, () => {
      expect(escapeFormValue('plain')).assertEqual('plain');
      expect(escapeFormValue('a"b')).assertEqual('a\\"b');
      expect(escapeFormValue('a\nb')).assertEqual('a%0Ab');
      const quoted: Record<string, string> = {};
      quoted['we"ird'] = 'line1\r\nline2';
      const assembled: MultipartBody = buildMultipartBody(BOUNDARY, quoted, undefined, deviceUtf8Encoder);
      const text: string = decodeUtf8(assembled.body);
      expect(text.includes('name="we\\"ird"')).assertTrue();
      // 字段**值**按参考实现原样写出（不转义）：换行原样进入 body。
      // `escapeFormValue` 只用于字段名与文件名，避免破坏提交值的语义。
      expect(text.includes('line1\r\nline2')).assertTrue();
      expect(text.includes('line1%0D%0Aline2')).assertFalse();
    });

    it('generatesStableBoundaryShape', 0, () => {
      const generated: string = generateBoundary(0.5, 'abc');
      expect(generated.startsWith('----WebKitFormBoundary')).assertTrue();
      expect(generated.endsWith('abc')).assertTrue();
      expect(generateBoundary(0.5, 'abc')).assertEqual(generated);
      expect(generateBoundary(0.25, 'xyz') !== generated).assertTrue();
    });
  });
}
