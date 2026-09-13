/*
 * 下载端口（data/remote）：**独立于 `FetchPort`** 的一个兄弟接口。
 *
 * ## 为什么新增一个接口，而不是给 `FetchPort` 加方法
 *
 * ticket 06 给"原始请求通道"（登录流）加 `RawFetchPort` 时定的先例：`FetchPort` 描述的是
 * **三域抓取那三种固定请求**（args 已收敛成 courseId/id），下载既不是那三种、又需要
 * 响应头与分块字节，所以新增一个同级接口，由**同一个平台适配层**（HttpDownloadPort）实现。
 * 既有 `FetchPort` / `RawFetchPort` 的签名与语义**一行未动** —— 三域 Fetcher 与既有单测
 * 无需改动（见 ticket 11 交付说明的边界一节）。
 *
 * ## 为什么它能给"真进度"
 *
 * `@ohos.net.http` 的 `requestInStream` 是**同一个 HTTP 平台模块**（不是
 * `@ohos.request` 那个下载库）。它按块交付
 * `dataReceive`（ArrayBuffer）+ `headersReceive`（Content-Length），
 * 于是"已接收字节 / 总字节"是**真实**的可观察量，不是估算。
 * **没有**假装百分比：Content-Length 缺失时 total = -1，界面走不确定进度。
 *
 * ## 次序的诚实说明（很重要）
 *
 * 平台只在 `requestInStream` **结束**时给出状态码，响应头则在**第一个字节之前**给出。
 * 因此：
 *   - Content-Type 判定（HTML/JSON → 不落盘）发生在**任何字节写出之前**；
 *   - 状态码判定只能发生在流结束之后（调用方据此删除刚写的文件并报错）。
 * 这里把两件事如实拆开，而不是把状态码"假装"能在头里看到。
 */

import { Session } from './Requests';

/** 响应头里我们需要的三个量（**不含状态码**：平台在 headersReceive 里不给它）。 */
export interface DownloadHeaders {
  /** `Content-Type` 原样（可能为空串 = 服务端没给）。 */
  contentType: string;
  /** `Content-Length`；-1 = 未知/非法。 */
  contentLength: number;
}

/** 下载落点的写入端口（由编排层提供；端口自己不碰文件系统）。 */
export interface DownloadSink {
  /**
   * 响应头到达（**同步**，第一个字节之前）。返回 `false` = 不落盘：
   * 端口必须立即中止，并且**不得**再调用 `onChunk`。
   */
  onHeaders(headers: DownloadHeaders): boolean;
  /** 一块响应体（仅在 `onHeaders` 返回 true 后被调用）。 */
  onChunk(chunk: ArrayBuffer): void;
}

/** 一次流式下载的结果。 */
export interface DownloadStreamResult {
  /** 网络层拿到 200、且未被 sink 拒绝、且没有写错误。 */
  ok: boolean;
  status: number;
  contentType: string;
  contentLength: number;
  receivedBytes: number;
  /** true = `sink.onHeaders` 返回了 false（没有任何字节交付给 sink）。 */
  rejected: boolean;
  error?: string;
}

/** 下载端口。 */
export interface DownloadPort {
  download(session: Session, url: string, sink: DownloadSink): Promise<DownloadStreamResult>;
}
