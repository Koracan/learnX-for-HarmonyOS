/*
 * Mock 模式的**样例数据**（data/mock）。
 *
 * ## 参考实现出处
 *
 * 参考实现是 `src/data/mock.ts`（723 行，整棵 redux state 的硬编码快照），由
 * `data/actions/root.ts` 的 `setMockStore()` 整体替换 store；登录页在
 * `username === DUMMY_USERNAME && password === DUMMY_PASSWORD` 时 dispatch 它
 * （`screens/Login.tsx:43-46`），于是**一行请求都不发**。
 *
 * ## 本工程的做法（有意偏离）
 *
 * 本工程没有 redux，也没有"整棵 state"可以被替换：数据源是**四个注入式仓储**
 * （NoticeRepository / CourseRepository / FileRepository / 提交出口）。所以 Mock 模式
 * 落在**仓储这一层**：四个 tab 的仓储 provider（features/<tab>/repository/<X>Provider）在 mock 模式下返回
 * `data/mock/Mock*Repository`，界面与 store 一行都不用改。
 *
 * 样例数据**不逐字复制**参考实现那 723 行（那是另一套字段名的 RN state 快照），
 * 但**三个内容域 + 课程都要有可浏览的样例**，所以这里按本工程的领域类型
 * （`domain/model/ContentItem` 与 `data/notices/NoticeRepository.NoticeRecord`）如实写一份。
 *
 * ## 数据是"活的"
 *
 * 作业的截止时间与公告的发布时间都按**当前时间**算出来（`Date.now()` 偏移），
 * 这样"未到期 / 已截止"两种状态在任何时候看都成立，不会随着时间推移退化成
 * "全部已截止"（参考实现的固定时间戳就没有这个性质）。
 *
 * ## 作业上的「提交台账」覆盖层
 *
 * `mockAssignments()` 返回的**不是**一份纯静态样例：每次调用都会套用
 * `data/mock/MockSubmissionJournal` 里记着的提交（键是 `studentHomeworkId`），
 * 把被提交过的作业翻成 `submitted: true` + `submitTime` + `submittedContent`
 * （有附件时还有 `submittedAttachment`）。**样例数据本身一字未改**，覆盖层只在有提交记录时生效。
 * 台账是内存态（进程重启即清空），所以重启后作业回到下面的初始态；
 * 为什么要有它、为什么是内存态：见 `MockSubmissionJournal.ets` 的文件头。
 */

import { Assignment, Attachment, CourseFile } from '../../domain/model/ContentItem';
import { NoticeRecord } from '../notices/NoticeRepository';
import { CourseRecord } from '../courses/CourseRepository';
import { MockSubmissionEntry, submissionFor } from './MockSubmissionJournal';

/** Mock 用户的显示名 / 院系（参考实现 `mock.ts:21-24` 的 `user` 段：测试学生 / 电子系）。 */
export const MOCK_USER_NAME: string = '测试学生';
export const MOCK_USER_DEPARTMENT: string = '电子系';

/** 样例学期（最新在前，与站点排序口径一致）。 */
export const MOCK_SEMESTERS: string[] = ['2026-2027-1', '2025-2026-2', '2025-2026-1'];

/** 样例数据的"当前学期"。 */
export const MOCK_CURRENT_SEMESTER: string = '2026-2027-1';

const HOUR_MS: number = 3600 * 1000;
const DAY_MS: number = 24 * HOUR_MS;

/** `YYYY-MM-DD HH:mm`（站点与 `domain/parse/Text.parseTimestamp` 认的形状）。 */
function formatDateTime(millis: number): string {
  const d: Date = new Date(millis);
  const pad = (value: number): string => value < 10 ? '0' + value.toString() : value.toString();
  return d.getFullYear().toString() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate())
    + ' ' + pad(d.getHours()) + ':' + pad(d.getMinutes());
}

