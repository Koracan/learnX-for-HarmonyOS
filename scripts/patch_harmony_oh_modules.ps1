Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot

function Update-FileContent {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path,
    [Parameter(Mandatory = $true)]
    [scriptblock]$Transform
  )

  if (-not (Test-Path -LiteralPath $Path)) {
    Write-Warning "Skip missing file: $Path"
    return
  }

  $content = Get-Content -LiteralPath $Path -Raw
  $updated = & $Transform $content

  if ($updated -ne $content) {
    Set-Content -LiteralPath $Path -Value $updated -NoNewline
    Write-Host "Patched: $Path"
  } else {
    Write-Host "No change: $Path"
  }
}

$viewerPath = Join-Path $repoRoot 'harmony/entry/oh_modules/@react-native-ohos/react-native-file-viewer/src/main/ets/RNFileViewerTurboModule.ts'
Update-FileContent -Path $viewerPath -Transform {
  param([string]$content)

  if ($content -notmatch 'private normalizeLocalPath\(filepath: string\): string') {
    $needle = @"
  constructor(protected ctx: TurboModuleContext) {
    super(ctx);
    this.ctx = ctx;
  }

  open(filepath: string, currentId: number, options: RNFileViewerOptions | string = {}): Promise<void> {
"@
    $replacement = @"
  constructor(protected ctx: TurboModuleContext) {
    super(ctx);
    this.ctx = ctx;
  }

  private normalizeLocalPath(filepath: string): string {
    let normalizedPath = filepath;

    while (normalizedPath.startsWith('file://')) {
      normalizedPath = normalizedPath.substring('file://'.length);
    }

    return normalizedPath;
  }

  open(filepath: string, currentId: number, options: RNFileViewerOptions | string = {}): Promise<void> {
"@
    if ($content.Contains($needle)) {
      $content = $content.Replace($needle, $replacement)
    }
  }

  if ($content -notmatch 'const normalizedPath = this\.normalizeLocalPath\(filepath\);') {
    $content = $content.Replace(
"    const _options = typeof options === 'string' ? { displayName: options } : options;",
"    const _options = typeof options === 'string' ? { displayName: options } : options;`n    const normalizedPath = this.normalizeLocalPath(filepath);"
    )
  }

  $content = $content -replace '(?m)(\s*const normalizedPath = this\.normalizeLocalPath\(filepath\);\r?\n)\1+', '$1'

  $content = $content.Replace('fs.stat(filepath)', 'fs.stat(normalizedPath)')
  $content = $content.Replace('this.OpenFile(filepath, this.ctx, _options);', 'this.OpenFile(normalizedPath, this.ctx, _options);')
  $content = $content.Replace(
'  private async OpenFile(uri: string, ctx: TurboModuleContext, options: RNFileViewerOptions): Promise<void> {',
'  private async OpenFile(localPath: string, ctx: TurboModuleContext, options: RNFileViewerOptions): Promise<void> {'
  )

  if ($content -notmatch 'const normalizedUri = fileUri.getUriFromPath\(localPath\)\.toString\(\);') {
    $content = $content.Replace(
'    const { showOpenWithDialog, showAppsSuggestions, displayName } = options;`n    const uiContext: Context = ctx.uiAbilityContext;',
'    const { showOpenWithDialog, showAppsSuggestions, displayName } = options;`n    const uiContext: Context = ctx.uiAbilityContext;`n    const normalizedUri = fileUri.getUriFromPath(localPath).toString();'
    )
  }

  $content = $content.Replace('new fileUri.FileUri(uri);', 'new fileUri.FileUri(normalizedUri);')

  $content = $content.Replace(
"    const canPreviewFlag: boolean = await filePreview.canPreview(`n      uiContext,`n      uri,`n    );",
"    const canPreviewFlag: boolean = await filePreview.canPreview(`n      uiContext,`n      normalizedUri,`n    );"
  )

  $content = $content.Replace('this.OpenByFilePreview(ctx, uri, fileMimeType, showFileName);', 'this.OpenByFilePreview(ctx, localPath, fileMimeType, showFileName);')
  $content = $content.Replace("uri: 'file://' + uri,", 'uri: normalizedUri,')

  return $content
}

$shareUtilsPath = Join-Path $repoRoot 'harmony/entry/oh_modules/@react-native-ohos/react-native-share/src/main/ets/utils/FileUtils.ts'
Update-FileContent -Path $shareUtilsPath -Transform {
  param([string]$content)

  if ($content -notmatch 'private normalizePathForFs\(pathOrUri: string\): string') {
    $needle = @"
  getTypeFromMIMEType(mime: string) {
    let type = '';
    let mimeTypes = FileUtils.mimeTypes;
    let mimeTypeKeys = Object.keys(mimeTypes);
    for (let key of mimeTypeKeys) {
      if (mime === mimeTypes[key]) {
        type = key;
        break;
      }
    }
    return type;
  }
  isLocalFile(url: string): boolean {
"@
    $replacement = @"
  getTypeFromMIMEType(mime: string) {
    let type = '';
    let mimeTypes = FileUtils.mimeTypes;
    let mimeTypeKeys = Object.keys(mimeTypes);
    for (let key of mimeTypeKeys) {
      if (mime === mimeTypes[key]) {
        type = key;
        break;
      }
    }
    return type;
  }

  private normalizePathForFs(pathOrUri: string): string {
    let normalizedPath = pathOrUri;

    while (normalizedPath.startsWith('file://')) {
      normalizedPath = normalizedPath.substring('file://'.length);
    }

    return normalizedPath;
  }

  private normalizeUriForShare(pathOrUri: string): string {
    if (!pathOrUri) {
      return pathOrUri;
    }

    if (pathOrUri.startsWith('content://')) {
      return pathOrUri;
    }

    const normalizedPath = this.normalizePathForFs(pathOrUri);
    if (normalizedPath.startsWith('/')) {
      return fileUri.getUriFromPath(normalizedPath).toString();
    }

    return pathOrUri;
  }

  isLocalFile(url: string): boolean {
"@
    if ($content.Contains($needle)) {
      $content = $content.Replace($needle, $replacement)
    }
  }

  $content = $content.Replace(
"  isLocalFile(url: string): boolean {`n    let scheme = new uri.URI(url).scheme;`n    if ((scheme != null && scheme === ""content"") || scheme === ""file"") {`n      return true;`n    }`n    return false;`n  }",
"  isLocalFile(url: string): boolean {`n    if (url.startsWith('/')) {`n      return true;`n    }`n`n    let scheme = new uri.URI(url).scheme;`n    if ((scheme != null && scheme === ""content"") || scheme === ""file"") {`n      return true;`n    }`n`n    return false;`n  }"
  )

  $content = $content.Replace('uris.push(url)', 'uris.push(this.normalizeUriForShare(url))')

  $content = $content.Replace(
"  copyUriFromUrl(uri: string, url: string) {`n    let savefile = fs.openSync(uri, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE).fd;`n    let originFile = fs.openSync(url, fs.OpenMode.READ_ONLY).fd;",
"  copyUriFromUrl(uri: string, url: string) {`n    const normalizedOriginPath = this.normalizePathForFs(url);`n    let savefile = fs.openSync(uri, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE).fd;`n    let originFile = fs.openSync(normalizedOriginPath, fs.OpenMode.READ_ONLY).fd;"
  )

  $content = $content.Replace(
"  copyFileFromOriginPath(context: common.UIAbilityContext, oriPath: string, fileName?: string): string {`n    let dir = this.getCacheFile(context, 'share_cache');",
"  copyFileFromOriginPath(context: common.UIAbilityContext, oriPath: string, fileName?: string): string {`n    const normalizedOriginPath = this.normalizePathForFs(oriPath);`n    let dir = this.getCacheFile(context, 'share_cache');"
  )

  $content = $content.Replace('let suffix = this.getUrlSuffix(oriPath);', 'let suffix = this.getUrlSuffix(normalizedOriginPath);')
  $content = $content.Replace('this.copyUriFromUrl(path, oriPath);', 'this.copyUriFromUrl(path, normalizedOriginPath);')

  return $content
}

Write-Host 'Harmony oh_modules patch completed.'
