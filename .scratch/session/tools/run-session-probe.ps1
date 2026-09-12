# ticket 08 · 探针：冷启动纯 HTTP 重登 + 显式降级 + 会话 cookie 不落盘（**合成凭据，不是真实登记**）
#
# 为什么需要：验收第 1/3/4/5 条都要求"应用手里有一份凭据，于是冷启动走纯 HTTP 静默重登"。
# 真实凭据要用户手动完成短信登记（本 ticket 不做、也不经手），所以先用**合成凭据**走真实代码路径。
#
# 前置：两把锁归你（构建锁 + 设备锁），设备是模拟器 Pura 90（127.0.0.1:5555）。用法：
#   pwsh -File .scratch/session/tools/run-session-probe.ps1
#
# 步骤：
#   1. 拷探针 + 往 EntryAbility.onCreate 注入一行调用（TEMP-EVIDENCE(ticket08)）；
#   2. hvigorw assembleHap → hdc install -r；
#   3. seed（写**合成**凭据）→ 杀进程 → 正常启动（走纯 HTTP 重登）→ 抓 hilog + 截图；
#   4. 杀进程 → 扫描应用存储（asset / preferences / 文件 / database）里的**会话**痕迹；
#   5. clear（删掉合成凭据）→ 正常启动 → 抓 hilog + 截图（未登记 → 登录页）；
#   6. （默认）复原探针后**全量重建**并做产物级检查 + 装机确认——见 AGENTS.md 的「陈旧产物」条。
#
# 注意：devecocli build 在本机打完包后可能不返回，故用 hvigorw assembleHap（同 ticket 07 的经验）。

param(
  [string]$Device = '127.0.0.1:5555',
  [string]$Bundle = 'com.koracan.learnOH',
  [switch]$SkipBuild,
  [switch]$SkipCommittedStateCheck
)

$ErrorActionPreference = 'Continue'
$repo = 'D:\Koracan\source\harmony\learnOH'
Set-Location $repo
$probeSrc = '.scratch/session/tools/SessionProbe.ets'
$probeDst = 'entry/src/main/ets/core/codec/SessionProbe.ets'
$ability = 'entry/src/main/ets/entryability/EntryAbility.ets'
$logDir = '.dsh/logs'
$evidence = '.scratch/session/evidence'
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
  devecocli ui screenshot --device $Device --path $path *> (Join-Path $logDir ('ticket08-shot-' + $name + '.log'))
  if (Test-Path $path) { Write-Output ($name + '.png bytes=' + (Get-Item $path).Length) } else { Write-Output ($name + ' NOT CAPTURED') }
}

function Record-Revision([string]$name) {
  $out = Join-Path $evidence $name
  $lines = @()
  $lines += 'date=' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
  $lines += 'head=' + (git rev-parse HEAD)
  $dirty = (git status --porcelain) -join "`n"
  $lines += 'dirty=' + (($dirty -split "`n") | Where-Object { $_.Length -gt 0 } | Measure-Object).Count + ' entries'
  $lines += 'dirty-sha256=' + [System.BitConverter]::ToString(
    [System.Security.Cryptography.SHA256]::Create().ComputeHash(
      [System.Text.Encoding]::UTF8.GetBytes($dirty))).Replace('-', '').ToLower()
  $lines += '--- git status --porcelain ---'
  $lines += $dirty
  $lines += '--- installed package ---'
  $lines += (hdc -t $Device shell ('bm dump -n ' + $Bundle + ' | grep -E "versionName|versionCode" '))
  [System.IO.File]::WriteAllLines((Join-Path $evidence $name), $lines)
  Write-Output ('revision -> ' + $name)
}

# 逐个命令跑 hdc shell 并追加到本地文件：避免把多命令拼成一行时的引号地狱。
function Scan-Storage([string]$name) {
  $local = Join-Path $evidence ($name + '.txt')
  Remove-Item -Force $local -ErrorAction SilentlyContinue
  $commands = @(
    'date',
    'ls -laR /data/app/el2/100/base/' + $Bundle + ' 2>&1 | head -300',
    'ls -laR /data/app/el2/100/database/' + $Bundle + ' 2>&1 | head -200',
    'find /data/app/el2/100/base/' + $Bundle + ' -type f 2>/dev/null | head -200',
    'grep -ra -E "JSESSIONID|SERVERID|CASTGC|TGT-|_csrf|csrfToken" /data/app/el2/100/base/' + $Bundle + ' 2>/dev/null | head -40',
    'grep -ra -E "JSESSIONID|SERVERID|CASTGC|TGT-|_csrf|csrfToken" /data/app/el2/100/database/' + $Bundle + ' 2>/dev/null | head -40',
    'grep -ra "learnOH.credentials" /data/app/el2/100/base/' + $Bundle + ' 2>/dev/null | head -5',
    'ls -la /data/app/el2/100/base/' + $Bundle + '/preferences 2>&1',
    'ls -la /data/app/el2/100/base/' + $Bundle + '/files 2>&1'
  )
  foreach ($command in $commands) {
    Add-Content -Path $local -Value ('## ' + $command)
    $result = hdc -t $Device shell $command 2>&1
    Add-Content -Path $local -Value ($result -join "`n")
    Add-Content -Path $local -Value ''
  }
  Write-Output ($name + ' bytes=' + (Get-Item $local).Length)
}

