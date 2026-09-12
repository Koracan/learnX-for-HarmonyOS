/*
 * 课程详情里"文件"标签页的**占位详情页**（ticket 12）。
 *
 * 【ticket 12 → ticket 10 的交接】ticket 12 在这里放了**两个**占位页：
 * 作业详情（`AssignmentDetailPlaceholderPage`）与文件详情（`CourseFileDetailPlaceholderPage`）。
 * ticket 10 已把作业那个换成真身（`features/assignments/AssignmentDetailPage.ets`，
 * 路由名与参数也一并移到 `features/assignments/AssignmentRoutes.ets`），
 * **本文件从此只剩文件详情这一个占位页**。
 *
 * 为什么还是占位：参考实现的 `CourseDetail.tsx:115` 会 `navigation.push('FileDetail')`，
 * 而文件详情的真身（下载 / 预览 / 分享）归 **ticket 11**。这里：
 *
 *   - **照参考实现的导航契约把参数收全**（`CourseFileDetailRouteParams`），并逐项显示 ——
 *     于是"点进去的是这一条"是 layout dump 与截图可核对的；
 *   - 页面明确写出"该详情页将在后续迭代中实现"（`ui_tab_placeholder`），不假装已实现。
 *
 * 这与 ticket 04 的 `FileDetailPlaceholderPage` 是同一处置方式（同一套判断）。
 */
import { ConfigurationConstant } from '@kit.AbilityKit';
import { ThemeTokens, resolveTheme } from '../../ui/theme/Tokens';
import { i18nService } from '../../core/i18n/I18n';
import { COLOR_MODE_KEY } from '../../entryability/EntryAbility';
import { CourseFileDetailRouteParams } from './CourseRoutes';

/** 一行"字段名：值"。 */
interface CourseFieldSpec {
  theme: ThemeTokens;
  label: string;
  value: string;
}

@Builder
function courseFieldRow(spec: CourseFieldSpec) {
  Row() {
    Text(spec.label)
      .fontSize(spec.theme.typography.labelMedium.fontSize)
      .fontColor(spec.theme.colors.onSurfaceVariant)
      .width(spec.theme.sizes.controlHeight * 2.6)
    Text(spec.value)
      .fontSize(spec.theme.typography.bodyMedium.fontSize)
      .fontColor(spec.theme.colors.onSurface)
      .layoutWeight(1)
      .maxLines(3)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
  }
  .width('100%')
  .alignItems(VerticalAlign.Top)
  .padding({ top: spec.theme.sizes.space1, bottom: spec.theme.sizes.space1 })
}

/** 课程文件详情占位页（真身：ticket 11）。 */
@Component
export struct CourseFileDetailPlaceholderPage {
  @StorageProp(COLOR_MODE_KEY) colorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  params: CourseFileDetailRouteParams = {
    id: '', fileId: '', title: '', courseId: '', courseName: '', courseTeacherName: '',
    size: '', uploadTime: '', fileType: '', downloadUrl: ''
  };
  stack: NavPathStack | null = null;

  private theme(): ThemeTokens {
    return resolveTheme(this.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
  }

  private s(resource: Resource): string {
    return i18nService.tKey(resource);
  }

  build() {
    Column() {
      Row() {
        Text(this.s($r('app.string.loh_back')))
          .fontSize(this.theme().typography.labelLarge.fontSize)
          .fontColor(this.theme().colors.primary)
          .onClick(() => {
            if (this.stack !== null) {
              this.stack.pop();
            }
          })
      }
      .width('100%')
      .margin({ bottom: this.theme().sizes.space3 })

      Text(this.s($r('app.string.loh_files')))
        .fontSize(this.theme().typography.headlineSmall.fontSize)
        .fontColor(this.theme().colors.onSurface)
        .width('100%')

      courseFieldRow({ theme: this.theme(), label: 'title', value: this.params.title })
      courseFieldRow({ theme: this.theme(), label: 'courseName', value: this.params.courseName })
      courseFieldRow({ theme: this.theme(), label: 'id', value: this.params.id })
      courseFieldRow({ theme: this.theme(), label: 'fileId', value: this.params.fileId })
      courseFieldRow({ theme: this.theme(), label: 'size', value: this.params.size })
      courseFieldRow({ theme: this.theme(), label: 'uploadTime', value: this.params.uploadTime })
      courseFieldRow({ theme: this.theme(), label: 'fileType', value: this.params.fileType })
      courseFieldRow({ theme: this.theme(), label: 'downloadUrl', value: this.params.downloadUrl })

      Text(this.s($r('app.string.ui_tab_placeholder')))
        .fontSize(this.theme().typography.bodyMedium.fontSize)
        .fontColor(this.theme().colors.onSurfaceVariant)
        .width('100%')
        .margin({ top: this.theme().sizes.space5 })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .height('100%')
    .padding(this.theme().sizes.contentPadding)
    .backgroundColor(this.theme().colors.background)
  }
}
