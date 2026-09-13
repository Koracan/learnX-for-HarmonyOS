/*
 * 「交给系统打开方式」的纯规则 —— **零平台依赖**（见 scripts/check-domain-purity.mjs）。
 *
 * 参考实现里这个动作在 `reference/learnOH-old/src/screens/FileDetail.tsx:84-90`：`handleOpen`
 * 调 `helpers/fs.ts:171-179` 的 `openFile(path)`，后者是 react-native-file-viewer 的
 * `FileViewer.open(path, { showOpenWithDialog: true })`。语义是**把已落盘的路径交给系统，
 * 由系统给出"用什么打开"**。它既不是 `Linking.openURL`（那条路接受 URL，接不住应用沙箱里的
 * 本地路径），也不是 `Share.share`（参考实现的分享是另一个按钮、另一个函数 `shareFile`）。
 *
 * 这里只放两件**没有设备也能钉住输入→输出**的事：按钮的可用判定、want 的参数构造。
 * 真正调用平台 `startAbility` 的那一步在 features/files/FileDetailPage 里（那一步离开设备测不了）。
 */

/** 打开本地文件的 want action：与打开外链同一条 action。 */
export const EXTERNAL_OPEN_ACTION: string = 'ohos.want.action.viewData';

/**
 * 读权限授予位（平台 `wantConstant.Flags.FLAG_AUTH_READ_URI_PERMISSION` 的数值）。
 * 文件在应用沙箱里，不显式授予读权限时接收方拿到 uri 也读不出字节。
 */
export const EXTERNAL_OPEN_READ_FLAG: number = 0x00000001;

/** 「交给系统打开方式」的参数（纯数据；构造平台 Want 并调用由调用方做）。 */
export interface ExternalOpenIntent {
  action: string;
  uri: string;
  entities: string[];
  type: string;
  flags: number;
}

/** 文件是否真的落在本地：空串、只有空白、undefined 都算"没有可交给系统的文件"。 */
export function hasLocalCopy(localPath: string | undefined): boolean {
  if (localPath === undefined || localPath === null) {
    return false;
  }
  return localPath.trim().length > 0;
}

/**
 * 「外跳」按钮是否可用。对齐参考实现的 `disabled={error || !path}`（FileDetail.tsx:116,121）：
 * **下载成功且文件已落盘**才可点。
 */
export function canOpenExternally(downloadSucceeded: boolean, localPath: string | undefined): boolean {
  return downloadSucceeded && hasLocalCopy(localPath);
}

/**
 * 构造交给系统的 want 参数。
 *
 * `uri` 与 `type`（UTD）由调用方先算好 —— 前者要平台按路径转义中文与空格，后者来自平台的
 * 类型描述符表；这里只决定三件事：用哪条 action、要不要带浏览器标记、带哪个权限位。
 *
 * **不带 `entity.system.browsable`**：那是"交给浏览器"的标记，带上它会把隐式匹配收窄到浏览器，
 * 而这里要的是"任何能读这个类型的应用"。
 *
 * `type` 为空串时表示"算不出类型"：调用方**不要**把它放进 Want，隐式匹配一个空 type
 * 等于匹配到任意类型。判定留给调用方，这里如实把空串交出去。
 */
export function externalOpenIntent(uri: string, utd: string | undefined): ExternalOpenIntent {
  const normalizedType: string = utd === undefined || utd === null ? '' : utd.trim();
  return {
    action: EXTERNAL_OPEN_ACTION,
    uri: uri,
    entities: [],
    type: normalizedType,
    flags: EXTERNAL_OPEN_READ_FLAG
  };
}
