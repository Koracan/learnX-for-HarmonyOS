/*
 * 冷启动静默重登 + 运行期降级的单测（注入式部分）。
 *
 * 覆盖：
 *   - `credentialsFor`：凭据记录 → 登录表单字段的映射逐字段保真（重登依赖它）；
 *   - `SessionRestorer`：成功 / 无凭据 / 断网 / 被拒四类分类；**已有会话不再登录**；
 *     并发 N 个 restore() 只登录一次；整体超时（不卡在加载态）；网络恢复后重试能成功；
 *   - `AuthedTaskRunner`：健康响应不变；'[]' ∪ 403/login_timeout 触发重登且只重试一次；
 *     **重登后仍是 '[]' 时显式降级（不出现空列表）**；任务层断网 → 降级且标记 offline；
 *     并发 N 个请求只重登一次；重试用的是**刷新后的**会话；
 *   - ADR-0004：恢复全过程对秘密存储**零写入**，且存储里找不到会话痕迹。
 *
 * 全部依赖注入，无平台调用；"断网"用注入端口返回 status=0 的失败响应表示
 * （设备侧同形状来自 HttpClient 的 failure，见 data/remote/HttpClient.ets）。
 */

import { describe, it, expect } from '@ohos/hypium';
import { Logger } from '../main/ets/core/log/Logger';
import { CookieJar } from '../main/ets/core/http/CookieJar';
import { CredentialStore } from '../main/ets/data/auth/CredentialStore';
import { FailReason, LoginResult } from '../main/ets/data/auth/AuthTypes';
import { ReAuthCoordinator, SessionGate, TaskOutcome } from '../main/ets/data/auth/ReAuth';
import {
  AuthedRunResult, AuthedTaskRunner, SessionRestoreKind, SessionRestoreResult, SessionRestorer,
  credentialsFor
} from '../main/ets/data/auth/SessionRestore';
import { Session } from '../main/ets/data/remote/Requests';
import { CredentialRecord, createCredentialRecord } from '../main/ets/domain/auth/CredentialRecord';
import { EMPTY_LIST_BODY, LOGIN_TIMEOUT_BODY } from './fixtures/AuthFixtures';
import { FakeSecretStore } from './fixtures/EnrollmentFixtures';

const OK_BODY: string = '{"result":"success","object":{"aaData":[]}}';
const LIST_URL: string = 'https://learn.tsinghua.edu.cn/b/wlxt/kcgg/wlkc_ggb/student/pageListXsbyWgq';

function delay(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void): void => {
    setTimeout(resolve, ms);
  });
}

function okLoginWith(cookie: string): LoginResult {
  const session: Session = { cookie: cookie, csrfToken: 'TOKEN-' + cookie };
  return LoginResult.success(session, 'zh');
}

function failureLogin(reason: FailReason): LoginResult {
  return LoginResult.failure(reason, 'stub ' + reason);
}

function taskOutcome(status: number, body: string): TaskOutcome {
  return { status: status, body: body, responseUrl: LIST_URL };
}

/** 内存会话的持有者（对应设备侧的 AuthSession.current）。 */
class FakeSessionSink {
  session: Session | null = null;

  current = (): Session | null => this.session;
}

/** 脚本化登录：按序返回预置结果，并把成功的会话交给 sink（对应 AuthServices 的 login action）。 */
class ScriptedAuth {
  readonly sink: FakeSessionSink = new FakeSessionSink();
  calls: number = 0;
  private script: LoginResult[];
  private delayMs: number;

  constructor(script: LoginResult[], delayMs: number) {
    this.script = script;
    this.delayMs = delayMs;
  }

  login = async (): Promise<LoginResult> => {
    const index: number = this.calls < this.script.length ? this.calls : this.script.length - 1;
    this.calls++;
    if (this.delayMs > 0) {
      await delay(this.delayMs);
    }
    const result: LoginResult = this.script[index];
    if (result.ok && result.session !== undefined) {
      this.sink.session = result.session;
    }
    return result;
  };
}

/** 脚本化任务：按序返回预置 outcome，并记录每次实际使用的会话（重试应当换新会话）。 */
class ScriptedTask {
  readonly seenCookies: string[] = [];
  private script: TaskOutcome[];
  private cursor: number = 0;

  constructor(script: TaskOutcome[]) {
    this.script = script;
  }

  run = async (session: Session): Promise<TaskOutcome> => {
    this.seenCookies.push(session.cookie);
    const index: number = this.cursor < this.script.length ? this.cursor : this.script.length - 1;
    this.cursor++;
    return this.script[index];
  };
}

