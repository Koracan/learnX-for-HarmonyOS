/*
 * Mock 课程数据源（data/mock）。
 *
 * 一次 refresh 返回课程 tab 需要的全部东西（`CourseSnapshot`：课程 + 三域内容 + 学期集合），
 * 与 `RealCourseRepository` 同一契约 —— 界面、store、学期选择页都读同一份字段，**没有 mock 专用分支**。
 *
 * **样例数据只有一套**：切学期时 `semesterId` 跟着变（于是"选中的学期"在界面上可见），
 * 但课程/公告/作业/文件的内容不变。参考实现的 mock store 也只有一套固定内容（`mock.ts` 的
 * `semesters.items` 甚至只有两个学期），所以这里不为了"更像真的"而编造第二套。
 *
 * ## 三个计数是**算出来的**（与真实路径同一份实现）
 *
 * 快照组装好之后，用 `domain/courses/CourseCounts.countsForCourse` 从**同一份**
 * notices / assignments / files 重算每门课的三个计数；真实路径
 * （`data/courses/CourseFetchSource`）用的就是它。这一条是本轮收口：
 * 此前直接用 `MockData.mockCourses()` 里写死的字段，于是 mock 下提交完一条作业，
 * 作业列表说"已提交"、课程卡片仍写"1 未完成作业"。
 *
 * 重算还顺手修掉了样例文本的 off-by-one：大学物理写的是 2 条未完成，
 * 而样例里只有 1 条未提交作业（`mock-xszy-2`）—— 权威值现在是算出来的 **1**。
 *
 * ## 文件体积与「文件」tab 是同一个函数算的
 *
 * mockFiles() 的每条 size 经 `MockFileBlobs.applyBundledSizes` 换成包内样例的真实字节数，
 * 与 `MockFileRepository.refresh()` 调的是**同一个函数**；否则同一个文件在课程详情页
 * 与「文件」tab 上写着两个体积。
 *
 * ## 设备侧的包内 source 从哪来（为什么本类自己取一次）
 *
 * 课程仓储的组装点（`features/courses/repository/CourseRepositoryProvider`）不在本次改动
 * 范围内，所以这里用 `RawfileDownloadPort.hostRawfileBlobSource()` 取一次设备 source；
 * 拿不到（host 单测 / 没有宿主 Context）时为 null ⇒ 体积保留站点给的文本，**不假装算得出来**。
 * 构造函数允许注入 source，于是单测可以完全离线（不碰设备、不碰 rawfile）。
 */

import { Logger } from '../../core/log/Logger';
import { CourseCounts, countsForCourse } from '../../domain/courses/CourseCounts';
import { Assignment, CourseFile, Notice } from '../../domain/model/ContentItem';
import { CourseRecord, CourseRepository, CourseSnapshot } from '../courses/CourseRepository';
import { NoticeRecord } from '../notices/NoticeRepository';
import { networkAttemptCount } from '../remote/NetworkAudit';
import { BundledSizeResult, MockBlobSource, applyBundledSizes } from './MockFileBlobs';
import {
  MOCK_CURRENT_SEMESTER, MOCK_SEMESTERS, formatDateTime, mockAssignments, mockCourses, mockFiles,
  mockNotices
} from './MockData';
import { hostRawfileBlobSource } from './RawfileDownloadPort';

const logger: Logger = new Logger('data.mock.courses');

export class MockCourseRepository implements CourseRepository {
  /**
   * 读包内样例字节的端口（只为算文件体积）；null = 用设备侧默认值。
   *
   * 默认参数而不是必填：`CourseRepositoryProvider` 的 mock 分支是 `new MockCourseRepository()`
   * （那个文件不在本次改动范围内），而 host 单测也会注入一个内存替身。
   */
  private readonly blobs: MockBlobSource | null;

  constructor(blobs: MockBlobSource | null = null) {
    this.blobs = blobs;
  }

