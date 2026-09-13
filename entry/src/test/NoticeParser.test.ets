/*
 * 公告解析与排序单测（ticket 05 验收项 3、4）。
 *
 * 覆盖：
 *   - Base64 正文解码（成功 / 空串 / 畸形 base64 / 非法字符集 / 空 ggnr）与异常输入容错；
 *   - HTML 实体解码（参考实现的 6 个实体）；
 *   - 列表字段映射（ggid / bt / fbrxm / fbsj / jzsj / sfqd / sfyd / fjmc / 'null'）；
 *   - 排序：发布时间倒序 + 标识倒序（参考实现 actions/notices.ts 的 `localeCompare` 意图）；
 *   - 详情页附件：`ml-10` 优先分支与通用回退分支。
 *
 * 夹具成色见 fixtures/README.md：本文件用到的夹具除 `REAL_ID_LOGIN_HTML` 外均为**反推**。
 */

import { describe, it, expect } from '@ohos/hypium';
import { Notice } from '../main/ets/domain/model/ContentItem';
import { CourseName } from '../main/ets/domain/parse/CourseName';
import {
  RawNotice, parseNotice, parseNoticeList, parseNoticeAttachment,
  noticeAttachmentName, isNoticeRead, sortNotices, noticeDetailUrl
} from '../main/ets/domain/parse/NoticeParser';
import { compareIdDesc, compareByTimeThenIdDesc, parseTimestamp, decodeHtmlEntities } from '../main/ets/domain/parse/Text';
import { strictPureBase64Decoder } from './TestHelpers';
import {
  REAL_ID_LOGIN_HTML, NOTICE_DETAIL_ML10_HTML, NOTICE_DETAIL_ML10_AMP_HTML,
  NOTICE_DETAIL_GENERIC_AMP_HTML, NOTICE_DETAIL_PREVIEW_HTML,
  NOTICE_LIST_RESPONSE_JSON, RAW_NOTICE_WITH_BASE64
} from './fixtures/ContentItemFixtures';

/** 与真实调用一致：课程名映射按课程 id 查表。 */
const COURSES: Record<string, CourseName> = {
  '2019-2020-1139283212': { name: '通信与网络', teacherName: '周世东' }
};

function noticeOf(id: string, publishTime: string): Notice {
  return parseNotice({ ggid: id, bt: 't' + id, fbrxm: 'p', fbsj: publishTime },
    '2019-2020-1139283212', COURSES, strictPureBase64Decoder);
}

/** 把夹具 JSON 里的 `aaData` 逐字段搬成 `RawNotice`（夹具是 JSON 文本，无法自动带类型）。 */
function rowsOf(listJson: string): RawNotice[] {
  const parsed: Object = JSON.parse(listJson) as Object;
  const box: Record<string, Object> = (parsed as Record<string, Object>)['object'] as Record<string, Object>;
  const rows: Object[] = box['aaData'] as Object[];
  const typed: RawNotice[] = [];
  for (let i = 0; i < rows.length; i++) {
    const record: Record<string, Object> = rows[i] as Record<string, Object>;
    const raw: RawNotice = {
      ggid: String(record['ggid']),
      bt: String(record['bt']),
      fbrxm: String(record['fbrxm'])
    };
    if (record['fbsj'] !== undefined && record['fbsj'] !== null) {
      raw.fbsj = String(record['fbsj']);
    }
    if (record['jzsj'] !== undefined && record['jzsj'] !== null) {
      raw.jzsj = String(record['jzsj']);
    }
    if (record['sfqd'] !== undefined && record['sfqd'] !== null) {
      raw.sfqd = String(record['sfqd']);
    }
    if (record['sfyd'] !== undefined && record['sfyd'] !== null) {
      raw.sfyd = String(record['sfyd']);
    }
    // 站点把"没有附件"下发成字符串 'null'（参考实现判定 `attachmentName !== 'null'`）；
    // 这里按同一条规则还原，避免把 'null' 当成真的附件名。
    if (record['fjmc'] !== undefined && record['fjmc'] !== null && String(record['fjmc']) !== 'null') {
      raw.fjmc = String(record['fjmc']);
    }
    if (record['fjbt'] !== undefined && record['fjbt'] !== null && String(record['fjbt']) !== 'null') {
      raw.fjbt = String(record['fjbt']);
    }
    typed.push(raw);
  }
  return typed;
}

