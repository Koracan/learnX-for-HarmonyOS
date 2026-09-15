/*
 * 列表行 ForEach key 的单测（host 侧 hypium）—— 把 t24 那台设备上的**真缺陷**变成可回归的钉子。
 *
 * ## 缺陷（设备实测，2026-09-15）
 *
 * mock 提交作业后，作业列表说"已提交"、课程卡片仍写"1 未完成作业"；页面头部已经
 * 显示"刚刚更新"（它直读 store 的 fetchedAtMillis），行却停在旧值上。
 * 根因是 `CoursesPage` 的 ForEach key 只有 `semesterId|id|hidden|sel`：
 * 提交只改三个**推导计数**，key 的四个分量一个都没动 ⇒ ArkUI 判定"这一项没变"、
 * **复用旧行、不重建**。真实路径同族（读掉一条公告的未读数、站点侧提交后的未完成数、
 * 刷新后的文件体积）——所以按通用缺陷修，没有 mock 分支。
 *
 * ## 这里为什么能钉死它
 *
 * ArkUI 的复用行为本身在 host 上测不到（没有 UI 运行时），但**key 的等价类是纯函数**：
 * 只要"两条只有计数不同的记录必须给出不同的 key"成立，那次复用就不可能发生。
 * 本文件对每一类行都做两件事：
 *   (a) **同输入 ⇒ 同 key**（等价类成立，不会每次刷新都重建行）；
 *   (b) **只有某个渲染状态不同 ⇒ 不同 key**（逐个状态分量单测，回归时就红）。
 * 课程那一条还额外与**上一版的旧 key 公式**做对照：旧公式在同样两条记录上是相等的
 * —— 这正是复用的成因；有人把 key 改回旧式，这里立刻红。
 *
 * ## 边界（诚实说明）
 *
 *   1. theme / 文案不进 key（页面级状态驱动）；
 *   2. 时间驱动的文本（"还剩 X 天"）不进 key：它随时间变、与刷新无关；
 *   3. 长自由文本（公告正文 HTML / 描述）不进 key：会让 key 与正文同量级。
 * 2 与 3 是**有意的取舍**，不是遗漏；key 的完整规则写在
 * entry/src/main/ets/features/courses/CourseRowKey.ets 的文件头。
 */

import { describe, it, expect } from '@ohos/hypium';
import { CourseRecord } from '../main/ets/data/courses/CourseRepository';
import { NoticeRecord } from '../main/ets/data/notices/NoticeRepository';
import { Assignment, CourseFile, ExcellentHomework } from '../main/ets/domain/model/ContentItem';
import {
  courseAssignmentRowKey, courseFileRowKey, courseNoticeRowKey, courseRowKey
} from '../main/ets/features/courses/CourseRowKey';
import { noticeListRowKey } from '../main/ets/features/notices/NoticeRowKey';
import { fileListRowKey } from '../main/ets/features/files/FileRowKey';
import { assignmentListRowKey } from '../main/ets/features/assignments/AssignmentRowKey';

/* ------------------------------------------------------------------ *
 * 夹具
 * ------------------------------------------------------------------ */

function makeCourse(id: string): CourseRecord {
  return {
    id: id, name: '课-' + id, chineseName: '课-' + id, englishName: 'c-' + id,
    teacherName: 't', teacherNumber: '', courseNumber: '', courseIndex: 0,
    unreadNoticeCount: 0, unfinishedAssignmentCount: 0, unreadFileCount: 0
  };
}

function makeNotice(id: string): NoticeRecord {
  return {
    id: id, title: 'n-' + id, content: '<p>正文</p>', publisher: 'p',
    courseId: 'c1', courseName: '课-c1', courseTeacherName: 't',
    publishTimeMillis: 1000, hasRead: false, markedImportant: false, url: ''
  };
}

