/*
 * 课程三类计数的单测。
 *
 * 逐条对齐参考实现 `data/selectors/filteredData.ts:24-49` 的 `selectCoursesWithCounts`：
 * 未读公告、**未提交且未截止**的作业、`isNew` 的文件；三门课之间互不串味。
 * 时间用远未来 / 远过去两个常量，测试不依赖"今天几号"。
 */

import { describe, it, expect } from '@ohos/hypium';
import { Assignment, CourseFile, Notice } from '../main/ets/domain/model/ContentItem';
import {
  countNewFilesForCourse, countUnfinishedAssignmentsForCourse, countUnreadNoticesForCourse,
  countsForCourse, isUnfinishedAssignment
} from '../main/ets/domain/courses/CourseCounts';
import { parseTimestamp } from '../main/ets/domain/parse/Text';

const FAR_FUTURE: string = '2999-01-01 00:00';
const FAR_PAST: string = '2000-01-01 00:00';

function noticeOf(id: string, courseId: string, hasRead: boolean): Notice {
  return {
    id: id, title: 't', content: '', publisher: 'p', publishTime: '2026-09-10 13:07',
    markedImportant: false, hasRead: hasRead, url: '', courseId: courseId,
    courseName: 'c', courseTeacherName: 'x'
  };
}

function assignmentOf(id: string, courseId: string, deadline: string, submitted: boolean): Assignment {
  return {
    id: id, baseId: 'b-' + id, title: 't', url: '', deadline: deadline,
    isLateSubmission: false, completionType: '', submissionType: '', submitUrl: '',
    gradeContent: '', submittedContent: '', answerContent: '', description: '',
    submitted: submitted, graded: false, courseId: courseId, courseName: 'c',
    courseTeacherName: 'x'
  };
}

function fileOf(id: string, courseId: string, isNew: boolean): CourseFile {
  return {
    id: id, fileId: 'f-' + id, title: 't', description: '', size: '1KB',
    uploadTime: '2026-09-10 13:07', fileType: 'pdf', isNew: isNew, downloadUrl: '',
    courseId: courseId, courseName: 'c', courseTeacherName: 'x'
  };
}

export default function courseCountsTest() {
  describe('domain.CourseCounts', () => {
    it('counts only the unread notices of that course', 0, () => {
      const notices: Notice[] = [
        noticeOf('n1', 'c1', false),
        noticeOf('n2', 'c1', true),
        noticeOf('n3', 'c1', false),
        noticeOf('n4', 'c2', false)
      ];
      expect(countUnreadNoticesForCourse(notices, 'c1')).assertEqual(2);
      expect(countUnreadNoticesForCourse(notices, 'c2')).assertEqual(1);
      expect(countUnreadNoticesForCourse(notices, 'c3')).assertEqual(0);
    });

    it('treats an assignment as unfinished only when unsubmitted and not past its deadline', 0, () => {
      const now: number = Date.now();
      const assignments: Assignment[] = [
        assignmentOf('a1', 'c1', FAR_FUTURE, false),  // 未交、未截止 → 计入
        assignmentOf('a2', 'c1', FAR_PAST, false),    // 未交、已截止 → 不计入（参考实现口径）
        assignmentOf('a3', 'c1', FAR_FUTURE, true),   // 已交 → 不计入
        assignmentOf('a4', 'c1', '', false),          // 脏值（dayjs 无效日期）→ 不计入
        assignmentOf('a5', 'c2', FAR_FUTURE, false)   // 别的课 → 不计入
      ];
      expect(isUnfinishedAssignment(assignments[0], now)).assertTrue();
      expect(isUnfinishedAssignment(assignments[1], now)).assertFalse();
      expect(isUnfinishedAssignment(assignments[2], now)).assertFalse();
      expect(isUnfinishedAssignment(assignments[3], now)).assertFalse();
      expect(countUnfinishedAssignmentsForCourse(assignments, 'c1', now)).assertEqual(1);
      expect(countUnfinishedAssignmentsForCourse(assignments, 'c2', now)).assertEqual(1);
    });

    it('counts new files only', 0, () => {
      const files: CourseFile[] = [
        fileOf('f1', 'c1', true),
        fileOf('f2', 'c1', false),
        fileOf('f3', 'c2', true)
      ];
      expect(countNewFilesForCourse(files, 'c1')).assertEqual(1);
      expect(countNewFilesForCourse(files, 'c2')).assertEqual(1);
      expect(countNewFilesForCourse(files, 'c9')).assertEqual(0);
    });

    /*
     * 真实数据缺陷的回归（2026-09-12 模拟器 Pura 90，2025-2026 春季学期）：
     * 站点的作业 jzsj（截止时间）**不保证是字符串**。parseTimestamp 直接
     * 对入参调用 raw.trim()，一个数字就让整条课程/作业链路抛 "undefined is not callable"。
     * 修法按 dayjs 对齐（数字 ⇒ epoch 毫秒；其它非字符串 ⇒ 不可解析）。
     * 证据：.scratch/courses/evidence/P1-hilog-probe.txt（含调用栈）。
     */
    it('accepts a numeric site timestamp like dayjs and never crashes on junk', 0, () => {
      expect(parseTimestamp(32472115200000)).assertEqual(32472115200000);
      expect(parseTimestamp(0)).assertEqual(0);
      expect(Number.isNaN(parseTimestamp('nope'))).assertTrue();
      expect(Number.isNaN(parseTimestamp(''))).assertTrue();
    });

    it('combines the three counts per course', 0, () => {
      const now: number = Date.now();
      const notices: Notice[] = [noticeOf('n1', 'c1', false), noticeOf('n2', 'c1', true)];
      const assignments: Assignment[] = [
        assignmentOf('a1', 'c1', FAR_FUTURE, false),
        assignmentOf('a2', 'c1', FAR_FUTURE, true)
      ];
      const files: CourseFile[] = [fileOf('f1', 'c1', true), fileOf('f2', 'c1', true)];
      const counts = countsForCourse('c1', notices, assignments, files, now);
      expect(counts.unreadNoticeCount).assertEqual(1);
      expect(counts.unfinishedAssignmentCount).assertEqual(1);
      expect(counts.unreadFileCount).assertEqual(2);
      const other = countsForCourse('c2', notices, assignments, files, now);
      expect(other.unreadNoticeCount).assertEqual(0);
      expect(other.unfinishedAssignmentCount).assertEqual(0);
      expect(other.unreadFileCount).assertEqual(0);
    });
  });
}