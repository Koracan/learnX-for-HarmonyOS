/*
 * 会话内请求的小工具（data/remote，ticket 09）：把"发一次 GET/POST 并把结果变成
 * 可观察量"这一件事收在一处，供 data/notices 的课程列表与公告仓储使用。
 *
 * 为什么要它：`AuthedTaskRunner`（data/auth/SessionRestore）要的是一个
 * `(session) => Promise<TaskOutcome>` 的任务，而三域 Fetcher（ticket 05）接的是
 * `FetchPort` + `Session`。本文件是两者之间的桥：**不碰会话、不重试、不降级**——
 * 重登与降级全部留在 AuthedTaskRunner（AGENTS.md 明写"不要自己再造重登/重试/降级逻辑"）。
 *
 * 每个请求都把"我们发出去了什么"变成可观察量（状态码、字节数、带了几条 cookie）：
 * ticket 08 的教训是"在把失败归因给站点或架构之前，先证明自己发出去的请求是完备的"。
 * **绝不落 cookie 值**，只落条数。
 */

import { Logger } from '../../core/log/Logger';
import { FetchOutcome, FetchPort, GetSpec, PostFormSpec } from './Port';
import { Session } from './Requests';

/** 请求摘要：条数 + 每条值长度，例如 `[JSESSIONID(32),XSRF-TOKEN(36)]`。 */
export function describeCookieHeader(cookie: string): string {
  if (cookie.length === 0) {
    return '[]';
  }
  const parts: string[] = cookie.split(';');
  const names: string[] = [];
  for (let i = 0; i < parts.length; i++) {
    const piece: string = parts[i].trim();
    if (piece.length === 0) {
      continue;
    }
    const eq: number = piece.indexOf('=');
    names.push(eq > 0 ? piece.substring(0, eq) + '(' + (piece.length - eq - 1).toString() + ')' : piece);
  }
  return '[' + names.join(',') + ']';
}

/** 会话内 GET；返回原始 outcome（不抛异常，失败也是结果）。 */
export async function authedGet(port: FetchPort, session: Session, logger: Logger, label: string,
  url: string): Promise<FetchOutcome> {
  const spec: GetSpec = { url: url };
  const outcome: FetchOutcome = await port.get(session, spec);
  logger.info(label + ' GET status=' + outcome.status.toString()
    + ' bytes=' + outcome.body.length.toString()
    + ' ok=' + outcome.ok.toString()
    + ' cookies=' + describeCookieHeader(session.cookie));
  if (!outcome.ok) {
    const detail: string = outcome.error === undefined ? 'HTTP ' + outcome.status.toString() : outcome.error;
    logger.warn(label + ' GET failed ' + detail + ' url=' + url);
  }
  return outcome;
}

/** 会话内 POST 表单（列表接口用）。 */
export async function authedPostForm(port: FetchPort, session: Session, logger: Logger, label: string,
  spec: PostFormSpec): Promise<FetchOutcome> {
  const outcome: FetchOutcome = await port.postForm(session, spec);
  logger.info(label + ' POST status=' + outcome.status.toString()
    + ' bytes=' + outcome.body.length.toString()
    + ' ok=' + outcome.ok.toString()
    + ' cookies=' + describeCookieHeader(session.cookie));
  if (!outcome.ok) {
    const detail: string = outcome.error === undefined ? 'HTTP ' + outcome.status.toString() : outcome.error;
    logger.warn(label + ' POST failed ' + detail + ' url=' + spec.url);
  }
  return outcome;
}
