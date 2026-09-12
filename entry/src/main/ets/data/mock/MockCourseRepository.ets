/*
 * Mock 课程数据源（data/mock，ticket 17）。
 *
 * 一次 refresh 返回课程 tab 需要的全部东西（`CourseSnapshot`：课程 + 三域内容 + 学期集合），
 * 与 `RealCourseRepository` 同一契约 —— 界面、store、学期选择页都读同一份字段，**没有 mock 专用分支**。
 *
 * **样例数据只有一套**：切学期时 `semesterId` 跟着变（于是"选中的学期"在界面上可见），
 * 但课程/公告/作业/文件的内容不变。参考实现的 mock store 也只有一套固定内容（`mock.ts` 的
 * `semesters.items` 甚至只有两个学期），所以这里不为了"更像真的"而编造第二套。
 */

import { Logger } from '../../core/log/Logger';
import { networkAttemptCount } from '../remote/NetworkAudit';
import { CourseRepository, CourseSnapshot } from '../courses/CourseRepository';
import {
  MOCK_CURRENT_SEMESTER, MOCK_SEMESTERS, mockAssignments, mockCourses, mockFiles, mockNotices
} from './MockData';

const logger: Logger = new Logger('data.mock.courses');

export class MockCourseRepository implements CourseRepository {
  async refresh(semesterId?: string): Promise<CourseSnapshot> {
    const requested: string = semesterId === undefined ? '' : semesterId;
    const effective: string = requested.length > 0 ? requested : MOCK_CURRENT_SEMESTER;
    const snapshot: CourseSnapshot = {
      courses: mockCourses(),
      notices: mockNotices(),
      assignments: mockAssignments(),
      files: mockFiles(),
      semesterId: effective,
      siteCurrentSemesterId: MOCK_CURRENT_SEMESTER,
      semesterSource: requested.length > 0 ? 'mock-selection' : 'mock-site-current',
      semesters: MOCK_SEMESTERS,
      semestersAvailable: true,
      fetchedAtMillis: Date.now()
    };
    logger.info('mock course snapshot served: semester=' + effective
      + ' requested=' + (requested.length === 0 ? 'none' : requested)
      + ' source=' + snapshot.semesterSource
      + ' courses=' + snapshot.courses.length.toString()
      + ' notices=' + snapshot.notices.length.toString()
      + ' assignments=' + snapshot.assignments.length.toString()
      + ' files=' + snapshot.files.length.toString()
      + ' networkAttempts=' + networkAttemptCount().toString());
    return snapshot;
  }
}
