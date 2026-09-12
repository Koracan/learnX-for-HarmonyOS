/*
 * 文件落盘端口（data/files）：编排层（FileDownloader）唯一的文件系统依赖。
 *
 * 为什么要有这一层：`domain/files` 的纯函数算路径，"下载到登录页不落盘"这条要在**写第一个
 * 字节之前**决定，于是"文件系统"必须是可注入的——单测里换成内存替身就能断言
 * "一次 `openSink` 都没发生过"（即确实没落盘），无需设备。
 *
 * 同步 API：平台的 `@ohos.file.fs` 提供 `openSync/writeSync/closeSync`，
 * 而响应头回调（`DownloadSink.onHeaders`）是**同步**返回布尔值的，两者正好对齐。
 */

/** 已打开的输出文件（一次下载一个）。 */
export interface FileSink {
  /** 写一块字节（失败抛异常，由编排层记为写错误）。 */
  write(chunk: ArrayBuffer): void;
  /** 正常关闭。 */
  close(): void;
  /** 异常关闭（随后由编排层删除半成品文件）。 */
  abort(): void;
}

/** 应用沙箱的两个根目录（`common.Context.filesDir` / `cacheDir`）。 */
export interface FileRoots {
  /** "文档"根：只随应用卸载删除（参考实现的 `DocumentDirectoryPath`）。 */
  filesDir: string;
  /** "缓存"根：系统可能在空间不足时清除（参考实现的 `CachesDirectoryPath`）。 */
  cacheDir: string;
}

/** 文件系统端口。 */
export interface FileStore {
  roots(): FileRoots;
  /** 递归建目录；已存在时静默成功。 */
  ensureDir(dir: string): void;
  exists(path: string): boolean;
  /** 创建/截断并打开输出文件（调用方保证父目录已存在）。 */
  openSink(path: string): FileSink;
  /** 删除一个文件；不存在时静默成功。 */
  remove(path: string): void;
  /** 递归删除目录树（"清理缓存"用）；不存在时静默成功。 */
  removeTree(path: string): void;
  /** 文件大小；不存在时返回 0。 */
  fileSize(path: string): number;
}
