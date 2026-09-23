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

/** 会话失效的学期错误：三域取数源在"学期解析"失败时抛出的那条（设备实测 bytes=69）。 */
const STALE_SESSION_SEMESTER_ERROR: string =
  'semester resolution failed: no xnxq in current semester response: bytes=69';

/**
 * 会**抛错**的脚本化任务：`script[i] === ''` 表示第 i 次调用抛会话失效错，否则返回 200 + 该体。
 * 对应真实形态：学期是取数的前置条件，取数源在这一步失败时**抛错**而不是返回 TaskOutcome。
 */
class ThrowingTask {
  readonly runs: number[] = [];
  private script: string[];
  private cursor: number = 0;

  constructor(script: string[]) {
    this.script = script;
  }

  run = async (): Promise<TaskOutcome> => {
    const index: number = this.cursor < this.script.length ? this.cursor : this.script.length - 1;
    this.cursor++;
    this.runs.push(index + 1);
    const body: string = this.script[index];
    if (body.length === 0) {
      throw new Error(STALE_SESSION_SEMESTER_ERROR);
    }
    return outcome(200, body);
  };
}

/** 抛一个**非**会话原因的错（站点改版 / 账号事实这类信号）。 */
class OtherThrowingTask {
  run = async (): Promise<TaskOutcome> => {
    throw new Error('course list is EMPTY for the site current semester 2026-2027-1');
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

    it('recoversWhenTheTaskThrowsTheStaleSessionSemesterError', 0, async () => {
      // 设备现象：驻留后台后刷新，学期接口回 200 但不含 xnxq ⇒ 取数源**抛错**。
      // 抛错必须与"返回 '[]' / noLogin"一样触发重登 + 只重试一次（否则界面只看到原始错误串）。
      const login: CountingLogin = new CountingLogin(okLogin(), 0);
      const task: ThrowingTask = new ThrowingTask(['', OK_BODY]);
      const result: ReAuthRunResult = await gateFor(login).run(task.run);
      expect(result.ok).assertTrue();
      expect(result.value).assertEqual(OK_BODY);
      expect(result.reAuthAttempted).assertTrue();
      expect(login.calls).assertEqual(1);
      expect(task.runs.length).assertEqual(2);
    });

    it('degradesWhenTheSemesterErrorPersistsAfterReAuth', 0, async () => {
      const login: CountingLogin = new CountingLogin(okLogin(), 0);
      const task: ThrowingTask = new ThrowingTask(['', '']);
      const result: ReAuthRunResult = await gateFor(login).run(task.run);
      expect(result.ok).assertFalse();
      expect(result.reason).assertEqual(FailReason.NOT_LOGGED_IN);
      expect(result.requiresEnrollment()).assertTrue();
      // 登录本身成功、任务仍抛同样的错 ⇒ 恰好两次尝试，不循环
      expect(login.calls).assertEqual(1);
      expect(task.runs.length).assertEqual(2);
    });

    it('doesNotTreatOtherThrowsAsSessionLoss', 0, async () => {
      const login: CountingLogin = new CountingLogin(okLogin(), 0);
      let message: string = '';
      try {
        await gateFor(login).run(new OtherThrowingTask().run);
      } catch (error) {
        message = (error as Error).message;
      }
      expect(message.includes('course list is EMPTY')).assertTrue();
      // 不是会话原因的抛错不许触发登录（否则每次站点改版都会白跑一次登录）
      expect(login.calls).assertEqual(0);
    });
  });
}
