/*
 * 主壳：底部五个 tab（公告 / 作业 / 文件 / 课程 / 设置）。
 *
 * 选型与理由（ticket 03 要求说明）：
 *   - 内容容器用 ArkUI 的 **Tabs + TabContent**：TabContent 的子树在首次显示
 *     后留在组件树上（不因切走而销毁），所以各 tab 的滚动位置天然保留；这正是
 *     “切换后各自保留浏览位置”最省事、最可靠的实现。若改用 Navigation +
 *     NavPathStack 单栈，要么自己实现 tab 切换时保存/恢复滚动偏移，要么每次
 *     重建页面，反而更复杂。
 *   - 每个 tab 将来要有自己的详情栈（公告详情、作业详情…），那时在每个
 *     TabContent 内部各放一个 Navigation + 自己的 NavPathStack 即可（参考实现
 *     也是“每个 tab 一个 stack”）。本 ticket 不预先搭这些空栈，避免写死。
 *   - 底栏自绘（Tabs.barHeight(0) 隐藏系统 tabBar）：这样配色能逐项取主题令牌
 *     （系统 tabBar 用系统品牌色，拿不到 #9A25AE 这类令牌），且 @Prop 驱动的
 *     五个按钮能随 activeIndex / 深浅色 / 语言可靠刷新。
 *
 * 位置保留的取证方式：滚动公告列表 → 切到课程 → 切回公告，截图与无障碍树里
 * 仍是同一批条目。
 */
import { ConfigurationConstant, common } from '@kit.AbilityKit';
import { ThemeTokens, resolveTheme } from '../../ui/theme/Tokens';
import { i18nService } from '../../core/i18n/I18n';
import { Logger } from '../../core/log/Logger';
import { COLOR_MODE_KEY, LOCALE_VERSION_KEY } from '../../entryability/EntryAbility';
import { NoticesPage } from '../notices/NoticesPage';
import { AssignmentsPage } from '../assignments/AssignmentsPage';
import { CoursesPage } from '../courses/CoursesPage';
import { FilesPage } from '../files/FilesPage';
import {
  FORCE_DARK_FOR_EVIDENCE, FORCE_ENGLISH_FOR_EVIDENCE, logEvidenceSwitchState
} from '../notices/repository/NoticeRepositoryProvider';
import { PlaceholderTab } from './PlaceholderTab';
import { AppIcon } from '../../ui/icons/IconCatalog';
import { IconGlyph } from '../../ui/icons/IconGlyph';

const logger: Logger = new Logger('features.shell');

/** 取证用语言标签（应用级 setLanguage，不改设备全局设置）。 */
const EVIDENCE_LOCALE: string = 'en-Latn-US';

/** 底部 tab 序号（公告在前，与参考实现 MainTabScreens 的顺序一致）。 */
export enum ShellTab {
  NOTICES = 0,
  ASSIGNMENTS = 1,
  FILES = 2,
  COURSES = 3,
  SETTINGS = 4
}

/**
 * 底栏单个 tab 按钮。@Prop 是基本类型，切 tab / 切主题 / 切语言都会刷新。
 *
 * ticket 11.5：图标从"自绘的圆形色点"换成**参考实现 tabBarIcon 用的同一批图标**
 * （`App.tsx:617-631` 的 MaterialIcons `notifications` / `event` / `folder` / `apps` / `settings`），
 * 颜色仍按选中态取 `primary` / `outline`（参考实现是 primary / gray）。尺寸令牌与间距**未动**。
 */
@Component
struct ShellTabBarItem {
  @Prop label: string = '';
  @Prop icon: AppIcon = AppIcon.NOTIFICATIONS;
  @Prop active: boolean = false;
  @Prop isDark: boolean = false;
  onTap: () => void = () => {
  };

  private theme(): ThemeTokens {
    return resolveTheme(this.isDark);
  }

  build() {
    Column() {
      IconGlyph({
        icon: this.icon,
        glyphSize: this.theme().sizes.iconMedium,
        color: this.active ? this.theme().colors.primary : this.theme().colors.outline,
        label: this.label
      })
      Text(this.label)
        .fontSize(this.theme().typography.labelMedium.fontSize)
        .fontColor(this.active ? this.theme().colors.primary : this.theme().colors.onSurfaceVariant)
        .maxLines(1)
        .margin({ top: this.theme().sizes.space1 })
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.onTap();
    })
  }
}

@Component
export struct ShellTabs {
  @StorageProp(COLOR_MODE_KEY) colorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageLink(LOCALE_VERSION_KEY) localeVersion: number = 0;
  @State activeIndex: number = ShellTab.NOTICES;

  private tabsController: TabsController = new TabsController();

