/*
 * FileDetail 的占位页（ticket 04 范围内）。
 *
 * 参考实现 `navigation.push('FileDetail', {...})`（NoticeDetail.tsx:63-73）把附件交给
 * 文件详情页；本工程的文件详情页属于 ticket 07（files）。ticket 04 的验收第 4 条只要求
 * "附件可点、且行为明确"，所以这里：
 *
 *   - **照参考实现组装并接收全部导航参数**（`FileDetailRouteParams`），参数在这里
 *     逐项显示，于是"附件点击确实带上了正确参数"是可截图、可 layout dump 验证的；
 *   - 真正的文件详情（下载/预览/分享）留给 ticket 07，页面文案明确说明这一点，
 *     不假装已实现。
 *
 * 也就是说：这条路由的"导航契约"已交付，"文件详情内容"未交付 —— 见 ticket Comments。
 */
import { ConfigurationConstant } from '@kit.AbilityKit';
import { ThemeTokens, resolveTheme } from '../../ui/theme/Tokens';
import { i18nService } from '../../core/i18n/I18n';
import { COLOR_MODE_KEY } from '../../entryability/EntryAbility';
import { FileDetailRouteParams } from './NoticeRoutes';

/** 一行"字段名：值"。 */
interface DetailFieldSpec {
  theme: ThemeTokens;
  label: string;
  value: string;
}

@Component
export struct FileDetailPlaceholderPage {
  @StorageProp(COLOR_MODE_KEY) colorMode: number = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;

  /** 由 NavDestination 传入的附件参数。 */
  params: FileDetailRouteParams = {
    noticeId: '',
    courseName: '',
    courseTeacherName: '',
    title: '',
    attachmentName: '',
    downloadUrl: '',
    fileType: ''
  };

  private theme(): ThemeTokens {
    return resolveTheme(this.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
  }

  private s(resource: Resource): string {
    return i18nService.tKey(resource);
  }

  @Builder
  field(spec: DetailFieldSpec) {
    Row() {
      Text(spec.label)
        .fontSize(spec.theme.typography.labelMedium.fontSize)
        .fontColor(spec.theme.colors.onSurfaceVariant)
        .width(spec.theme.sizes.controlHeight * 2)
      Text(spec.value)
        .fontSize(spec.theme.typography.bodyMedium.fontSize)
        .fontColor(spec.theme.colors.onSurface)
        .layoutWeight(1)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ top: spec.theme.sizes.space1, bottom: spec.theme.sizes.space1 })
  }

  build() {
    Column() {
      Text(this.s($r('app.string.loh_files')))
        .fontSize(this.theme().typography.headlineSmall.fontSize)
        .fontColor(this.theme().colors.onSurface)
        .width('100%')
        .margin({ bottom: this.theme().sizes.space4 })
      this.field({ theme: this.theme(), label: 'title', value: this.params.title })
      this.field({ theme: this.theme(), label: 'fileType', value: this.params.fileType })
      this.field({ theme: this.theme(), label: 'attachmentName', value: this.params.attachmentName })
      this.field({ theme: this.theme(), label: 'courseName', value: this.params.courseName })
      this.field({ theme: this.theme(), label: 'noticeId', value: this.params.noticeId })
      this.field({ theme: this.theme(), label: 'downloadUrl', value: this.params.downloadUrl })
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
