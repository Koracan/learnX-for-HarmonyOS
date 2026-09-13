/*
 * 设置 tab（settings）—— 参考实现 `screens/Settings.tsx`（133 行）的移植，
 * 并挂上 5 个子页（沉浸式 / 学期选择 / 文件设置 / 帮助 / 关于）。
 *
 * ## 逐行对照（顺序、图标、行为都照抄）
 *
 * | # | 参考实现 `Settings.tsx` | 图标（MaterialIcons） | 行为 | 这里 |
 * | --- | --- | --- | --- | --- |
 * | 1 | 用户信息（`name ?? username ?? 'learnX'` + `department`） | —（头像） | 不可点 | `userCell` |
 * | 2 | 退出登录 | `person-remove` | 确认框 → logout + 清 cookie + 清 store | `logoutCell` |
 * | 3 | 沉浸式模式（**mock 用户不显示**） | `fullscreen` | 进子页 | `immersiveCell` |
 * | 4 | 学期选择 | `loop` | 进子页 | `semesterCell`（复用学期切换页） |
 * | 5 | 文件设置 | `rule-folder` | 进子页 | `fileSettingsCell`（复用文件设置页） |
 * | 6 | 隐私政策 | `policy` | **外链** | `privacyCell`（URL 逐字取自 `:101-105`） |
 * | 7 | 帮助与反馈 | `help` | 进子页 | `helpCell` |
 * | 8 | 关于 | `copyright` | 进子页 | `aboutCell` |
 *
 * `marginTop: 16` 的分组（`:76,84,97`）逐条保留：进子页的导航与参考实现的
 * `handlePush`（`:27-35`）同义 —— 有右栏就进右栏、否则压本 tab 的主栈
 * （本工程的对应物是分栏，见 features/shell/SplitView.ets 的 pushDetailFromMaster）。
 *
 * ## 两处**增补**（参考实现没有）
 *
 *   1. **「导出日志」一行**（图标 `description`）：core/log/LogBuffer.ets 把
 *      `exportLogs()` 的调用方明确留给「settings 切片的「导出日志」」，本工程
 *      也列了它。带 Toast 反馈（`ui_exported` / `ui_export_failed`）；
 *      **导出的文件落在哪要看得见**：成功时 Toast 与列表下方那一行都给出
 *      `LogExportResult.path` 的**完整路径**（Toast 几秒就没了，留在屏幕上的那一行才是
 *      用户回头能查到的地方），失败分支仍只说原因（`ui_export_failed`，**不显示路径**）。
 *   2. **Mock 模式自证行**（只在 mock 用户下出现，见 mockBanner）：要求
 *      「不发起真实网络请求」**可证明**，而计数必须打在**消费点**上 ——
 *      这一行显示的就是 data/remote/NetworkAudit 的实时计数（两个 http 出口共用同一个计数器）。
 */

import { ConfigurationConstant, common } from '@kit.AbilityKit';
import { ThemeTokens, resolveTheme } from '../../ui/theme/Tokens';
import { i18nService } from '../../core/i18n/I18n';
import { COLOR_MODE_KEY, LOCALE_VERSION_KEY } from '../../entryability/EntryAbility';
import { Logger } from '../../core/log/Logger';
import { LogExportResult, exportLogs } from '../../core/log/LogBuffer';
import { networkAttemptCount } from '../../data/remote/NetworkAudit';
import { MOCK_USER_DEPARTMENT, MOCK_USER_NAME } from '../../data/mock/MockData';
import { TableCell, TableCellType } from '../../ui/components/TableCell';
import { ToastController, ToastOverlay } from '../../ui/components/Toast';
import { AppIcon } from '../../ui/icons/IconCatalog';
import { openExternalUrl } from '../../ui/components/ExternalLink';
import { EmptyState } from '../../ui/components/EmptyState';
import { AuthStore, authStore } from '../auth/AuthStore';
import { isMockMode } from '../mock/MockMode';
import { CourseListStore } from '../courses/CourseListStore';
import { courseListStore } from '../courses/CourseListStoreProvider';
import { SemesterSelectionPage } from '../courses/SemesterSelectionPage';
import { SemesterSelectionRouteParams, ROUTE_SEMESTER_SELECTION } from '../courses/CourseRoutes';
import { FileSettingsPage } from '../files/FileSettingsPage';
import { FileSettingsRouteParams, ROUTE_FILE_SETTINGS } from '../files/FileRoutes';
import { ImmersiveSettingsPage } from './ImmersiveSettingsPage';
import { AboutPage } from './AboutPage';
import { HelpPage } from './HelpPage';
import { ROUTE_ABOUT, ROUTE_HELP, ROUTE_IMMERSIVE_SETTINGS, SettingsPageParams } from './SettingsRoutes';
import {
  SPLIT_VIEW_ACTIVE_KEY, SPLIT_VIEW_DIVIDER_WIDTH, SPLIT_VIEW_MASTER_HIDDEN_KEY,
  SPLIT_VIEW_MASTER_WIDTH, migrateDetailRoutesBack, migrateDetailRoutesInto, pushDetailFromMaster
} from '../shell/SplitView';

