/*
 * 文件 tab（ticket 11）：文件列表 + 详情栈的根。
 *
 * 对齐参考实现 `screens/Files.tsx` 与 `components/FileCard.tsx`：
 *
 * | 项 | 参考实现 | 这里 |
 * | --- | --- | --- |
 * | 取数 | `getAllFilesForCourses(courseIds)`（:29-32，courseIds 取自已加载的课程） | `FileListStore.refresh()`（自己解析学期 + 取课程列表 + 取文件；见 data/files/FileRepository 的说明） |
 * | 次序 | processor 按上传时间倒序 | `data/remote/FilesFetcher.fetch`（ticket 05 的同一比较器） |
 * | 卡片 | 课程名 / 标题（removeTags）/ 描述 2 行 / `TYPE SIZE` 一行 / 相对时间（:37-78） | 同（验收第 1 条"显示大小与类型"就是那一行） |
 * | 点击 | `navigate('FileDetail', item)` | 推本 tab 的 `ROUTE_FILE_DETAIL`（真身 FileDetailPage） |
 * | 下拉刷新 | `handleRefresh` | 同 |
 *
 * 三种状态都显式呈现，**没有"失败就显示空列表"这条路**（与课程/公告列表同一口径）。
 */

import { ConfigurationConstant } from '@kit.AbilityKit';
import { ThemeTokens, resolveTheme } from '../../ui/theme/Tokens';
import { i18nService } from '../../core/i18n/I18n';
import { getSemesterTextFromId, formatRelativeTo } from '../../core/i18n/DateTimeUtil';
import { COLOR_MODE_KEY, LOCALE_VERSION_KEY } from '../../entryability/EntryAbility';
import { Logger } from '../../core/log/Logger';
import { parseTimestamp } from '../../domain/parse/Text';
import { CourseFile } from '../../domain/model/ContentItem';
import { fileMetaLine } from '../../domain/files/FilePath';
import { removeTags } from '../../domain/render/WebViewTemplate';
import { EmptyState } from '../../ui/components/EmptyState';
import { FileListStore } from './FileListStore';
import { fileRepository } from './repository/FileRepositoryProvider';
import { FileDetailPage } from './FileDetailPage';
import { FileSettingsPage } from './FileSettingsPage';
import { FileSettingsRouteParams, ROUTE_FILE_SETTINGS } from './FileRoutes';
import { FileDetailRouteParams, ROUTE_FILE_DETAIL } from '../notices/NoticeRoutes';

const logger: Logger = new Logger('features.files');

/** 一行文件卡片的渲染参数（文本在构造时算好，避免 build 里做重活）。 */
interface FileRowSpec {
  theme: ThemeTokens;
  courseName: string;
  titleText: string;
  descriptionText: string;
  /** `TYPE SIZE`（验收第 1 条）。 */
  metaText: string;
  timeText: string;
  isNew: boolean;
  newLabel: string;
}

@Component
export struct FilesPage {
  @StorageProp(COLOR_MODE_KEY) colorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageLink(LOCALE_VERSION_KEY) localeVersion: number = 0;
  @State refreshing: boolean = false;

  private store: FileListStore | null = null;
  private stack: NavPathStack = new NavPathStack();

