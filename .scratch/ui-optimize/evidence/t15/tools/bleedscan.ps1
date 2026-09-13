param(
  [Parameter(Mandatory=$true)][string]$Path,
  [int]$XFrom = 370, [int]$XTo = 780,
  [int]$YFrom = 860, [int]$YTo = 1700,
  [int]$RowStep = 4, [int]$ColStep = 4, [int]$Tol = 10
)
Add-Type -AssemblyName System.Drawing
$bmp = [System.Drawing.Bitmap]::new($Path)
$w = $bmp.Width
# 采样窗口是**左栏中部的空白区**：稳定态那里是纯白（列表只有两条、且底栏之上无内容）。
$hit = 0
$total = 0
$minX = -1; $maxX = -1; $minY = -1; $maxY = -1
$hist = @{}
for ($y = $YFrom; $y -le $YTo; $y += $RowStep) {
  $rect = [System.Drawing.Rectangle]::new(0, $y, $w, 1)
  $data = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $bytes = New-Object byte[] ($data.Stride)
  [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $bytes, 0, $data.Stride)
  $bmp.UnlockBits($data)
  for ($x = $XFrom; $x -le $XTo; $x += $ColStep) {
    $i = $x * 4
    $r = [int]$bytes[$i+2]; $g = [int]$bytes[$i+1]; $b = [int]$bytes[$i]
    $v = ($r + $g + $b) / 3
    $total++
    if ($v -lt 250) {
      $hit++
      if ($minX -lt 0 -or $x -lt $minX) { $minX = $x }
      if ($x -gt $maxX) { $maxX = $x }
      if ($minY -lt 0) { $minY = $y }
      $maxY = $y
      $hex = '{0:X2}{1:X2}{2:X2}' -f $r, $g, $b
      if ($hist.ContainsKey($hex)) { $hist[$hex]++ } else { $hist[$hex] = 1 }
    }
  }
}
$bmp.Dispose()
$verdict = if ($hit -gt 0) { 'BLEED' } else { 'clean' }
$top = $hist.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 5
Write-Output ("{0} {1} hit={2}/{3} bbox=x[{4},{5}] y[{6},{7}] top={8}" -f (Split-Path $Path -Leaf), $verdict, $hit, $total, $minX, $maxX, $minY, $maxY, (($top | ForEach-Object { '{0}x{1}' -f $_.Key, $_.Value }) -join ' '))