/** 三门样例课程（计数与下面的三个域一一对得上）。 */
export function mockCourses(): CourseRecord[] {
  return [
    {
      id: '2026-2027-1-100001',
      name: '数据结构',
      chineseName: '数据结构',
      englishName: 'Data Structures',
      teacherName: '李强',
      teacherNumber: '2001000001',
      courseNumber: '30240011',
      courseIndex: 0,
      unreadNoticeCount: 1,
      unfinishedAssignmentCount: 1,
      unreadFileCount: 1
    },
    {
      id: '2026-2027-1-100002',
      name: '大学物理（1）',
      chineseName: '大学物理（1）',
      englishName: 'University Physics (1)',
      teacherName: '王敏',
      teacherNumber: '2001000002',
      courseNumber: '10421014',
      courseIndex: 1,
      unreadNoticeCount: 1,
      unfinishedAssignmentCount: 2,
      unreadFileCount: 1
    },
    {
      id: '2026-2027-1-100003',
      name: '马克思主义基本原理',
      chineseName: '马克思主义基本原理',
      englishName: 'Basic Principles of Marxism',
      teacherName: '赵磊',
      teacherNumber: '2001000003',
      courseNumber: '10610012',
      courseIndex: 2,
      unreadNoticeCount: 0,
      unfinishedAssignmentCount: 0,
      unreadFileCount: 0
    }
  ];
}

/** 四条样例公告（一条重要 / 一条未读 / 一条带附件 / 一条已读）。 */
export function mockNotices(): NoticeRecord[] {
  const now: number = Date.now();
  return [
    {
      id: 'mock-notice-1',
      title: '关于期中考试安排的通知',
      content: '<p>各位同学：</p><p>本学期《数据结构》期中考试定于第 9 周周三晚 19:00-21:00，'
        + '地点另行通知。</p><p>请相互转告。</p>',
      publisher: '李强',
      courseId: '2026-2027-1-100001',
      courseName: '数据结构',
      courseTeacherName: '李强',
      publishTimeMillis: now - 3 * HOUR_MS,
      hasRead: false,
      markedImportant: true,
      url: 'https://learn.tsinghua.edu.cn/f/wlxt/index/course/student/notice?mock=1'
    },
    {
      id: 'mock-notice-2',
      title: '实验课调整通知（附实验指导书）',
      content: '<p>本周五的实验课调整到周六上午 9:00，实验室不变。</p>',
      attachment: {
        downloadUrl: 'https://learn.tsinghua.edu.cn/b/wlxt/kc/wj_download?mock=1',
        name: '实验指导书.pdf',
        id: 'mock-wjid-1',
        size: '1.2MB'
      },
      publisher: '王敏',
      courseId: '2026-2027-1-100002',
      courseName: '大学物理（1）',
      courseTeacherName: '王敏',
      publishTimeMillis: now - 26 * HOUR_MS,
      hasRead: false,
      markedImportant: false,
      url: 'https://learn.tsinghua.edu.cn/f/wlxt/index/course/student/notice?mock=2'
    },
    {
      id: 'mock-notice-3',
      title: '课程论文选题说明',
      content: '<p>课程论文选题见附件，请在两周内确定选题。</p>',
      publisher: '赵磊',
      courseId: '2026-2027-1-100003',
      courseName: '马克思主义基本原理',
      courseTeacherName: '赵磊',
      publishTimeMillis: now - 5 * DAY_MS,
      hasRead: true,
      markedImportant: false,
      url: 'https://learn.tsinghua.edu.cn/f/wlxt/index/course/student/notice?mock=3'
    },
    {
      id: 'mock-notice-4',
      title: '关于提交平时作业的提醒',
      content: '<p>请尚未提交第一次平时作业的同学尽快提交。</p>',
      publisher: '李强',
      courseId: '2026-2027-1-100001',
      courseName: '数据结构',
      courseTeacherName: '李强',
      publishTimeMillis: now - 9 * DAY_MS,
      hasRead: true,
      markedImportant: false,
      url: 'https://learn.tsinghua.edu.cn/f/wlxt/index/course/student/notice?mock=4'
    }
  ];
}

/**
 * 四条样例作业：
 *   - 两条**未提交且未截止**（计数用）；
 *   - 一条已提交未批改；
 *   - 一条已提交且已评分（带成绩与批改人）。
 */
