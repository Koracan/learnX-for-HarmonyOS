/*
 * Web 容器所需外部资产的读取端口（rawfile → 字符串）。
 *
 * 参考实现用 @preval 在**构建期**把 katex/darkreader 内联成字符串
 * （reference/learnOH-old/src/helpers/preval/*.preval.js，合计约 630 KB）。
 * ArkTS 没有 preval，照搬会让 630 KB 变成 .ets 字符串字面量；因此改为放进
 * `entry/src/main/resources/rawfile/webview/`，运行时读出：
 *
 *   katex.min.js        276,705 B   ← node_modules/katex/dist/katex.min.js
 *   auto-render.min.js    3,467 B   ← node_modules/katex/dist/contrib/auto-render.min.js
 *   katex.min.css        26,792 B   ← node_modules/katex/dist/katex.min.css（见下）
 *   darkreader.js       322,649 B   ← node_modules/darkreader/darkreader.js
 *
 * katex.min.css 在**复制进来时**已把 `url(fonts/` 重写成
 * `https://fastly.jsdelivr.net/npm/katex@0.16.27/dist/fonts/`（对应参考实现的
 * katexStyles.preval.js；版本取自 reference/learnOH-old/package.json）。**公式字体
 * 因此依赖外网 CDN**——离线时公式排版会退化。
 *
 * 生产路径只有 `getRawFileContentSync`（字节 → 文本走 domain/parse/Utf8 纯实现，
 * 与解析层同一份代码）。host 单测环境没有 rawfile，构造时传 null 即可：读不到就落空串，
 * 模板拼装的纯逻辑由 domain/render/WebViewTemplate 的单测覆盖，不需要资产本身。
 */
import { resourceManager } from '@kit.LocalizationKit';
import { decodeUtf8 } from '../../domain/parse/Utf8';
import { Logger } from '../log/Logger';

const logger: Logger = new Logger('core.web.assets');

/** rawfile 下的目录名；资产路径是 relativePath 形式（无前导斜杠）。 */
export const WEB_ASSET_DIR: string = 'webview';

export const KATEX_SCRIPT_FILE: string = 'katex.min.js';
export const KATEX_AUTO_RENDER_FILE: string = 'auto-render.min.js';
export const KATEX_STYLES_FILE: string = 'katex.min.css';
export const DARK_READER_FILE: string = 'darkreader.js';

/** 读 rawfile 文本。读不到返回空串并记日志（不抛：缺资产不该让详情页崩掉）。 */
export function readRawFileText(manager: resourceManager.ResourceManager | null, path: string): string {
  if (manager === null) {
    return '';
  }
  try {
    const bytes: Uint8Array = manager.getRawFileContentSync(path);
    return decodeUtf8(bytes);
  } catch (error) {
    logger.error('读取 rawfile 失败：' + path + '（' + (error as Error).message + '）');
    return '';
  }
}

/**
 * Web 容器资产的内存缓存。四份资产合计约 630 KB 且是不可变的构建产物，
 * 每次打开公告详情重新解码一遍没有意义，故进程内缓存。
 */
export class WebPageAssets {
  private readonly manager: resourceManager.ResourceManager | null;
  private loaded: boolean = false;
  private katexScript: string = '';
  private katexStyles: string = '';
  private darkReaderScript: string = '';

  /** @param manager 应用资源管理器；单测传 null 得到一组空资产。 */
  constructor(manager: resourceManager.ResourceManager | null) {
    this.manager = manager;
  }

  /** 首次调用时读盘，之后走内存。 */
  load(): void {
    if (this.loaded) {
      return;
    }
    this.loaded = true;
    const base: string = WEB_ASSET_DIR + '/';
    this.katexScript = readRawFileText(this.manager, base + KATEX_SCRIPT_FILE)
      + '\n' + readRawFileText(this.manager, base + KATEX_AUTO_RENDER_FILE);
    this.katexStyles = readRawFileText(this.manager, base + KATEX_STYLES_FILE);
    this.darkReaderScript = readRawFileText(this.manager, base + DARK_READER_FILE);
    logger.info('web assets loaded: katexScript=' + this.katexScript.length.toString()
      + ' katexStyles=' + this.katexStyles.length.toString()
      + ' darkReader=' + this.darkReaderScript.length.toString());
  }

  /** KaTeX 是否真的就位（缺了就不注入 `renderMathInElement` 调用，避免控制台刷错）。 */
  hasKatex(): boolean {
    return this.katexScript.trim().length > 0;
  }

  /** `katex.min.js` + `contrib/auto-render.min.js`（换行拼接，与参考实现的 readFiles 一致）。 */
  katex(): string {
    return this.katexScript;
  }

  /** `katex.min.css`（字体 URL 已是 CDN 绝对地址）。 */
  styles(): string {
    return this.katexStyles;
  }

  /** `darkreader.js`。 */
  darkReader(): string {
    return this.darkReaderScript;
  }
}