const logger: Logger = new Logger('features.settings');

/** 隐私政策外链（**逐字**取自参考实现 Settings.tsx:101-105）。 */
const PRIVACY_POLICY_URL: string =
  'https://agreement-drcn.hispace.dbankcloud.cn/index.html?lang=zh&agreementId=1864655084378428992';

/** 用户信息行的兜底显示名（参考实现 Settings.tsx:63-64 的 ?? 'learnX'）。 */
const DEFAULT_ACCOUNT_LABEL: string = 'learnX';

@Component
export struct SettingsPage {
  @StorageProp(COLOR_MODE_KEY) colorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageLink(LOCALE_VERSION_KEY) localeVersion: number = 0;

  private auth: AuthStore = authStore;
  private toast: ToastController = new ToastController();
  /** 主栈（单栏时子页压在这里，也就是左栏）。 */
  private stack: NavPathStack = new NavPathStack();
  /** 右栏（详情）的栈。 */
  private detailStack: NavPathStack = new NavPathStack();
  @StorageProp(SPLIT_VIEW_ACTIVE_KEY) @Watch('onSplitViewChanged') splitActive: boolean = false;
  @StorageProp(SPLIT_VIEW_MASTER_HIDDEN_KEY) masterHidden: boolean = false;
  /** 主栏当前高亮的那一项（= 右栏正在显示的那一个子页）。 */
  @State selectedId: string = '';
  /** 学期选择子页用的课程 store：**只在第一次点进去时创建**（避免开设置页就发一轮取数）。 */
  private courseStore: CourseListStore | null = null;
  /** 最近一次**成功**导出的结果（含完整落盘路径）；空串 = 还没导出过。失败时不写它。 */
  @State exportedSummary: string = '';
  /**
   * 学期切换在途（由学期页回调设置）：在途时消费掉返回手势。
   *
   * 与课程入口（CoursesPage 的 ROUTE_SEMESTER_SELECTION）**行为一致**：切换要跑 5–9 s，
   * 在途时若允许返回，页面会先 pop，编排仍在后台跑完，成功/失败提示落在已经销毁的页面上
   * ——用户看不到结果。两个入口都是学期页的宿主，都得拦。
   */
  private semesterSwitchInFlight: boolean = false;

  aboutToAppear(): void {
    logger.info('settings page appear: ' + this.describeAccount());
  }