try {
  Write-Step 'preconditions'
  hdc -t $Device shell 'echo device-ok'
  Write-Output ('HEAD=' + (git rev-parse HEAD))
  git status --porcelain
  Record-Revision 'revision.txt'

  Write-Step 'probe: copy + inject'
  Copy-Item $probeSrc $probeDst -Force
  $text = Get-Content -Raw $ability
  if ($text -notmatch 'SessionProbe') {
    $importLine = "import { i18nService } from '../core/i18n/I18n';"
    $newImport = $importLine + "`nimport { runSessionEvidenceProbe } from '../core/codec/SessionProbe'; // TEMP-EVIDENCE(ticket08)"
    $text = $text.Replace($importLine, $newImport)
    $anchor = '    // 语言变化通知：注册应用级环境回调'
    $inject = "    // TEMP-EVIDENCE(ticket08)：冷启动重登 / 会话不落盘取证探针`n    runSessionEvidenceProbe(want);`n`n" + $anchor
    $text = $text.Replace($anchor, $inject)
    [System.IO.File]::WriteAllText((Resolve-Path $ability), $text)
    Write-Output 'injected'
  } else {
    Write-Output 'already injected'
  }

  $env:DEVECO_SDK_HOME = 'C:\Program Files\Huawei\DevEco Studio\sdk'
  if (-not $SkipBuild) {
    Write-Step 'build (hvigorw assembleHap)'
    & 'C:/Program Files/Huawei/DevEco Studio/tools/hvigor/bin/hvigorw.bat' --mode module -p module=entry@default -p product=default assembleHap *> (Join-Path $logDir 'ticket08-probe-build.log')
    Write-Output ('BUILD_EXIT=' + $LASTEXITCODE + ' hapTime=' + (Get-Item $hap).LastWriteTime.ToString('HH:mm:ss'))
  }

  Write-Step 'install'
  hdc -t $Device install -r $hap

  Write-Step 'seed synthetic credentials'
  Start-App 'seed'
  Start-Sleep -Seconds 3
  Capture-Hilog '08-probe-seed'

  Write-Step 'cold start -> silent re-auth over pure HTTP (this is acceptance 1 / 3)'
  Start-App ''
  Start-Sleep -Seconds 12
  Capture-Hilog '08-coldstart-reauth'
  Screenshot '08-coldstart-degraded'

  Write-Step 'kill, then scan app storage for session data (acceptance 5)'
  hdc -t $Device shell ('aa force-stop ' + $Bundle) | Out-Null
  Start-Sleep -Seconds 2
  Scan-Storage '08-storage-scan'

  Write-Step 'clear synthetic credentials + cold start -> login page (no half state)'
  Start-App 'clear'
  Start-Sleep -Seconds 3
  Capture-Hilog '08-probe-clear'
  Start-App ''
  Start-Sleep -Seconds 6
  Capture-Hilog '08-coldstart-unenrolled'
  Screenshot '08-coldstart-login'
} finally {
  Write-Step 'restore sources'
  git checkout -- $ability
  Remove-Item -Force $probeDst -ErrorAction SilentlyContinue
  git status --porcelain
  Write-Output '(上面应只剩你自己的改动；探针与 EntryAbility 必须干净)'

  if (-not $SkipCommittedStateCheck) {
    Write-Step 'committed state: full rebuild + artifact-level check + install'
    $env:DEVECO_SDK_HOME = 'C:\Program Files\Huawei\DevEco Studio\sdk'
    Remove-Item -Recurse -Force entry/build -ErrorAction SilentlyContinue
    & 'C:/Program Files/Huawei/DevEco Studio/tools/hvigor/bin/hvigorw.bat' --mode module -p module=entry@default -p product=default assembleHap *> (Join-Path $logDir 'ticket08-committed-build.log')
    Write-Output ('COMMITTED_BUILD_EXIT=' + $LASTEXITCODE + ' hapTime=' + (Get-Item $hap).LastWriteTime.ToString('HH:mm:ss') + ' bytes=' + (Get-Item $hap).Length)

    $zip = Join-Path $env:TEMP 'ticket08-hap.zip'
    $out = Join-Path $env:TEMP 'ticket08-hap-out'
    Remove-Item -Force $zip -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force $out -ErrorAction SilentlyContinue
    Copy-Item $hap $zip -Force
    Expand-Archive $zip -DestinationPath $out -Force
    $abc = Join-Path $out 'ets/modules.abc'
    $probeHits = (Select-String -Path $abc -Pattern 'SessionProbe' -SimpleMatch -AllMatches | Measure-Object).Count
    $tempHits = (Select-String -Path $abc -Pattern 'TEMP-EVIDENCE' -SimpleMatch -AllMatches | Measure-Object).Count
    $newHits = (Select-String -Path $abc -Pattern 'SessionRestorer' -SimpleMatch -AllMatches | Measure-Object).Count
    Write-Output ('artifact scan: SessionProbe=' + $probeHits + ' TEMP-EVIDENCE=' + $tempHits + ' SessionRestorer=' + $newHits)
    hdc -t $Device install -r $hap
    Start-App ''
    Start-Sleep -Seconds 6
    Capture-Hilog '08-committed-coldstart'
    Screenshot '08-committed-login'
  }
}
