# ⚠️ 已废弃（DEPRECATED，2026-09-12，ticket 08）—— **不要运行**。
#
# 原因与替代物见同目录 EnrollmentProbe.ets 顶部的说明（以及 ticket 08 的 Comments）：
#   1. 认证门已收紧为"有凭据**且会话建起来** = 已登记"，本探针要观察的
#      `startup: enrolled -> main shell (credentials from asset store)` 不再可复现
#      （合成凭据现在会真发一次纯 HTTP 重登，失败后显式回登录页）；
#   2. 它注入的 `AuthStore.loadPersisted()` 已更名为 `start()`，运行会编译失败。
#
# 替代：pwsh -File .scratch/session/tools/run-session-probe.ps1
# ticket 07 · 探针：凭据落盘 + 重启后仍处于已登记状态（**合成凭据，不是真实登记**）
#
# 为什么需要：验收第 3 条要求"凭据加密落盘；重启应用后仍处于已登记状态"，而"完整登记"必须由用户
# 本人完成短信验证。这里用合成凭据走**真实代码路径**（AssetSecretStore → CredentialStore →
# AuthStore.loadPersisted），并在杀进程后读回来。
#
# 前置：两把锁归你（构建锁 + 设备锁）。用法：
#   pwsh -File .scratch/enrollment/tools/run-enrollment-probe.ps1
#
# 脚本做四件事，无论成败都在 finally 里复原探针与 EntryAbility：
#   1. 拷探针 + 往 EntryAbility.onCreate 注入一行调用；
#   2. devecocli build → hdc install -r；
#   3. seed（写合成凭据）→ 杀进程 → 正常启动（读回）→ 截图 → clear（删掉）；
#   4. 打印 git status（探针与 EntryAbility 必须干净）。

param(
  [string]$Device = '127.0.0.1:5555',
  [string]$Bundle = 'com.koracan.learnOH',
  [switch]$SkipBuild
)

$ErrorActionPreference = 'Continue'
$repo = 'D:\Koracan\source\harmony\learnOH'
Set-Location $repo
$probeSrc = '.scratch/enrollment/tools/EnrollmentProbe.ets'
$probeDst = 'entry/src/main/ets/core/codec/EnrollmentProbe.ets'
$ability = 'entry/src/main/ets/entryability/EntryAbility.ets'
$logDir = '.dsh/logs'
$evidence = '.scratch/enrollment/evidence'
$hap = 'entry/build/default/outputs/default/entry-default-signed.hap'
New-Item -ItemType Directory -Force -Path $logDir, $evidence | Out-Null

function Write-Step([string]$text) { Write-Output ('=== ' + $text) }

function Capture-Hilog([string]$name) {
  $remote = '/data/local/tmp/' + $name + '.txt'
  $local = Join-Path $evidence ($name + '.txt')
  hdc -t $Device shell ('hilog -x -D 0x4C4F > ' + $remote) | Out-Null
  hdc -t $Device file recv $remote $local | Out-Null
  if (Test-Path $local) {
    Write-Output ($name + ' bytes=' + (Get-Item $local).Length)
  } else {
    Write-Output ($name + ' NOT CAPTURED')
  }
}

function Start-App([string]$probeAction) {
  hdc -t $Device shell ('aa force-stop ' + $Bundle) | Out-Null
  Start-Sleep -Seconds 1
  if ($probeAction.Length -gt 0) {
    hdc -t $Device shell ('aa start -b ' + $Bundle + ' -a EntryAbility --ps learnohProbe ' + $probeAction)
  } else {
    hdc -t $Device shell ('aa start -b ' + $Bundle + ' -a EntryAbility')
  }
}

function Screenshot([string]$name) {
  $path = Join-Path $evidence ($name + '.png')
  Remove-Item -Force $path -ErrorAction SilentlyContinue
  devecocli ui screenshot --device $Device --path $path *> (Join-Path $logDir ('ticket07-shot-' + $name + '.log'))
  if (Test-Path $path) { Write-Output ($name + '.png bytes=' + (Get-Item $path).Length) } else { Write-Output ($name + ' NOT CAPTURED') }
}

try {
  Write-Output ('HEAD=' + (git rev-parse HEAD))
  git status --porcelain

  Write-Step 'probe: copy + inject'
  Copy-Item $probeSrc $probeDst -Force
  $text = Get-Content -Raw $ability
  if ($text -notmatch 'EnrollmentProbe') {
    $importLine = "import { i18nService } from '../core/i18n/I18n';"
    $newImport = $importLine + "`nimport { runEnrollmentEvidenceProbe } from '../core/codec/EnrollmentProbe'; // TEMP-EVIDENCE(ticket07)"
    $text = $text.Replace($importLine, $newImport)
    $anchor = '    // 语言变化通知：注册应用级环境回调'
    $inject = "    // TEMP-EVIDENCE(ticket07)：登记落盘探针`n    runEnrollmentEvidenceProbe(want);`n`n" + $anchor
    $text = $text.Replace($anchor, $inject)
    [System.IO.File]::WriteAllText((Resolve-Path $ability), $text)
    Write-Output 'injected'
  } else {
    Write-Output 'already injected'
  }

  $env:DEVECO_SDK_HOME = 'C:\Program Files\Huawei\DevEco Studio\sdk'
  if (-not $SkipBuild) {
    # 用 hvigorw 而不是 devecocli build：后者在本机打完包后不返回（AGENTS.md 记过同类现象），
    # 会让一次性脚本挂在这里。常设门禁里的 devecocli build 另行单独跑（见 ticket Comments）。
    Write-Step 'build (hvigorw assembleHap)'
    & 'C:/Program Files/Huawei/DevEco Studio/tools/hvigor/bin/hvigorw.bat' --mode module -p module=entry@default -p product=default assembleHap *> (Join-Path $logDir 'ticket07-probe-build.log')
    Write-Output ('BUILD_EXIT=' + $LASTEXITCODE + ' hapTime=' + (Get-Item $hap).LastWriteTime.ToString('HH:mm:ss'))
  }

  Write-Step 'install'
  hdc -t $Device install -r $hap

  Write-Step 'seed (synthetic credentials through the real store)'
  Start-App 'seed'
  Start-Sleep -Seconds 3
  Capture-Hilog '07-probe-seed'

  Write-Step 'restart (no parameters) -> app must boot enrolled'
  Start-App ''
  Start-Sleep -Seconds 5
  Capture-Hilog '07-probe-restart-enrolled'
  Screenshot '07-probe-restart-shell'

  Write-Step 'clear + restart -> app must boot unenrolled'
  Start-App 'clear'
  Start-Sleep -Seconds 3
  Capture-Hilog '07-probe-clear'
  Start-App ''
  Start-Sleep -Seconds 5
  Capture-Hilog '07-probe-restart-unenrolled'
  Screenshot '07-probe-restart-login'
} finally {
  Write-Step 'restore'
  git checkout -- $ability
  Remove-Item -Force $probeDst -ErrorAction SilentlyContinue
  git status --porcelain
  Write-Output '(上面应只剩你自己的改动；探针与 EntryAbility 必须干净)'
}
