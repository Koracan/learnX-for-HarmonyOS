/*
 * Local Test 入口：hvigor 的 test 任务从这里发现用例。
 */

import semesterTest from './Semester.test';
import tokensTest from './Tokens.test';
import logFormatTest from './LogFormat.test';
import i18nTest from './I18n.test';
import noticeParserTest from './NoticeParser.test';
import assignmentParserTest from './AssignmentParser.test';
import fileParserTest from './FileParser.test';
import multipartTest from './Multipart.test';
import dataFetchTest from './DataFetch.test';
import noticesTest from './Notices.test';
import noticeDetailTest from './NoticeDetail.test';
import utf8Test from './Utf8.test';

export default function testsuite() {
  semesterTest();
  tokensTest();
  logFormatTest();
  i18nTest();
  noticeParserTest();
  assignmentParserTest();
  fileParserTest();
  multipartTest();
  dataFetchTest();
  noticesTest();
  noticeDetailTest();
  utf8Test();
}