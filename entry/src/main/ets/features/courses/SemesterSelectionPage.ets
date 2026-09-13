/*
 * 学期切换页 —— 对齐参考实现 `screens/SemesterSelection.tsx`：
 * 列出可选学期（最新在前），当前学期带**与参考实现同源的** check 图标，点一条即切换。
 *
 * 与参考实现的三处差异（都已写明）：
 *   1. **位置**：参考实现把它放在"设置"栈里（`SettingsStackParams.SemesterSelection`），
 *      本工程的交付物把它与课程放在一起（课程 tab 头部点学期名进入）。
 *   2. **切换是一次编排**：点一条 → 进入"切换中"（加载遮罩，期间不可重复点击、**不可返回**）
 *      → 等课程 / 公告 / 文件三条取数路径全部落地 → 给成功 / 部分失败 / 失败提示。
 *      **不自动返回**：本页留在栈顶，由用户自己按返回（账号所有者点名的行为）。
 *   3. **脚本入口**：参考实现只能靠界面点；本工程另有
 *      `aa start --ps lohSemester <id>` 与构建期常量（见 data/courses/SemesterOverride.ets），
 *      因为作业与提交需要在无界面交互的情况下切到 2025-2026 春季学期取真实作业。
 *      该覆盖**优先于**界面选择。
 *
 * 学期集合接口不可用时（`semestersAvailable=false`）**不假装完整**：页面顶部显式说明，
 * 列表退化为"站点当前学期 + 实际生效学期"。
 */
import { ConfigurationConstant } from '@kit.AbilityKit';
import { ThemeTokens, resolveTheme } from '../../ui/theme/Tokens';
import { i18nService } from '../../core/i18n/I18n';
import { getSemesterTextFromId } from '../../core/i18n/DateTimeUtil';
import { COLOR_MODE_KEY, LOCALE_VERSION_KEY } from '../../entryability/EntryAbility';
import { Logger } from '../../core/log/Logger';
import { CourseListStore } from './CourseListStore';
import { SwitchResult, switchSemester } from './SemesterSwitch';
import { ToastController, ToastOverlay, resolveToastMillis } from '../../ui/components/Toast';
import { AppIcon } from '../../ui/icons/IconCatalog';
import { IconGlyph } from '../../ui/icons/IconGlyph';

const logger: Logger = new Logger('features.courses.semesters');

@Component
export struct SemesterSelectionPage {
  @StorageProp(COLOR_MODE_KEY) colorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageLink(LOCALE_VERSION_KEY) localeVersion: number = 0;
  @State refreshing: boolean = false;
  /** 切换在途：加载遮罩据此显示，行点击与返回据此失效。 */
  @State switching: boolean = false;
  /** 切换的目标学期（遮罩上显示"正在切换到 …"）。 */
  @State switchingTo: string = '';

  store: CourseListStore | null = null;
  stack: NavPathStack | null = null;
  /** 通知宿主（CoursesPage）"切换在途"，由它消费系统返回手势。 */
  onSwitchInFlight: (inFlight: boolean) => void = () => {};

  private toast: ToastController = new ToastController();