  async refresh(semesterId?: string): Promise<CourseSnapshot> {
    const requested: string = semesterId === undefined ? '' : semesterId;
    const effective: string = requested.length > 0 ? requested : MOCK_CURRENT_SEMESTER;
    const now: number = Date.now();
    const source: MockBlobSource | null =
      this.blobs !== null ? this.blobs : hostRawfileBlobSource();
    // 三域内容只生成一次：下面的计数与快照里的数组必须是**同一份数据**（各调一次样例函数
    // 会得到两份内容相同但引用不同的数组，计数与列表就可能各说各话）。
    const notices: NoticeRecord[] = mockNotices();
    const assignments: Assignment[] = mockAssignments();
    const sized: BundledSizeResult = applyBundledSizes(mockFiles(), source);
    const files: CourseFile[] = sized.files;
    const snapshot: CourseSnapshot = {
      courses: deriveCounts(mockCourses(), noticesForCounts(notices), assignments, files, now),
      notices: notices,
      assignments: assignments,
      files: files,
      semesterId: effective,
      siteCurrentSemesterId: MOCK_CURRENT_SEMESTER,
      semesterSource: requested.length > 0 ? 'mock-selection' : 'mock-site-current',
      semesters: MOCK_SEMESTERS,
      semestersAvailable: true,
      fetchedAtMillis: now
    };
    logger.info('mock course snapshot served: semester=' + effective
      + ' requested=' + (requested.length === 0 ? 'none' : requested)
      + ' source=' + snapshot.semesterSource
      + ' courses=' + snapshot.courses.length.toString()
      + ' notices=' + snapshot.notices.length.toString()
      + ' assignments=' + snapshot.assignments.length.toString()
      + ' files=' + snapshot.files.length.toString()
      + ' countsDerived=' + snapshot.courses.length.toString()
      + ' fileSizesFromBundledAssets=' + sized.resolvedCount.toString()
      + ' rawfileSource=' + (source === null ? 'none' : 'available')
      + ' networkAttempts=' + networkAttemptCount().toString());
    return snapshot;
  }
}

/**
 * NoticeRecord → domain `Notice` 的显式适配器（**只服务计数**）。
 *
 * 为什么需要它：ArkTS 不做结构类型（arkts-no-structural-typing），而 `countsForCourse`
 * 吃的是 domain 的 `Notice[]` —— 真实路径在"抓取结果转成 NoticeRecord 之前"算计数，
 * 手里两个类型都有；mock 的快照里只有 NoticeRecord。这里按域类型逐字段还原，
 * `publishTime` 用 MockData.formatDateTime 从**同一个**毫秒时间戳生成
 * （与 `NoticeRecord.publishTimeMillis` 是同一时刻，不是另编一个时间）。
 *
 * 导出是给单测用的：测试断言"快照里的计数 == countsForCourse(同一个适配器的输出)"，
 * 用同一个函数才不会把适配器本身写错当成"实现对了"。
 */
export function noticesForCounts(records: NoticeRecord[]): Notice[] {
  const out: Notice[] = [];
  for (let i = 0; i < records.length; i++) {
    const record: NoticeRecord = records[i];
    const notice: Notice = {
      id: record.id,
      title: record.title,
      publisher: record.publisher,
      publishTime: formatDateTime(record.publishTimeMillis),
      markedImportant: record.markedImportant,
      hasRead: record.hasRead,
      url: record.url,
      content: record.content,
      courseId: record.courseId,
      courseName: record.courseName,
      courseTeacherName: record.courseTeacherName
    };
    if (record.attachment !== undefined) {
      notice.attachment = record.attachment;
    }
    out.push(notice);
  }
  return out;
}

/**
 * 三门课的计数全部由 `countsForCourse` 算出来（覆盖样例里写死的字段）。
 *
 * 逐字段复制而不是就地改 `courses[i]`：`mockCourses()` 每次返回新对象，就地改今天没副作用，
 * 但"样例是只读的"这条契约应当在代码里看得见。
 */
function deriveCounts(courses: CourseRecord[], notices: Notice[],
  assignments: Assignment[], files: CourseFile[], nowMillis: number): CourseRecord[] {
  const out: CourseRecord[] = [];
  for (let i = 0; i < courses.length; i++) {
    const course: CourseRecord = courses[i];
    const counts: CourseCounts =
      countsForCourse(course.id, notices, assignments, files, nowMillis);
    out.push(copyWithCounts(course, counts));
  }
  return out;
}

/** 只换三个计数的副本（显式列出每个字段：域类型加字段时在这里编译失败，而不是静默丢字段）。 */
function copyWithCounts(course: CourseRecord, counts: CourseCounts): CourseRecord {
  return {
    id: course.id,
    name: course.name,
    chineseName: course.chineseName,
    englishName: course.englishName,
    teacherName: course.teacherName,
    teacherNumber: course.teacherNumber,
    courseNumber: course.courseNumber,
    courseIndex: course.courseIndex,
    unreadNoticeCount: counts.unreadNoticeCount,
    unfinishedAssignmentCount: counts.unfinishedAssignmentCount,
    unreadFileCount: counts.unreadFileCount
  };
}
