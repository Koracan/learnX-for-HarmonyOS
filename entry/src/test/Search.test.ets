/*
 * 全局搜索单测（ticket 15）—— 钉住 `features/search/SearchCore.ets` 的三段结构与数据口径。
 *
 * 期望值全部来自参考实现 `reference/learnOH-old/src/hooks/useSearch.ts`：
 *   - 字段表与权重（:5-42）；
 *   - 手工精确/前缀合并层（:44-49,107-110）；
 *   - 手工在前 + 按 id 去重（:51-61）；
 *   - 空查询 = 全量（`String.includes('')` 恒真，参考实现的实际行为）。
 *
 * 数据口径（工单验收第 5 条 + ticket 14 转来的那半）：
 *   - 喂进检索的是**原始 items 只排除被屏蔽课程**（参考实现 Search.tsx:35-37 用 items，不是 all
 *     ⇒ 归档项仍会被搜到；本工程另加屏蔽排除）；
 *   - 排除动作复用 `features/marks/FilteredContent` 的 selector，不另写过滤谓词。
 */

import { describe, it, expect } from '@ohos/hypium';
import { Assignment, CourseFile } from '../main/ets/domain/model/ContentItem';
import { NoticeRecord } from '../main/ets/data/notices/NoticeRepository';
import {
  ASSIGNMENT_SEARCH_FIELDS, FILE_SEARCH_FIELDS, MODEL_MISSING_KEYS, NOTICE_SEARCH_FIELDS,
  REFERENCE_INERT_KEYS, SCORE_EXACT, SCORE_FUZZY, SCORE_PREFIX, SCORE_SUBSTRING,
  WeightedField, fieldScore, searchAssignments, searchFiles, searchNotices, withinEditDistance
} from '../main/ets/features/search/SearchCore';
import {
  assignmentsExcludingHiddenCourses, filesExcludingHiddenCourses, noticesExcludingHiddenCourses,
  selectFilteredNotices
} from '../main/ets/features/marks/FilteredContent';

/* ------------------------------------------------------------------ *
 * 造条目（只填断言要用的字段，其余给稳定默认值）
 * ------------------------------------------------------------------ */

function makeNotice(id: string, title: string, courseId: string, courseName: string,
  content: string, publisher: string): NoticeRecord {
  return {
    id: id, title: title, content: content, publisher: publisher, courseId: courseId,
    courseName: courseName, courseTeacherName: 'Teacher ' + courseId, publishTimeMillis: 1000,
    hasRead: false, markedImportant: false, url: ''
  };
}

function makeAssignment(id: string, title: string, courseId: string, courseName: string,
  description: string, answerContent: string, graderName: string): Assignment {
  return {
    id: id, baseId: id + '-base', title: title, url: '', deadline: '2030-01-01 00:00',
    isLateSubmission: false, completionType: '1', submissionType: '2', submitUrl: '',
    courseId: courseId, courseName: courseName, courseTeacherName: 'Teacher ' + courseId,
    description: description, submittedContent: '', answerContent: answerContent,
    gradeContent: '', submitted: false, graded: false,
    graderName: graderName.length === 0 ? undefined : graderName
  };
}

function makeFile(id: string, title: string, courseId: string, courseName: string,
  description: string, fileType: string): CourseFile {
  return {
    id: id, fileId: id + '-wj', title: title, description: description, size: '1KB',
    uploadTime: '2020-01-01 00:00', fileType: fileType, isNew: false, downloadUrl: '',
    courseId: courseId, courseName: courseName, courseTeacherName: 'Teacher ' + courseId
  };
}

function idsOfNotices(items: NoticeRecord[]): string[] {
  const out: string[] = [];
  for (let i = 0; i < items.length; i++) {
    out.push(items[i].id);
  }
  return out;
}

function idsOfAssignments(items: Assignment[]): string[] {
  const out: string[] = [];
  for (let i = 0; i < items.length; i++) {
    out.push(items[i].id);
  }
  return out;
}

function idsOfFiles(items: CourseFile[]): string[] {
  const out: string[] = [];
  for (let i = 0; i < items.length; i++) {
    out.push(items[i].id);
  }
  return out;
}