  private theme(): ThemeTokens {
    return resolveTheme(this.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
  }

  private isDark(): boolean {
    return this.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  }

  private s(resource: Resource): string {
    return i18nService.tKey(resource);
  }

  private semesterIds(): string[] {
    return this.store === null ? [] : this.store.semesters;
  }

  /**
   * 哪一行打勾：切换在途时以**正在应用的选择**为准，否则用快照里的实际生效值。
   * 直接读两个 @Trace 字段（不绕包装函数），保证勾选标记随选择同步移动，
   * 而不是等整轮取数跑完才动。
   */
  private activeSemesterId(): string {
    const store: CourseListStore | null = this.store;
    if (store === null) {
      return '';
    }
    return store.pendingSemesterId.length > 0 ? store.pendingSemesterId : store.semesterId;
  }

  private listAvailable(): boolean {
    return this.store === null ? false : this.store.semestersAvailable;
  }

  private semesterText(semesterId: string): string {
    return getSemesterTextFromId(semesterId, i18nService.locale(), i18nService);
  }

  /**
   * 点一行 = 一次编排：加载遮罩 → 等全部域落地 → 结果提示。
   *
   * **不 pop**：本页留在栈顶（账号所有者点名）。在途时重复点击被忽略，
   * 返回手势由宿主页的 `onBackPressed` 消费（见 CoursesPage 的 ROUTE_SEMESTER_SELECTION）。
   */
  private async select(semesterId: string): Promise<void> {
    const store: CourseListStore | null = this.store;
    logger.info('semester row tapped: ' + semesterId + ' switching=' + this.switching.toString());
    if (store === null) {
      logger.error('semester row tapped but the store is missing');
      return;
    }
    if (this.switching) {
      // 遮罩期间不可重复点击：否则会叠出第二轮编排，提示会互相覆盖。
      logger.warn('semester row tapped while a switch is in flight, ignored: ' + semesterId);
      return;
    }
    this.switching = true;
    this.switchingTo = semesterId;
    this.onSwitchInFlight(true);
    let result: SwitchResult | null = null;
    try {
      result = await switchSemester(semesterId);
    } catch (error) {
      // 编排自身不该抛（逐域已 allSettled）；真抛了也要如实说出来，不假装切换成功。
      const message: string = (error as Error).message;
      logger.error('semester switch orchestration failed: ' + message);
      this.toast.show(i18nService.t('ui_semester_switch_failed',
        this.semesterText(semesterId), message), '', null);
    } finally {
      this.switching = false;
      this.switchingTo = '';
      this.onSwitchInFlight(false);
    }
    if (result === null) {
      return;
    }
    // 消费点自证：把**实际生效**的提示时长打进 hilog（取证覆盖是否生效不看源码行号）。
    logger.info('semester switch toast: millis=' + resolveToastMillis(0).toString());
    this.toast.show(this.resultMessage(result), '', null);
    logger.info('semester switch result presented: target=' + semesterId
      + ' result=' + result.kind
      + ' message=' + this.resultMessage(result));
  }

  /**
   * 结果 → 提示文案。
   *   全部成功 → 成功提示（带上目标学期）；
   *   部分失败 → 说清哪个域失败 + 第一条原因要点；
   *   全部失败 → 失败提示 + 原因要点。
   * **绝不假装切换成功**。
   */
  private resultMessage(result: SwitchResult): string {
    const target: string = this.semesterText(result.targetSemesterId);
    if (result.isSuccess()) {
      return i18nService.t('ui_semester_switch_succeeded', target);
    }
    let labels: string = '';
    const failed: string[] = result.failedDomains();
    for (let i = 0; i < failed.length; i++) {
      labels = labels.length === 0 ? this.domainText(failed[i])
        : labels + ' / ' + this.domainText(failed[i]);
    }
    if (result.kind === 'partial') {
      return i18nService.t('ui_semester_switch_partial', target, labels, result.firstReason());
    }
    return i18nService.t('ui_semester_switch_failed', target, result.firstReason());
  }

  /** 失败域的界面标签（域 → 资源键）。 */
  private domainText(domain: string): string {
    if (domain === 'courses') {
      return this.s($r('app.string.loh_courses'));
    }
    if (domain === 'notices') {
      return this.s($r('app.string.ui_tab_notices'));
    }
    if (domain === 'files') {
      return this.s($r('app.string.loh_files'));
    }
    return domain;
  }

  private async handlePullRefresh(): Promise<void> {
    const store: CourseListStore | null = this.store;
    if (store === null) {
      return;
    }
    this.refreshing = true;
    await store.refresh();
    this.refreshing = false;
  }

  /**
   * 页头：返回图标与标题**同一行**（标题不再另占一行）。
   *
   * 图标是图标闭集里既有的返回箭头，外框固定 40vp×40vp（点击区不小于改动前那行 labelLarge
   * 文字，行高只有约 20–24vp）；`label` 传可读文案，字体未就绪时回退分支直接把它画出来。
   * 切换在途时返回入口**失效**（同 onBackPressed 的去抖）。
   */
  @Builder
  header() {
    Column() {
      Row() {
        Stack() {
          IconGlyph({
            icon: AppIcon.ARROW_BACK, glyphSize: this.theme().sizes.iconMedium,
            color: this.theme().colors.primary, label: this.s($r('app.string.loh_back'))
          })
        }
        .width(this.theme().sizes.controlHeight)
        .height(this.theme().sizes.controlHeight)
        .onClick(() => {
          if (this.switching) {
            return;
          }
          if (this.stack !== null) {
            this.stack.pop();
          }
        })
        Text(this.s($r('app.string.loh_semester_selection')))
          .fontSize(this.theme().typography.headlineSmall.fontSize)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.theme().colors.onSurface)
          .layoutWeight(1)
          .margin({ left: this.theme().sizes.space3 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (!this.listAvailable()) {
        Text(this.s($r('app.string.ui_course_semester_list_unavailable')))
          .fontSize(this.theme().typography.labelSmall.fontSize)
          .fontColor(this.theme().colors.error)
          .width('100%')
          .margin({ top: this.theme().sizes.space1 })
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({
      left: this.theme().sizes.contentPadding,
      right: this.theme().sizes.contentPadding,
      top: this.theme().sizes.space3,
      bottom: this.theme().sizes.space2
    })
  }

  @Builder
  semesterRow(semesterId: string) {
    Row() {
      Text(this.semesterText(semesterId))
        .fontSize(this.theme().typography.bodyLarge.fontSize)
        .fontColor(this.theme().colors.onSurface)
        .layoutWeight(1)
      if (semesterId === this.activeSemesterId()) {
        // 参考实现 SemesterSelection.tsx:60,69：选中项 `iconName='check'`（MCI `check`）。
        // 语义挪进图标的 accessibilityText，行本身的无障碍文本不再拼 U+2713 字符。
        IconGlyph({
          icon: AppIcon.CHECK, glyphSize: this.theme().sizes.iconSmall,
          color: this.theme().colors.primary,
          label: this.s($r('app.string.ui_courses_semester_label'))
        })
      }
    }
    .width('100%')
    .height(this.theme().sizes.listItemMinHeight)
    .padding({ left: this.theme().sizes.contentPadding, right: this.theme().sizes.contentPadding })
    .backgroundColor(this.theme().colors.surface)
    .accessibilityText(this.semesterText(semesterId))
    .onClick(() => {
      this.select(semesterId);
    })
  }

  /**
   * 切换中的加载遮罩：**全屏拦截点击**（遮罩本身吃掉触摸），
   * 显示旋转指示器 + "正在切换到 <学期>"。提示会出现在它之上（见 build 的层序）。
   */
  @Builder
  switchingOverlay() {
    Column() {
      Column() {
        LoadingProgress()
          .width(this.theme().sizes.iconLarge)
          .height(this.theme().sizes.iconLarge)
          .color(this.theme().colors.primary)
        Text(this.s($r('app.string.ui_semester_switching')))
          .fontSize(this.theme().typography.bodyMedium.fontSize)
          .fontColor(this.theme().colors.onSurface)
          .margin({ top: this.theme().sizes.space3 })
        Text(this.semesterText(this.switchingTo))
          .fontSize(this.theme().typography.labelMedium.fontSize)
          .fontColor(this.theme().colors.onSurfaceVariant)
          .margin({ top: this.theme().sizes.space1 })
      }
      .padding(this.theme().sizes.contentPadding)
      .backgroundColor(this.theme().colors.surface)
      .borderRadius(this.theme().sizes.space2)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#66000000')
    // 默认命中测试即拦截：遮罩期间点到的是遮罩，不是下面的学期行。
  }

  build() {
    Stack() {
      Column() {
        this.header()
        Refresh({ refreshing: $$this.refreshing, promptText: this.s($r('app.string.loh_refresh')) }) {
          List({ space: 0 }) {
            ForEach(this.semesterIds(), (semesterId: string) => {
              ListItem() {
                this.semesterRow(semesterId)
              }
            }, (semesterId: string) => semesterId + '|' + this.activeSemesterId())
          }
          .width('100%')
          .height('100%')
          .divider({
            strokeWidth: this.theme().sizes.borderWidth,
            color: this.theme().colors.outlineVariant,
            startMargin: this.theme().sizes.contentPadding,
            endMargin: this.theme().sizes.contentPadding
          })
        }
        .layoutWeight(1)
        .width('100%')
        .onRefreshing(() => {
          this.handlePullRefresh();
        })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.theme().colors.background)

      if (this.switching) {
        this.switchingOverlay()
      }
      // 提示画在遮罩之上：切换刚结束那一帧里，结果提示不能被遮罩盖住。
      ToastOverlay({ controller: this.toast, isDark: this.isDark() })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme().colors.background)
  }
}
