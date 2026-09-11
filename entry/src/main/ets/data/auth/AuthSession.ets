/*
 * 会话持有者（data/auth）：**纯内存**的 cookie jar + Session + 当前凭据。
 *
 * ADR-0004 / spec 第 4 节：会话 cookie 与 CSRF **只在内存、不落盘**；这个类没有、也不该有
 * 任何 preferences / 文件 / asset 调用。冷启动重建会话是 ticket 08 的事（用这里持有的凭据
 * 走纯 HTTP 重登），本文件只提供"会话放哪儿"。
 *
 * 为什么把凭据也放这里：重登（08）需要"凭据 + jar"一起用，而两者都是内存单例；
 * 持久化那一份由 CredentialStore 负责，这里只缓存刚读到的那一份，避免每次请求都读 asset。
 */

import { CookieJar } from '../../core/http/CookieJar';
import { CredentialRecord } from '../../domain/auth/CredentialRecord';
import { Session } from '../remote/Requests';

export class AuthSession {
  private readonly jar: CookieJar = new CookieJar();
  private session: Session | null = null;
  private credentials: CredentialRecord | null = null;

  /** HTTP 客户端与 Web 容器共用的内存 jar。 */
  getJar(): CookieJar {
    return this.jar;
  }

  /** 当前会话；未登录时为 null。 */
  current(): Session | null {
    return this.session;
  }

  /** 登记成功 / 重登成功后写入（内存态）。 */
  adopt(session: Session): void {
    this.session = session;
  }

  hasSession(): boolean {
    return this.session !== null;
  }

  setCredentials(record: CredentialRecord | null): void {
    this.credentials = record;
  }

  getCredentials(): CredentialRecord | null {
    return this.credentials;
  }

  /** 登出 / 降级回 Enrollment：会话与凭据缓存一起清掉。 */
  clear(): void {
    this.jar.reset();
    this.session = null;
    this.credentials = null;
  }
}
