/*
 * 取数失败 → 界面文案（features/shell）：把"失败原因串"翻成用户文案的**唯一**一处。
 *
 * 为什么需要它：四个列表页（课程 / 作业 / 文件 / 搜索）各自有一份 errorText()，都只按
 * `message.includes('requiresEnrollment=true')` 判会话失效。设备实测（2026-09-24 01:30 真机日志）
 * 暴露了两个漏判 —— 两个都会把"没网"说成"登录又过期了"：
 *   1. **学期解析那一步断网**：抛的是 `data/remote/Port` 的 NO_RESPONSE_MARKER，
 *      旧文案 `semester resolution failed: current semester request failed: status=0`
 *      被原样贴在横幅上，用户读成"会话问题"（实际原因：手机刚回到前台，DNS 还没就绪）；
 *   2. **会话失效但重登因断网失败**：仓储抛的是
 *      `… requiresEnrollment=true reason=network unreachable …` —— 原因同样是网络。
 * 判据按原因分类，文案**复用既有两条串**（`loh_network_unavailable` / `loh_session_expired`），
 * 不新增文案；两者都不匹配时保持原样显示诊断串（"失败一律显式降级，绝不静默显示空列表"）。
 *
 * 为什么**不**把 `isSessionLostErrorMessage` 也算成 SESSION：那条标记（学期响应不可用）在到达界面
 * 之前一定已经被 `SessionGate` 处理过 —— 要么重登后成功，要么降级成带 `requiresEnrollment=true`
 * 的消息。真让它原样出现在横幅上，说明链路本身出了问题，那种诊断串应当可见（落进 OTHER）。
 *
 * 分类是**纯函数**、取串走注入端口（照 core/i18n 的 `RelativeTimeFormatter` 同一手法），
 * 所以"哪一类失败该说什么"能在 host 单测里钉住（entry/src/test/LoadFailureText.test.ets）。
 */

import { i18nService } from '../../core/i18n/I18n';
import { I18nKey } from '../../core/i18n/I18nKeys';
import { FailReason } from '../../data/auth/AuthTypes';
import { isNoResponseErrorMessage } from '../../data/remote/Port';

/** 一次取数失败的原因类别（界面据此选文案）。 */
export enum LoadFailureKind {
  /** 网络层失败：没收到响应，或重登/请求本身断网。提示"检查网络"。 */
  OFFLINE = 'offline',
  /** 会话失效且需要重新验证（信任过期 / 无凭据 / 服务端拒绝）。 */
  SESSION = 'session',
  /** 其它：原样显示诊断串（站点改版等）。 */
  OTHER = 'other'
}

/** 取串端口（注入是为了 host 单测；设备侧实现见本文件末尾）。 */
export interface LoadFailureTranslator {
  t(key: I18nKey, ...args: Array<string | number>): string;
}

/**
 * 原因分类。
 *
 * **判据顺序有意**：断网优先于会话 —— 降级消息里 `reason=network unreachable` 与
 * `requiresEnrollment=true` 是同时出现的，先判会话就会把"没网"说成"登录已失效"。
 */
export function classifyLoadFailure(message: string): LoadFailureKind {
  if (isNoResponseErrorMessage(message)) {
    return LoadFailureKind.OFFLINE;
  }
  if (message.includes('reason=' + FailReason.NETWORK_UNREACHABLE)) {
    return LoadFailureKind.OFFLINE;
  }
  if (message.includes('requiresEnrollment=true')) {
    return LoadFailureKind.SESSION;
  }
  return LoadFailureKind.OTHER;
}

/**
 * 横幅文案（可注入取串，供单测逐字断言）。
 *
 * @param message 仓储抛出的原因串（`store.errorMessage`）。
 * @param prefixKey 本页的"XX 加载失败：%1$s"键（课程页与搜索页共用 `ui_courses_load_failed`）。
 */
export function loadFailureTextUsing(message: string, prefixKey: I18nKey,
  translator: LoadFailureTranslator): string {
  const kind: LoadFailureKind = classifyLoadFailure(message);
  if (kind === LoadFailureKind.OFFLINE) {
    return translator.t('loh_network_unavailable');
  }
  if (kind === LoadFailureKind.SESSION) {
    return translator.t('loh_session_expired');
  }
  return translator.t(prefixKey, message);
}

/** 设备侧取串：把单例 i18nService 显式适配成端口（避免隐式结构化类型）。 */
class ServiceTranslator implements LoadFailureTranslator {
  t(key: I18nKey, ...args: Array<string | number>): string {
    return i18nService.t(key, ...args);
  }
}

const deviceTranslator: LoadFailureTranslator = new ServiceTranslator();

/** 界面入口：本页错误横幅的文案。 */
export function loadFailureText(message: string, prefixKey: I18nKey): string {
  return loadFailureTextUsing(message, prefixKey, deviceTranslator);
}