  aboutToAppear(): void {
    const store: FileListStore = new FileListStore(fileRepository());
    this.store = store;
    store.loadOnce();
    logger.info('files page appear');
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

  private semesterText(): string {
    const store: FileListStore | null = this.store;
    if (store === null || store.semesterId.length === 0) {
      return '';
    }
    return getSemesterTextFromId(store.semesterId, i18nService.locale(), i18nService);
  }

  private updatedText(): string {
    const store: FileListStore | null = this.store;
    if (store === null || store.fetchedAtMillis <= 0) {
      return '';
    }
    const relative: string = formatRelativeTo(store.fetchedAtMillis, Date.now(), i18nService.locale());
    return relative.length > 0 ? relative : '';
  }

  private errorText(): string {
    const store: FileListStore | null = this.store;
    const message: string = store === null ? '' : store.errorMessage;
    if (message.includes('requiresEnrollment=true')) {
      return i18nService.t('loh_session_expired');
    }
    return i18nService.t('ui_files_load_failed', message);
  }

  private timeTextOf(file: CourseFile): string {
    const millis: number = parseTimestamp(file.uploadTime);
    if (millis <= 0) {
      return file.uploadTime;
    }
    const relative: string = formatRelativeTo(millis, Date.now(), i18nService.locale());
    return relative.length > 0 ? relative : file.uploadTime;
  }

  /** 列表项 → 详情路由参数（详情页自己算缓存键，见 FileDetailPage.request）。 */
  private paramsFor(file: CourseFile): FileDetailRouteParams {
    const extension: string = file.fileType.length > 0 ? '.' + file.fileType : '';
    return {
      noticeId: file.fileId.length > 0 ? file.fileId : file.id,
      courseName: file.courseName,
      courseTeacherName: file.courseTeacherName,
      title: file.title,
      attachmentName: file.title + extension,
      downloadUrl: file.downloadUrl,
      fileType: file.fileType,
      size: file.size,
      uploadTime: file.uploadTime,
      description: file.description
    };
  }

  private openFile(file: CourseFile): void {
    logger.info('file tapped: id=' + file.id + ' title="' + file.title + '" type=' + file.fileType);
    this.stack.pushPath({ name: ROUTE_FILE_DETAIL, param: this.paramsFor(file) });
  }

  private openSettings(): void {
    const store: FileListStore | null = this.store;
    const params: FileSettingsRouteParams = {
      activeRoot: store === null ? '' : store.semesterId
    };
    this.stack.pushPath({ name: ROUTE_FILE_SETTINGS, param: params });
  }

  private async handlePullRefresh(): Promise<void> {
    this.refreshing = true;
    const store: FileListStore | null = this.store;
    if (store !== null) {
      await store.refresh();
    }
    this.refreshing = false;
  }

  @Builder
  header() {
    Column() {
      Row() {
        Text(this.s($r('app.string.loh_files')))
          .fontSize(this.theme().typography.headlineSmall.fontSize)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.theme().colors.onSurface)
          .layoutWeight(1)
        // 文件设置入口（**本页自己的入口**；全局设置页的入口/外观归 ticket 17）。
        Text(this.s($r('app.string.ui_file_settings_open')))
          .fontSize(this.theme().typography.labelLarge.fontSize)
          .fontColor(this.theme().colors.primary)
          .onClick(() => {
            this.openSettings();
          })
      }
      .width('100%')

      Row() {
        Text(this.s($r('app.string.ui_courses_semester_label')))
          .fontSize(this.theme().typography.labelSmall.fontSize)
          .fontColor(this.theme().colors.onSurfaceVariant)
        Text(this.semesterText())
          .fontSize(this.theme().typography.labelMedium.fontSize)
          .fontColor(this.theme().colors.primary)
          .margin({ left: this.theme().sizes.space1 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .margin({ top: this.theme().sizes.space1 })

      Row() {
        Text(this.updatedText())
          .fontSize(this.theme().typography.labelSmall.fontSize)
          .fontColor(this.theme().colors.onSurfaceVariant)
          .layoutWeight(1)
        Text(this.store === null ? '0' : this.store.files.length.toString())
          .fontSize(this.theme().typography.labelSmall.fontSize)
          .fontColor(this.theme().colors.primary)
      }
      .width('100%')
      .margin({ top: this.theme().sizes.space1 })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({
      left: this.theme().sizes.contentPadding,
      right: this.theme().sizes.contentPadding,
      top: this.theme().sizes.space4,
      bottom: this.theme().sizes.space3
    })
  }

  @Builder
  fileRow(spec: FileRowSpec) {
    Column() {
      Row() {
        Text(spec.courseName)
          .fontSize(spec.theme.typography.labelMedium.fontSize)
          .fontColor(spec.theme.colors.onSurfaceVariant)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        if (spec.isNew) {
          Text('●')
            .fontSize(spec.theme.sizes.iconSmall)
            .fontColor(spec.theme.colors.primary)
            .accessibilityText(spec.newLabel)
        }
      }
      .width('100%')

      Text(spec.titleText)
        .fontSize(spec.theme.typography.titleMedium.fontSize)
        .fontWeight(FontWeight.Medium)
        .fontColor(spec.theme.colors.onSurface)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      if (spec.descriptionText.length > 0) {
        Text(spec.descriptionText)
          .fontSize(spec.theme.typography.bodyMedium.fontSize)
          .fontColor(spec.theme.colors.onSurfaceVariant)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .margin({ top: spec.theme.sizes.space1 })
      }

      Row() {
        // 验收第 1 条：**大小与类型**在同一行里逐字可见。
        Text(spec.metaText)
          .fontSize(spec.theme.typography.labelSmall.fontSize)
          .fontColor(spec.theme.colors.onSurfaceVariant)
          .layoutWeight(1)
        Text(spec.timeText)
          .fontSize(spec.theme.typography.labelSmall.fontSize)
          .fontColor(spec.theme.colors.onSurfaceVariant)
          .margin({ left: spec.theme.sizes.space2 })
      }
      .width('100%')
      .margin({ top: spec.theme.sizes.space1 })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({
      left: spec.theme.sizes.contentPadding,
      right: spec.theme.sizes.contentPadding,
      top: spec.theme.sizes.space3,
      bottom: spec.theme.sizes.space3
    })
    .backgroundColor(spec.theme.colors.surface)
  }

  @Builder
  listBody() {
    Stack() {
      List({ space: 0 }) {
        ForEach(this.store === null ? [] : this.store.files, (item: CourseFile) => {
          ListItem() {
            this.fileRow({
              theme: this.theme(),
              courseName: item.courseName,
              titleText: removeTags(item.title),
              descriptionText: removeTags(item.description),
              metaText: fileMetaLine(item.fileType, item.size),
              timeText: this.timeTextOf(item),
              isNew: item.isNew,
              newLabel: this.s($r('app.string.ui_course_new_files_label'))
            })
          }
          .onClick(() => {
            this.openFile(item);
          })
        }, (item: CourseFile) => 'file|' + item.courseId + '|' + item.id)
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Auto)
      .divider({
        strokeWidth: this.theme().sizes.borderWidth,
        color: this.theme().colors.outlineVariant,
        startMargin: this.theme().sizes.contentPadding,
        endMargin: this.theme().sizes.contentPadding
      })

      if (this.store !== null && this.store.isInitialLoading()) {
        Column() {
          LoadingProgress()
            .width(this.theme().sizes.iconLarge)
            .height(this.theme().sizes.iconLarge)
            .color(this.theme().colors.primary)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.store !== null && this.store.hasError()) {
        Column() {
          Text(this.errorText())
            .fontSize(this.theme().typography.bodyMedium.fontSize)
            .fontColor(this.theme().colors.error)
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .padding(this.theme().sizes.contentPadding)
      } else if (this.store !== null && this.store.isEmpty()) {
        EmptyState({
          message: this.s($r('app.string.ui_files_empty')),
          isDark: this.isDark()
        })
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  destinationBuilder(name: string, param: object) {
    if (name === ROUTE_FILE_DETAIL) {
      NavDestination() {
        FileDetailPage({ params: param as FileDetailRouteParams, stack: this.stack })
      }
      .hideTitleBar(true)
    } else if (name === ROUTE_FILE_SETTINGS) {
      NavDestination() {
        FileSettingsPage({ params: param as FileSettingsRouteParams, stack: this.stack })
      }
      .hideTitleBar(true)
    }
  }

  build() {
    Navigation(this.stack) {
      Column() {
        this.header()
        Refresh({ refreshing: $$this.refreshing, promptText: this.s($r('app.string.loh_refresh')) }) {
          this.listBody()
        }
        .layoutWeight(1)
        .width('100%')
        .onRefreshing(() => {
          this.handlePullRefresh();
        })
        .onStateChange((state: RefreshStatus) => {
          logger.info('files pull refresh state: ' + state.toString());
        })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.theme().colors.background)
    }
    .navDestination(this.destinationBuilder)
    .hideTitleBar(true)
    .mode(NavigationMode.Stack)
    .width('100%')
    .height('100%')
  }
}