export function mockAssignments(): Assignment[] {
  const now: number = Date.now();
  const items: Assignment[] = [
    {
      id: 'mock-assignment-1',
      studentHomeworkId: 'mock-xszy-1',
      baseId: 'mock-zy-1',
      title: '第一次作业：线性表',
      url: 'https://learn.tsinghua.edu.cn/f/wlxt/kczy/zy/student/viewZy?mock=1',
      deadline: formatDateTime(now + 6 * DAY_MS),
      isLateSubmission: false,
      completionType: '1',
      submissionType: '2',
      submitUrl: 'https://learn.tsinghua.edu.cn/f/wlxt/kczy/zy/student/submit?mock=1',
      gradeContent: '',
      submittedContent: '',
      answerContent: '',
      description: '<p>完成教材第 2 章习题 1、3、5。</p>',
      submitted: false,
      graded: false,
      courseId: '2026-2027-1-100001',
      courseName: '数据结构',
      courseTeacherName: '李强'
    },
    {
      id: 'mock-assignment-2',
      studentHomeworkId: 'mock-xszy-2',
      baseId: 'mock-zy-2',
      title: '第一次作业：质点运动学',
      url: 'https://learn.tsinghua.edu.cn/f/wlxt/kczy/zy/student/viewZy?mock=2',
      deadline: formatDateTime(now + 2 * DAY_MS),
      lateSubmissionDeadline: formatDateTime(now + 9 * DAY_MS),
      isLateSubmission: true,
      completionType: '1',
      submissionType: '2',
      submitUrl: 'https://learn.tsinghua.edu.cn/f/wlxt/kczy/zy/student/submit?mock=2',
      gradeContent: '',
      submittedContent: '',
      answerContent: '',
      description: '<p>教材第 1 章课后习题全部。</p>',
      submitted: false,
      graded: false,
      courseId: '2026-2027-1-100002',
      courseName: '大学物理（1）',
      courseTeacherName: '王敏'
    },
    {
      id: 'mock-assignment-3',
      studentHomeworkId: 'mock-xszy-3',
      baseId: 'mock-zy-3',
      title: '第二次作业：栈与队列',
      url: 'https://learn.tsinghua.edu.cn/f/wlxt/kczy/zy/student/viewCj?mock=3',
      deadline: formatDateTime(now - 2 * DAY_MS),
      isLateSubmission: false,
      completionType: '1',
      submissionType: '2',
      submitUrl: 'https://learn.tsinghua.edu.cn/f/wlxt/kczy/zy/student/submit?mock=3',
      submitTime: formatDateTime(now - 3 * DAY_MS),
      gradeContent: '',
      submittedContent: '<p>见附件。</p>',
      answerContent: '',
      description: '<p>实现一个支持最小值查询的栈。</p>',
      submitted: true,
      graded: false,
      courseId: '2026-2027-1-100001',
      courseName: '数据结构',
      courseTeacherName: '李强'
    },
    {
      id: 'mock-assignment-4',
      studentHomeworkId: 'mock-xszy-4',
      baseId: 'mock-zy-4',
      title: '课程论文提纲',
      url: 'https://learn.tsinghua.edu.cn/f/wlxt/kczy/zy/student/viewCj?mock=4',
      deadline: formatDateTime(now - 12 * DAY_MS),
      isLateSubmission: false,
      completionType: '1',
      submissionType: '2',
      submitUrl: 'https://learn.tsinghua.edu.cn/f/wlxt/kczy/zy/student/submit?mock=4',
      submitTime: formatDateTime(now - 13 * DAY_MS),
      grade: 92,
      graderName: '赵磊',
      gradeTime: formatDateTime(now - 10 * DAY_MS),
      gradeContent: '<p>提纲结构清晰，注意补充参考文献。</p>',
      submittedContent: '<p>提纲见正文。</p>',
      answerContent: '',
      description: '<p>提交课程论文提纲（不少于 500 字）。</p>',
      submitted: true,
      graded: true,
      courseId: '2026-2027-1-100003',
      courseName: '马克思主义基本原理',
      courseTeacherName: '赵磊'
    }
  ];
  return applyMockSubmissionJournal(items);
}

/** 样例提交附件的下载地址前缀（与其它样例地址同一形状：真实域名 + `mock=`，不指向任何真实文件）。 */
const MOCK_SUBMITTED_ATTACHMENT_URL: string =
  'https://learn.tsinghua.edu.cn/b/wlxt/kc/wj_download?mock=submitted-';

/** 字节数 → 站点形状的体积文本（`139.54KB` / `1.20MB`；小于 1KB 用字节）。 */
function formatAttachmentSize(bytes: number): string {
  if (bytes >= 1024 * 1024) {
    return (bytes / (1024 * 1024)).toFixed(2) + 'MB';
  }
  if (bytes >= 1024) {
    return (bytes / 1024).toFixed(2) + 'KB';
  }
  return bytes.toString() + 'B';
}

