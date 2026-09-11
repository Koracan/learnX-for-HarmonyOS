/*
 * Local Test 入口：hvigor 的 test 任务从这里发现用例。
 */

import semesterTest from './Semester.test';
import tokensTest from './Tokens.test';
import logFormatTest from './LogFormat.test';
import i18nTest from './I18n.test';

export default function testsuite() {
  semesterTest();
  tokensTest();
  logFormatTest();
  i18nTest();
}
