/*
 * 真实课程仓储（data/courses，ticket 12）：把"取数"接到**数据路径的统一入口**
 * `AuthedTaskRunner`（data/auth/SessionRestore）上——先确保有会话（冷启动就是那次纯 HTTP
 * 重登）+ 会话失效时重登且只重试一次 + 失败显式降级。**本文件不自己造重登/重试/降级逻辑**。
 *
 * 与 RealNoticeRepository 的两个差别：
 *   1. 任务返回值用 `ok:courses=N` 而不是 `ok:N`／`[]`：**合法的 0 课程**（用户切到一个
 *      没有选课的学期）不能被 SessionGate 当成原生路径的 `'[]'` 而触发一次无谓的重登；
 *   2. 课程**不落快照**：ticket 12 没有要求，而"计数"必须来自同一次抓取的三个域
 *      （分开落盘再拼会让计数与列表不同步）。冷启动直接抓一次，界面显示加载态。
 *
 * 为什么结果经过 `SnapshotBox`：任务闭包要把结果带出来，而"成员变量 + null 判断"
 * 在 ArkTS 的检查下会被收窄成 `never`（编译期实测：`Property 'semesterId' does not exist
 * on type 'never'`）。用一个只有 `put/take` 的持有者，读侧的类型来自方法返回值，
 * 控制流分析不会把它收窄坏。
 */

import { Logger } from '../../core/log/Logger';
import { AuthedRunResult, SessionTask } from '../auth/SessionRestore';
import { TaskOutcome } from '../auth/ReAuth';
import { Session } from '../remote/Requests';
import { AuthedTaskExecutor } from '../notices/RealNoticeRepository';
import { CourseFetchSource } from './CourseFetchSource';
import { CourseRepository, CourseSnapshot } from './CourseRepository';

/** 抓取结果持有者（任务闭包写入，refresh 读出）。 */
class SnapshotBox {
  private value: CourseSnapshot | null = null;

  put(snapshot: CourseSnapshot): void {
    this.value = snapshot;
  }

  take(): CourseSnapshot | null {
    return this.value;
  }
}

/** 真实课程数据源。 */
export class RealCourseRepository implements CourseRepository {
  private readonly executor: AuthedTaskExecutor;
  private readonly source: CourseFetchSource;
  private readonly logger: Logger;

  constructor(executor: AuthedTaskExecutor, source: CourseFetchSource, logger: Logger) {
    this.executor = executor;
    this.source = source;
    this.logger = logger;
  }

  async refresh(semesterId?: string): Promise<CourseSnapshot> {
    const selected: string = semesterId === undefined ? '' : semesterId;
    const box: SnapshotBox = new SnapshotBox();
    const run: AuthedRunResult = await this.executor.run(
      async (session: Session): Promise<TaskOutcome> => {
        const snapshot: CourseSnapshot = await this.source.fetchWithSession(session, selected);
        box.put(snapshot);
        return {
          status: 200,
          body: 'ok:courses=' + snapshot.courses.length.toString(),
          responseUrl: ''
        };
      });
    if (!run.ok || run.requiresEnrollment) {
      throw new Error('course refresh degraded: requiresEnrollment=true reason=' + run.reason
        + ' reAuth=' + run.reAuthAttempted.toString() + ' diag=' + run.diagnostic);
    }
    const snapshot: CourseSnapshot | null = box.take();
    if (snapshot === null) {
      throw new Error('course refresh produced no snapshot (source returned without a value)');
    }
    this.logger.info('courses refresh done: semester=' + snapshot.semesterId
      + ' courses=' + snapshot.courses.length.toString()
      + ' notices=' + snapshot.notices.length.toString()
      + ' assignments=' + snapshot.assignments.length.toString()
      + ' files=' + snapshot.files.length.toString());
    return snapshot;
  }
}
