/*
 * 登录页（features/auth）：收集账号 + 口令，然后打开网页完成设备登记。
 *
 * 对应参考实现 src/screens/Login.tsx（账号/口令 + 提示对话框 → SSO 页）：
 *   - 两个输入框 + 「登录」按钮；空值先拦（loh_missing_username / loh_missing_password）；
 *   - 点「登录」先弹**说明对话框**（loh_sso / loh_sso_note），确认后才打开网页——
 *     参考实现就是这么做的，用户需要知道"接下来要在网页里完成短信验证"；
 *   - 网页登记容器以**覆盖层**的形式盖在本页上（不另起路由）：于是"用户中途放弃/验证失败
 *     回到登录页"就是一次状态回落，不涉及导航栈，也就没有"半登记状态"可残留。
 *
 * 参考实现里"mock 账号"那一支（`Login.tsx:43-46`：`username === DUMMY_USERNAME &&
 * password === DUMMY_PASSWORD` ⇒ `dispatch(setMockStore())`）**已落地**：
 * 见下面 `handleLoginTap` 里 `isMockCredentials` 那一段 —— 它**先于** SSO 说明对话框，
 * 因此 mock 登录既不打开网页、也不发任何请求。
 */

import { ConfigurationConstant } from '@kit.AbilityKit';
import { ThemeTokens, resolveTheme } from '../../ui/theme/Tokens';
import { i18nService } from '../../core/i18n/I18n';
import { Logger } from '../../core/log/Logger';
import { COLOR_MODE_KEY, LOCALE_VERSION_KEY } from '../../entryability/EntryAbility';
import { EnrollmentDomValues } from '../../domain/auth/EnrollmentScript';
import { AuthFailure, AuthStore, authStore } from './AuthStore';
import { EnrollmentWebView } from './EnrollmentWebView';
import { isMockCredentials } from '../mock/MockMode';

const logger: Logger = new Logger('features.login');

/**
 * 登录表单的最大宽度（vp）。
 *
 * **出处：参考实现 `screens/Login.tsx:127-130`** —— `inputs: { width: '100%', maxWidth: 480 }`，
 * 外层 `root` 是 `alignItems: 'center'`。在平板上实测过（模拟器 MatePad Pro 13，
 * 1440vp 横向）本页**整屏拉伸**（两个输入框与按钮各 2848px / 2880px ⇒ 约 1424vp），
 * 是移植时漏掉了这条约束，不是有意偏离 —— 所以这里是**补回参考实现的行为**。
 * 单栏（电话）本来就是 100% < 480vp，加上限后观感不变。
 */
const LOGIN_FORM_MAX_WIDTH_VP: number = 480;

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

  /**
   * 回到本页时的提示（由 AuthStore.failure 决定）。
   *
   * 要求"说明需要重新验证"，所以静默重登失败（REAUTH）与断网（OFFLINE）
   * 各有**自己的**文案，不能笼统地说"登录失败"——用户需要知道该做什么（重新验证 / 检查网络）。
   */
  private failureHint(): string {
    if (this.store.failure === AuthFailure.REAUTH) {
      return this.s($r('app.string.loh_session_expired'));
    }
    if (this.store.failure === AuthFailure.OFFLINE) {
      return this.s($r('app.string.loh_network_unavailable'));
    }
    if (this.store.failure === AuthFailure.SESSION || this.store.failure === AuthFailure.PERSIST) {
      return this.s($r('app.string.loh_login_failed'));
    }
    if (this.store.failure === AuthFailure.INJECTION) {
      return this.s($r('app.string.loh_sso_failed'));
    }
    return '';
  }

  /**
   * 是否有"重试静默重登"这一入口：只有"有持久化凭据但这次没登上"（REAUTH / OFFLINE）才显示。
   * 首次安装（无凭据）没有可重试的东西。
   */
  private canRetryRestore(): boolean {
    return this.store.failure === AuthFailure.REAUTH || this.store.failure === AuthFailure.OFFLINE;
  }

  /** 提示区文本：重试进行中 > 本地校验提示 > 失败提示。 */
  private messageText(): string {
    if (this.store.isRestoring()) {
      return this.s($r('app.string.loh_logging_in'));
    }
    if (this.hint.length > 0) {
      return this.hint;
    }
    return this.failureHint();
  }

  /** 用户点"重试"：只触发**一次**重登，不做静默循环（Q25）。 */
  private handleRetryTap(): void {
    this.hint = '';
    logger.info('login: user tapped retry for the silent re-auth');
    this.store.retryRestore();
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
    // 参考实现 Login.tsx:43-46：**guest/guest 直接进 Mock 模式**，不发请求、不弹 SSO 说明。
    // 参考实现的两个输入框都在 onChangeText 里做了 trim（Login.tsx:82,95），这里按同一口径比较。
    if (isMockCredentials(account, this.password.trim())) {
      logger.info('login: mock credentials detected -> mock mode (no request, no webview)');
      this.store.loginAsMockUser();
      return;
    }
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
      // 表单本体：宽度上限 480vp（参考实现 Login.tsx:127-130 的 inputs.maxWidth），居中。
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
          .enabled(!this.store.isRestoring())
          .backgroundColor(this.theme().colors.primary)
          .fontColor(this.theme().colors.onPrimary)
          .onClick(() => {
            this.handleLoginTap();
          })

        if (this.canRetryRestore()) {
          Button(this.s($r('app.string.loh_retry')))
            .width('100%')
            .backgroundColor(this.theme().colors.secondaryContainer)
            .fontColor(this.theme().colors.onSecondaryContainer)
            .margin({ top: this.theme().sizes.space2 })
            .onClick(() => {
              this.handleRetryTap();
            })
        }

        if (this.messageText().length > 0) {
          Text(this.messageText())
            .fontSize(this.theme().typography.labelMedium.fontSize)
            .fontColor(this.theme().colors.error)
            .margin({ top: this.theme().sizes.space3 })
        }
      }
      .width('100%')
      .constraintSize({ maxWidth: LOGIN_FORM_MAX_WIDTH_VP })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
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
