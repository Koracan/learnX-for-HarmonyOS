/*
 * 课程数据源的组装点（composition root，ticket 12）。
 *
 * 界面只依赖 `CourseRepository` 接口，且只从这里拿实现。数据路径**只经过**
 * `AuthedTaskRunner`（data/auth/SessionRestore：先确保有会话 + 会话失效时重登且只重试一次
 * + 失败显式降级）——**这里不重新实现重登/重试/降级**。
 *
 * 为什么没有 Context / 快照：课程不落盘（ticket 12 未要求，且三类计数必须与列表来自
 * 同一次抓取），所以这里不需要 `common.Context`，也就没有"拿不到 Context 就失败"的分支。
 */

import { Logger } from '../../../core/log/Logger';
import { decodeBase64Text } from '../../../core/codec/TextCodec';
import { authServices } from '../../auth/AuthServices';
import { AuthedRunResult, AuthedTaskRunner, SessionTask } from '../../../data/auth/SessionRestore';
import { HttpFetchPort } from '../../../data/remote/HttpFetchPort';
import { AuthedTaskExecutor } from '../../../data/notices/RealNoticeRepository';
import {
  COURSE_LIST_LOG_DOMAIN, HttpCourseListSource
} from '../../../data/courses/CourseListFetcher';
import { HttpSemesterSource } from '../../../data/courses/SemesterFetcher';
import { HttpCourseFetchSource } from '../../../data/courses/CourseFetchSource';
import { CourseRepository } from '../../../data/courses/CourseRepository';
import { RealCourseRepository } from '../../../data/courses/RealCourseRepository';
import { MockCourseRepository } from '../../../data/mock/MockCourseRepository';
import { isMockMode } from '../../mock/MockMode';

const logger: Logger = new Logger('features.courses.provider');

/** 当前生效的课程数据源。 */
export function createCourseRepository(): CourseRepository {
  // Mock 模式（ticket 17）：样例数据，**不发任何请求**。
  if (isMockMode()) {
    logger.info('course repository wired: source=mock (guest mode, zero network)');
    return new MockCourseRepository();
  }
  const port: HttpFetchPort = new HttpFetchPort();
  const semesters: HttpSemesterSource =
    new HttpSemesterSource(new Logger(COURSE_LIST_LOG_DOMAIN), port);
  const courses: HttpCourseListSource =
    new HttpCourseListSource(new Logger(COURSE_LIST_LOG_DOMAIN), port, semesters);
  const source: HttpCourseFetchSource = new HttpCourseFetchSource(port, semesters, courses,
    decodeBase64Text, new Logger('data.courses.source'));
  const executor: AuthedTaskExecutor = new RunnerTaskExecutor(authServices.runner);
  logger.info('course repository wired: source=real (semesters + course list + three domains)');
  return new RealCourseRepository(executor, source, new Logger('data.courses.repository'));
}

/**
 * 把 `AuthedTaskRunner` 显式适配成 `AuthedTaskExecutor`。
 *
 * 为什么不直接赋值：ArkTS 不做结构类型（arkts-no-structural-typing），两个形状相同的接口
 * 也不能互相赋值（ticket 09 实测）。适配器只有一行转发，并让"数据路径只经过
 * AuthedTaskRunner"这件事在类型上可见。
 */
class RunnerTaskExecutor implements AuthedTaskExecutor {
  private readonly runner: AuthedTaskRunner;

  constructor(runner: AuthedTaskRunner) {
    this.runner = runner;
  }

  run(task: SessionTask): Promise<AuthedRunResult> {
    return this.runner.run(task);
  }
}
