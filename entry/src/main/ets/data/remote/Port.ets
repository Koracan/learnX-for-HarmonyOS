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

import { HttpOutcome, Session } from './Requests';

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

/** multipart 的文本字段（照参考实现提交接口的两个字段）。 */
export interface UploadFormParams {
  id: string;
  xszyid: string;
}

/** 一次 multipart 上传。 */
export interface UploadSpec {
  url: string;
  params: UploadFormParams;
  fileName: string;
  contentType: string;
  data: Uint8Array;
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
