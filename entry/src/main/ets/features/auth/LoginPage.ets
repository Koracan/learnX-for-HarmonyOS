/*
 * 登录页（features/auth）：收集账号 + 口令，然后打开网页完成设备登记。
 *
 * 对应参考实现 src/screens/Login.tsx（账号/口令 + 提示对话框 → SSO 页）：
 *   - 两个输入框 + 「登录」按钮；空值先拦（loh_missing_username / loh_missing_password）；
 *   - 点「登录」先弹**说明对话框**（loh_sso / loh_sso_note），确认后才打开网页——
 *     参考实现就是这么做的，用户需要知道"接下来要在网页里完成短信验证"；
 *   - 网页登记容器以**覆盖层**的形式盖在本页上（不另起路由）：于是"用户中途放弃/验证失败
 *     回到登录页"就是一次状态回落，不涉及导航栈，也就没有"半登记状态"可残留（验收第 4 条）。
 *
 * 参考实现里"记住我/mock 账号"那一支（Login.tsx:43-46 的 DUMMY_USERNAME 离线模式）不在本
 * ticket：Mock 数据源策略归 ticket 17。
 */

import { ConfigurationConstant } from '@kit.AbilityKit';
import { ThemeTokens, resolveTheme } from '../../ui/theme/Tokens';
import { i18nService } from '../../core/i18n/I18n';
import { Logger } from '../../core/log/Logger';
import { COLOR_MODE_KEY, LOCALE_VERSION_KEY } from '../../entryability/EntryAbility';
import { EnrollmentDomValues } from '../../domain/auth/EnrollmentScript';
import { AuthFailure, AuthStore, authStore } from './AuthStore';
import { EnrollmentWebView } from './EnrollmentWebView';

const logger: Logger = new Logger('features.login');

@Component
export struct LoginPage {
  @StorageProp(COLOR_MODE_KEY) colorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageLink(LOCALE_VERSION_KEY) localeVersion: number = 0;

  @State username: string = '';
  @State password: string = '';
  /** 空值/失败的即时提示（i18n 文案）。 */
  @State hint: string = '';

  private store: AuthStore = authStore;

  private theme(): ThemeTokens {
    return resolveTheme(this.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
  }

  private s(resource: Resource): string {
    return i18nService.tKey(resource);
  }

  /** 登记失败后回到本页时的提示（由 AuthStore.failure 决定）。 */
  private failureHint(): string {
    if (this.store.failure === AuthFailure.SESSION || this.store.failure === AuthFailure.PERSIST) {
      return this.s($r('app.string.loh_login_failed'));
    }
    if (this.store.failure === AuthFailure.INJECTION) {
      return this.s($r('app.string.loh_sso_failed'));
    }
    return '';
  }

  private handleLoginTap(): void {
    const account: string = this.username.trim();
    if (account.length === 0) {
      this.hint = this.s($r('app.string.loh_missing_username'));
      return;
    }
    if (this.password.length === 0) {
      this.hint = this.s($r('app.string.loh_missing_password'));
      return;
    }
    this.hint = '';
    // 参考实现 Login.tsx:48-64：先弹说明，用户确认后才进入网页登记。
    AlertDialog.show({
      title: this.s($r('app.string.loh_sso')),
      message: this.s($r('app.string.loh_sso_note')),
      autoCancel: true,
      primaryButton: {
        value: this.s($r('app.string.loh_cancel')),
        action: () => {
          logger.info('login: user cancelled the sso note dialog');
        }
      },
      secondaryButton: {
        value: this.s($r('app.string.loh_ok')),
        action: () => {
          this.startEnrollment();
        }
      }
    });
  }

  private startEnrollment(): void {
    const started: boolean = this.store.beginEnrollment(this.username.trim(), this.password);
    if (!started) {
      this.hint = this.s($r('app.string.loh_sso_failed'));
    }
  }

  @Builder
  form() {
    Column() {
      Text('learnOH')
        .fontSize(this.theme().typography.headlineSmall.fontSize)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.theme().colors.onSurface)
        .margin({ bottom: this.theme().sizes.space4 })

      TextInput({ text: this.username, placeholder: this.s($r('app.string.loh_username_or_id')) })
        .type(InputType.Normal)
        .maxLines(1)
        .width('100%')
        .margin({ bottom: this.theme().sizes.space3 })
        .onChange((value: string) => {
          this.username = value;
        })

      TextInput({ text: this.password, placeholder: this.s($r('app.string.loh_password')) })
        .type(InputType.Password)
        .maxLines(1)
        .width('100%')
        .margin({ bottom: this.theme().sizes.space3 })
        .onChange((value: string) => {
          this.password = value;
        })

      Button(this.s($r('app.string.loh_login')))
        .width('100%')
        .backgroundColor(this.theme().colors.primary)
        .fontColor(this.theme().colors.onPrimary)
        .onClick(() => {
          this.handleLoginTap();
        })

      if (this.hint.length > 0 || this.failureHint().length > 0) {
        Text(this.hint.length > 0 ? this.hint : this.failureHint())
          .fontSize(this.theme().typography.labelMedium.fontSize)
          .fontColor(this.theme().colors.error)
          .margin({ top: this.theme().sizes.space3 })
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ left: this.theme().sizes.contentPadding, right: this.theme().sizes.contentPadding })
    .backgroundColor(this.theme().colors.background)
  }

  build() {
    Stack() {
      this.form()
      if (this.store.isEnrolling()) {
        EnrollmentWebView({
          username: this.store.enrollmentUsername(),
          password: this.store.enrollmentPassword(),
          fingerPrint: this.store.enrollmentFingerPrint(),
          deviceName: this.store.enrollmentDeviceName(),
          onSucceeded: (dom: EnrollmentDomValues, cookieHeader: string): void => {
            logger.info('enrollment succeeded in web container; completing enrollment');
            this.store.completeEnrollment(dom, cookieHeader);
          },
          onCancelled: (): void => {
            logger.info('enrollment cancelled in web container');
            this.store.cancelEnrollment();
          },
          onFailed: (reason: string): void => {
            logger.error('enrollment failed in web container: ' + reason);
            this.store.cancelEnrollment();
          },
          onStatus: (text: string): void => {
            this.store.noteStatus(text);
          }
        })
      }
    }
    .width('100%')
    .height('100%')
  }
}
