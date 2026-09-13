/*
 * 收藏 / 归档 / 隐藏课程的规则单测。
 *
 * 覆盖：
 *   - **状态迁移**：三个域的收藏 / 归档与课程的屏蔽，flag 语义对齐参考实现 reducer，
 *     但**置真去重**（同一条内容项连续两次置真只留一份 id）；
 *   - **过滤语义**：all 排除归档与隐藏课程、fav 在 all 之上再筛、archived / hidden 用原始 items
 *     （reference/learnOH-old/src/data/selectors/filteredData.ts:69-169），以及各分组的计数；
 *   - **隐藏课程的内容从三个域同时消失**（列表那一半；搜索那一半归搜索页）；
 *   - **持久化**：编解码往返、损坏数据丢弃、未知过滤视图回退、跨 store 实例恢复；
 *   - 过滤选择的默认值（参考实现 settings.ts:24-29，assignment 默认 unfinished）。
 *
 * 界面组件（ArkUI struct）不在 host 单测里实例化，所以这里测的是它们背后的纯规则与 store。
 */

import { describe, it, expect } from '@ohos/hypium';
import { Assignment, CourseFile } from '../main/ets/domain/model/ContentItem';
import { NoticeRecord } from '../main/ets/data/notices/NoticeRepository';
import { CourseRecord } from '../main/ets/data/courses/CourseRepository';
import { ContentFilter } from '../main/ets/domain/marks/ContentFilter';
import {
  DEFAULT_TAB_FILTER_SELECTIONS, MarksDomain, MarksTab, describeCollectionFlags,
  emptyCollectionFlags, withArchived, withFavorite, withHiddenCourse, withTabFilter
} from '../main/ets/domain/marks/CollectionFlags';
import { decodeCollectionFlags, encodeCollectionFlags } from '../main/ets/domain/marks/CollectionFlagsCodec';
import {
  CollectionFlagsStore, InMemoryCollectionFlagsPort
} from '../main/ets/data/marks/CollectionFlagsStore';
import {
  assignmentCounts, assignmentsForFilter, fileCounts, filesForFilter, isHiddenCourse,
  noticeCounts, noticesForFilter, selectFilteredAssignments, selectFilteredFiles,
  selectFilteredNotices
} from '../main/ets/features/marks/FilteredContent';
import {
  TOAST_MILLIS_FOR_EVIDENCE, TOAST_SUCCESS_MILLIS, effectiveToastMillis
} from '../main/ets/ui/components/Toast';

/* ------------------------------------------------------------------ *
 * 造条目（只填断言要用的字段，其余给稳定默认值）
 * ------------------------------------------------------------------ */

function makeNotice(id: string, courseId: string, hasRead: boolean): NoticeRecord {
  return {
    id: id, title: 'n-' + id, content: '', publisher: 'p', courseId: courseId,
    courseName: '课-' + courseId, courseTeacherName: 't', publishTimeMillis: 1000,
    hasRead: hasRead, markedImportant: false, url: ''
  };
}

function makeAssignment(id: string, courseId: string, submitted: boolean): Assignment {
  return {
    id: id, baseId: id + '-base', title: 'a-' + id, url: '', deadline: '2030-01-01 00:00',
    isLateSubmission: false, completionType: '1', submissionType: '2', submitUrl: '',
    courseId: courseId, courseName: '课-' + courseId, courseTeacherName: 't',
    description: '', submittedContent: '', answerContent: '', gradeContent: '',
    submitted: submitted, graded: false
  };
}

function makeFile(id: string, courseId: string, isNew: boolean): CourseFile {
  return {
    id: id, fileId: id + '-wj', title: 'f-' + id, description: '', size: '1KB',
    uploadTime: '2020-01-01 00:00', fileType: 'pdf', isNew: isNew, downloadUrl: '',
    courseId: courseId, courseName: '课-' + courseId, courseTeacherName: 't'
  };
}

function makeCourse(id: string): CourseRecord {
  return {
    id: id, name: '课-' + id, chineseName: '课-' + id, englishName: 'c-' + id, teacherName: 't',
    teacherNumber: '', courseNumber: '', courseIndex: 0,
    unreadNoticeCount: 0, unfinishedAssignmentCount: 0, unreadFileCount: 0
  };
}

