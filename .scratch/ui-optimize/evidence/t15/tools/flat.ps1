param([Parameter(Mandatory=$true)][string]$Path, [string]$Filter = '')
$json = Get-Content -Raw -Path $Path | ConvertFrom-Json
function Walk($node, $depth) {
  $t = $node.attributes.type
  $b = $node.attributes.bounds
  $x = $node.attributes.text
  $line = (' ' * ($depth * 2)) + $t + ' ' + $b
  if ($x) { $line = $line + ' text=' + ($x -replace '\s+',' ') }
  if ($node.attributes.clickable -eq 'true') { $line = $line + ' clickable' }
  if (-not $Filter -or $line -match $Filter) { $line }
  if ($node.children) { foreach ($c in $node.children) { Walk $c ($depth + 1) } }
}
function WalkFlat($node) {
  $t = $node.attributes.type
  $b = $node.attributes.bounds
  $x = $node.attributes.text
  $line = $t + ' ' + $b
  if ($x) { $line = $line + ' text=' + ($x -replace '\s+',' ') }
  if ($node.attributes.clickable -eq 'true') { $line = $line + ' clickable' }
  if (-not $Filter -or $line -match $Filter) { $line }
  if ($node.children) { foreach ($c in $node.children) { WalkFlat $c } }
}
WalkFlat $json

