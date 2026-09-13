/*
 * 重登协调与单飞单测（第 5 条与现实约束部分）。
 *
 * 覆盖：两条触发路径的并集与**各自保留的失败语义**、单飞（并发只登录一次）、
 * 只重试一次、失败分类（NOT_LOGGED_IN / UNEXPECTED_STATUS）、降级 Enrollment 判定。
 */

import { describe, it, expect } from '@ohos/hypium';
import { Logger } from '../main/ets/core/log/Logger';
import { FailReason, LoginResult } from '../main/ets/data/auth/AuthTypes';
import {
  ReAuthCoordinator, ReAuthRunResult, SessionGate, SessionLostKind, TaskOutcome, sessionLostKind
} from '../main/ets/data/auth/ReAuth';
import { EMPTY_LIST_BODY, LOGIN_TIMEOUT_BODY } from './fixtures/AuthFixtures';

const OK_BODY: string = '{"result":"success","object":{"aaData":[]}}';

function outcome(status: number, body: string): TaskOutcome {
  return { status: status, body: body, responseUrl: 'https://learn.tsinghua.edu.cn/b/x' };
}

/** 记录执行次数的任务。 */
class ScriptedTask {
  readonly runs: number[] = [];
  private script: string[];
  private cursor: number = 0;

  constructor(script: string[]) {
    this.script = script;
  }

  run = async (): Promise<TaskOutcome> => {
    this.runs.push(this.cursor + 1);
    const body: string = this.cursor < this.script.length ? this.script[this.cursor] : this.script[this.script.length - 1];
    this.cursor++;
    return outcome(200, body);
  };
}

class CountingLogin {
  calls: number = 0;
  private result: LoginResult;
  private delayMs: number;

  constructor(result: LoginResult, delayMs: number) {
    this.result = result;
    this.delayMs = delayMs;
  }

  login = async (): Promise<LoginResult> => {
    this.calls++;
    if (this.delayMs > 0) {
      await new Promise<void>((resolve: () => void): void => {
        setTimeout(resolve, this.delayMs);
      });
    }
    return this.result;
  };
}

function okLogin(): LoginResult {
  return LoginResult.success({ cookie: 'JSESSIONID=x', csrfToken: 'TOKEN' }, 'zh');
}

function gateFor(login: CountingLogin): SessionGate {
  const coordinator: ReAuthCoordinator = new ReAuthCoordinator(login.login, new Logger('data.auth.reauth'));
  return new SessionGate(coordinator, new Logger('data.auth.reauth'));
}

