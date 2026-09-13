/*
 * 抓取定义与响应记录——**纯数据 / 纯字符串运算，零平台依赖**。
 *
 * 三张"抓什么"的表照抄参考实现 DataProcessorModule.ts：
 * 公告两个列表接口、作业三个列表接口（未交 / 已交 / 已评分）、文件一个接口。
 * 平台调用（http）在 data/remote/HttpClient，本文件只描述请求。
 *
 * 注意 ArkTS 的两条硬约束（本工程反复踩过）：
 *   - 不支持结构化类型：对象字面量必须对应**显式声明的接口**，所以表单参数用命名接口
 *     描述，不用匿名形状，也不要用 `Record<string, string>` 当表单参数类型；
 *   - `@ohos.net.http` 的 `method` 是枚举，不能用裸字符串。
 */

/** HTTP 方法。 */
export enum HttpMethod {
  GET = 'GET',
  POST = 'POST'
}

export const LEARN_ORIGIN: string = 'https://learn.tsinghua.edu.cn';
export const USER_AGENT: string =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
export const FORM_CONTENT_TYPE: string = 'application/x-www-form-urlencoded';

/** 会话：cookie 与 CSRF 令牌。内存态，不落盘。 */
export interface Session {
  cookie: string;
  csrfToken: string;
}

/** 一次 HTTP 请求的描述（方法 + 地址 + 头 + body）。 */
export interface RequestSpec {
  url: string;
  method: HttpMethod;
  headers: Record<string, string>;
  body?: string;
}

/** 一次 HTTP 请求的结果（不抛异常，失败也是结果）。 */
export interface HttpOutcome {
  ok: boolean;
  status: number;
  body: string;
  error?: string;
}

export function defaultHeaders(session: Session): Record<string, string> {
  const headers: Record<string, string> = {};
  headers['Cookie'] = session.cookie;
  headers['User-Agent'] = USER_AGENT;
  return headers;
}

export function formHeaders(session: Session): Record<string, string> {
  const headers: Record<string, string> = {};
  headers['Content-Type'] = FORM_CONTENT_TYPE;
  headers['Cookie'] = session.cookie;
  headers['User-Agent'] = USER_AGENT;
  return headers;
}

export function withCsrf(url: string, csrfToken: string): string {
  return url + '?_csrf=' + csrfToken;
}

/** 公告列表：两个接口分别对应"未过期"与"已过期"。 */
export const NOTICE_LIST_PATHS: string[] = [
  '/b/wlxt/kcgg/wlkc_ggb/student/pageListXsbyWgq',
  '/b/wlxt/kcgg/wlkc_ggb/student/pageListXsbyYgq'
];
