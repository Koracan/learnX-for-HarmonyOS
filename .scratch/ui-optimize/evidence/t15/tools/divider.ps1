param(
  [Parameter(Mandatory=$true)][string]$Path,
  [int]$Y = 900,
  [int]$XFrom = 700, [int]$XTo = 900
)
Add-Type -AssemblyName System.Drawing
$bmp = [System.Drawing.Bitmap]::new($Path)
$w = $bmp.Width
$rect = [System.Drawing.Rectangle]::new(0, $Y, $w, 1)
$data = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$bytes = New-Object byte[] ($data.Stride)
[System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $bytes, 0, $data.Stride)
$bmp.UnlockBits($data)
$nonWhite = @()
for ($x = $XFrom; $x -le $XTo; $x++) {
  $i = $x * 4
  $v = ([int]$bytes[$i+2] + [int]$bytes[$i+1] + [int]$bytes[$i]) / 3
  if ($v -lt 250) { $nonWhite += ('{0}:{1:X2}{2:X2}{3:X2}' -f $x, $bytes[$i+2], $bytes[$i+1], $bytes[$i]) }
}
$bmp.Dispose()
Write-Output ('file=' + (Split-Path $Path -Leaf) + ' y=' + $Y + ' window=x[' + $XFrom + ',' + $XTo + ']')
Write-Output ('nonWhiteColumns=' + $nonWhite.Count + ' -> ' + ($nonWhite -join ' '))
