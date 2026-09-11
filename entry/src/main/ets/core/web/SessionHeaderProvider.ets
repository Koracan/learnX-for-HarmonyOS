/*
 * Web 容器的**会话注入端口**（cookie 头 + CSRF 令牌）。
 *
 * 参考实现 `AutoHeightWebView.tsx:57-71,90-92` 直接向两个全局单例取值：
 * `CookieManager.get(Urls.learn)` 得到 cookie 写进请求头，
 * `dataSource.getCSRFToken()` 的值进模板。ArkTS 里没有这两个单例，
 * Web 层也不该反向依赖 data 层 —— 所以收敛成一个可注入端口：
 *
 *   - Mock 阶段（ticket 04）默认实现返回空串；
 *   - ticket 06/09 在会话建立后把**内存里的**值注入进来，调用点不动。
 *
 * 硬约束（spec 第 4 节 / ADR-0004）：**会话 cookie 与 CSRF 只在内存，绝不落盘**。
 * 本文件因此只有取值端口，没有任何 preferences / 文件写入。
 */
import { Logger } from '../log/Logger';

const logger: Logger = new Logger('core.web.session');

/** learn 站点根（参考实现 constants/Urls.ts 的 `Urls.learn`）。 */
export const LEARN_URL: string = 'https://learn.tsinghua.edu.cn';

/** 会话注入端口。 */
export interface SessionHeaderProvider {
  /** 请求头 `Cookie` 的值；无会话时为空串。 */
  cookieHeader(): string;
  /** 模板注入脚本用的 CSRF 令牌；Mock 下为空串。 */
  csrfToken(): string;
}

/** Mock / 未登录阶段的实现：两个值都是空串（与参考实现未登录时一致）。 */
export class EmptySessionHeaderProvider implements SessionHeaderProvider {
  cookieHeader(): string {
    return '';
  }

  csrfToken(): string {
    return '';
  }
}

/**
 * 内存会话（ticket 06 的注入点）。**只存内存**：进程结束即丢，符合 ADR-0004。
 */
export class InMemorySessionHeaderProvider implements SessionHeaderProvider {
  private cookie: string = '';
  private token: string = '';

  /** 由会话建立方（ticket 06/09）调用；参数为空即清空。 */
  update(cookie: string, csrfToken: string): void {
    this.cookie = cookie;
    this.token = csrfToken;
  }

  cookieHeader(): string {
    return this.cookie;
  }

  csrfToken(): string {
    return this.token;
  }
}

const emptyProvider: EmptySessionHeaderProvider = new EmptySessionHeaderProvider();

/** 当前生效的会话提供者。Mock 阶段是空实现；ticket 06 在此换成内存实现并 update。 */
export function createSessionHeaderProvider(): SessionHeaderProvider {
  return emptyProvider;
}

/**
 * 把**实际生效值**打进 hilog —— 取证要求（AGENTS.md「取证开关必须自证生效」）：
 * "没抓到"与"端口没接上"必须能区分开。**不打印 cookie 内容**（那是会话凭证），
 * 只打印条目数与令牌是否存在。
 */
export function logSessionHeaderState(provider: SessionHeaderProvider): void {
  const cookie: string = provider.cookieHeader();
  const token: string = provider.csrfToken();
  const entries: string[] = cookie.length === 0 ? [] : cookie.split('; ');
  logger.info('web session header: cookieEntries=' + entries.length.toString()
    + ' cookieBytes=' + cookie.length.toString()
    + ' csrfTokenPresent=' + (token.length > 0).toString());
}
