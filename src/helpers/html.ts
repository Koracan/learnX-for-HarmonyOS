import he from 'he';

/**
 * 移除 HTML 标签，提取纯文本摘要。
 */
export const removeTags = (html?: string) => {
  if (!html) return '';
  try {
    return he
      .decode(html.replace(/<!--(.*?)-->/g, '').replace(/<(?:.|\n)*?>/gm, ''))
      .replace(/\s\s+/g, ' ')
      .trim();
  } catch {
    return '';
  }
};

/**
 * 生成内联 HTML 模板，用于 WebView 渲染公告内容。
 */
export const getWebViewTemplate = (
  content: string,
  options?: {
    backgroundColor?: string;
    textColor?: string;
    linkColor?: string;
    isDark?: boolean;
  },
) => {
  const {
    backgroundColor = '#fff',
    textColor = '#222',
    linkColor = '#1e6eff',
    isDark = false,
  } = options || {};

  const codeBackground = isDark ? '#1f1f1f' : '#f5f5f5';

  return `
  <!DOCTYPE html>
  <html lang="zh-cmn-Hans">
    <head>
      <meta charset="utf-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1" />
      <style>
        :root { color-scheme: ${isDark ? 'dark' : 'light'}; }
        * { box-sizing: border-box; }
        body { margin: 0; padding: 12px; background: ${backgroundColor}; color: ${textColor}; font-size: 16px; line-height: 1.6; }
        #root { height: 100%; width: 100%; overflow: hidden; }
        img { max-width: 100%; height: auto; }
        a { color: ${linkColor}; word-break: break-word; }
        p { margin: 0 0 0.6em 0; }
        pre, code { background: ${codeBackground}; color: ${textColor}; border-radius: 4px; }
        pre { padding: 8px; overflow-x: auto; }
        code { padding: 2px 4px; }
      </style>
    </head>
    <body>
      <div id="root">${content}</div>
    </body>
  </html>
`;
};

/**
 * 判断文件是否可以在 WebView 中渲染（图片等）
 */
export const canRenderInWebview = (fileType?: string) => {
  if (!fileType) return false;
  const type = fileType.toLowerCase();
  return ['jpg', 'jpeg', 'png', 'gif', 'svg', 'bmp', 'webp'].includes(type);
};

/**
 * 判断文件是否需要白色背景（如透明图片）
 */
export const needWhiteBackground = (fileType?: string) => {
  if (!fileType) return false;
  const type = fileType.toLowerCase();
  return ['png', 'svg', 'gif'].includes(type);
};
