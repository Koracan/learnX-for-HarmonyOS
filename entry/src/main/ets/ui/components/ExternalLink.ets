/*
 * 打开外部链接（ui/components）：参考实现 `Linking.openURL` 的 ArkTS 对应物。
 *
 * **从 `ui/components/HtmlWebView.ets` 原样搬到这里**（设置页需要同一能力：
 * "隐私政策"、帮助页的 GitHub / 邮件链接、关于页的备案号与若干仓库地址）。行为一字未改：
 * `ohos.want.action.viewData` + `entity.system.browsable` + uri，失败只落日志、不抛给调用方。
 *
 * `mailto:` 也走同一条 want：系统里有邮件应用时由它接管，没有时 `startAbility` 失败并被记下来
 * （**不假装打开成功**）。
 */

import { common, Want } from '@kit.AbilityKit';
import { Logger } from '../../core/log/Logger';

const logger: Logger = new Logger('ui.external-link');

/** 用系统浏览器 / 对应应用打开一个 URL。空串直接忽略。 */
export function openExternalUrl(url: string): void {
  if (url.length === 0) {
    return;
  }
  try {
    const want: Want = {
      action: 'ohos.want.action.viewData',
      entities: ['entity.system.browsable'],
      uri: url
    };
    // getContext() 的静态类型是 Context，startAbility 在 UIAbilityContext 上；
    // 组件运行在 UIAbility 里，故这里收窄（拿不到就落回 catch，不抛给调用方）。
    const context: common.UIAbilityContext = getContext() as common.UIAbilityContext;
    context.startAbility(want);
    logger.info('external link opened in system browser: ' + url);
  } catch (error) {
    logger.error('open external url failed: ' + url + ' (' + (error as Error).message + ')');
  }
}