function makeFile(id: string): CourseFile {
  return {
    id: id, fileId: id + '-wj', title: 'f-' + id, description: '', size: '268.31KB',
    uploadTime: '2020-01-01 00:00', fileType: 'pdf', isNew: false, downloadUrl: '',
    courseId: 'c1', courseName: '课-c1', courseTeacherName: 't'
  };
}

function makeAssignment(id: string): Assignment {
  return {
    id: id, baseId: id + '-base', title: 'a-' + id, url: '', deadline: '2030-01-01 00:00',
    isLateSubmission: false, completionType: '1', submissionType: '2', submitUrl: '',
    courseId: 'c1', courseName: '课-c1', courseTeacherName: 't',
    description: '', submittedContent: '', answerContent: '', gradeContent: '',
    submitted: false, graded: false
  };
}

function makeExcellent(id: string): ExcellentHomework {
  return {
    id: id, baseId: id + '-base', title: 'x-' + id, authorId: 'u1', authorName: '同学',
    anonymous: false
  };
}

/**
 * 上一版（t24 事故前）的课程行 key 形状 —— 只用于对照。
 *
 * 它漏了整条行渲染出来的计数与课程名；在被提交改写的那两条记录上它**相等**，
 * 于是 ForEach 复用旧行。保留这个函数是为了让"回归"这件事有对照物。
 */
function legacyCourseRowKey(semesterId: string, course: CourseRecord): string {
  return semesterId + '|' + course.id + '|shown|nosel';
}

/* ------------------------------------------------------------------ *
 * 用例
 * ------------------------------------------------------------------ */

