/*
 * 登记单测夹具：注入式端口替身 + 从浏览器收割到的 cookie 头。
 *
 * 成色：
 *   - **注入式替身**（FakeSecretStore / ScriptedRawPort）是"脚本化假实现"，不是真实平台行为——
 *     与既有端口替身同口径；
 *   - **COURSE_LIST_PAGE_HTML 直接复用 AuthFixtures**（那份夹具的成色见
 *     fixtures/README.md），本文件不另造一份，避免同一事实两处维护。
 *
 * 这里没有、也不该有：真实账号、真实指纹、真实会话 cookie。
 */

import { SecretStore } from '../../main/ets/core/asset/SecretStorePort';
import { RawFetchPort, RawRequest, RawResponse } from '../../main/ets/data/remote/Port';

/** 内存秘密存储：记录写入次数，便于断言"不该写的时候没写"。 */
export class FakeSecretStore implements SecretStore {
  private values: Map<string, string> = new Map<string, string>();
  writes: number = 0;
  removes: number = 0;

  async read(alias: string): Promise<string | null> {
    const value: string | undefined = this.values.get(alias);
    return value === undefined ? null : value;
  }

  async write(alias: string, value: string): Promise<boolean> {
    this.writes++;
    this.values.set(alias, value);
    return true;
  }

  async remove(alias: string): Promise<boolean> {
    this.removes++;
    this.values.delete(alias);
    return true;
  }

  /** 仅测试用：直接塞一个值（模拟"盘上有一条历史记录"）。 */
  plant(alias: string, value: string): void {
    this.values.set(alias, value);
  }

  raw(alias: string): string | undefined {
    return this.values.get(alias);
  }

  /** 存储里的字节形态（用于断言"没有明文口令/cookie 以明文形式被我们另存"）。 */
  allValues(): string[] {
    const out: string[] = [];
    this.values.forEach((value: string) => {
      out.push(value);
    });
    return out;
  }
}

/** 脚本化的原始请求端口：每次调用返回下一个脚本响应，并记录收到的请求。 */
export class ScriptedRawPort implements RawFetchPort {
  readonly requests: RawRequest[] = [];
  private script: RawResponse[] = [];
  private cursor: number = 0;

  constructor(script: RawResponse[]) {
    this.script = script;
  }

  async sendRaw(spec: RawRequest): Promise<RawResponse> {
    this.requests.push(spec);
    const index: number = this.cursor < this.script.length ? this.cursor : this.script.length - 1;
    this.cursor++;
    return this.script[index];
  }

  lastCookieHeader(): string {
    if (this.requests.length === 0) {
      return '';
    }
    const headers: Record<string, string> = this.requests[this.requests.length - 1].headers;
    const cookie: string | undefined = headers['Cookie'];
    return cookie === undefined ? '' : cookie;
  }
}

/** 组装一个脚本响应。 */
export function rawResponse(status: number, body: string, setCookie: string): RawResponse {
  return {
    ok: status >= 200 && status < 300,
    status: status,
    body: body,
    setCookie: setCookie,
    headers: {},
    requestUrl: 'https://learn.tsinghua.edu.cn/f/wlxt/index/course/student/'
  };
}

/** 浏览器收割到的 Cookie 头（形态照 \`WebCookieManager.fetchCookieSync\` 的返回）。 */
export const HARVESTED_COOKIE_HEADER: string =
  'JSESSIONID=HARVEST-1; SERVERID=node1; _ga=GA1.2.3; learn=1';

/** 只含一个 cookie 的最小头。 */
export const HARVESTED_COOKIE_HEADER_ONE: string = 'JSESSIONID=HARVEST-1';

/** 一个完整凭据记录的字段（**合成值**，不是任何真实账号/指纹）。 */
export const SYNTHETIC_USERNAME: string = 'probe-user';
export const SYNTHETIC_PASSWORD: string = 'probe-secret';
export const SYNTHETIC_FINGERPRINT: string = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
export const SYNTHETIC_FINGER_GEN_PRINT: string = 'site-finger-3';
export const SYNTHETIC_FINGER_GEN_PRINT3: string = 'site-finger-3';