function idsOfNotices(items: NoticeRecord[]): string {
  let out: string = '';
  for (let i = 0; i < items.length; i++) {
    out += (i === 0 ? '' : ',') + items[i].id;
  }
  return out;
}

function idsOfAssignments(items: Assignment[]): string {
  let out: string = '';
  for (let i = 0; i < items.length; i++) {
    out += (i === 0 ? '' : ',') + items[i].id;
  }
  return out;
}

function idsOfFiles(items: CourseFile[]): string {
  let out: string = '';
  for (let i = 0; i < items.length; i++) {
    out += (i === 0 ? '' : ',') + items[i].id;
  }
  return out;
}

/* ------------------------------------------------------------------ *
 * 夹具：两条公告 / 三条作业 / 两条文件，分散在两门课（c1 / c2）上
 * ------------------------------------------------------------------ */

const NOTICES: NoticeRecord[] = [
  makeNotice('n1', 'c1', false),
  makeNotice('n2', 'c2', true)
];

const ASSIGNMENTS: Assignment[] = [
  makeAssignment('a1', 'c1', false),
  makeAssignment('a2', 'c2', true),
  makeAssignment('a3', 'c1', true)
];

const FILES: CourseFile[] = [
  makeFile('f1', 'c1', true),
  makeFile('f2', 'c2', false)
];