export default function reAuthTest() {
  describe('data.auth.ReAuth', () => {
    it('classifiesBothLossPathsAndLeavesHealthyResponsesAlone', 0, () => {
      expect(sessionLostKind(outcome(200, EMPTY_LIST_BODY))).assertEqual(SessionLostKind.EMPTY_LIST);
      expect(sessionLostKind(outcome(403, 'forbidden'))).assertEqual(SessionLostKind.NO_LOGIN);
      expect(sessionLostKind(outcome(200, LOGIN_TIMEOUT_BODY))).assertEqual(SessionLostKind.NO_LOGIN);
      expect(sessionLostKind({ status: 200, body: LOGIN_TIMEOUT_BODY,
        responseUrl: 'https://learn.tsinghua.edu.cn/f/login_timeout' })).assertEqual(SessionLostKind.NO_LOGIN);
      expect(sessionLostKind(outcome(200, OK_BODY))).assertEqual(SessionLostKind.NONE);
      expect(sessionLostKind(outcome(200, '[] '))).assertEqual(SessionLostKind.NONE);
    });

    it('doesNotReAuthWhenTheFirstAttemptIsHealthy', 0, async () => {
      const login: CountingLogin = new CountingLogin(okLogin(), 0);
      const task: ScriptedTask = new ScriptedTask([OK_BODY, OK_BODY]);
      const result: ReAuthRunResult = await gateFor(login).run(task.run);
      expect(result.ok).assertTrue();
      expect(result.reAuthAttempted).assertFalse();
      expect(login.calls).assertEqual(0);
      expect(task.runs.length).assertEqual(1);
    });

    it('retriesOnceWhenTheResultIsAnEmptyList', 0, async () => {
      const login: CountingLogin = new CountingLogin(okLogin(), 0);
      const task: ScriptedTask = new ScriptedTask([EMPTY_LIST_BODY, OK_BODY]);
      const result: ReAuthRunResult = await gateFor(login).run(task.run);
      expect(result.ok).assertTrue();
      expect(result.reAuthAttempted).assertTrue();
      expect(result.value).assertEqual(OK_BODY);
      expect(result.sessionLostAfterReAuth).assertFalse();
      expect(login.calls).assertEqual(1);
      expect(task.runs.length).assertEqual(2);
    });

    it('keepsTheNativePathSemanticsWhenStillEmptyAfterReAuth', 0, async () => {
      // 原生处理器路径：重登后仍返回 '[]' 也照样返回给调用方（不改判成错误）
      const login: CountingLogin = new CountingLogin(okLogin(), 0);
      const task: ScriptedTask = new ScriptedTask([EMPTY_LIST_BODY, EMPTY_LIST_BODY]);
      const result: ReAuthRunResult = await gateFor(login).run(task.run);
      expect(result.ok).assertTrue();
      expect(result.value).assertEqual(EMPTY_LIST_BODY);
      expect(result.sessionLostAfterReAuth).assertTrue();
      expect(task.runs.length).assertEqual(2);
    });

    it('recoversFromNoLoginAfterReAuth', 0, async () => {
      const login: CountingLogin = new CountingLogin(okLogin(), 0);
      const port: ScriptedTask = new ScriptedTask([LOGIN_TIMEOUT_BODY, OK_BODY]);
      const result: ReAuthRunResult = await gateFor(login).run(port.run);
      expect(result.ok).assertTrue();
      expect(result.value).assertEqual(OK_BODY);
      expect(result.reAuthAttempted).assertTrue();
      expect(login.calls).assertEqual(1);
    });

    it('reportsNotLoggedInWhenNoLoginPersists', 0, async () => {
      const login: CountingLogin = new CountingLogin(okLogin(), 0);
      const task: ScriptedTask = new ScriptedTask([LOGIN_TIMEOUT_BODY, LOGIN_TIMEOUT_BODY]);
      const result: ReAuthRunResult = await gateFor(login).run(task.run);
      expect(result.ok).assertFalse();
      expect(result.reason).assertEqual(FailReason.NOT_LOGGED_IN);
      expect(result.requiresEnrollment()).assertTrue();
      expect(task.runs.length).assertEqual(2);
    });

    it('surfacesTheLoginFailureWhenReAuthItselfFails', 0, async () => {
      const failure: LoginResult = LoginResult.failure(FailReason.ERROR_ROAMING, 'roam status=500');
      const login: CountingLogin = new CountingLogin(failure, 0);
      const task: ScriptedTask = new ScriptedTask([LOGIN_TIMEOUT_BODY, OK_BODY]);
      const result: ReAuthRunResult = await gateFor(login).run(task.run);
      expect(result.ok).assertFalse();
      expect(result.reason).assertEqual(FailReason.ERROR_ROAMING);
      expect(result.requiresEnrollment()).assertTrue();
      // 登录失败就不该再重试任务
      expect(task.runs.length).assertEqual(1);
    });

    it('singleFlightsConcurrentReAuths', 0, async () => {
      const login: CountingLogin = new CountingLogin(okLogin(), 30);
      const gate: SessionGate = gateFor(login);
      const tasks: Promise<ReAuthRunResult>[] = [];
      for (let i = 0; i < 5; i++) {
        const task: ScriptedTask = new ScriptedTask([EMPTY_LIST_BODY, OK_BODY]);
        tasks.push(gate.run(task.run));
      }
      const results: ReAuthRunResult[] = await Promise.all(tasks);
      for (let i = 0; i < results.length; i++) {
        expect(results[i].ok).assertTrue();
        expect(results[i].reAuthAttempted).assertTrue();
      }
      // 并发 N 个请求只触发一次登录（照 source.ts:111-121 的单飞）
      expect(login.calls).assertEqual(1);
    });

    it('classifiesUnexpectedStatusAfterNoLoginReAuth', 0, async () => {
      const login: CountingLogin = new CountingLogin(okLogin(), 0);
      const task: ScriptedTask = new ScriptedTask([LOGIN_TIMEOUT_BODY, LOGIN_TIMEOUT_BODY]);
      // 重登后状态码非 200 且不是 noLogin：用 500 + 普通体
      const scripted: TaskOutcome[] = [outcome(200, LOGIN_TIMEOUT_BODY), outcome(500, 'server error')];
      let cursor: number = 0;
      const result: ReAuthRunResult = await gateFor(login).run(async (): Promise<TaskOutcome> => {
        const item: TaskOutcome = scripted[cursor < scripted.length ? cursor : scripted.length - 1];
        cursor++;
        return item;
      });
      expect(result.ok).assertFalse();
      expect(result.reason).assertEqual(FailReason.UNEXPECTED_STATUS);
      expect(result.requiresEnrollment()).assertTrue();
    });
  });
}