  private theme(): ThemeTokens {
    return resolveTheme(this.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
  }

  private isDark(): boolean {
    return this.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  }

  private s(resource: Resource): string {
    return i18nService.tKey(resource);
  }

  private hostContext(): common.Context | null {
    try {
      return this.getUIContext().getHostContext() as common.Context;
    } catch (error) {
      logger.error('settings page: no host context (' + (error as Error).message + ')');
      return null;
    }
  }

  /** 是否 mock 用户（参考实现 Settings.tsx:25 的 username === env.DUMMY_USERNAME）。 */
  private mock(): boolean {
    return isMockMode();
  }

  /** 自证串（账号 + mock 状态 + 网络请求计数）。 */
  private describeAccount(): string {
    return 'settings account: label=' + (this.auth.accountLabel.length > 0
      ? this.auth.accountLabel : DEFAULT_ACCOUNT_LABEL)
      + ' mock=' + this.mock().toString()
      + ' networkAttempts=' + networkAttemptCount().toString();
  }

  /** 用户信息行的主文案：mock 用户显示样例姓名，其余显示账号名（参考实现的 name ?? username）。 */
  private userPrimary(): string {
    if (this.mock()) {
      return MOCK_USER_NAME;
    }
    return this.auth.accountLabel.length > 0 ? this.auth.accountLabel : DEFAULT_ACCOUNT_LABEL;
  }

  /** 用户信息行的副文案（参考实现的 userInfo.department ?? undefined）。 */
  private userSecondary(): string {
    return this.mock() ? MOCK_USER_DEPARTMENT : '';
  }

  /* ------------------------------------------------------------------ *
   * 退出登录（参考实现 Settings.tsx:37-57）
   * ------------------------------------------------------------------ */

  private handleLogout(): void {
    logger.info('logout tapped: showing the confirmation dialog');
    AlertDialog.show({
      title: this.s($r('app.string.loh_logout')),
      message: this.s($r('app.string.loh_logout_confirmation')),
      autoCancel: true,
      primaryButton: {
        value: this.s($r('app.string.loh_cancel')),
        action: () => {
          logger.info('logout cancelled by user');
        }
      },
      secondaryButton: {
        value: this.s($r('app.string.loh_ok')),
        action: () => {
          this.confirmLogout();
        }
      },
      cancel: () => {
        logger.info('logout dialog dismissed');
      }
    });
  }

  private async confirmLogout(): Promise<void> {
    await this.auth.logout();
    logger.info('logout applied: ' + this.describeAccount());
  }

  /* ------------------------------------------------------------------ *
   * 子页导航（参考实现 handlePush，:27-35）
   * ------------------------------------------------------------------ */

  private pushSettingsPage(name: string): void {
    const params: SettingsPageParams = { source: 'settings' };
    logger.info('settings push: route=' + name + ' split=' + this.splitActive.toString());
    this.selectedId = name;
    pushDetailFromMaster(this.stack, this.detailStack, this.splitActive, name, params);
  }

  private openSemesterSelection(): void {
    if (this.courseStore === null) {
      this.courseStore = courseListStore();
    }
    const store: CourseListStore = this.courseStore;
    const params: SemesterSelectionRouteParams = { activeSemesterId: '' };
    this.selectedId = ROUTE_SEMESTER_SELECTION;
    pushDetailFromMaster(this.stack, this.detailStack, this.splitActive,
      ROUTE_SEMESTER_SELECTION, params);
    // **不阻塞导航**：先压栈再取数，学期列表填充后由 @Trace 自动刷新（学期 store 是 @ObservedV2）。
    store.loadOnce();
    logger.info('semester selection opened from settings: split=' + this.splitActive.toString());
  }

  private openFileSettings(): void {
    const params: FileSettingsRouteParams = { activeRoot: '' };
    this.selectedId = ROUTE_FILE_SETTINGS;
    pushDetailFromMaster(this.stack, this.detailStack, this.splitActive, ROUTE_FILE_SETTINGS, params);
  }

  /* ------------------------------------------------------------------ *
   * 隐私政策（外链）与导出日志（增补）
   * ------------------------------------------------------------------ */

  private handlePrivacyPolicy(): void {
    logger.info('privacy policy tapped: opening external url=' + PRIVACY_POLICY_URL);
    openExternalUrl(PRIVACY_POLICY_URL);
  }

  private handleExportLogs(): void {
    const context: common.Context | null = this.hostContext();
    if (context === null) {
      this.toast.show(i18nService.t('ui_export_failed', 'no host context'), '', null);
      return;
    }
    try {
      const result: LogExportResult = exportLogs(context);
      logger.info('logs exported: path=' + result.path
        + ' records=' + result.recordCount.toString()
        + ' bytes=' + result.byteLength.toString());
      // 同一份文案两处消费（Toast + 列表下方那一行），只格式化一次 ⇒ 屏幕上的路径
      // 与上面 hilog 里那条 path= 必然逐字一致。
      const summary: string = i18nService.t('ui_exported', result.recordCount,
        result.byteLength, result.path);
      this.exportedSummary = summary;
      this.toast.show(summary, '', null);
    } catch (error) {
      const message: string = (error as Error).message;
      logger.error('log export failed: ' + message);
      // 失败时清掉上一次的成功结果，免得旧路径被读成"这次也导出成功了"。
      this.exportedSummary = '';
      this.toast.show(i18nService.t('ui_export_failed', message), '', null);
    }
  }

  /** 分栏开关翻转（消费点自证；口径与四个 tab 页一致）。 */
  onSplitViewChanged(): void {
    if (this.splitActive) {
      AppStorage.setOrCreate(SPLIT_VIEW_MASTER_HIDDEN_KEY, false);
      const moved: number = migrateDetailRoutesInto(this.stack, this.detailStack);
      logger.info('split view enter: tab=settings moved=' + moved.toString()
        + ' masterRoutes=' + this.stack.getAllPathName().length.toString()
        + ' detailRoutes=' + this.detailStack.getAllPathName().length.toString());
    } else {
      const moved: number = migrateDetailRoutesBack(this.detailStack, this.stack);
      logger.info('split view exit: tab=settings moved=' + moved.toString()
        + ' masterRoutes=' + this.stack.getAllPathName().length.toString()
        + ' detailRoutes=' + this.detailStack.getAllPathName().length.toString());
    }
  }

  private masterPaneWidth(): Length {
    if (!this.splitActive) {
      return '100%';
    }
    return this.masterHidden ? 0 : SPLIT_VIEW_MASTER_WIDTH;
  }

  /* ------------------------------------------------------------------ *
   * 视图
   * ------------------------------------------------------------------ */

  @Builder
  header() {
    Column() {
      Text(this.s($r('app.string.loh_settings')))
        .fontSize(this.theme().typography.headlineSmall.fontSize)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.theme().colors.onSurface)
        .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({
      left: this.theme().sizes.contentPadding,
      right: this.theme().sizes.contentPadding,
      top: this.theme().sizes.space4,
      bottom: this.theme().sizes.space2
    })
  }

  /**
   * Mock 模式自证行（**只在 mock 用户下出现**）。
   *
   * 计数来自 data/remote/NetworkAudit —— 它由两个真实 http 出口（HttpClient / HttpDownloadPort）
   * 共同维护，所以「界面可用 + 计数为 0」是同一张截图里可核的。
   */
  @Builder
  mockBanner() {
    Text(i18nService.t('ui_mock_mode_active', networkAttemptCount()))
      .fontSize(this.theme().typography.labelMedium.fontSize)
      .fontColor(this.theme().colors.primary)
      .width('100%')
      .padding({
        left: this.theme().sizes.contentPadding,
        right: this.theme().sizes.contentPadding,
        top: this.theme().sizes.space2,
        bottom: this.theme().sizes.space2
      })
      .backgroundColor(this.theme().colors.surfaceVariant)
      .accessibilityText(i18nService.t('ui_mock_mode_active', networkAttemptCount()))
  }

  @Builder
  settingsList() {
    Scroll() {
      Column() {
        // 1. 用户信息（不可点）
        TableCell({
          primaryText: this.userPrimary(),
          secondaryText: this.userSecondary(),
          showIcon: false,
          showAvatar: true,
          cellType: TableCellType.NONE,
          isDark: this.isDark()
        })
        if (this.mock()) {
          this.mockBanner()
        }

        // 2. 退出登录（确认框）
        TableCell({
          icon: AppIcon.PERSON_REMOVE,
          primaryText: this.s($r('app.string.loh_logout')),
          cellType: TableCellType.NONE,
          isDark: this.isDark(),
          onPress: (): void => {
            this.handleLogout();
          }
        })

        // 3. 沉浸式模式（**mock 用户不显示**，参考实现 Settings.tsx:74-82）
        if (!this.mock()) {
          TableCell({
            icon: AppIcon.FULLSCREEN,
            primaryText: this.s($r('app.string.loh_immersive_mode')),
            cellType: TableCellType.ARROW,
            isDark: this.isDark(),
            marginTop: 16,
            onPress: (): void => {
              this.pushSettingsPage(ROUTE_IMMERSIVE_SETTINGS);
            }
          })
        }

        // 4. 学期选择（复用学期切换页）
        TableCell({
          icon: AppIcon.LOOP,
          primaryText: this.s($r('app.string.loh_semester_selection')),
          cellType: TableCellType.ARROW,
          isDark: this.isDark(),
          marginTop: 16,
          onPress: (): void => {
            this.openSemesterSelection();
          }
        })

        // 5. 文件设置（复用文件设置页）
        TableCell({
          icon: AppIcon.RULE_FOLDER,
          primaryText: this.s($r('app.string.loh_file_settings')),
          cellType: TableCellType.ARROW,
          isDark: this.isDark(),
          onPress: (): void => {
            this.openFileSettings();
          }
        })

        // 6. 隐私政策（外链）
        TableCell({
          icon: AppIcon.POLICY,
          primaryText: this.s($r('app.string.loh_privacy_policy')),
          cellType: TableCellType.ARROW,
          isDark: this.isDark(),
          marginTop: 16,
          onPress: (): void => {
            this.handlePrivacyPolicy();
          }
        })

        // 7. 帮助与反馈
        TableCell({
          icon: AppIcon.HELP,
          primaryText: this.s($r('app.string.loh_help_and_feedback')),
          cellType: TableCellType.ARROW,
          isDark: this.isDark(),
          onPress: (): void => {
            this.pushSettingsPage(ROUTE_HELP);
          }
        })

        // 8. 关于
        TableCell({
          icon: AppIcon.COPYRIGHT,
          primaryText: this.s($r('app.string.loh_about')),
          cellType: TableCellType.ARROW,
          isDark: this.isDark(),
          onPress: (): void => {
            this.pushSettingsPage(ROUTE_ABOUT);
          }
        })

        // 9. 导出日志（**本工程增补**，见文件头）
        TableCell({
          icon: AppIcon.DESCRIPTION,
          primaryText: i18nService.t('ui_export_logs'),
          cellType: TableCellType.NONE,
          isDark: this.isDark(),
          marginTop: 16,
          onPress: (): void => {
            this.handleExportLogs();
          }
        })
        // 导出成功后把**确切落盘路径**留在屏幕上（Toast 会自己消失）。
        if (this.exportedSummary.length > 0) {
          Text(this.exportedSummary)
            .fontSize(this.theme().typography.bodySmall.fontSize)
            .fontColor(this.theme().colors.onSurfaceVariant)
            .width('100%')
            .padding({
              left: this.theme().sizes.contentPadding,
              right: this.theme().sizes.contentPadding,
              bottom: this.theme().sizes.space3
            })
            .accessibilityText(this.exportedSummary)
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .layoutWeight(1)
    .align(Alignment.Top)
    .scrollBar(BarState.Auto)
  }

  /** 左栏内容 = 设置列表。 */
  @Builder
  masterPane() {
    Stack() {
      Column() {
        this.header()
        this.settingsList()
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.theme().colors.background)

      ToastOverlay({ controller: this.toast, isDark: this.isDark() })
    }
    .width('100%')
    .height('100%')
  }

  /** 右栏的栈根：还没选中子页时的空态（对应参考实现 DetailStack 的 EmptyDetail）。 */
  @Builder
  detailPane() {
    Column() {
      EmptyState({ message: this.s($r('app.string.loh_empty')), isDark: this.isDark() })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme().colors.background)
  }

  /** 子页路由表（两个导航容器共用；stack 决定返回落到哪个栈）。 */
  @Builder
  routeTo(name: string, param: object, stack: NavPathStack) {
    if (name === ROUTE_IMMERSIVE_SETTINGS) {
      NavDestination() {
        ImmersiveSettingsPage({ stack: stack })
      }
      .hideTitleBar(true)
    } else if (name === ROUTE_ABOUT) {
      NavDestination() {
        AboutPage({ stack: stack })
      }
      .hideTitleBar(true)
    } else if (name === ROUTE_HELP) {
      NavDestination() {
        HelpPage({ stack: stack })
      }
      .hideTitleBar(true)
    } else if (name === ROUTE_SEMESTER_SELECTION) {
      NavDestination() {
        SemesterSelectionPage({
          store: this.courseStore,
          stack: stack,
          onSwitchInFlight: (inFlight: boolean) => {
            this.semesterSwitchInFlight = inFlight;
          }
        })
      }
      .hideTitleBar(true)
      // 切换在途时**不允许返回**：返回 true = 本页消费了这次返回，系统不再弹栈。
      // routeTo 被 masterDestination 与 detailDestination **共用**，所以单栏（主栈）与
      // 分栏（右栏 detailStack）两条路径都拦得住。
      .onBackPressed((): boolean => this.semesterSwitchInFlight)
    } else if (name === ROUTE_FILE_SETTINGS) {
      NavDestination() {
        FileSettingsPage({ params: param as FileSettingsRouteParams, stack: stack })
      }
      .hideTitleBar(true)
    }
  }

  @Builder
  masterDestination(name: string, param: object) {
    this.routeTo(name, param, this.stack)
  }

  @Builder
  detailDestination(name: string, param: object) {
    this.routeTo(name, param, this.detailStack)
  }

  build() {
    Row() {
      Column() {
        Navigation(this.stack) {
          this.masterPane()
        }
        .navDestination(this.masterDestination)
        .hideTitleBar(true)
        .mode(NavigationMode.Stack)
        .width('100%')
        .height('100%')
      }
      .width(this.masterPaneWidth())
      .height('100%')

      Divider()
        .vertical(true)
        .strokeWidth(SPLIT_VIEW_DIVIDER_WIDTH)
        .color(this.theme().colors.outlineVariant)
        .height('100%')
        .visibility(this.splitActive ? Visibility.Visible : Visibility.None)

      if (this.splitActive) {
        Column() {
          Navigation(this.detailStack) {
            this.detailPane()
          }
          .navDestination(this.detailDestination)
          .hideTitleBar(true)
          .mode(NavigationMode.Stack)
          .width('100%')
          .height('100%')
          // 右栏 NavDestination 的进入/退出转场会画到本 Navigation 的边界之外（盖住左栏一截），
          // 就地裁剪：动画只允许出现在右栏自己的范围内。
          .clip(true)
        }
        .layoutWeight(1)
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
  }
}