function restorerFor(auth: ScriptedAuth, timeoutMillis: number = 20000): SessionRestorer {
  const coordinator: ReAuthCoordinator = new ReAuthCoordinator(auth.login, new Logger('data.auth.test'));
  return new SessionRestorer({
    coordinator: coordinator,
    currentSession: auth.sink.current,
    logger: new Logger('data.auth.test'),
    timeoutMillis: timeoutMillis
  });
}

/** 装好的 runner：restorer 与 gate 共享同一个 coordinator（设备侧同构，见 AuthServices）。 */
class Harness {
  readonly auth: ScriptedAuth;
  readonly restorer: SessionRestorer;
  readonly runner: AuthedTaskRunner;

  constructor(auth: ScriptedAuth, timeoutMillis: number = 20000) {
    this.auth = auth;
    const coordinator: ReAuthCoordinator = new ReAuthCoordinator(auth.login, new Logger('data.auth.test'));
    this.restorer = new SessionRestorer({
      coordinator: coordinator,
      currentSession: auth.sink.current,
      logger: new Logger('data.auth.test'),
      timeoutMillis: timeoutMillis
    });
    const gate: SessionGate = new SessionGate(coordinator, new Logger('data.auth.test'));
    this.runner = new AuthedTaskRunner(this.restorer, gate, auth.sink.current, new Logger('data.auth.test'));
  }
}