export default function listRowKeysTest() {
  describe('features.listRowKeys', () => {
    it('keepsTheCourseRowKeyStableAndMovesItWithEveryRenderedState', 0, () => {
      const base: CourseRecord = makeCourse('c1');
      const key: string = courseRowKey('s1', base, false, false);
      // (a) 同输入 ⇒ 同 key（否则每次刷新都重建整列表）。
      expect(courseRowKey('s1', makeCourse('c1'), false, false)).assertEqual(key);
      // (b) 三个**推导计数**各自变了都必须换 key —— 这就是设备上那次"卡片不更新"的形态。
      const notices: CourseRecord = makeCourse('c1');
      notices.unreadNoticeCount = 1;
      expect(courseRowKey('s1', notices, false, false) === key).assertFalse();
      const unfinished: CourseRecord = makeCourse('c1');
      unfinished.unfinishedAssignmentCount = 1;
      expect(courseRowKey('s1', unfinished, false, false) === key).assertFalse();
      const files: CourseRecord = makeCourse('c1');
      files.unreadFileCount = 1;
      expect(courseRowKey('s1', files, false, false) === key).assertFalse();
      // 其余 key 分量（身份 / 学期 / 渲染出的课程名与教师名 / 屏蔽态 / 高亮态）同样要换 key。
      expect(courseRowKey('s2', base, false, false) === key).assertFalse();
      expect(courseRowKey('s1', makeCourse('c2'), false, false) === key).assertFalse();
      expect(courseRowKey('s1', base, true, false) === key).assertFalse();
      expect(courseRowKey('s1', base, false, true) === key).assertFalse();
      const renamed: CourseRecord = makeCourse('c1');
      renamed.name = '改过的课名';
      expect(courseRowKey('s1', renamed, false, false) === key).assertFalse();
      const retaught: CourseRecord = makeCourse('c1');
      retaught.teacherName = '换了个老师';
      expect(courseRowKey('s1', retaught, false, false) === key).assertFalse();
    });

    it('showsTheCoursesRegressionAgainstTheLegacyKey', 0, () => {
      // 对照：**只有未完成作业数不同**的两条记录。
      const before: CourseRecord = makeCourse('c1');
      const after: CourseRecord = makeCourse('c1');
      after.unfinishedAssignmentCount = 1;
      // 旧 key 在两者上相等 ⇒ ForEach 认为"没变"⇒ 复用旧行（设备上就是这个现象）。
      expect(legacyCourseRowKey('s1', before)).assertEqual(legacyCourseRowKey('s1', after));
      // 新 key 必须不同（有人改回旧式，这一行就红）。
      expect(courseRowKey('s1', before, false, false))
        .assertEqual(courseRowKey('s1', makeCourse('c1'), false, false));
      expect(courseRowKey('s1', before, false, false) === courseRowKey('s1', after, false, false))
        .assertFalse();
    });

    it('tracksTheCourseDetailNoticeMarks', 0, () => {
      const base: NoticeRecord = makeNotice('n1');
      const key: string = courseNoticeRowKey(base);
      expect(courseNoticeRowKey(makeNotice('n1'))).assertEqual(key);
      // 读完一条公告：未读圆点必须消失 ⇒ key 换。
      const read: NoticeRecord = makeNotice('n1');
      read.hasRead = true;
      expect(courseNoticeRowKey(read) === key).assertFalse();
      // 站点把公告标成重要 / 加/去附件 ⇒ key 换（上一版 id-only 的 key 三种情况全都相等）。
      const important: NoticeRecord = makeNotice('n1');
      important.markedImportant = true;
      expect(courseNoticeRowKey(important) === key).assertFalse();
      const attached: NoticeRecord = makeNotice('n1');
      attached.attachment = { downloadUrl: '', name: 'a.pdf' };
      expect(courseNoticeRowKey(attached) === key).assertFalse();
      // 旧 key 的对照：这三种变化它一个都看不出来。
      expect('notice|' + read.id).assertEqual('notice|' + base.id);
      expect('notice|' + important.id).assertEqual('notice|' + base.id);
      expect('notice|' + attached.id).assertEqual('notice|' + base.id);
    });

    it('tracksTheCourseDetailAssignmentSubmissionState', 0, () => {
      const base: Assignment = makeAssignment('a1');
      const key: string = courseAssignmentRowKey(base);
      expect(courseAssignmentRowKey(makeAssignment('a1'))).assertEqual(key);
      // 提交（submitted false → true）必须换 key：卡片右边那枚对勾就是它。
      const submitted: Assignment = makeAssignment('a1');
      submitted.submitted = true;
      expect(courseAssignmentRowKey(submitted) === key).assertFalse();
      // 截止时间变了也要换（它是这一行渲染出来的）。
      const moved: Assignment = makeAssignment('a1');
      moved.deadline = '2031-01-01 00:00';
      expect(courseAssignmentRowKey(moved) === key).assertFalse();
      // 旧 key 的对照。
      expect('assignment|' + submitted.id).assertEqual('assignment|' + base.id);
    });

    it('tracksTheCourseDetailFileSizeAndNewMark', 0, () => {
      const base: CourseFile = makeFile('f1');
      const key: string = courseFileRowKey(base);
      expect(courseFileRowKey(makeFile('f1'))).assertEqual(key);
      // 体积被刷新（mock 侧换成包内真实字节数就是这个形态）⇒ key 换。
      const resized: CourseFile = makeFile('f1');
      resized.size = '3.71KB';
      expect(courseFileRowKey(resized) === key).assertFalse();
      // "新文件"蓝点消失 ⇒ key 换。
      const old: CourseFile = makeFile('f1');
      old.isNew = true;
      expect(courseFileRowKey(old) === key).assertFalse();
      // 旧 key 的对照。
      expect('file|' + resized.id).assertEqual('file|' + base.id);
    });

    it('tracksTheNoticeListMarksAndFlags', 0, () => {
      const base: NoticeRecord = makeNotice('n1');
      const key: string = noticeListRowKey(base, false, false, false);
      expect(noticeListRowKey(makeNotice('n1'), false, false, false)).assertEqual(key);
      const read: NoticeRecord = makeNotice('n1');
      read.hasRead = true;
      expect(noticeListRowKey(read, false, false, false) === key).assertFalse();
      const important: NoticeRecord = makeNotice('n1');
      important.markedImportant = true;
      expect(noticeListRowKey(important, false, false, false) === key).assertFalse();
      const attached: NoticeRecord = makeNotice('n1');
      attached.attachment = { downloadUrl: '', name: 'a.pdf' };
      expect(noticeListRowKey(attached, false, false, false) === key).assertFalse();
      // 交互态三格。
      expect(noticeListRowKey(base, true, false, false) === key).assertFalse();
      expect(noticeListRowKey(base, false, true, false) === key).assertFalse();
      expect(noticeListRowKey(base, false, false, true) === key).assertFalse();
    });

    it('tracksTheFileListIsNewSizeAndFlags', 0, () => {
      const base: CourseFile = makeFile('f1');
      const key: string = fileListRowKey(base, false, false, false);
      expect(fileListRowKey(makeFile('f1'), false, false, false)).assertEqual(key);
      const fresh: CourseFile = makeFile('f1');
      fresh.isNew = true;
      expect(fileListRowKey(fresh, false, false, false) === key).assertFalse();
      const resized: CourseFile = makeFile('f1');
      resized.size = '1.00MB';
      expect(fileListRowKey(resized, false, false, false) === key).assertFalse();
      const retyped: CourseFile = makeFile('f1');
      retyped.fileType = 'pptx';
      expect(fileListRowKey(retyped, false, false, false) === key).assertFalse();
      const later: CourseFile = makeFile('f1');
      later.uploadTime = '2021-01-01 00:00';
      expect(fileListRowKey(later, false, false, false) === key).assertFalse();
      expect(fileListRowKey(base, true, false, false) === key).assertFalse();
      expect(fileListRowKey(base, false, true, false) === key).assertFalse();
      expect(fileListRowKey(base, false, false, true) === key).assertFalse();
    });

    it('tracksAllFiveAssignmentMarksAndFlags', 0, () => {
      const base: Assignment = makeAssignment('a1');
      const key: string = assignmentListRowKey(base, false, false, false);
      expect(assignmentListRowKey(makeAssignment('a1'), false, false, false)).assertEqual(key);
      // 五枚标记：附件 / 已提交 / 已评分 / 有答案 / 优秀作业。
      const attached: Assignment = makeAssignment('a1');
      attached.attachment = { downloadUrl: '', name: 'a.pdf' };
      expect(assignmentListRowKey(attached, false, false, false) === key).assertFalse();
      const submitted: Assignment = makeAssignment('a1');
      submitted.submitted = true;
      expect(assignmentListRowKey(submitted, false, false, false) === key).assertFalse();
      const graded: Assignment = makeAssignment('a1');
      graded.graded = true;
      expect(assignmentListRowKey(graded, false, false, false) === key).assertFalse();
      const answered: Assignment = makeAssignment('a1');
      answered.answerContent = '<p>参考答案</p>';
      expect(assignmentListRowKey(answered, false, false, false) === key).assertFalse();
      const answeredByAttachment: Assignment = makeAssignment('a1');
      answeredByAttachment.answerAttachment = { downloadUrl: '', name: 'ans.pdf' };
      expect(assignmentListRowKey(answeredByAttachment, false, false, false) === key).assertFalse();
      const excellent: Assignment = makeAssignment('a1');
      excellent.excellentHomeworkList = [makeExcellent('x1')];
      expect(assignmentListRowKey(excellent, false, false, false) === key).assertFalse();
      // 截止时间也是这一行渲染出来的。
      const moved: Assignment = makeAssignment('a1');
      moved.deadline = '2031-01-01 00:00';
      expect(assignmentListRowKey(moved, false, false, false) === key).assertFalse();
      // 交互态三格。
      expect(assignmentListRowKey(base, true, false, false) === key).assertFalse();
      expect(assignmentListRowKey(base, false, true, false) === key).assertFalse();
      expect(assignmentListRowKey(base, false, false, true) === key).assertFalse();
    });
  });
}
