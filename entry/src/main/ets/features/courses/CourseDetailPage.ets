/*
 * 课程详情页（ticket 12）—— 对齐参考实现 `screens/CourseDetail.tsx`：
 * 三个标签页（公告 / 作业 / 文件），每页只列**本课程**的内容，点一条进对应详情。
 *
 * 与参考实现逐项对照：
 *
 * | 项 | 参考实现 | 这里 |
 * | --- | --- | --- |
 * | 三个标签页与顺序 | `routes = [notices, assignments, files]`（:144-148） | 同 |
 * | 数据来源 | 从全局 state 按 `courseId` 过滤（:161-172） | 从 `CourseListStore` 按 `courseId` 过滤 |
 * | 公告点击 | `navigation.push('NoticeDetail', item)`（:49） | 同（推入**课程 tab 自己的** NavPathStack） |
 * | 作业点击 | `navigation.push('AssignmentDetail', item)`（:85） | 同（详情页真身由 ticket 10 交付，参数就是整个 Assignment） |
 * | 文件点击 | `navigation.push('FileDetail', item)`（:115） | 同（详情页真身在 ticket 11，本轮为占位页） |
 * | 每页下拉刷新 | `getXxxForCourse(courseId)` | 复用课程 tab 的同一次刷新（`store.refresh()`）——本工程一次抓取就含三域 |
 * | 页头标题 = 课程名 | `navigation.setOptions({title: course.name})`（:198-200） | 页头显示课程名 + 教师 |
 *
 * 三处"不移植"：
 *   1. 参考实现用 `InteractionManager` 等转场结束才渲染（:150-155）；ArkUI 由框架管转场，
 *      这里直接渲染（与 ticket 04 的判断一致）；
 *   2. 参考实现每个标签页各发一次"按课程取数"的 action；本工程的一次刷新已经带回三域，
 *      再各发一次会重复请求（3 个标签页 × N 门课），故不复制该行为；
 *   3. 参考实现**没有**空态以外的错误态（取数失败只在 redux 里留 error）；这里保留空态，
 *      错误态放在列表页（课程 tab 的根）显示，避免三个标签页各弹一遍同一句话。
 */
import { ConfigurationConstant } from '@kit.AbilityKit';
import { PLAIN_PALETTE, ThemeTokens, resolveTheme } from '../../ui/theme/Tokens';
import { i18nService } from '../../core/i18n/I18n';
import { formatDateTimeShort, formatRelativeTo } from '../../core/i18n/DateTimeUtil';
import { COLOR_MODE_KEY, LOCALE_VERSION_KEY } from '../../entryability/EntryAbility';
import { Logger } from '../../core/log/Logger';
import { Assignment, CourseFile } from '../../domain/model/ContentItem';
import { removeTags } from '../../domain/render/WebViewTemplate';
import { NoticeRecord } from '../../data/notices/NoticeRepository';
import { EmptyState } from '../../ui/components/EmptyState';
import { AppIcon } from '../../ui/icons/IconCatalog';
import { IconGlyph } from '../../ui/icons/IconGlyph';
import { CourseListStore } from './CourseListStore';
import {
  CourseDetailRouteParams, CourseFileDetailRouteParams, ROUTE_COURSE_FILE_DETAIL
} from './CourseRoutes';
// ticket 10：作业详情的路由与页面收敛在作业那条线（本页只推同一个路由）。
import { ROUTE_ASSIGNMENT_DETAIL } from '../assignments/AssignmentRoutes';
import { ROUTE_NOTICE_DETAIL } from '../notices/NoticeRoutes';

const logger: Logger = new Logger('features.courses.detail');

/** 公告行渲染参数（@Builder 按引用传参）。 */
interface CourseNoticeRowSpec {
  theme: ThemeTokens;
  notice: NoticeRecord;
  titleText: string;
  timeText: string;
}

/** 作业行渲染参数。 */
interface CourseAssignmentRowSpec {
  theme: ThemeTokens;
  assignment: Assignment;
}

/** 文件行渲染参数。 */
interface CourseFileRowSpec {
  theme: ThemeTokens;
  file: CourseFile;
}

@Component
export struct CourseDetailPage {
  @StorageProp(COLOR_MODE_KEY) colorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  @StorageLink(LOCALE_VERSION_KEY) localeVersion: number = 0;
  @State activeIndex: number = 0;

  params: CourseDetailRouteParams = { courseId: '', courseName: '', courseTeacherName: '' };
  store: CourseListStore | null = null;
  stack: NavPathStack | null = null;

