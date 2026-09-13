param(
  [Parameter(Mandatory=$true)][string]$Phase,
  [Parameter(Mandatory=$true)][string]$Prefix,
  [Parameter(Mandatory=$true)][string]$LocalDir,
  [int]$Trials = 6,
  [int]$Frames = 12,
  [string]$Device = '127.0.0.1:5559',
  [string]$Package = 'com.koracan.learnOH'
)
New-Item -ItemType Directory -Force $LocalDir | Out-Null
# 右栏详情已挂载的判据：右栏返回按钮的 bounds（来自 layout dump，不是截图目测）
$marker = '788,86][868,158'
for ($i = 0; $i -lt $Trials; $i++) {
  $tag = "$Prefix-$i"
  hdc -t $Device shell "aa force-stop $Package" | Out-Null
  Start-Sleep -Milliseconds 800
  hdc -t $Device shell "aa start -a EntryAbility -b $Package" | Out-Null
  Start-Sleep -Milliseconds 7000
  if ($Phase -eq 'exit') {
    hdc -t $Device shell 'uitest uiInput click 400 380' | Out-Null
    # 轮询到期盼的详情挂载为止（不赌固定等待时长）
    $ready = $false
    for ($p = 0; $p -lt 12; $p++) {
      Start-Sleep -Milliseconds 700
      $c = hdc -t $Device shell "uitest dumpLayout -p /data/local/tmp/t15/probe.json >/dev/null 2>&1; grep -c '$marker' /data/local/tmp/t15/probe.json"
      if ("$c".Trim() -ne '0') { $ready = $true; break }
    }
    if (-not $ready) { Write-Output "trial=$tag SKIPPED(detail not mounted)"; continue }
  }
  if ($Phase -eq 'enter') { $x = 400; $y = 380 } else { $x = 828; $y = 122 }
  hdc -t $Device shell "sh /data/local/tmp/t15/cap.sh $tag $x $y $Frames 0.05 0.30" | Out-Null
  for ($f = 0; $f -lt $Frames; $f++) {
    hdc -t $Device file recv "/data/local/tmp/t15/$tag-$f.jpeg" "$LocalDir\$tag-$f.jpeg" | Out-Null
  }
  hdc -t $Device file recv "/data/local/tmp/t15/$tag-tl.txt" "$LocalDir\$tag-tl.txt" | Out-Null
  $tl = (Get-Content "$LocalDir\$tag-tl.txt" -Raw) -replace [char]13, '' -replace [char]10, ' '
  Write-Output ("trial=$tag ready=$ready timeline=" + $tl)
}
