/*
 * 取数失败文案单测（纯逻辑 + 注入取串，无平台依赖）。
 *
 * 起因（设备实测 2026-09-24 01:30 真机日志）：手机驻留后台 3 小时后回到前台，DNS 还没就绪 ——
 * 第一次刷新作业时横幅显示的是**内部诊断**
 * `semester resolution failed: current semester request failed: status=0`，
 * 被读成"登录又过期了"（实际是断网；同一次驻留里会话确实失效，但那是稍后课程页刷新才暴露的）。
 * 这里钉住三类原因各自的文案，以及**判据顺序**：降级消息里
 * `reason=network unreachable` 与 `requiresEnrollment=true` 同时出现，断网必须优先。
 */

import { describe, it, expect } from '@ohos/hypium';
import { I18nKey } from '../main/ets/core/i18n/I18nKeys';
import { FailReason } from '../main/ets/data/auth/AuthTypes';
import { NO_RESPONSE_MARKER } from '../main/ets/data/remote/Port';
import {
  LoadFailureKind, LoadFailureTranslator, classifyLoadFailure, loadFailureTextUsing
} from '../main/ets/features/shell/LoadFailureText';

/** 取串替身：回显键与第一个参数，于是断言可以逐字看到"用了哪条串、带没带诊断"。 */
class FakeTranslator implements LoadFailureTranslator {
  t(key: I18nKey, ...args: Array<string | number>): string {
    return args.length === 0 ? key : key + '|' + String(args[0]);
  }
}

const translator: LoadFailureTranslator = new FakeTranslator();

/** 设备日志里的那条断网消息（学期解析那一步抛出来的，status=0）。 */
const NO_RESPONSE_MESSAGE: string =
  'semester resolution failed: ' + NO_RESPONSE_MARKER + ': status=0';

/** 设备日志里的另一条：会话失效 + 重登也断网（仓储的显式降级串）。 */
const OFFLINE_DEGRADED_MESSAGE: string = 'course refresh degraded: requiresEnrollment=true reason='
  + FailReason.NETWORK_UNREACHABLE + ' reAuth=true diag=reAuth login failed: network unreachable';

/** 会话失效（重登后仍是登录态）：该回登录页。 */
const SESSION_DEGRADED_MESSAGE: string = 'course refresh degraded: requiresEnrollment=true reason='
  + FailReason.NOT_LOGGED_IN + ' reAuth=true diag=still noLogin after reAuth status=403';

export default function loadFailureTextTest() {
  describe('features.shell.LoadFailureText', () => {
    it('callsADeadNetworkADeadNetworkNotASession', 0, () => {
      // 1. 学期解析那一步没收到响应（设备实测的那一条）
      expect(classifyLoadFailure(NO_RESPONSE_MESSAGE)).assertEqual(LoadFailureKind.OFFLINE);
      expect(loadFailureTextUsing(NO_RESPONSE_MESSAGE, 'ui_assignments_load_failed', translator))
        .assertEqual('loh_network_unavailable');
      // 2. 会话失效但重登也断网：消息里 requiresEnrollment=true 与 reason=network unreachable 并存
      expect(classifyLoadFailure(OFFLINE_DEGRADED_MESSAGE)).assertEqual(LoadFailureKind.OFFLINE);
      expect(loadFailureTextUsing(OFFLINE_DEGRADED_MESSAGE, 'ui_courses_load_failed', translator))
        .assertEqual('loh_network_unavailable');
      // 3. 真的会话失效：回登录页那一条
      expect(classifyLoadFailure(SESSION_DEGRADED_MESSAGE)).assertEqual(LoadFailureKind.SESSION);
      expect(loadFailureTextUsing(SESSION_DEGRADED_MESSAGE, 'ui_courses_load_failed', translator))
        .assertEqual('loh_session_expired');
    });

    it('keepsUnexplainedFailuresVisibleWithTheirDiagnostic', 0, () => {
      // 站点改版这类抛错：原样显示诊断串，绝不静默成空列表、也不假装是会话问题
      const shapeFailure: string = 'course list shape changed: expected resultList';
      expect(classifyLoadFailure(shapeFailure)).assertEqual(LoadFailureKind.OTHER);
      expect(loadFailureTextUsing(shapeFailure, 'ui_courses_load_failed', translator))
        .assertEqual('ui_courses_load_failed|' + shapeFailure);

      // 旧文案（没有标记）当时就是**不可分类**的 —— 这正是要在端口层加 NO_RESPONSE_MARKER 的原因：
      // 界面对它只能原样显示，用户读到的是内部诊断。
      const legacy: string = 'semester resolution failed: current semester request failed: status=0';
      expect(classifyLoadFailure(legacy)).assertEqual(LoadFailureKind.OTHER);
      // 站点给了状态码（拿到响应）时保持既有文案，不被断网判据吞掉
      const serverError: string = 'semester resolution failed: current semester request failed: status=403';
      expect(classifyLoadFailure(serverError)).assertEqual(LoadFailureKind.OTHER);
    });
  });
}
