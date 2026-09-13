/*
 * 把应用内存会话写进 Web 容器 cookie 存储的**参数构造**（纯逻辑，可单测）。
 *
 * 为什么需要：公告正文里的图片是 learn 源上的子资源，请求由 ArkWeb 自己发出；
 * 容器里的 cookie 存储与应用 HTTP 栈是两套互不相通的东西。不把当前会话显式写进去，
 * 子资源就会带着空会话发出，服务端 302 到登录超时页，<img> 于是 naturalWidth=0。
 *
 * 硬约束（ADR-0004）：会话 cookie 不落盘。因此 incognito 恒为 true —— 写进 Web 容器的
 * **内存态**存储（Web 组件本身也置 incognitoMode，两者是同一个存储）；includeHttpOnly
 * 恒为 true，否则覆盖不了很可能带 HttpOnly 的 JSESSIONID。
 */
import { CookiePair, parseCookieHeaderPairs } from '../http/CookieJar';

/** 写入 Web 容器 cookie 存储时是否走 incognito（内存态）；恒为 true，见文件头。 */
export const WEB_COOKIE_INCOGNITO: boolean = true;
/** 是否允许覆盖 HttpOnly cookie；恒为 true（JSESSIONID 很可能是 HttpOnly）。 */
export const WEB_COOKIE_INCLUDE_HTTP_ONLY: boolean = true;

/** 一次 `WebCookieManager.configCookieSync` 调用的全部参数。 */
export interface WebCookieWrite {
  /** cookie 归属的 URL（只写 learn 源）。 */
  url: string;
  /** `Set-Cookie` 形态的串：`name=value`。 */
  value: string;
  /** cookie 名（**只用于日志**）。 */
  name: string;
  /** 值长度（**只用于日志**；值本身是会话凭证，不进日志）。 */
  valueChars: number;
  incognito: boolean;
  includeHttpOnly: boolean;
}

/**
 * 把 `Cookie` 头形态的会话串（`a=1; b=2`）转成逐条写入参数。
 *
 * 空串、空白串、只有非法段时返回空数组 —— 调用方据此**不写任何 cookie**
 * （未登录 / 登出后容器里不能留可用会话）。
 */
export function buildWebCookieWrites(cookieHeader: string, url: string): WebCookieWrite[] {
  const writes: WebCookieWrite[] = [];
  const pairs: CookiePair[] = parseCookieHeaderPairs(cookieHeader);
  for (let i = 0; i < pairs.length; i++) {
    const pair: CookiePair = pairs[i];
    writes.push({
      url: url,
      value: pair.name + '=' + pair.value,
      name: pair.name,
      valueChars: pair.value.length,
      incognito: WEB_COOKIE_INCOGNITO,
      includeHttpOnly: WEB_COOKIE_INCLUDE_HTTP_ONLY
    });
  }
  return writes;
}