  aboutToAppear(): void {
    logger.info('course detail appear: courseId=' + this.params.courseId
      + ' name=' + this.params.courseName);
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

  private notices(): NoticeRecord[] {
    return this.store === null ? [] : this.store.noticesFor(this.params.courseId);
  }

  private assignments(): Assignment[] {
    return this.store === null ? [] : this.store.assignmentsFor(this.params.courseId);
  }

  private files(): CourseFile[] {
    return this.store === null ? [] : this.store.filesFor(this.params.courseId);
  }

  private timeTextOf(notice: NoticeRecord): string {
    const locale: string = i18nService.locale();
    const relative: string = formatRelativeTo(notice.publishTimeMillis, Date.now(), locale);
    if (relative.length > 0) {
      return relative;
    }
    return formatDateTimeShort(notice.publishTimeMillis, locale);
  }

  private openNotice(notice: NoticeRecord): void {
    logger.info('course detail notice tapped: id=' + notice.id);
    if (this.stack !== null) {
      this.stack.pushPath({ name: ROUTE_NOTICE_DETAIL, param: notice });
    }
  }

  private openAssignment(assignment: Assignment): void {
    logger.info('course detail assignment tapped: id=' + assignment.id);
    if (this.stack !== null) {
      // ticket 10：详情页是真身（不再是占位页），参数就是整个 Assignment ——
      // 与参考实现 `navigation.push('AssignmentDetail', item)`（CourseDetail.tsx:85）一致。
      this.stack.pushPath({ name: ROUTE_ASSIGNMENT_DETAIL, param: assignment });
    }
  }

  private openFile(file: CourseFile): void {
    logger.info('course detail file tapped: id=' + file.id);
    const params: CourseFileDetailRouteParams = {
      id: file.id,
      fileId: file.fileId,
      title: file.title,
      courseId: file.courseId,
      courseName: file.courseName,
      courseTeacherName: file.courseTeacherName,
      size: file.size,
      uploadTime: file.uploadTime,
      fileType: file.fileType,
      downloadUrl: file.downloadUrl
    };
    if (this.stack !== null) {
      this.stack.pushPath({ name: ROUTE_COURSE_FILE_DETAIL, param: params });
    }
  }

  /**
   * 页头：返回是图标，占位与公告详情页的返回一致。
   *
   * 点击目标固定 **40vp×40vp**（`sizes.controlHeight`），不小于改动前那行 `labelLarge` 文字
   * （行高约 20–24vp）；`label` 传可读文案，字体未就绪时回退分支直接把它画出来。
   */
  @Builder
  header() {
    Column() {
      Stack() {
        IconGlyph({
          icon: AppIcon.ARROW_BACK, glyphSize: this.theme().sizes.iconMedium,
          color: this.theme().colors.primary, label: this.s($r('app.string.loh_back'))
        })
      }
      .width(this.theme().sizes.controlHeight)
      .height(this.theme().sizes.controlHeight)
      .onClick(() => {
        if (this.stack !== null) {
          this.stack.pop();
        }
      })
      Text(this.params.courseName)
        .fontSize(this.theme().typography.headlineSmall.fontSize)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.theme().colors.onSurface)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .margin({ top: this.theme().sizes.space2 })
      if (this.params.courseTeacherName.length > 0) {
        Text(this.params.courseTeacherName)
          .fontSize(this.theme().typography.labelMedium.fontSize)
          .fontColor(this.theme().colors.onSurfaceVariant)
          .width('100%')
      }
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
  noticeRow(spec: CourseNoticeRowSpec) {
    Column() {
      Text(spec.titleText)
        .fontSize(spec.theme.typography.titleMedium.fontSize)
        .fontColor(spec.theme.colors.onSurface)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Row() {
        Text(spec.notice.publisher)
          .fontSize(spec.theme.typography.labelSmall.fontSize)
          .fontColor(spec.theme.colors.onSurfaceVariant)
        Text(spec.timeText)
          .fontSize(spec.theme.typography.labelSmall.fontSize)
          .fontColor(spec.theme.colors.onSurfaceVariant)
          .margin({ left: spec.theme.sizes.space2 })
        Blank()
        if (!spec.notice.hasRead) {
          Column()
            .width(spec.theme.sizes.space2)
            .height(spec.theme.sizes.space2)
            .borderRadius(spec.theme.sizes.space2 / 2)
            .backgroundColor(PLAIN_PALETTE.blue500)
        }
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
    .onClick(() => {
      this.openNotice(spec.notice);
    })
  }

  @Builder
  assignmentRow(spec: CourseAssignmentRowSpec) {
    Column() {
      Text(spec.assignment.title)
        .fontSize(spec.theme.typography.titleMedium.fontSize)
        .fontColor(spec.theme.colors.onSurface)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Row() {
        Text(spec.assignment.deadline)
          .fontSize(spec.theme.typography.labelSmall.fontSize)
          .fontColor(spec.theme.colors.onSurfaceVariant)
        if (spec.assignment.submitted) {
          // 参考实现这条走的是 AssignmentCard（已提交 = MCI `check`）。
          // 字形不再自带可读文字，所以必须给 accessibilityText（原来是 U+2713 字符本身被读出来）。
          IconGlyph({
            icon: AppIcon.CHECK, glyphSize: spec.theme.sizes.iconSmall,
            color: spec.theme.colors.primary,
            label: this.s($r('app.string.ui_assignment_submitted_mark_label')),
            marginLeft: spec.theme.sizes.space2
          })
        }
        Blank()
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
    .onClick(() => {
      this.openAssignment(spec.assignment);
    })
  }

  @Builder
  fileRow(spec: CourseFileRowSpec) {
    Column() {
      Text(spec.file.title)
        .fontSize(spec.theme.typography.titleMedium.fontSize)
        .fontColor(spec.theme.colors.onSurface)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Row() {
        Text(spec.file.size)
          .fontSize(spec.theme.typography.labelSmall.fontSize)
          .fontColor(spec.theme.colors.onSurfaceVariant)
        Text(spec.file.uploadTime)
          .fontSize(spec.theme.typography.labelSmall.fontSize)
          .fontColor(spec.theme.colors.onSurfaceVariant)
          .margin({ left: spec.theme.sizes.space2 })
        Blank()
        if (spec.file.isNew) {
          // 参考实现 FileCard.tsx:55-62：MCI `checkbox-blank-circle`（blue500）。
          IconGlyph({
            icon: AppIcon.CHECKBOX_BLANK_CIRCLE, glyphSize: spec.theme.sizes.iconSmall,
            color: PLAIN_PALETTE.blue500,
            label: this.s($r('app.string.ui_course_new_files_label'))
          })
        }
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
    .onClick(() => {
      this.openFile(spec.file);
    })
  }

  @Builder
  noticesTab() {
    Stack() {
      List({ space: 0 }) {
        ForEach(this.notices(), (item: NoticeRecord) => {
          ListItem() {
            this.noticeRow({
              theme: this.theme(),
              notice: item,
              titleText: removeTags(item.title),
              timeText: this.timeTextOf(item)
            })
          }
        }, (item: NoticeRecord) => 'notice|' + item.id)
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

      if (this.notices().length === 0) {
        EmptyState({ message: this.s($r('app.string.loh_empty')), isDark: this.isDark() })
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  assignmentsTab() {
    Stack() {
      List({ space: 0 }) {
        ForEach(this.assignments(), (item: Assignment) => {
          ListItem() {
            this.assignmentRow({ theme: this.theme(), assignment: item })
          }
        }, (item: Assignment) => 'assignment|' + item.id)
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

      if (this.assignments().length === 0) {
        EmptyState({ message: this.s($r('app.string.loh_empty')), isDark: this.isDark() })
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  filesTab() {
    Stack() {
      List({ space: 0 }) {
        ForEach(this.files(), (item: CourseFile) => {
          ListItem() {
            this.fileRow({ theme: this.theme(), file: item })
          }
        }, (item: CourseFile) => 'file|' + item.id)
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

      if (this.files().length === 0) {
        EmptyState({ message: this.s($r('app.string.loh_empty')), isDark: this.isDark() })
      }
    }
    .width('100%')
    .height('100%')
  }

  build() {
    Column() {
      this.header()
      Tabs({ barPosition: BarPosition.Start, index: this.activeIndex }) {
        TabContent() {
          this.noticesTab()
        }
        .tabBar(this.s($r('app.string.loh_notices')))

        TabContent() {
          this.assignmentsTab()
        }
        .tabBar(this.s($r('app.string.loh_assignments')))

        TabContent() {
          this.filesTab()
        }
        .tabBar(this.s($r('app.string.loh_files')))
      }
      .barMode(BarMode.Fixed)
      .layoutWeight(1)
      .width('100%')
      .onChange((index: number) => {
        this.activeIndex = index;
        logger.info('course detail tab changed: index=' + index.toString()
          + ' courseId=' + this.params.courseId);
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme().colors.background)
  }
}