export default function noticeParserTest() {
  describe('domain.NoticeParser', () => {
    it('decodesBase64Content', 0, () => {
      const decoded: string = strictPureBase64Decoder(RAW_NOTICE_WITH_BASE64.ggnr as string);
      expect(decoded).assertEqual('<p>务必交作业，请不要交到理科楼。</p>');
      const notice: Notice = parseNotice(RAW_NOTICE_WITH_BASE64, '2019-2020-1139283212', COURSES, strictPureBase64Decoder);
      expect(notice.content).assertEqual('<p>务必交作业，请不要交到理科楼。</p>');
    });

    it('toleratesMalformedBase64', 0, () => {
      expect(strictPureBase64Decoder('')).assertEqual('');
      expect(strictPureBase64Decoder('%%%not-base64%%%')).assertEqual('');
      expect(strictPureBase64Decoder('a')).assertEqual('');
      expect(strictPureBase64Decoder('PHA+5Yqh')).assertEqual('<p>务');
      const missingGgnr: Notice = parseNotice({ ggid: 'g0', bt: 't', fbrxm: 'p', fbsj: '2020-01-01 00:00' },
        'c', COURSES, strictPureBase64Decoder);
      expect(missingGgnr.content).assertEqual('');
      const badGgnr: Notice = parseNotice({ ggid: 'g1', bt: 't', fbrxm: 'p', fbsj: '2020-01-01 00:00', ggnr: '!!!' },
        'c', COURSES, strictPureBase64Decoder);
      expect(badGgnr.content).assertEqual('');
    });

    it('decodesHtmlEntities', 0, () => {
      expect(decodeHtmlEntities('&lt;p&gt;a&amp;b&quot;c&apos;d&nbsp;e')).assertEqual('<p>a&b"c\'d e');
      expect(decodeHtmlEntities('')).assertEqual('');
      expect(decodeHtmlEntities('no entities')).assertEqual('no entities');
      expect(decodeHtmlEntities('&unknown;')).assertEqual('&unknown;');
    });

    it('mapsNoticeFieldsFromRawRecord', 0, () => {
      const notice: Notice = parseNotice(RAW_NOTICE_WITH_BASE64, '2019-2020-1139283212', COURSES, strictPureBase64Decoder);
      expect(notice.id).assertEqual('26ef84e86d60f069016dadb09dd673b2');
      expect(notice.title).assertEqual('请按照助教的安排交作业');
      expect(notice.publisher).assertEqual('杜春光');
      expect(notice.publishTime).assertEqual('2020-09-25 07:21');
      expect(notice.hasRead).assertFalse();
      expect(notice.markedImportant).assertFalse();
      expect(notice.courseName).assertEqual('通信与网络');
      expect(notice.courseTeacherName).assertEqual('周世东');
      expect(notice.attachment === undefined).assertTrue();
      expect(notice.url).assertEqual(noticeDetailUrl('2019-2020-1139283212', RAW_NOTICE_WITH_BASE64.ggid));
    });

    /**
     * 真实记录（模拟器 Pura 90，2026-09-12，ticket 09 取证）：
     * 站点的 `id` 是 `<ggid><学号>`，**不是** ggid 本身。参考实现只取 ggid，
     * 而 mock 数据里两者恰好相同，所以这条差异只在真实数据上显形。
     * 原始响应见 .scratch/notices/evidence/raw/learnoh_diag.txt（`C-c0-p0` 段）。
     */
    it('usesTheSiteIdWhichIsGgidPlusStudentNumber', 0, () => {
      const real: RawNotice = {
        id: '26ef84e8a00ef07901a0755e06e333502023011272',
        ggid: '26ef84e8a00ef07901a0755e06e33350',
        bt: 'Welcome message from the professor',
        fbrxm: '张为民',
        fbsj: '2026-09-10 13:07',
        fbsjStr: '2026-09-10 13:07',
        sfqd: '0',
        sfyd: '否',
        fjmc: undefined,
        ggnr: 'PHA+RGVhciBhbGwsPC9wPiAKICA8cD5XZWxjb21lIHRvIHRoaXMgY291cnNlITwvcD4gCg=='
      };
      const notice: Notice = parseNotice(real, '2026-2027-1152226210', COURSES, strictPureBase64Decoder);
      expect(notice.id).assertEqual('26ef84e8a00ef07901a0755e06e333502023011272');
      expect(notice.id.startsWith(real.ggid)).assertTrue();
      expect(notice.markedImportant).assertFalse();
      expect(notice.hasRead).assertFalse();
      expect(notice.content.includes('Welcome to this course!')).assertTrue();
      // 详情页地址仍用 ggid（站点 beforeViewXs 的 id 参数）
      expect(notice.url).assertEqual(noticeDetailUrl('2026-2027-1152226210', real.ggid));
    });

    it('treatsSfqdAndSfydVariantsLikeTheReference', 0, () => {
      const important: Notice = parseNotice({ ggid: 'g2', bt: 't', fbrxm: 'p', fbsj: '2020-01-01 00:00', sfqd: '1' },
        'c', COURSES, strictPureBase64Decoder);
      expect(important.markedImportant).assertTrue();
      expect(isNoticeRead('1')).assertTrue();
      expect(isNoticeRead(1)).assertTrue();
      expect(isNoticeRead('是')).assertTrue();
      expect(isNoticeRead('已读')).assertTrue();
      expect(isNoticeRead('0')).assertFalse();
      expect(isNoticeRead(0)).assertFalse();
      expect(isNoticeRead(undefined)).assertFalse();
    });

    it('readsListResponseAndSortsNewestFirst', 0, () => {
      const rows: RawNotice[] = rowsOf(NOTICE_LIST_RESPONSE_JSON);
      expect(rows.length).assertEqual(2);
      const notices: Notice[] = [];
      for (let i = 0; i < rows.length; i++) {
        notices.push(parseNotice(rows[i], '2019-2020-1139283212', COURSES, strictPureBase64Decoder));
      }
      const sorted: Notice[] = sortNotices(notices);
      expect(sorted.length).assertEqual(2);
      expect(sorted[0].id).assertEqual('26ef84e86d60f069016dadb09dd673b2');
      expect(sorted[1].id).assertEqual('26ef84e76cc258ed016d3ea25a95157d');
      expect(sorted[1].expireTime).assertEqual('2020-09-30 23:59');
      expect(sorted[0].expireTime === undefined).assertTrue();
      expect(sorted[1].markedImportant).assertTrue();
      expect(sorted[0].hasRead).assertTrue();
      const nullNamed: RawNotice = { ggid: 'g', bt: 't', fbrxm: 'p', fjmc: 'null', fjbt: 'null' };
      expect(noticeAttachmentName(nullNamed) === undefined).assertTrue();
      const byFjmc: RawNotice = { ggid: 'g', bt: 't', fbrxm: 'p', fjmc: 'a.pdf' };
      expect(noticeAttachmentName(byFjmc)).assertEqual('a.pdf');
      const byFjbt: RawNotice = { ggid: 'g', bt: 't', fbrxm: 'p', fjbt: 'b.pdf' };
      expect(noticeAttachmentName(byFjbt)).assertEqual('b.pdf');
    });

    it('breaksTimeTiesByIdDescending', 0, () => {
      const b: Notice = noticeOf('bb', '2020-09-25 07:21');
      const a: Notice = noticeOf('aa', '2020-09-25 07:21');
      const c: Notice = noticeOf('cc', '2020-09-24 07:21');
      const sorted: Notice[] = sortNotices([a, b, c]);
      expect(sorted[0].id).assertEqual('bb');
      expect(sorted[1].id).assertEqual('aa');
      expect(sorted[2].id).assertEqual('cc');
      expect(compareIdDesc('bb', 'aa') < 0).assertTrue();
      expect(compareIdDesc('aa', 'bb') > 0).assertTrue();
      expect(compareIdDesc('aa', 'aa')).assertEqual(0);
      expect(compareByTimeThenIdDesc('2020-09-25 07:21', 'aa', '2020-09-25 07:21', 'bb') > 0).assertTrue();
      expect(compareByTimeThenIdDesc('2020-09-25 07:21', 'bb', '2020-09-25 07:21', 'aa') < 0).assertTrue();
    });

    it('parsesSiteLocalTimeAndIsoTime', 0, () => {
      const local: number = parseTimestamp('2020-09-25 07:21');
      expect(new Date(local).getFullYear()).assertEqual(2020);
      expect(new Date(local).getMonth()).assertEqual(8);
      expect(new Date(local).getDate()).assertEqual(25);
      expect(new Date(local).getHours()).assertEqual(7);
      expect(new Date(local).getMinutes()).assertEqual(21);
      expect(parseTimestamp('2020-09-25T07:21:00.000Z')).assertEqual(Date.parse('2020-09-25T07:21:00.000Z'));
      expect(Number.isNaN(parseTimestamp('not a time'))).assertTrue();
      expect(Number.isNaN(parseTimestamp(undefined))).assertTrue();
      expect(Number.isNaN(parseTimestamp(''))).assertTrue();
      const withSeconds: number = parseTimestamp('2020-09-25 07:21:30');
      expect(new Date(withSeconds).getSeconds()).assertEqual(30);
      // 不可解析的时间排在最后
      const noTime: RawNotice = { ggid: 'z', bt: 't', fbrxm: 'p' };
      const d: Notice = parseNotice(noTime, 'c', COURSES, strictPureBase64Decoder);
      const e: Notice = noticeOf('aa', '2020-09-25 07:21');
      expect(sortNotices([d, e])[1].id).assertEqual('z');
    });

    it('extractsNoticeAttachmentFromMl10Branch', 0, () => {
      // 有 ml-10 时**重拼** downloadUrl（noticeDownloadUrl），因此 href 里是裸 '&' 还是
      // '&amp;' 都不影响结果——这正是参考实现的行为（ml-10 分支只从 href 里取 wjid）。
      const attachment = parseNoticeAttachment(NOTICE_DETAIL_ML10_HTML, '第一次大作业说明.pdf');
      expect(attachment !== undefined).assertTrue();
      expect(attachment?.name).assertEqual('第一次大作业说明.pdf');
      expect(attachment?.id).assertEqual('1998990181_GG_5f2c9a1b');
      expect(attachment?.downloadUrl).assertEqual(
        'https://learn.tsinghua.edu.cn/b/wlxt/kj/wlkc_kjxxb/student/downloadFile?sfgk=0&wjid=1998990181_GG_5f2c9a1b');
      const ampFixture = parseNoticeAttachment(NOTICE_DETAIL_ML10_AMP_HTML, '课程大纲.pdf');
      expect(ampFixture?.id).assertEqual('1998990182_GG_6a7b');
      expect(ampFixture?.downloadUrl).assertEqual(
        'https://learn.tsinghua.edu.cn/b/wlxt/kj/wlkc_kjxxb/student/downloadFile?sfgk=0&wjid=1998990182_GG_6a7b');
    });

    it('keepsHtmlEntitiesVerbatimOnTheGenericFallback', 0, () => {
      // 参考实现的正则不解码 HTML 实体。
      // 通用回退分支直接用 href 原文 ⇒ '&amp;' 原样保留；该分支也不推导附件 id。
      const attachment = parseNoticeAttachment(NOTICE_DETAIL_GENERIC_AMP_HTML, '课件.pdf');
      expect(attachment !== undefined).assertTrue();
      expect(attachment?.name).assertEqual('课件.pdf');
      expect(attachment?.downloadUrl).assertEqual(
        'https://learn.tsinghua.edu.cn/b/wlxt/kj/wlkc_kjxxb/student/downloadFile?fileId=1996990181_GG_88bb&amp;wjid=1996990181_GG_88bb');
      expect(attachment?.id === undefined).assertTrue();
    });

    it('fallsBackToGenericDownloadLinkAndUnwrapsPreview', 0, () => {
      const preview: string = '<div class="list fujian clearfix"><div class="fl">'
        + '<a class="ml-10" href="/f/wlxt/kj/wlkc_kjxxb/student/openNewWindow?fileId=1996990181_GG_77aa&amp;downloadUrl=%2Fb%2Fwlxt%2Fkj%2Fwlkc_kjxxb%2Fstudent%2FdownloadFile%3Fsfgk%3D0%26wjid%3D1996990181_GG_77aa">课程安排.pdf</a>'
        + '</div></div>';
      const attachment = parseNoticeAttachment(preview, '课程安排.pdf');
      expect(attachment !== undefined).assertTrue();
      expect(attachment?.downloadUrl).assertEqual(
        'https://learn.tsinghua.edu.cn/b/wlxt/kj/wlkc_kjxxb/student/downloadFile?sfgk=0&wjid=1996990181_GG_77aa');
      expect(NOTICE_DETAIL_PREVIEW_HTML.length > 0).assertTrue();
      const generic: string = '<div class="x"><a class="a1" href="/b/wlxt/kj/wlkc_kjxxb/student/downloadFile?fileId=abc123">x.pdf</a></div>';
      const fallback = parseNoticeAttachment(generic, 'x.pdf');
      expect(fallback?.downloadUrl).assertEqual('https://learn.tsinghua.edu.cn/b/wlxt/kj/wlkc_kjxxb/student/downloadFile?fileId=abc123');
      // 参考实现的通用回退分支不推导附件 id
      expect(fallback?.id === undefined).assertTrue();
      expect(parseNoticeAttachment('', 'x.pdf') === undefined).assertTrue();
      expect(parseNoticeAttachment('<div>no link</div>', 'x.pdf') === undefined).assertTrue();
    });

    it('doesNotMisreportOnRealLoginPage', 0, () => {
      // [抓取] 真实站点 HTML 作反例：解析器不得凭巧合命中
      expect(parseNoticeAttachment(REAL_ID_LOGIN_HTML, 'x.pdf') === undefined).assertTrue();
      expect(REAL_ID_LOGIN_HTML.includes('sm2publicKey')).assertTrue();
    });

    it('parseNoticeListSortsAndAssignsCourse', 0, () => {
      const notices: Notice[] = parseNoticeList(
        rowsOf(NOTICE_LIST_RESPONSE_JSON), '2019-2020-1139283212', COURSES, strictPureBase64Decoder);
      expect(notices.length).assertEqual(2);
      expect(notices[0].courseName).assertEqual('通信与网络');
      const unknownCourse: RawNotice = { ggid: 'aa', bt: 't', fbrxm: 'p', fbsj: '2020-01-01 00:00' };
      expect(parseNotice(unknownCourse, 'no-such-course', COURSES, strictPureBase64Decoder).courseName)
        .assertEqual('Unknown Course');
    });
  });
}