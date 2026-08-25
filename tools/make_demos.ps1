# Separate Box vs Deposit demos for Bill's PC Plus.
# Runs two deterministic drivers and assembles two GIFs:
#   images/demo_box.gif      - withdraw / grab-and-place / paging
#   images/demo_deposit.gif  - party row / destination paging / deposit
# Usage: powershell -File tools\make_demos.ps1
param(
  [string]$Game = "$(Split-Path (Split-Path $PSScriptRoot -Parent) -Parent)\game",
  [string]$Love = "$(Split-Path (Split-Path $PSScriptRoot -Parent) -Parent)\tools\love\love.exe",
  [string]$OutDir = "$(Split-Path $PSScriptRoot -Parent)\images",
  [int]$Scale = 3,
  [int]$Delay = 40,
  [int]$Loop = 0
)
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

if (-not (Test-Path "$Game\main.lua")) { throw "engine checkout not found at $Game" }
if (-not (Test-Path $Love)) { throw "love.exe not found at $Love" }

function Get-CanvasBounds([string]$path) {
  $img = [System.Drawing.Bitmap]::FromFile($path)
  $bg = $img.GetPixel(2,2)
  $same = { param($c) [Math]::Abs($c.R - $bg.R) -le 6 -and [Math]::Abs($c.G - $bg.G) -le 6 -and [Math]::Abs($c.B - $bg.B) -le 6 }
  $top = 0; while ($top -lt $img.Height -1) { $clear=$true; for($x=0;$x -lt $img.Width;$x+=4){ if(-not (& $same $img.GetPixel($x,$top))){$clear=$false;break}} if(-not $clear){break}; $top++ }
  $bot = $img.Height-1; while($bot -gt $top){ $clear=$true; for($x=0;$x -lt $img.Width;$x+=4){ if(-not (& $same $img.GetPixel($x,$bot))){$clear=$false;break}} if(-not $clear){break}; $bot-- }
  $left = 0; while($left -lt $img.Width-1){ $clear=$true; for($y=$top;$y -le $bot;$y+=4){ if(-not (& $same $img.GetPixel($left,$y))){$clear=$false;break}} if(-not $clear){break}; $left++ }
  $right = $img.Width-1; while($right -gt $left){ $clear=$true; for($y=$top;$y -le $bot;$y+=4){ if(-not (& $same $img.GetPixel($right,$y))){$clear=$false;break}} if(-not $clear){break}; $right-- }
  $r = @{ Left=$left; Top=$top; Width=$right-$left+1; Height=$bot-$top+1; Img=$img }
  return $r
}
function New-DelayProperty([int]$count, [int]$delay) {
  $pi = [System.Runtime.Serialization.FormatterServices]::GetUninitializedObject([System.Drawing.Imaging.PropertyItem])
  $pi.Id = 0x5100; $pi.Type = 4; $pi.Len = $count * 4
  $bytes = New-Object byte[] ($count * 4)
  for ($i=0; $i -lt $count; $i++) { [BitConverter]::GetBytes([int]$delay).CopyTo($bytes, $i*4) }
  $pi.Value = $bytes; return $pi
}
function New-LoopProperty([int]$loop) {
  $pi = [System.Runtime.Serialization.FormatterServices]::GetUninitializedObject([System.Drawing.Imaging.PropertyItem])
  $pi.Id = 0x5110; $pi.Type = 3; $pi.Len = 2; $pi.Value = [BitConverter]::GetBytes([int16]$loop); return $pi
}
function Invoke-Demo([string]$driver, [string]$out) {
  $srcId = "$env:APPDATA\LOVE\pokemon-love2d"
  $id = "$env:APPDATA\LOVE\bills-pc-plus-shots"
  if (-not (Test-Path $srcId)) { throw "no save identity at $srcId - run the game once first" }
  if (Test-Path $id) { Remove-Item $id -Recurse -Force }
  Copy-Item $srcId $id -Recurse
  $shots = "$env:TEMP\bpc_frames"
  if (Test-Path $shots) { Remove-Item $shots -Recurse -Force }
  New-Item -ItemType Directory -Path $shots -Force | Out-Null
  $env:POKEPORT_DRIVER = $driver
  $env:SHOT_DIR = $shots
  $env:POKEPORT_IDENTITY = "bills-pc-plus-shots"
  $env:POKEPORT_TOUCH = "0"
  Write-Host "Running $driver -> $shots ..."
  Push-Location $Game
  try {
    $eap = $ErrorActionPreference; $ErrorActionPreference = "Continue"
    try { & $Love . 2>&1 | Out-Null } finally { $ErrorActionPreference = $eap }
  } finally { Pop-Location }
  $frames = Get-ChildItem "$shots\frame_*.png" | Sort-Object Name
  if ($frames.Count -eq 0) { throw "no frames from $driver" }
  Write-Host "$($frames.Count) frames captured for $(Split-Path $out -Leaf)"
  $nativeW = 160; $nativeH = 144
  $b0 = Get-CanvasBounds $frames[0].FullName; $b0.Img.Dispose()
  $targetW = $nativeW * $Scale; $targetH = $nativeH * $Scale
  $tmp = "$env:TEMP\bpc_cropped"
  if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
  New-Item -ItemType Directory -Path $tmp -Force | Out-Null
  $paths = @()
  foreach ($f in $frames) {
    $src = [System.Drawing.Bitmap]::FromFile($f.FullName)
    $b = Get-CanvasBounds $f.FullName
    $src2 = $src; $src = $src.Clone([System.Drawing.Rectangle]::new($b.Left,$b.Top,$b.Width,$b.Height),$src.PixelFormat)
    $src2.Dispose(); $b.Img.Dispose()
    $dst = New-Object System.Drawing.Bitmap($targetW,$targetH)
    $g = [System.Drawing.Graphics]::FromImage($dst)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
    $g.DrawImage($src,0,0,$targetW,$targetH); $g.Dispose(); $src.Dispose()
    $p = Join-Path $tmp $f.Name; $dst.Save($p,[System.Drawing.Imaging.ImageFormat]::Png); $dst.Dispose(); $paths += $p
  }
  $outDir = Split-Path $out -Parent; if ($outDir -and -not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
  $enc = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq "image/gif" }
  $first = [System.Drawing.Bitmap]::FromFile($paths[0])
  $first.SetPropertyItem((New-DelayProperty $paths.Count $Delay))
  $first.SetPropertyItem((New-LoopProperty $Loop))
  $ep = New-Object System.Drawing.Imaging.EncoderParameters(1)
  $ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::SaveFlag,[long][System.Drawing.Imaging.EncoderValue]::MultiFrame)
  $first.Save($out,$enc,$ep)
  $ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::SaveFlag,[long][System.Drawing.Imaging.EncoderValue]::FrameDimensionTime)
  for ($i=1; $i -lt $paths.Count; $i++) { $bmp=[System.Drawing.Bitmap]::FromFile($paths[$i]); $first.SaveAdd($bmp,$ep); $bmp.Dispose() }
  $ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::SaveFlag,[long][System.Drawing.Imaging.EncoderValue]::Flush)
  $first.SaveAdd($ep); $first.Dispose()
  Remove-Item $tmp -Recurse -Force
  Write-Host "GIF -> $out ($($paths.Count) frames) - file:///$($out -replace '\\','/')"
}

Invoke-Demo "$PSScriptRoot\record_box.lua" "$OutDir\demo_box.gif"
Invoke-Demo "$PSScriptRoot\record_deposit.lua" "$OutDir\demo_deposit.gif"
Write-Host "Done. Both demos in $OutDir"