/**
 * 把提交台账套到样例作业上（**覆盖层**）。
 *
 * 为什么钉在样例出口而不是仓储里：本函数是样例作业的唯一出口
 * （`MockCourseRepository.refresh()` 取作业列表、作业详情页也经由同一份快照），
 * 覆盖层放在这里，所有读样例的地方都会看到同一份"已提交"状态，不需要各自记得套一遍。
 *
 * 只改**被提交过**的那几条（台账里没有的条目原样返回），所以"两条未提交 + 两条已提交"
 * 的样例性质还在，日期也仍然按当前时间算。
 */
function applyMockSubmissionJournal(items: Assignment[]): Assignment[] {
  for (let i = 0; i < items.length; i++) {
    const item: Assignment = items[i];
    const xszyid: string | undefined = item.studentHomeworkId;
    if (xszyid === undefined) {
      continue;
    }
    const entry: MockSubmissionEntry | undefined = submissionFor(xszyid);
    if (entry === undefined) {
      continue;
    }
    item.submitted = true;
    item.submitTime = formatDateTime(entry.submittedAtMillis);
    // 正文形状与样例里其它已提交条目一致（`<p>…</p>`，站点给的就是 HTML）。
    // 「移除附件」那一支正文是空串：这时**不给**一个空的 `<p></p>`——
    // 那观感像"提交了一段空正文"，而实际上这一次只是把附件删了。
    item.submittedContent = entry.content.length > 0 ? '<p>' + entry.content + '</p>' : '';
    if (entry.removeAttachment) {
      // 移除附件：清掉"已提交附件"。ArkTS 侧不用 `delete`，统一赋值 undefined。
      item.submittedAttachment = undefined;
    } else if (entry.attachment !== undefined) {
      const attachment: Attachment = {
        downloadUrl: MOCK_SUBMITTED_ATTACHMENT_URL + xszyid,
        name: entry.attachment.name,
        size: formatAttachmentSize(entry.attachment.size)
      };
      item.submittedAttachment = attachment;
    }
  }
  return items;
}

/** 四条样例文件（一条"新"）。 */
export function mockFiles(): CourseFile[] {
  const now: number = Date.now();
  return [
    {
      id: 'mock-file-1',
      fileId: 'mock-wjid-101',
      title: '课程大纲',
      description: '本学期课程大纲与考核方式',
      size: '268.31KB',
      uploadTime: formatDateTime(now - 4 * HOUR_MS),
      fileType: 'pdf',
      isNew: true,
      downloadUrl: 'https://learn.tsinghua.edu.cn/b/wlxt/kc/wj_download?mock=101',
      courseId: '2026-2027-1-100001',
      courseName: '数据结构',
      courseTeacherName: '李强'
    },
    {
      id: 'mock-file-2',
      fileId: 'mock-wjid-102',
      title: '第一次作业参考答案',
      description: '',
      size: '512.00KB',
      uploadTime: formatDateTime(now - 2 * DAY_MS),
      fileType: 'pdf',
      isNew: false,
      downloadUrl: 'https://learn.tsinghua.edu.cn/b/wlxt/kc/wj_download?mock=102',
      courseId: '2026-2027-1-100001',
      courseName: '数据结构',
      courseTeacherName: '李强'
    },
    {
      id: 'mock-file-3',
      fileId: 'mock-wjid-103',
      title: '实验指导书',
      description: '大学物理实验一至实验四',
      size: '1.20MB',
      uploadTime: formatDateTime(now - 26 * HOUR_MS),
      fileType: 'pdf',
      isNew: true,
      downloadUrl: 'https://learn.tsinghua.edu.cn/b/wlxt/kc/wj_download?mock=103',
      courseId: '2026-2027-1-100002',
      courseName: '大学物理（1）',
      courseTeacherName: '王敏'
    },
    {
      id: 'mock-file-4',
      fileId: 'mock-wjid-104',
      title: '课堂讲义（第三讲）',
      description: '',
      size: '3.42MB',
      uploadTime: formatDateTime(now - 6 * DAY_MS),
      fileType: 'pptx',
      isNew: false,
      downloadUrl: 'https://learn.tsinghua.edu.cn/b/wlxt/kc/wj_download?mock=104',
      courseId: '2026-2027-1-100003',
      courseName: '马克思主义基本原理',
      courseTeacherName: '赵磊'
    }
  ];
}
