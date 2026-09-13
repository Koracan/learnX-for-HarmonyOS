/*
 * 抓取端口（data 层）：域仓储唯一的对外依赖。
 *
 * 参考实现的 `fetchNotices(courseIds, cookie, csrfToken)` 在模块内部直接调
 * `@ohos.net.http`；移植后**网络调用经本端口注入**，于是：
 *   - 设备上注入 `HttpFetchPort`（包 `HttpClient`）；
 *   - 单测里注入脚本化假端口，用真实结构的响应夹具跑通整条"抓取 → 解析 → 排序"链路，
 *     并检查每个域打了条目数与耗时日志。
 *
 * 端口不抛异常：失败也是 `FetchOutcome`（照参考实现 `catch(err => console.error)` 的容错）。
 */

import { HttpMethod, HttpOutcome, Session } from './Requests';
import { UploadFile } from '../upload/Multipart';

export { Session } from './Requests';

export interface FetchOutcome {
  ok: boolean;
  status: number;
  body: string;
  error?: string;
}

/**
 * 一次 POST `urlencoded` 请求。
 *
 * 表单体只有两种形态（照参考实现的两个 POST 接口），因此用两个可选字段表达，
 * 而不是联合类型 + 匿名对象（ArkTS 不支持结构化类型）：
 *   - `courseId` 给出时发 `aoData=[{"name":"wlkcid","value":<courseId>}]`（列表接口）；
 *   - `id` 给出时发 `id=<zyid>`（作业描述接口）。
 */
export interface PostFormSpec {
  url: string;
  courseId?: string;
  id?: string;
}

/** 一次 GET 请求（查询串已在 url 里）。 */
export interface GetSpec {
  url: string;
}

/**
 * multipart 的文本字段：**作业提交接口**的三个字段。
 *
 * 逐字对齐参考实现 `src/data/source.ts:175-179` 的 `params`：
 *   - `xszyid` = 学生作业 id；
 *   - `zynr` = 正文（无正文时空串）；
 *   - `isDeleted` = 移除附件时 `'1'`，否则 `'0'`。
 *
 * **没有 `id`**：`id` 是**作业描述接口**的字段（见下面的 `PostFormSpec.id`，发 `id=<zyid>`），
 * 这两个接口曾经揉在一起。参考实现的提交不发 `id`（见字段对照表）。
 * 字段顺序有意义：multipart 的文本部分按本对象的构造顺序写出。
 */
export interface UploadFormParams {
  xszyid: string;
  zynr: string;
  isDeleted: string;
}

/**
 * 一次 multipart 上传。
 *
 * `file` 为 `undefined` 时**不写文件部分** —— 只提交正文（或"移除附件"）时参考实现同样
 * 不产生任何文件段（`source.ts:168-205` 里 `filePath` 未定义就不写文件）。
 */
export interface UploadSpec {
  url: string;
  params: UploadFormParams;
  /** 文件部分；字段名固定 `fileupload`（无附件时为 `undefined`）。 */
  file?: UploadFile;
  requestId?: string;
}

/** 上传进度（参考实现走 RN 设备事件，这里走普通回调）。 */
export interface UploadProgress {
  requestId: string;
  sent: number;
  total: number;
}

export type UploadProgressSink = (progress: UploadProgress) => void;

/** 抓取端口。 */
export interface FetchPort {
  postForm(session: Session, spec: PostFormSpec): Promise<FetchOutcome>;
  get(session: Session, spec: GetSpec): Promise<FetchOutcome>;
  upload(session: Session, spec: UploadSpec, onProgress?: UploadProgressSink): Promise<HttpOutcome>;
}
/* ------------------------------------------------------------------ *
 * 扩展：**原始请求**通道，供登录流使用。
 *
 * 为什么不改 FetchPort：FetchPort 描述的是「三域抓取」那三种固定请求（args 已收敛成
 * courseId/id），登录要发的是 ID 域的表单页、multipart 检查请求、漫游 GET 与课程列表页，
 * 需要响应头与 Set-Cookie。新增一个独立接口，两个接口由同一个 HttpFetchPort 实现，
 * 三域仓储与既有测试端口**无需改动**。
 * ------------------------------------------------------------------ */

/** 一次原始请求（头与体都由调用方给全，端口不做任何业务判断）。 */
export interface RawRequest {
  url: string;
  method: HttpMethod;
  headers: Record<string, string>;
  /** 文本体（urlencoded 等）。与 binaryBody 互斥。 */
  body?: string;
  /** 二进制体（multipart）。与 body 互斥。 */
  binaryBody?: Uint8Array;
}

/** 一次原始响应。 */
export interface RawResponse {
  /** 网络层是否拿到响应（4xx/5xx 也算 true）。 */
  ok: boolean;
  status: number;
  body: string;
  /** 服务端下发的 Set-Cookie 原始串（可能含多个 cookie，解析见 core/http/CookieJar）。 */
  setCookie: string;
  /** 响应头原样（诊断用）。 */
  headers: Record<string, string>;
  /** 请求 URL。平台**不暴露重定向后的最终 URL**，见 LoginParsers 的说明。 */
  requestUrl: string;
  error?: string;
}

/** 原始请求端口。 */
export interface RawFetchPort {
  sendRaw(spec: RawRequest): Promise<RawResponse>;
}