export default function sessionRestoreTest() {
  describe('data.auth.SessionRestore', () => {
    it('mapsEveryCredentialFieldIntoTheLoginFormFields', 0, () => {
      const record: CredentialRecord = createCredentialRecord('u1', 'p1', 'FP-1', 'GP-2', 'GP3-3');
      const credentials = credentialsFor(record);
      expect(credentials.username).assertEqual('u1');
      expect(credentials.password).assertEqual('p1');
      expect(credentials.fingerPrint).assertEqual('FP-1');
      expect(credentials.fingerGenPrint).assertEqual('GP-2');
      expect(credentials.fingerGenPrint3).assertEqual('GP3-3');
    });

    it('restoresASessionFromPersistedCredentials', 0, async () => {
      const auth: ScriptedAuth = new ScriptedAuth([okLoginWith('COLD')], 0);
      const restorer: SessionRestorer = restorerFor(auth);
      const result: SessionRestoreResult = await restorer.restore();
      expect(result.ok()).assertTrue();
      expect(result.kind).assertEqual(SessionRestoreKind.RESTORED);
      expect(result.requiresEnrollment()).assertFalse();
      expect(result.isOffline()).assertFalse();
      expect(result.session?.csrfToken).assertEqual('TOKEN-COLD');
      expect(result.language).assertEqual('zh');
      expect(auth.calls).assertEqual(1);
      expect(restorer.attemptCount()).assertEqual(1);
    });

    it('reusesTheInMemorySessionWithoutLoggingInAgain', 0, async () => {
      const auth: ScriptedAuth = new ScriptedAuth([okLoginWith('COLD')], 0);
      const restorer: SessionRestorer = restorerFor(auth);
      await restorer.restore();
      const second: SessionRestoreResult = await restorer.restore();
      expect(second.ok()).assertTrue();
      // 已有会话就短路：数据路径每个请求都会问一次，不短路就会每个请求都登一次
      expect(auth.calls).assertEqual(1);
      expect(restorer.attemptCount()).assertEqual(1);
    });

    it('forcesANewLoginWhenTheInMemorySessionIsStale', 0, async () => {
      // 回到前台且闲置过久：内存里有会话**不等于**服务端还认它 ⇒ 必须换一份
      // （restore() 的短路是数据路径要的；这条路径要的正是绕过它）。
      const auth: ScriptedAuth = new ScriptedAuth([okLoginWith('COLD'), okLoginWith('FRESH')], 0);
      const restorer: SessionRestorer = restorerFor(auth);
      const cold: SessionRestoreResult = await restorer.restore();
      expect(cold.session?.cookie).assertEqual('COLD');
      const refreshed: SessionRestoreResult = await restorer.refreshSession();
      expect(refreshed.ok()).assertTrue();
      expect(refreshed.session?.cookie).assertEqual('FRESH');
      expect(auth.calls).assertEqual(2);
      expect(restorer.attemptCount()).assertEqual(2);
      // 换完之后数据路径拿到的就是新会话（restore() 短路的已是 adopt 之后那一份）
      const after: SessionRestoreResult = await restorer.restore();
      expect(after.session?.cookie).assertEqual('FRESH');
      expect(auth.calls).assertEqual(2);
    });

    it('joinsAnInFlightForcedRefreshInsteadOfReturningTheStaleSession', 0, async () => {
      // 前台换会话与用户此刻触发的数据请求可能并发：两边必须共享同一次登录，
      // 且并发的那次 restore() 不能把**旧**会话交出去（否则那一轮请求注定白跑）。
      const auth: ScriptedAuth = new ScriptedAuth([okLoginWith('COLD'), okLoginWith('FRESH')], 30);
      const restorer: SessionRestorer = restorerFor(auth);
      await restorer.restore();
      const forced: Promise<SessionRestoreResult> = restorer.refreshSession();
      const joined: SessionRestoreResult = await restorer.restore();
      const refreshed: SessionRestoreResult = await forced;
      expect(joined.session?.cookie).assertEqual('FRESH');
      expect(refreshed.session?.cookie).assertEqual('FRESH');
      expect(auth.calls).assertEqual(2);
      expect(restorer.attemptCount()).assertEqual(2);
    });

    it('classifiesMissingCredentialsAsNeedsEnrollment', 0, async () => {
      const auth: ScriptedAuth = new ScriptedAuth([failureLogin(FailReason.NO_CREDENTIAL)], 0);
      const result: SessionRestoreResult = await restorerFor(auth).restore();
      expect(result.ok()).assertFalse();
      expect(result.kind).assertEqual(SessionRestoreKind.NO_CREDENTIALS);
      expect(result.requiresEnrollment()).assertTrue();
      expect(result.isOffline()).assertFalse();
    });

    it('classifiesANetworkFailureAsOffline', 0, async () => {
      const auth: ScriptedAuth = new ScriptedAuth([failureLogin(FailReason.NETWORK_UNREACHABLE)], 0);
      const result: SessionRestoreResult = await restorerFor(auth).restore();
      expect(result.ok()).assertFalse();
      expect(result.kind).assertEqual(SessionRestoreKind.OFFLINE);
      expect(result.isOffline()).assertTrue();
      // 断网也要有可理解的提示 —— 界面据 isOffline 选"检查网络"那条文案
      expect(result.requiresEnrollment()).assertTrue();
    });

    it('classifiesServerRejectionAsExplicitDegradation', 0, async () => {
      // 信任过期 / 403 / login_timeout：服务端直接拒绝，参考实现的原生路径在这里**不会**重登
      const auth: ScriptedAuth = new ScriptedAuth([failureLogin(FailReason.NOT_LOGGED_IN)], 0);
      const result: SessionRestoreResult = await restorerFor(auth).restore();
      expect(result.ok()).assertFalse();
      expect(result.kind).assertEqual(SessionRestoreKind.REJECTED);
      expect(result.reason).assertEqual(FailReason.NOT_LOGGED_IN);
      expect(result.requiresEnrollment()).assertTrue();
      expect(result.isOffline()).assertFalse();
    });

    it('singleFlightsConcurrentColdStartRestores', 0, async () => {
      const auth: ScriptedAuth = new ScriptedAuth([okLoginWith('COLD')], 30);
      const restorer: SessionRestorer = restorerFor(auth);
      const pending: Promise<SessionRestoreResult>[] = [];
      for (let i = 0; i < 5; i++) {
        pending.push(restorer.restore());
      }
      const results: SessionRestoreResult[] = await Promise.all(pending);
      for (let i = 0; i < results.length; i++) {
        expect(results[i].ok()).assertTrue();
      }
      // 并发 N 个 restore() 只触发一次登录（照 source.ts:111-121 的单飞）
      expect(auth.calls).assertEqual(1);
      expect(restorer.attemptCount()).assertEqual(1);
    });

    it('timesOutInsteadOfHangingInTheLoadingState', 0, async () => {
      // 登录比整体超时慢：必须结束在 OFFLINE，而不是无限期停在 LOADING
      const auth: ScriptedAuth = new ScriptedAuth([okLoginWith('TOO-LATE')], 200);
      const restorer: SessionRestorer = restorerFor(auth, 20);
      const result: SessionRestoreResult = await restorer.restore();
      expect(result.ok()).assertFalse();
      expect(result.kind).assertEqual(SessionRestoreKind.OFFLINE);
      expect(result.diagnostic.indexOf('timed out') >= 0).assertTrue();
    });

    it('succeedsWhenTheUserRetriesAfterTheNetworkComesBack', 0, async () => {
      const auth: ScriptedAuth = new ScriptedAuth(
        [failureLogin(FailReason.NETWORK_UNREACHABLE), okLoginWith('COLD')], 0);
      const restorer: SessionRestorer = restorerFor(auth);
      const first: SessionRestoreResult = await restorer.restore();
      expect(first.isOffline()).assertTrue();
      const second: SessionRestoreResult = await restorer.restore();
      expect(second.ok()).assertTrue();
      // 第二次是**一次用户动作**触发的重试，不是静默循环：正好两次
      expect(auth.calls).assertEqual(2);
    });

    it('doesNotDegradeWhenTheTaskIsHealthy', 0, async () => {
      const auth: ScriptedAuth = new ScriptedAuth([okLoginWith('COLD')], 0);
      const harness: Harness = new Harness(auth);
      const task: ScriptedTask = new ScriptedTask([taskOutcome(200, OK_BODY)]);
      const result: AuthedRunResult = await harness.runner.run(task.run);
      expect(result.ok).assertTrue();
      expect(result.requiresEnrollment).assertFalse();
      expect(result.value).assertEqual(OK_BODY);
      expect(auth.calls).assertEqual(1);
      expect(task.seenCookies.length).assertEqual(1);
    });

    it('retriesOnceWithTheRefreshedSessionWhenTheResultIsAnEmptyList', 0, async () => {
      const auth: ScriptedAuth = new ScriptedAuth([okLoginWith('COLD'), okLoginWith('REAUTH')], 0);
      const harness: Harness = new Harness(auth);
      const task: ScriptedTask = new ScriptedTask([taskOutcome(200, EMPTY_LIST_BODY), taskOutcome(200, OK_BODY)]);
      const result: AuthedRunResult = await harness.runner.run(task.run);
      expect(result.ok).assertTrue();
      expect(result.reAuthAttempted).assertTrue();
      expect(result.value).assertEqual(OK_BODY);
      expect(auth.calls).assertEqual(2);
      // 重试必须用**刷新后**的会话（cookie 会随响应轮换，拿旧的等于没重登）
      expect(task.seenCookies.length).assertEqual(2);
      expect(task.seenCookies[0]).assertEqual('COLD');
      expect(task.seenCookies[1]).assertEqual('REAUTH');
    });

    it('degradesWhenTheListIsStillEmptyAfterReAuth', 0, async () => {
      // 已知缺口：原生路径在重登后仍是 '[]' 时会静默成功（界面看到空列表）。
      // 这里显式把它翻成"需要重新验证"，并且**不把空列表交给上层**。
      const auth: ScriptedAuth = new ScriptedAuth([okLoginWith('COLD'), okLoginWith('REAUTH')], 0);
      const harness: Harness = new Harness(auth);
      const task: ScriptedTask = new ScriptedTask([taskOutcome(200, EMPTY_LIST_BODY), taskOutcome(200, EMPTY_LIST_BODY)]);
      const result: AuthedRunResult = await harness.runner.run(task.run);
      expect(result.ok).assertFalse();
      expect(result.requiresEnrollment).assertTrue();
      expect(result.reason).assertEqual(FailReason.NOT_LOGGED_IN);
      expect(result.value).assertEqual('');
      expect(result.value === EMPTY_LIST_BODY).assertFalse();
      expect(result.reAuthAttempted).assertTrue();
      expect(task.seenCookies.length).assertEqual(2);
    });

    it('degradesOnLoginTimeoutAndRetriesOnlyOnce', 0, async () => {
      const auth: ScriptedAuth = new ScriptedAuth([okLoginWith('COLD'), okLoginWith('REAUTH')], 0);
      const harness: Harness = new Harness(auth);
      const task: ScriptedTask = new ScriptedTask([taskOutcome(200, LOGIN_TIMEOUT_BODY), taskOutcome(200, OK_BODY)]);
      const result: AuthedRunResult = await harness.runner.run(task.run);
      expect(result.ok).assertTrue();
      expect(result.value).assertEqual(OK_BODY);
      expect(task.seenCookies.length).assertEqual(2);
    });

    it('degradesWithoutRunningTheTaskWhenNoSessionCanBeEstablished', 0, async () => {
      const auth: ScriptedAuth = new ScriptedAuth([failureLogin(FailReason.NOT_LOGGED_IN)], 0);
      const harness: Harness = new Harness(auth);
      const task: ScriptedTask = new ScriptedTask([taskOutcome(200, OK_BODY)]);
      const result: AuthedRunResult = await harness.runner.run(task.run);
      expect(result.ok).assertFalse();
      expect(result.requiresEnrollment).assertTrue();
      expect(result.reason).assertEqual(FailReason.NOT_LOGGED_IN);
      // 没有会话就不该发任务（避免"空列表"这种中间态）
      expect(task.seenCookies.length).assertEqual(0);
      expect(auth.calls).assertEqual(1);
    });

    it('singleFlightsConcurrentRequestsIntoOneReAuth', 0, async () => {
      const auth: ScriptedAuth = new ScriptedAuth([okLoginWith('COLD'), okLoginWith('REAUTH')], 30);
      const harness: Harness = new Harness(auth);
      // 先热一次：拿到冷启动会话（登录 #1）
      const warm: ScriptedTask = new ScriptedTask([taskOutcome(200, OK_BODY)]);
      expect((await harness.runner.run(warm.run)).ok).assertTrue();
      expect(auth.calls).assertEqual(1);

      // 5 个并发请求同时发现会话失效：只允许**一次**重登（登录 #2）
      const pending: Promise<AuthedRunResult>[] = [];
      for (let i = 0; i < 5; i++) {
        const task: ScriptedTask = new ScriptedTask([taskOutcome(200, EMPTY_LIST_BODY), taskOutcome(200, OK_BODY)]);
        pending.push(harness.runner.run(task.run));
      }
      const results: AuthedRunResult[] = await Promise.all(pending);
      for (let i = 0; i < results.length; i++) {
        expect(results[i].ok).assertTrue();
        expect(results[i].reAuthAttempted).assertTrue();
      }
      expect(auth.calls).assertEqual(2);
    });

    it('treatsANetworkFailureInsideATaskAsDegradationNotAsAnEmptyList', 0, async () => {
      const auth: ScriptedAuth = new ScriptedAuth(
        [okLoginWith('COLD'), failureLogin(FailReason.NETWORK_UNREACHABLE)], 0);
      const harness: Harness = new Harness(auth);
      // 任务层断网：平台给的就是 status=0（HttpResponse.failure）
      const task: ScriptedTask = new ScriptedTask([taskOutcome(0, '')]);
      const result: AuthedRunResult = await harness.runner.run(task.run);
      expect(result.ok).assertFalse();
      expect(result.requiresEnrollment).assertTrue();
      expect(result.isOffline()).assertTrue();
      expect(result.reason).assertEqual(FailReason.NETWORK_UNREACHABLE);
      expect(result.value).assertEqual('');
    });

    it('keepsTheRestoredSessionOutOfAnyPersistentStore', 0, async () => {
      const secrets: FakeSecretStore = new FakeSecretStore();
      const store: CredentialStore = new CredentialStore(secrets);
      expect(await store.save(createCredentialRecord('u1', 'p1', 'FP-1', 'GP-2', 'GP3-3'))).assertTrue();
      const writesAfterCredentials: number = secrets.writes;

      const sink: FakeSessionSink = new FakeSessionSink();
      const coordinator: ReAuthCoordinator = new ReAuthCoordinator(async (): Promise<LoginResult> => {
        const record: CredentialRecord | undefined = await store.load();
        if (record === undefined) {
          return LoginResult.failure(FailReason.NO_CREDENTIAL, 'none');
        }
        const result: LoginResult = okLoginWith('COLD');
        if (result.session !== undefined) {
          sink.session = result.session;
        }
        return result;
      }, new Logger('data.auth.test'));
      const restorer: SessionRestorer = new SessionRestorer({
        coordinator: coordinator,
        currentSession: sink.current,
        logger: new Logger('data.auth.test')
      });
      const result: SessionRestoreResult = await restorer.restore();
      expect(result.ok()).assertTrue();
      // ADR-0004：恢复会话的过程对秘密存储**零写入**（会话 cookie / CSRF 不落盘）
      expect(secrets.writes).assertEqual(writesAfterCredentials);
      const stored: string = secrets.allValues().join('|');
      expect(stored.indexOf('JSESSIONID')).assertEqual(-1);
      expect(stored.indexOf('TOKEN')).assertEqual(-1);
      expect(stored.indexOf('csrf')).assertEqual(-1);
    });

    it('keepsTheCookieJarAndTheSessionInMemoryOnly', 0, async () => {
      // 会话建立后 jar 里确实有 cookie（不是"没抓到"），但它只活在这个内存对象里
      const jar: CookieJar = new CookieJar();
      jar.absorbCookieHeader('JSESSIONID=INMEMORY-1; SERVERID=node1', 'https://learn.tsinghua.edu.cn/');
      expect(jar.size() > 0).assertTrue();
      expect(jar.cookieHeaderFor('https://learn.tsinghua.edu.cn/f/wlxt/index/course/student/')
        .indexOf('INMEMORY-1') >= 0).assertTrue();
      // 诊断串也不泄漏值（日志会被导出，见 CookieJar.describe）
      expect(jar.describe().indexOf('INMEMORY-1')).assertEqual(-1);
    });
  });
}
