/*
 * 公告数据源的组装点（composition root）。
 *
 * 界面（features/notices/NoticesPage.ets）只依赖 NoticeRepository 接口，且只从
 * 这里拿实现：ticket 09 换成真实实现 + 快照时，改本文件一行即可，界面不动。
 *
 * 两个 `*_FOR_EVIDENCE` 常量是本 ticket 的取证开关（默认关闭，提交态为 false）：
 *   - MOCK_EMPTY_FOR_EVIDENCE：Mock 返回空集合，用来截“空态”图；
 *   - FORCE_DARK_FOR_EVIDENCE：启动时调用应用级 setColorMode(DARK)，用来截深色图
 *     （不修改设备全局深色模式，只作用于本应用，避免影响并行工作的其他 agent）；
 *   - FORCE_ENGLISH_FOR_EVIDENCE：启动时调用应用级 setLanguage(en-Latn-US)，用来截英文图
 *     （同样不碰设备全局语言设置）；
 *   - SLOW_MOCK_FOR_EVIDENCE：把 Mock 延迟临时调到 5s，稳定截到下拉刷新的 refreshing 帧。
 * ticket 17（设置 + Mock 模式）落地时应把它们换成用户可见的开关。
 */
import { NoticeRepository } from './NoticeRepository';
import { MockNoticeRepository } from './MockNoticeRepository';

/** 取证开关：Mock 返回空集合（空态截图）。提交态 false。 */
export const MOCK_EMPTY_FOR_EVIDENCE: boolean = false;

/** 取证开关：启动时强制深色（深色截图）。提交态 false。 */
export const FORCE_DARK_FOR_EVIDENCE: boolean = false;

/** 取证开关：启动时切应用语言到英文（英文截图）。提交态 false。 */
export const FORCE_ENGLISH_FOR_EVIDENCE: boolean = false;

/** Mock 数据源的人为延迟，让下拉刷新的动效可见（毫秒）。 */
export const MOCK_LATENCY_MILLIS: number = 700;

/** 取证开关：把 Mock 延迟临时调到 5s，用来稳定截到 Refresh 的 refreshing 帧。提交态 false。 */
export const SLOW_MOCK_FOR_EVIDENCE: boolean = false;

/** 取证期的慢速延迟（毫秒）。 */
export const SLOW_MOCK_LATENCY_MILLIS: number = 5000;

/** 当前生效的公告数据源。ticket 09 在这里换成真实实现。 */
export function createNoticeRepository(): NoticeRepository {
  const latency: number = SLOW_MOCK_FOR_EVIDENCE ? SLOW_MOCK_LATENCY_MILLIS : MOCK_LATENCY_MILLIS;
  return new MockNoticeRepository(MOCK_EMPTY_FOR_EVIDENCE, latency);
}
