/*
 * 课程数据源契约（data/courses，ticket 12）——features 只依赖本接口，不依赖任何具体实现。
 *
 * 一次 refresh 就返回**课程 tab 需要的全部东西**（对齐参考实现的做法：课程页与课程详情页
 * 都从同一份全局 state 里取数）：
 *   - `courses`：课程卡片（名称/教师 + 三类计数）；
 *   - `notices` / `assignments` / `files`：课程详情三个标签页的内容（按 `courseId` 过滤即得）；
 *   - `semesterId` / `semesters`：学期选择页要的"实际生效值"与可选集合。
 *
 * 三个"绝不"（与 RealNoticeRepository 同一口径）：
 *   - 取数失败一律 reject，**绝不用空列表兜底**；
 *   - `AuthedRunResult.requiresEnrollment` 为真时抛错并带 `requiresEnrollment=true`；
 *   - 站点当前学期返回 **0 门课 = 失败信号**（用户提供的事实：本账号本学期课程非空），
 *     只有"显式切到别的学期"时空结果才被当作合法空态。
 */

import { CourseCounts } from '../../domain/courses/CourseCounts';
import { Assignment, CourseFile } from '../../domain/model/ContentItem';
import { NoticeRecord } from '../notices/NoticeRepository';

/** 课程卡片上的一门课（`CourseEntry` 的字段 + 三类计数）。 */
export interface CourseRecord extends CourseCounts {
  id: string;
  /** 卡片显示名（参考实现口径：`decodeHTML(zywkcm)`，空则退回 `kcm`）。 */
  name: string;
  chineseName: string;
  englishName: string;
  teacherName: string;
  teacherNumber: string;
  courseNumber: string;
  courseIndex: number;
}

/** 一次成功获取得到的课程全量视图。 */
export interface CourseSnapshot {
  courses: CourseRecord[];
  /** 全部公告（每个标签页按 `courseId` 过滤）。 */
  notices: NoticeRecord[];
  assignments: Assignment[];
  files: CourseFile[];
  /** **实际生效**的学期（覆盖 / 界面选择 / 站点当前，见 CourseFetchSource）。 */
  semesterId: string;
  /** 站点报的当前学期；解析失败时为空串。 */
  siteCurrentSemesterId: string;
  /** 生效来源：`override` / `selection` / `site-current`。 */
  semesterSource: string;
  /** 学期选择页的可选学期（最新在前）；接口不可用时是"当前 + 生效"的退化集合。 */
  semesters: string[];
  /** 学期集合接口是否给出可用结果（false 时界面要说明"列表可能不全"）。 */
  semestersAvailable: boolean;
  /** 抓取时间，epoch 毫秒。 */
  fetchedAtMillis: number;
}

/** 课程数据源。 */
export interface CourseRepository {
  /**
   * 抓取课程 + 三域内容 + 学期集合。
   * @param semesterId 界面选择的学期；空串 = 由覆盖开关 / 站点当前学期决定。
   */
  refresh(semesterId?: string): Promise<CourseSnapshot>;
}