  private theme(): ThemeTokens {
    return resolveTheme(this.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
  }

  private isDark(): boolean {
    return this.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  }

  private s(resource: Resource): string {
    return i18nService.tKey(resource);
  }

  /**
   * 取宿主上下文：优先 UIContext（推荐接口），拿不到时退回 getContext(this)。
   * aboutToAppear 阶段组件可能尚未挂到 UI 实例上，故取证开关延后一帧执行（见下）。
   */
  private hostContext(): common.Context | null {
    try {
      return this.getUIContext().getHostContext() as common.Context;
    } catch (error) {
      logger.warn('getUIContext().getHostContext() unavailable: ' + (error as Error).message);
    }
    try {
      return getContext(this) as common.Context;
    } catch (error) {
      logger.error('getContext unavailable: ' + (error as Error).message);
    }
    return null;
  }

  /** 取证开关：只作用于本应用（不碰设备全局深色模式 / 语言）。默认全关。 */
  private applyEvidenceOverrides(): void {
    logEvidenceSwitchState();
    if (!FORCE_DARK_FOR_EVIDENCE && !FORCE_ENGLISH_FOR_EVIDENCE) {
      return;
    }
    const context: common.Context | null = this.hostContext();
    if (context === null) {
      logger.error('evidence overrides skipped: no host context');
      return;
    }
    if (FORCE_DARK_FOR_EVIDENCE) {
      context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
      logger.info('force dark for evidence: setColorMode(DARK)');
    }
    if (FORCE_ENGLISH_FOR_EVIDENCE) {
      context.getApplicationContext().setLanguage(EVIDENCE_LOCALE);
      i18nService.bindResourceManager(context.resourceManager, EVIDENCE_LOCALE);
      i18nService.refresh();
      this.localeVersion = Date.now();
      logger.info('force english for evidence: setLanguage(' + EVIDENCE_LOCALE + ')');
    }
  }

  aboutToAppear(): void {
    // 延后一帧：aboutToAppear 时组件可能还没挂到 UI 实例上。
    setTimeout(() => {
      this.applyEvidenceOverrides();
    }, 0);
    logger.info('shell ready: tabs=notices,assignments,files,courses,settings'
      + ' locale=' + i18nService.locale());
  }

  private switchTo(index: number): void {
    if (index === this.activeIndex) {
      return;
    }
    this.activeIndex = index;
    this.tabsController.changeIndex(index);
    logger.info('tab switched: index=' + index.toString());
  }

  private barHeight(): number {
    return this.theme().sizes.controlHeight + this.theme().sizes.space4;
  }

  @Builder
  tabBar() {
    Row() {
      ShellTabBarItem({
        label: this.s($r('app.string.ui_tab_notices')),
        icon: AppIcon.NOTIFICATIONS,
        active: this.activeIndex === ShellTab.NOTICES,
        isDark: this.isDark(),
        onTap: () => {
          this.switchTo(ShellTab.NOTICES);
        }
      })
      ShellTabBarItem({
        label: this.s($r('app.string.loh_assignments')),
        icon: AppIcon.EVENT,
        active: this.activeIndex === ShellTab.ASSIGNMENTS,
        isDark: this.isDark(),
        onTap: () => {
          this.switchTo(ShellTab.ASSIGNMENTS);
        }
      })
      ShellTabBarItem({
        label: this.s($r('app.string.loh_files')),
        icon: AppIcon.FOLDER,
        active: this.activeIndex === ShellTab.FILES,
        isDark: this.isDark(),
        onTap: () => {
          this.switchTo(ShellTab.FILES);
        }
      })
      ShellTabBarItem({
        label: this.s($r('app.string.loh_courses')),
        icon: AppIcon.APPS,
        active: this.activeIndex === ShellTab.COURSES,
        isDark: this.isDark(),
        onTap: () => {
          this.switchTo(ShellTab.COURSES);
        }
      })
      ShellTabBarItem({
        label: this.s($r('app.string.loh_settings')),
        icon: AppIcon.SETTINGS,
        active: this.activeIndex === ShellTab.SETTINGS,
        isDark: this.isDark(),
        onTap: () => {
          this.switchTo(ShellTab.SETTINGS);
        }
      })
    }
    .width('100%')
    .height(this.barHeight())
    .backgroundColor(this.theme().colors.surface)
    .border({ width: { top: this.theme().sizes.borderWidth }, color: this.theme().colors.outlineVariant })
  }

  build() {
    Column() {
      Tabs({ barPosition: BarPosition.End, index: this.activeIndex, controller: this.tabsController }) {
        TabContent() {
          NoticesPage()
        }
        .tabBar(this.s($r('app.string.ui_tab_notices')))

        // 作业 tab（ticket 10）：真实作业列表 + 详情栈。
        TabContent() {
          AssignmentsPage()
        }
        .tabBar(this.s($r('app.string.loh_assignments')))

        // 文件 tab（ticket 11）：真实文件列表 + 详情栈（下载 / 应用内预览 / 分享）+ 文件设置。
        TabContent() {
          FilesPage()
        }
        .tabBar(this.s($r('app.string.loh_files')))

        // 课程 tab（ticket 12）：真实课程列表 + 详情栈 + 学期切换。
        TabContent() {
          CoursesPage()
        }
        .tabBar(this.s($r('app.string.loh_courses')))

        TabContent() {
          PlaceholderTab({
            title: this.s($r('app.string.loh_settings')),
            message: this.s($r('app.string.ui_tab_placeholder')),
            isDark: this.isDark()
          })
        }
        .tabBar(this.s($r('app.string.loh_settings')))
      }
      .barHeight(0)
      .barMode(BarMode.Fixed)
      .scrollable(false)
      .animationDuration(0)
      .layoutWeight(1)
      .width('100%')
      .onChange((index: number) => {
        this.activeIndex = index;
      })

      this.tabBar()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme().colors.background)
  }
}