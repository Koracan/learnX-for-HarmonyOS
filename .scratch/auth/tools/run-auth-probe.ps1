# ticket 06 · 一次性设备脚本（登录 → 取 CSRF → 抓一次列表）
#
# 前置：用户已手动完成登记（ticket 07）；两把锁归你（构建锁 + 设备锁）。
# 用法：先在 AuthProbe.ets 里填 USERNAME / PASSWORD / FINGER_PRINT，然后：
#   pwsh -File .scratch/auth/tools/run-auth-probe.ps1
#
# 脚本会：拷探针 → 打 EntryAbility 两行 → hvigorw test（先编译校验）→ devecocli run → 取 hilog
#        → 无论成败都复原探针与 EntryAbility（finally）。

$ErrorActionPreference = 'Continue'
$repo = 'D:\Koracan\source\harmony\learnOH'
Set-Location $repo
$probeTarget = 'entry/src/main/ets/core/codec/AuthProbe.ets'
$ability = 'entry/src/main/ets/entryability/EntryAbility.ets'
$logDir = '.dsh/logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

Write-Output ('HEAD=' + (git rev-parse HEAD))
git status --porcelain

try {
  Copy-Item '.scratch/auth/tools/AuthProbe.ets' $probeTarget -Force
  $text = Get-Content -Raw $ability
  if ($text -notmatch 'AuthProbe') {
    $importLine = "import { i18nService } from '../core/i18n/I18n';"
    $newImport = $importLine + "`nimport { runAuthEvidenceProbe } from '../core/codec/AuthProbe'; // TEMP-EVIDENCE(ticket06)"
    $text = $text.Replace($importLine, $newImport)
    $anchor = '    // 语言变化通知：注册应用级环境回调'
    $inject = "    // TEMP-EVIDENCE(ticket06)：登录探针`n    runAuthEvidenceProbe();`n`n" + $anchor
    $text = $text.Replace($anchor, $inject)
    [System.IO.File]::WriteAllText((Resolve-Path $ability), $text)
  }
  $env:DEVECO_SDK_HOME = 'C:\Program Files\Huawei\DevEco Studio\sdk'
  Write-Output '--- compile check (hvigorw test) ---'
  Remove-Item -Recurse -Force 'entry/.test' -ErrorAction SilentlyContinue
  & 'C:/Program Files/Huawei/DevEco Studio/tools/hvigor/bin/hvigorw.bat' --mode module -p module=entry@default -p product=default test --no-incremental *> "$logDir/auth-probe-compile.log"
  Write-Output ('COMPILE_EXIT=' + $LASTEXITCODE)
  Write-Output '--- build + install + launch ---'
  devecocli run --device 127.0.0.1:5555 *> "$logDir/auth-probe-run.log"
  Write-Output ('RUN_EXIT=' + $LASTEXITCODE)
  Write-Output '--- hilog ---'
  devecocli log --device 127.0.0.1:5555 --from 10m --keyword PROBE *> "$logDir/auth-probe-hilog.log"
  Get-Content "$logDir/auth-probe-hilog.log" | Select-String -Pattern 'PROBE|data.files' | ForEach-Object { $_.Line }
} finally {
  Write-Output '--- restore ---'
  git checkout -- $ability
  Remove-Item -Force $probeTarget -ErrorAction SilentlyContinue
  git status --porcelain
  Write-Output '(上面应只剩你自己的改动；探针与 EntryAbility 必须干净)'
}
