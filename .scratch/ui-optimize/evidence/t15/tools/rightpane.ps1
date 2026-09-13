param([Parameter(Mandatory=$true)][string]$Path)
Add-Type -AssemblyName System.Drawing
$bmp = [System.Drawing.Bitmap]::new($Path)
$w = $bmp.Width
$hit = 0; $total = 0
for ($y = 100; $y -le 1740; $y += 20) {
  $rect = [System.Drawing.Rectangle]::new(800, $y, 2000, 1)
  $data = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $bytes = New-Object byte[] ($data.Stride)
  [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $bytes, 0, $data.Stride)
  $bmp.UnlockBits($data)
  for ($x = 0; $x -lt 2000; $x += 8) {
    $i = $x * 4
    $v = ([int]$bytes[$i+2] + [int]$bytes[$i+1] + [int]$bytes[$i]) / 3
    $total++
    if ($v -lt 245) { $hit++ }
  }
}
$bmp.Dispose()
$state = if ($hit -gt 200) { 'CONTENT' } else { 'EMPTY' }
Write-Output ("{0} rightPane={1} hit={2}/{3}" -f (Split-Path $Path -Leaf), $state, $hit, $total)
