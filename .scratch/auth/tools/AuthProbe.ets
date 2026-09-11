/*
 * 一次性设备探针（ticket 06）：等用户完成登记后，用它把「纯 HTTP 登录 → 取 CSRF → 抓一次列表」
 * 在设备上真跑一遍。**这是取证脚手架，不是生产代码**；跑完按 tools/README.md 复原。
 *
 * 为什么需要它：ticket 06 的验收第 1、3 条要真实账号，而账号要等 ticket 07 的登记流程；
 * 本探针把「换个真实凭据就能跑」这件事准备好，让那一步只需要填两个常量 + 跑一条命令。
 *
 * 凭据来源：**占位常量**（下方 USERNAME/PASSWORD/FINGER_*）。不要提交填好的版本——
 * .scratch/auth/tools/credentials.local.txt 与工具说明里都写了这条。等 07 交付凭据库后，
 * 可以改成从凭据库读（LoginClient 支持注入 provider）。
 */

import { Logger } from '../../core/log/Logger';
import { CookieJar } from '../../core/http/CookieJar';
import { encryptPasswordWithSm2 } from '../../core/crypto/Sm2Cipher';
import { HttpFetchPort } from '../../data/remote/HttpFetchPort';
import { HttpMethod, Session } from '../../data/remote/Requests';
import { RawResponse } from '../../data/remote/Port';
import { Credentials, LoginResult } from '../../data/auth/AuthTypes';
import { LEARN_STUDENT_COURSE_LIST_URL, LoginClient } from '../../data/auth/LoginClient';
import { FilesFetcher, FILES_LOG_DOMAIN } from '../../data/remote/FilesFetcher';
import { CourseFile } from '../../domain/model/ContentItem';
import { CourseName } from '../../domain/parse/CourseName';

/* ===== 取证开关与凭据：跑之前填这三行 ===== */
const AUTH_EVIDENCE: boolean = true;
const USERNAME: string = 'FILL_ME';
const PASSWORD: string = 'FILL_ME';
const FINGER_PRINT: string = 'FILL_ME';
const FINGER_GEN_PRINT: string = '';
const FINGER_GEN_PRINT3: string = '';
/* ======================================== */

const logger: Logger = new Logger('evidence.auth');

function filled(value: string): boolean {
  return value.length > 0 && value !== 'FILL_ME';
}

/** 从课程列表页里取第一个 wlkcid（只用它去抓一次列表，不依赖 08 的课程解析）。 */
function firstCourseId(html: string): string {
  const matched: RegExpMatchArray | null = html.match(/wlkcid=(\d+)/);
  return matched === null ? '' : matched[1];
}

export async function runAuthEvidenceProbe(): Promise<void> {
  logger.info('PROBE-SWITCH auth=' + (AUTH_EVIDENCE ? 'on' : 'off')
    + ' credentialsFilled=' + (filled(USERNAME) && filled(PASSWORD) && filled(FINGER_PRINT)).toString());
  if (!AUTH_EVIDENCE) {
    return;
  }
  if (!filled(USERNAME) || !filled(PASSWORD) || !filled(FINGER_PRINT)) {
    logger.error('PROBE aborted: fill USERNAME/PASSWORD/FINGER_PRINT in AuthProbe.ets first');
    return;
  }

  const jar: CookieJar = new CookieJar();
  const port: HttpFetchPort = new HttpFetchPort();
  const client: LoginClient = new LoginClient({
    jar: jar,
    port: port,
    encrypt: encryptPasswordWithSm2,
    logger: new Logger('evidence.auth.login')
  });
  const credentials: Credentials = {
    username: USERNAME,
    password: PASSWORD,
    fingerPrint: FINGER_PRINT,
    fingerGenPrint: FINGER_GEN_PRINT,
    fingerGenPrint3: FINGER_GEN_PRINT3
  };

  const startedAt: number = Date.now();
  const result: LoginResult = await client.login(credentials);
  logger.info('PROBE login ok=' + result.ok.toString()
    + ' reason=' + result.reason
    + ' requiresEnrollment=' + result.requiresEnrollment().toString()
    + ' csrfChars=' + (result.session === undefined ? 0 : result.session.csrfToken.length).toString()
    + ' cookieChars=' + (result.session === undefined ? 0 : result.session.cookie.length).toString()
    + ' elapsedMs=' + (Date.now() - startedAt).toString()
    + ' diag=' + result.diagnostic);
  if (!result.ok || result.session === undefined) {
    logger.error('PROBE login FAILED reason=' + result.reason + ' diag=' + result.diagnostic
      + ' jar=' + jar.describe());
    return;
  }

  // 会话有效性的现场证据：带会话再取一次课程列表页
  const session: Session = result.session;
  const page: RawResponse = await port.sendRaw({
    url: LEARN_STUDENT_COURSE_LIST_URL,
    method: HttpMethod.GET,
    headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Cookie': session.cookie
    }
  });
  const courseId: string = firstCourseId(page.body);
  logger.info('PROBE session page status=' + page.status.toString()
    + ' bytes=' + page.body.length.toString()
    + ' firstCourseId=' + (courseId.length === 0 ? '(none)' : courseId));

  if (courseId.length === 0) {
    logger.error('PROBE no wlkcid found; skip list fetch');
    return;
  }
  const courseNames: Record<string, CourseName> = {};
  const files: FilesFetcher = new FilesFetcher(new Logger(FILES_LOG_DOMAIN), port,
    { cookie: session.cookie, csrfToken: session.csrfToken }, courseNames);
  const items: CourseFile[] = await files.fetch([courseId]);
  logger.info('PROBE files list items=' + items.length.toString()
    + ' (see the data.files anchor line above for elapsedMs)');
}