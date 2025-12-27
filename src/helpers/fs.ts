/**
 * 获取文件扩展名。
 */
export const getExtension = (filename: string) => {
  const parts = filename.split('.');
  return parts.length > 1 ? parts.pop() : undefined;
};

/**
 * 移除文件扩展名。
 */
export const stripExtension = (filename: string) => {
  const parts = filename.split('.');
  return parts.length > 1 ? parts.slice(0, -1).join('.') : filename;
};