export default function searchTest() {
  describe('features.search.SearchCore', () => {
    it('keeps the reference field tables and weights verbatim', 0, () => {
      // useSearch.ts:5-14 / :16-31 / :33-42（去掉恒不命中的键，见 SearchCore 文件头）。
      const noticeExpected: string[] = [
        'courseName:1', 'courseTeacherName:1', 'publisher:1', 'title:2', 'content:2'
      ];
      const assignmentExpected: string[] = [
        'courseName:1', 'courseTeacherName:1', 'submittedContent:1', 'graderName:1',
        'gradeContent:1', 'answerContent:1', 'title:2', 'description:2'
      ];
      const fileExpected: string[] = [
        'courseName:1', 'courseTeacherName:1', 'title:2', 'description:2', 'fileType:2'
      ];
      const flatten = (fields: WeightedField[]): string[] => {
        const out: string[] = [];
        for (let i = 0; i < fields.length; i++) {
          out.push(fields[i].name + ':' + fields[i].weight.toString());
        }
        return out;
      };
      expect(flatten(NOTICE_SEARCH_FIELDS).join(',')).assertEqual(noticeExpected.join(','));
      expect(flatten(ASSIGNMENT_SEARCH_FIELDS).join(',')).assertEqual(assignmentExpected.join(','));
      expect(flatten(FILE_SEARCH_FIELDS).join(',')).assertEqual(fileExpected.join(','));
      // 恒不命中的参考键**不在**我们索引的字段里（补上就是行为增强，不是移植）。
      const all: WeightedField[] = NOTICE_SEARCH_FIELDS.concat(ASSIGNMENT_SEARCH_FIELDS).concat(FILE_SEARCH_FIELDS);
      for (let k = 0; k < REFERENCE_INERT_KEYS.length; k++) {
        for (let i = 0; i < all.length; i++) {
          expect(all[i].name === REFERENCE_INERT_KEYS[k]).assertFalse();
        }
      }
      // 本工程数据模型缺 category（参考实现能命中）——如实登记，别当成有意口径。
      expect(MODEL_MISSING_KEYS.length).assertEqual(1);
      expect(MODEL_MISSING_KEYS[0]).assertEqual('category.title');
    });

    it('tiers a field match as exact > prefix > substring > fuzzy', 0, () => {
      expect(fieldScore('Data Structures', 'DATA STRUCTURES')).assertEqual(SCORE_EXACT);
      expect(fieldScore('Data Structures', 'DATA')).assertEqual(SCORE_PREFIX);
      expect(fieldScore('Intro to Data Structures', 'DATA')).assertEqual(SCORE_SUBSTRING);
      // 大小写不敏感（工单验收第 2 条）
      expect(fieldScore('data', 'DATA')).assertEqual(SCORE_EXACT);
      // 空查询/空字段不产生分数
      expect(fieldScore('anything', '')).assertEqual(0);
      expect(fieldScore('', 'anything')).assertEqual(0);
      // 完全不相干 → 0（CJK 也一样，见下一条用例）
      expect(fieldScore('Data Structures', 'ZZZZ')).assertEqual(0);
    });

    it('tolerates ASCII typos but not CJK typos (documented boundary)', 0, () => {
      // ASCII：一个词内两处替换（homework → homewrok）在阈值内
      expect(withinEditDistance('HOMEWORK', 'HOMEWROK', 2)).assertTrue();
      expect(withinEditDistance('HOMEWORK', 'HOMEWORK', 0)).assertTrue();
      expect(withinEditDistance('cat', 'dog', 1)).assertFalse();
      expect(fieldScore('Homework One', 'HOMEWROK')).assertEqual(SCORE_FUZZY);
      // 短查询不启用编辑距离（避免噪声）
      expect(fieldScore('Homework One', 'HOM')).assertEqual(SCORE_PREFIX);
      // CJK：没有子串就命不中（评估文档第 3 条：CJK 只能到码点级）
      expect(fieldScore('春季学期公告', '春李')).assertEqual(0);
      expect(fieldScore('春季学期公告', '学期')).assertEqual(SCORE_SUBSTRING);
    });

    it('matches titles and course names case-insensitively, exact and prefix included', 0, () => {
      const items: NoticeRecord[] = [
        makeNotice('n1', 'Data Structures Exam', 'c1', 'Algorithms', '', 'Prof. Li'),
        makeNotice('n2', '课程通知', 'c2', '数据结构', '', '张老师')
      ];
      expect(idsOfNotices(searchNotices(items, 'data')).join(',')).assertEqual('n1');
      expect(idsOfNotices(searchNotices(items, 'DATA')).join(',')).assertEqual('n1');
      expect(idsOfNotices(searchNotices(items, 'Data Structures Exam')).join(',')).assertEqual('n1');
      expect(idsOfNotices(searchNotices(items, '算法')).join(',')).assertEqual('');
      // 课程名命中
      expect(idsOfNotices(searchNotices(items, 'algorithms')).join(',')).assertEqual('n1');
      expect(idsOfNotices(searchNotices(items, '数据结构')).join(',')).assertEqual('n2');
      // 前缀命中
      expect(idsOfNotices(searchNotices(items, '数据')).join(',')).assertEqual('n2');
    });

    it('lists everything, in input order, for an empty query (reference behaviour)', 0, () => {
      const items: NoticeRecord[] = [
        makeNotice('n1', 'b', 'c1', 'x', '', 'p'),
        makeNotice('n2', 'a', 'c1', 'y', '', 'p')
      ];
      expect(idsOfNotices(searchNotices(items, '')).join(',')).assertEqual('n1,n2');
      expect(idsOfNotices(searchNotices(items, '   ')).join(',')).assertEqual('n1,n2');
    });

    it('puts manual title/course hits first and deduplicates by id', 0, () => {
      const items: NoticeRecord[] = [
        makeNotice('n1', 'other', 'c1', 'x', 'the word target appears in content', 'p'),
        makeNotice('n2', 'Target', 'c1', 'y', '', 'p')
      ];
      // n2 手工命中（标题完全等于查询），n1 只被 ② 命中（正文子串）。
      const result: NoticeRecord[] = searchNotices(items, 'target');
      expect(idsOfNotices(result).join(',')).assertEqual('n2,n1');
      // 去重：n2 同时被 ① 与 ② 命中，只能出现一次
      expect(result.length).assertEqual(2);
      // 大小写不同不影响结果（同一条 n2 仍然只在手工层出现一次）
      const upper: NoticeRecord[] = searchNotices(items, 'Target');
      expect(idsOfNotices(upper).join(',')).assertEqual('n2,n1');
      expect(upper.length).assertEqual(2);
    });

    it('ranks higher-weight fields first among engine-only matches', 0, () => {
      // 两条都只被 ② 命中（标题/课程名都不含查询 ⇒ 不进手工层）：
      //   n1 命中 content（权重 2，子串 0.55×2 = 1.1）；n2 命中 publisher（权重 1，整串相等 1.0×1 = 1.0）
      const engineOnly: NoticeRecord[] = [
        makeNotice('n1', 'unrelated', 'c1', 'x', 'body has keyword here', 'zzz'),
        makeNotice('n2', 'other', 'c1', 'x', '', 'keyword')
      ];
      expect(idsOfNotices(searchNotices(engineOnly, 'keyword')).join(',')).assertEqual('n1,n2');
      // 手工层内部**保持输入顺序**（参考实现的手工结果就是 filter 的原顺序，不按分数重排）——
      // 这是容易被"顺手优化"掉的参考实现行为，单独钉一条。
      const bothManual: NoticeRecord[] = [
        makeNotice('n1', 'weak', 'c1', 'x', '', 'p'),            // 只有课程名命中（弱）
        makeNotice('n2', 'keyword', 'c1', 'y', '', 'p')          // 标题整串相等（强）
      ];
      // 课程名要先命中：把 n1 的课程名设成含 keyword 的串
      const first: NoticeRecord = makeNotice('n1', 'weak', 'c1', 'keyword course', '', 'p');
      const manualOrder: NoticeRecord[] = [first, bothManual[1]];
      expect(idsOfNotices(searchNotices(manualOrder, 'keyword')).join(',')).assertEqual('n1,n2');
    });

    it('searches the extra reference fields of all three domains', 0, () => {
      const notices: NoticeRecord[] = [
        makeNotice('n1', 't', 'c1', 'x', '', 'Prof. Smith'),
        makeNotice('n2', 't', 'c1', 'x', 'body mentions quantum', 'p')
      ];
      expect(idsOfNotices(searchNotices(notices, 'smith')).join(',')).assertEqual('n1');
      expect(idsOfNotices(searchNotices(notices, 'quantum')).join(',')).assertEqual('n2');

      const assignments: Assignment[] = [
        makeAssignment('a1', 'hw', 'c1', 'x', 'describe the lab', '', ''),
        makeAssignment('a2', 'hw', 'c1', 'x', '', '参考解答内容', 'Grader Wang')
      ];
      expect(idsOfAssignments(searchAssignments(assignments, 'lab')).join(',')).assertEqual('a1');
      expect(idsOfAssignments(searchAssignments(assignments, '参考解答')).join(',')).assertEqual('a2');
      expect(idsOfAssignments(searchAssignments(assignments, 'wang')).join(',')).assertEqual('a2');

      const files: CourseFile[] = [
        makeFile('f1', 'lecture notes', 'c1', 'x', '', 'pdf'),
        makeFile('f2', 'slides', 'c1', 'x', 'about compilers', 'pptx')
      ];
      expect(idsOfFiles(searchFiles(files, 'pdf')).join(',')).assertEqual('f1');
      expect(idsOfFiles(searchFiles(files, 'compilers')).join(',')).assertEqual('f2');
    });

    it('drops hidden-course content from every domain (acceptance #5)', 0, () => {
      const notices: NoticeRecord[] = [
        makeNotice('n1', 'visible keyword', 'c1', 'Visible Course', '', 'p'),
        makeNotice('n2', 'hidden keyword', 'c2', 'Hidden Course', '', 'p')
      ];
      const assignments: Assignment[] = [
        makeAssignment('a1', 'visible keyword', 'c1', 'Visible Course', '', '', ''),
        makeAssignment('a2', 'hidden keyword', 'c2', 'Hidden Course', '', '', '')
      ];
      const files: CourseFile[] = [
        makeFile('f1', 'visible keyword', 'c1', 'Visible Course', '', 'pdf'),
        makeFile('f2', 'hidden keyword', 'c2', 'Hidden Course', '', 'pdf')
      ];
      const hidden: string[] = ['c2'];
      // 排除口径来自 FilteredContent 的 selector（同一份判据）
      expect(idsOfNotices(noticesExcludingHiddenCourses(notices, hidden)).join(',')).assertEqual('n1');
      expect(idsOfAssignments(assignmentsExcludingHiddenCourses(assignments, hidden)).join(',')).assertEqual('a1');
      expect(idsOfFiles(filesExcludingHiddenCourses(files, hidden)).join(',')).assertEqual('f1');
      // 检索结果里也看不到被屏蔽课程（按标题、按课程名、空查询三种入口都断言一遍）
      const visibleNotices: NoticeRecord[] = noticesExcludingHiddenCourses(notices, hidden);
      expect(idsOfNotices(searchNotices(visibleNotices, 'keyword')).join(',')).assertEqual('n1');
      expect(idsOfNotices(searchNotices(visibleNotices, '')).join(',')).assertEqual('n1');
      expect(searchNotices(visibleNotices, 'Hidden Course').length).assertEqual(0);
      expect(idsOfAssignments(searchAssignments(
        assignmentsExcludingHiddenCourses(assignments, hidden), 'keyword')).join(',')).assertEqual('a1');
      expect(idsOfFiles(searchFiles(
        filesExcludingHiddenCourses(files, hidden), 'keyword')).join(',')).assertEqual('f1');
    });

    it('keeps archived items searchable (raw items, like the reference)', 0, () => {
      const notices: NoticeRecord[] = [
        makeNotice('n1', 'live item', 'c1', 'x', '', 'p'),
        makeNotice('n2', 'archived item', 'c1', 'x', '', 'p')
      ];
      const archived: string[] = ['n2'];
      // 列表口径（all）把它排除了……
      const filtered = selectFilteredNotices(notices, [], archived, []);
      expect(filtered.all.length).assertEqual(1);
      expect(filtered.archived.length).assertEqual(1);
      // ……但搜索结果口径（原始 items 只减屏蔽课程）**仍然搜得到**它 —— 与参考实现一致。
      const searchable: NoticeRecord[] = noticesExcludingHiddenCourses(notices, []);
      expect(idsOfNotices(searchable).join(',')).assertEqual('n1,n2');
      expect(idsOfNotices(searchNotices(searchable, 'archived')).join(',')).assertEqual('n2');
    });
  });
}