export default function favoritesTest() {
  describe('domain.marks.collectionFlags', () => {
    it('favoriteAndArchiveTogglingFollowsTheReferenceReducers', 0, () => {
      const empty = emptyCollectionFlags();

      // 置真 = 去重加入；置假 = 精确移除该 id（data/reducers/notices.ts:59-72）
      const favOn = withFavorite(empty, MarksDomain.NOTICE, 'n1', true);
      expect(favOn.noticeFavorites.join(',')).assertEqual('n1');
      const favOff = withFavorite(favOn, MarksDomain.NOTICE, 'n1', false);
      expect(favOff.noticeFavorites.length).assertEqual(0);

      // **置真去重**：同一条内容项连续两次置真，集合里仍只有一份 id
      // （从"屏蔽"视图再收藏一次不会写出重复 id）。
      const twice = withFavorite(favOn, MarksDomain.NOTICE, 'n1', true);
      expect(twice.noticeFavorites.join(',')).assertEqual('n1');
      expect(withFavorite(twice, MarksDomain.NOTICE, 'n1', false).noticeFavorites.length).assertEqual(0);
      // 去重也覆盖"同一批里已经含这一条"的情形，且入参不被修改
      const batch = withFavorite(empty, MarksDomain.ASSIGNMENT, 'a1', true);
      expect(withFavorite(batch, MarksDomain.ASSIGNMENT, 'a1', true).assignmentFavorites.join(',')).assertEqual('a1');

      // 归档：置真收 id 数组并去重、置假按集合整体移除
      const archOn = withArchived(empty, MarksDomain.NOTICE, ['n1', 'n2'], true);
      expect(archOn.noticeArchived.join(',')).assertEqual('n1,n2');
      expect(withArchived(archOn, MarksDomain.NOTICE, ['n1', 'n2'], true).noticeArchived.join(',')).assertEqual('n1,n2');
      expect(withArchived(archOn, MarksDomain.NOTICE, ['n2', 'n2'], true).noticeArchived.join(',')).assertEqual('n1,n2');
      const archPartial = withArchived(archOn, MarksDomain.NOTICE, ['n1'], false);
      expect(archPartial.noticeArchived.join(',')).assertEqual('n2');

      // 屏蔽课程：置真去重、置假移除
      const hideOn = withHiddenCourse(empty, 'c1', true);
      expect(hideOn.hiddenCourseIds.join(',')).assertEqual('c1');
      expect(withHiddenCourse(hideOn, 'c1', true).hiddenCourseIds.join(',')).assertEqual('c1');
      expect(withHiddenCourse(hideOn, 'c1', false).hiddenCourseIds.length).assertEqual(0);

      // 三个域的数组互不影响（参考实现是三个 reducer）
      const mixed = withFavorite(withArchived(withFavorite(empty, MarksDomain.FILE, 'f1', true),
        MarksDomain.ASSIGNMENT, ['a2'], true), MarksDomain.NOTICE, 'n1', true);
      expect(mixed.fileFavorites.join(',')).assertEqual('f1');
      expect(mixed.assignmentArchived.join(',')).assertEqual('a2');
      expect(mixed.noticeFavorites.join(',')).assertEqual('n1');
      expect(mixed.noticeArchived.length).assertEqual(0);
      // 入参不被修改
      expect(empty.noticeFavorites.length).assertEqual(0);
      expect(describeCollectionFlags(mixed).includes('favorites=notice:1,assignment:0,file:1')).assertTrue();
    });

    it('tabFilterDefaultsMatchTheReferenceSettings', 0, () => {
      // data/reducers/settings.ts:24-29 逐字照抄：notice=all / assignment=unfinished / file=all / course=all
      expect(DEFAULT_TAB_FILTER_SELECTIONS.notice).assertEqual(ContentFilter.ALL);
      expect(DEFAULT_TAB_FILTER_SELECTIONS.assignment).assertEqual(ContentFilter.UNFINISHED);
      expect(DEFAULT_TAB_FILTER_SELECTIONS.file).assertEqual(ContentFilter.ALL);
      expect(DEFAULT_TAB_FILTER_SELECTIONS.course).assertEqual(ContentFilter.ALL);

      const next = withTabFilter(DEFAULT_TAB_FILTER_SELECTIONS, MarksTab.FILE, ContentFilter.FAV);
      expect(next.file).assertEqual(ContentFilter.FAV);
      expect(next.assignment).assertEqual(ContentFilter.UNFINISHED);
      expect(DEFAULT_TAB_FILTER_SELECTIONS.file).assertEqual(ContentFilter.ALL);
    });
  });

  describe('domain.marks.codec', () => {
    it('roundTripsFlagsAndTabFilters', 0, () => {
      const flags = withArchived(
        withFavorite(withHiddenCourse(emptyCollectionFlags(), 'c9', true),
          MarksDomain.FILE, 'f9', true), MarksDomain.NOTICE, ['n9'], true);
      const tabs = withTabFilter(DEFAULT_TAB_FILTER_SELECTIONS, MarksTab.NOTICE, ContentFilter.HIDDEN);
      const payload = encodeCollectionFlags(flags, tabs);
      const decoded = decodeCollectionFlags(payload);
      expect(decoded.discardReason).assertEqual('');
      expect(decoded.flags.fileFavorites.join(',')).assertEqual('f9');
      expect(decoded.flags.noticeArchived.join(',')).assertEqual('n9');
      expect(decoded.flags.hiddenCourseIds.join(',')).assertEqual('c9');
      expect(decoded.tabFilters.notice).assertEqual(ContentFilter.HIDDEN);
    });

    it('discardsCorruptPayloadsInsteadOfThrowing', 0, () => {
      expect(decodeCollectionFlags('').discardReason).assertEqual('empty');
      expect(decodeCollectionFlags('{oops').discardReason).assertEqual('parse_failed');
      expect(decodeCollectionFlags('[]').discardReason).assertEqual('not_an_object');
      expect(decodeCollectionFlags('{\"flags\":{}}').discardReason).assertEqual('version_missing');
      expect(decodeCollectionFlags('{\"schemaVersion\":99}').discardReason).assertEqual('version_mismatch:99');
      expect(decodeCollectionFlags('{\"schemaVersion\":1}').discardReason).assertEqual('flags_missing');
      // 字段形状不对（数组里混进数字）也整体丢弃，绝不半信半疑地读一半
      const badEntry = '{\"schemaVersion\":1,\"flags\":{\"noticeFavorites\":[1],'
        + '\"noticeArchived\":[],\"assignmentFavorites\":[],\"assignmentArchived\":[],'
        + '\"fileFavorites\":[],\"fileArchived\":[],\"hiddenCourseIds\":[]}}';
      expect(decodeCollectionFlags(badEntry).discardReason).assertEqual('flags_invalid');
      // 丢弃时状态回到默认值（不是 null、不是抛异常）
      expect(decodeCollectionFlags('{oops').flags.noticeFavorites.length).assertEqual(0);
      expect(decodeCollectionFlags('{oops').tabFilters.assignment).assertEqual(ContentFilter.UNFINISHED);
    });

    it('fallsBackPerTabWhenAFilterNameIsUnknown', 0, () => {
      const payload = '{\"schemaVersion\":1,\"flags\":{\"noticeFavorites\":[],'
        + '\"noticeArchived\":[],\"assignmentFavorites\":[],\"assignmentArchived\":[],'
        + '\"fileFavorites\":[],\"fileArchived\":[],\"hiddenCourseIds\":[]},'
        + '\"tabFilters\":{\"notice\":\"nope\",\"assignment\":\"fav\",'
        + '\"file\":\"all\",\"course\":\"all\"}}';
      const decoded = decodeCollectionFlags(payload);
      expect(decoded.discardReason).assertEqual('');
      // 未知视图按该 tab 的默认值回退，不整体丢弃
      expect(decoded.tabFilters.notice).assertEqual(ContentFilter.ALL);
      expect(decoded.tabFilters.assignment).assertEqual(ContentFilter.FAV);
    });
  });

  describe('features.marks.filteredContent', () => {
    it('allExcludesArchivedItemsAndItemsOfHiddenCourses', 0, () => {
      const notices = selectFilteredNotices(NOTICES, [], ['n1'], ['c2']);
      expect(idsOfNotices(notices.all)).assertEqual('');
      // 归档 / 屏蔽两个视图用的是**原始 items**（不是 all）
      expect(idsOfNotices(notices.archived)).assertEqual('n1');
      expect(idsOfNotices(notices.hidden)).assertEqual('n2');
      expect(noticesForFilter(notices, ContentFilter.ALL).length).assertEqual(0);
      expect(idsOfNotices(noticesForFilter(notices, ContentFilter.HIDDEN))).assertEqual('n2');
      expect(idsOfNotices(noticesForFilter(notices, ContentFilter.ARCHIVED))).assertEqual('n1');

      const assignments = selectFilteredAssignments(ASSIGNMENTS, [], ['a2'], ['c1']);
      expect(idsOfAssignments(assignments.all)).assertEqual('');
      expect(idsOfAssignments(assignments.archived)).assertEqual('a2');
      expect(idsOfAssignments(assignments.hidden)).assertEqual('a1,a3');

      const files = selectFilteredFiles(FILES, [], ['f1'], ['c2']);
      expect(idsOfFiles(files.all)).assertEqual('');
      expect(idsOfFiles(files.archived)).assertEqual('f1');
      expect(idsOfFiles(files.hidden)).assertEqual('f2');
    });

    it('favoriteIsASubsetOfAllSoArchivedItemsNeverShowUpInFavorites', 0, () => {
      // n1 被收藏**且**被归档 ⇒ 收藏夹里没有它（fav = all ∩ favorites）
      const notices = selectFilteredNotices(NOTICES, ['n1', 'n2'], ['n1'], []);
      expect(idsOfNotices(notices.fav)).assertEqual('n2');
      // 被屏蔽课程里的条目同理（即便它在 favorites 里）
      const hiddenFav = selectFilteredNotices(NOTICES, ['n2'], [], ['c2']);
      expect(idsOfNotices(hiddenFav.fav)).assertEqual('');
      expect(idsOfNotices(hiddenFav.all)).assertEqual('n1');
    });

    it('aFavoritedItemStaysFavoritedAfterItsCourseIsHidden', 0, () => {
      // 收藏 → 屏蔽该课程：条目不在 all 也不在 fav 分组里（收藏夹口径不变），
      // 但**原始收藏集合**仍含它 —— 行上的收藏状态取的就是原始集合，
      // 所以"屏蔽"视图里这一行显示为已收藏（去重后也不会出现第二个 id）。
      let flags = withFavorite(emptyCollectionFlags(), MarksDomain.NOTICE, 'n2', true);
      const firstIdCount = flags.noticeFavorites.length;
      flags = withHiddenCourse(flags, 'c2', true);
      const groups = selectFilteredNotices(NOTICES, flags.noticeFavorites, flags.noticeArchived,
        flags.hiddenCourseIds);
      expect(idsOfNotices(groups.fav)).assertEqual('');
      expect(idsOfNotices(groups.hidden)).assertEqual('n2');
      expect(flags.noticeFavorites.join(',')).assertEqual('n2');
      expect(flags.noticeFavorites.length).assertEqual(firstIdCount);

      // 在屏蔽视图里再点一次收藏：界面读到的 isFav 为真 ⇒ 置假，集合被清空、不是又加一条
      const isFav: boolean = flags.noticeFavorites.includes('n2');
      expect(isFav).assertTrue();
      const afterToggle = withFavorite(flags, MarksDomain.NOTICE, 'n2', !isFav);
      expect(afterToggle.noticeFavorites.length).assertEqual(0);
    });

    it('archivedAndHiddenGroupsKeepTheOtherFilterOut', 0, () => {
      // 归档视图看得到被屏蔽课程里的条目；屏蔽视图也看得到已归档的条目
      const archivedOfHiddenCourse = selectFilteredNotices(NOTICES, [], ['n2'], ['c2']);
      expect(idsOfNotices(archivedOfHiddenCourse.archived)).assertEqual('n2');
      expect(idsOfNotices(archivedOfHiddenCourse.hidden)).assertEqual('n2');
      // 但 all 里两个都被排除
      expect(archivedOfHiddenCourse.all.length).assertEqual(1);
      expect(idsOfNotices(archivedOfHiddenCourse.all)).assertEqual('n1');
    });

    it('countsFollowEachGroup', 0, () => {
      const notices = selectFilteredNotices(NOTICES, ['n2'], ['n1'], ['c2']);
      const nc = noticeCounts(notices);
      expect(nc.all).assertEqual(0);
      expect(nc.unread).assertEqual(0);
      expect(nc.fav).assertEqual(0);
      expect(nc.archived).assertEqual(1);
      expect(nc.hidden).assertEqual(1);

      // 未读 = all 里 hasRead === false（参考实现 :82）
      const unread = selectFilteredNotices(NOTICES, [], [], []);
      expect(noticeCounts(unread).unread).assertEqual(1);
      expect(idsOfNotices(unread.unread)).assertEqual('n1');

      // 作业：unfinished = all 里 !submitted；finished 的计数是参考实现的 all - unfinished
      const plain = selectFilteredAssignments(ASSIGNMENTS, ['a1', 'a3'], [], []);
      expect(idsOfAssignments(plain.all)).assertEqual('a1,a2,a3');
      expect(idsOfAssignments(plain.unfinished)).assertEqual('a1');
      expect(idsOfAssignments(plain.finished)).assertEqual('a2,a3');
      expect(idsOfAssignments(plain.fav)).assertEqual('a1,a3');
      const pc = assignmentCounts(plain);
      expect(pc.all).assertEqual(3);
      expect(pc.unfinished).assertEqual(1);
      expect(pc.finished).assertEqual(2);
      expect(pc.fav).assertEqual(2);
      expect(pc.archived).assertEqual(0);
      expect(pc.hidden).assertEqual(0);

      // a2 同时被归档、被收藏，且其课程没被屏蔽 ⇒ all 里没有它、收藏夹里也没有它（B 条）
      // a1/a3 的课程被屏蔽 ⇒ all 里没有它们，但 archived / hidden 两个分组仍按原始 items 给出
      const mixed = selectFilteredAssignments(ASSIGNMENTS, ['a2'], ['a2'], ['c1']);
      expect(idsOfAssignments(mixed.all)).assertEqual('');
      expect(idsOfAssignments(mixed.archived)).assertEqual('a2');
      expect(idsOfAssignments(mixed.hidden)).assertEqual('a1,a3');
      expect(idsOfAssignments(mixed.fav)).assertEqual('');
      expect(assignmentCounts(mixed).archived).assertEqual(1);
      expect(assignmentCounts(mixed).hidden).assertEqual(2);

      // 文件：unread = all 里 isNew
      const files = selectFilteredFiles(FILES, [], [], []);
      const fc = fileCounts(files);
      expect(fc.all).assertEqual(2);
      expect(fc.unread).assertEqual(1);
      expect(idsOfFiles(filesForFilter(files, ContentFilter.UNREAD))).assertEqual('f1');
    });

    it('hidingACourseRemovesItsItemsFromAllThreeDomainsAndFromSearchInputs', 0, () => {
      const hidden: string[] = ['c1'];
      const notices = selectFilteredNotices(NOTICES, [], [], hidden);
      const assignments = selectFilteredAssignments(ASSIGNMENTS, [], [], hidden);
      const files = selectFilteredFiles(FILES, [], [], hidden);
      expect(idsOfNotices(notices.all)).assertEqual('n2');
      expect(idsOfAssignments(assignments.all)).assertEqual('a2');
      expect(idsOfFiles(files.all)).assertEqual('f2');
      // 三个域的 hidden 分组正是被剔除的那些（课程页点"取消屏蔽"就从这里找回）
      expect(idsOfNotices(notices.hidden)).assertEqual('n1');
      expect(idsOfAssignments(assignments.hidden)).assertEqual('a1,a3');
      expect(idsOfFiles(files.hidden)).assertEqual('f1');
    });

    it('coursesSplitByTheHiddenFlag', 0, () => {
      const courses: CourseRecord[] = [makeCourse('c1'), makeCourse('c2')];
      const hidden: string[] = ['c2'];
      let visible: number = 0;
      let hiddenCount: number = 0;
      for (let i = 0; i < courses.length; i++) {
        if (isHiddenCourse(hidden, courses[i].id)) {
          hiddenCount++;
        } else {
          visible++;
        }
      }
      expect(visible).assertEqual(1);
      expect(hiddenCount).assertEqual(1);
    });
  });

  describe('ui.components.Toast', () => {
    it('evidenceToastDurationOverrideIsOffAtCommit', 0, () => {
      // AGENTS.md："提交前用 git show HEAD:<文件> 核对开关已复原" —— 这里再加一道程序化断言。
      expect(TOAST_MILLIS_FOR_EVIDENCE).assertEqual(0);
      // 提交态的实际时长 = 参考实现的 success 档 3000ms（Toast.tsx:51-54）。
      expect(TOAST_SUCCESS_MILLIS).assertEqual(3000);
      expect(effectiveToastMillis()).assertEqual(3000);
    });
  });

  describe('data.marks.CollectionFlagsStore', () => {
    it('persistsAndRestoresAcrossStoreInstances', 0, async () => {
      const port = new InMemoryCollectionFlagsPort();
      const first = new CollectionFlagsStore(port);
      await first.loadOnce();
      expect(first.loaded).assertTrue();
      expect(first.filterFor(MarksTab.ASSIGNMENT)).assertEqual(ContentFilter.UNFINISHED);

      await first.setFavorite(MarksDomain.NOTICE, 'n1', true);
      await first.setArchived(MarksDomain.FILE, ['f1'], true);
      await first.setHidden('c1', true);
      await first.selectFilter(MarksTab.NOTICE, ContentFilter.FAV);

      // 第二个实例 = 重启后的应用：同一份持久层，状态应原样回来
      const second = new CollectionFlagsStore(port);
      await second.loadOnce();
      expect(second.noticeFavorites.join(',')).assertEqual('n1');
      expect(second.fileArchived.join(',')).assertEqual('f1');
      expect(second.hiddenCourseIds.join(',')).assertEqual('c1');
      expect(second.filterFor(MarksTab.NOTICE)).assertEqual(ContentFilter.FAV);
      expect(second.filterFor(MarksTab.FILE)).assertEqual(ContentFilter.ALL);

      // 撤销（置回 false）同样落盘
      await second.setFavorite(MarksDomain.NOTICE, 'n1', false);
      await second.setHidden('c1', false);
      const third = new CollectionFlagsStore(port);
      await third.loadOnce();
      expect(third.noticeFavorites.length).assertEqual(0);
      expect(third.hiddenCourseIds.length).assertEqual(0);
      expect(third.fileArchived.join(',')).assertEqual('f1');
    });

    it('treatsAnAbsentPayloadAsDefaultsAndSurvivesAGarbageOne', 0, async () => {
      const absent = new CollectionFlagsStore(new InMemoryCollectionFlagsPort());
      await absent.loadOnce();
      expect(absent.loaded).assertTrue();
      expect(absent.errorMessage).assertEqual('');
      expect(absent.noticeFavorites.length).assertEqual(0);

      const broken = new InMemoryCollectionFlagsPort();
      await broken.save('{not json');
      const store = new CollectionFlagsStore(broken);
      await store.loadOnce();
      // 损坏只表现为"回到默认值 + 一条原因"，不抛、不崩
      expect(store.errorMessage).assertEqual('parse_failed');
      expect(store.noticeFavorites.length).assertEqual(0);
      expect(store.filterFor(MarksTab.ASSIGNMENT)).assertEqual(ContentFilter.UNFINISHED);
    });
  });
}
