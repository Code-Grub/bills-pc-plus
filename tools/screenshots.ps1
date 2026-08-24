# README screenshot pipeline for Bill's PC Plus.
#
# Runs the engine under LÖVE with the scripted driver, then crops each
# capture to the game canvas (dropping the desktop-window letterbox) and
# writes the two README images. Everything is deterministic: a sandboxed
# save identity, a seeded box, fixed cursor positions.
#
# Usage:
#   powershell -File tools\screenshots.ps1
# Optional overrides:
#   -Game   path to the engine checkout (default ..\..\game)
#   -Love   path to love.exe              (default ..\..\tools\love\love.exe)
#   -Out    output dir for the images     (default ..\images)
param(
  [string]$Game = "$(Split-Path (Split-Path $PSScriptRoot -Parent) -Parent)\game",
  [string]$Love = "$(Split-Path (Split-Path $PSScriptRoot -Parent) -Parent)\tools\love\love.exe",
  [string]$Out = "$(Split-Path $PSScriptRoot -Parent)\images"
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

if (-not (Test-Path "$Game\main.lua")) { throw "engine checkout not found at $Game" }
if (-not (Test-Path $Love)) { throw "love.exe not found at $Love" }

# A sandbox save identity cloned from the real one: the driver overwrites
# boxes and party in memory, and this keeps that entirely away from the
# save the player actually uses. The clone carries the extracted ROM data,
# which a fresh identity would not have.
$srcId = "$env:APPDATA\LOVE\pokemon-love2d"
$id = "$env:APPDATA\LOVE\bills-pc-plus-shots"
if (-not (Test-Path $srcId)) { throw "no save identity at $srcId - run the game once first" }
if (Test-Path $id) { Remove-Item $id -Recurse -Force }
Copy-Item $srcId $id -Recurse

$shots = "$env:TEMP\bpc_shots"
if (Test-Path $shots) { Remove-Item $shots -Recurse -Force }
New-Item -ItemType Directory -Path $shots -Force | Out-Null

$env:POKEPORT_DRIVER = "$PSScriptRoot\screenshots.lua"
$env:SHOT_DIR = $shots
$env:POKEPORT_IDENTITY = "bills-pc-plus-shots"
$env:POKEPORT_TOUCH = "0"

Push-Location $Game
try {
  # love's stderr (the driver's POSIX mkdir probe, font probes) is noise;
  # do not let it trip ErrorActionPreference
  $eap = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try { & $Love . 2>&1 | Out-Null } finally { $ErrorActionPreference = $eap }
} finally { Pop-Location }

# Crop one capture to the game canvas: sample the letterbox colour from a
# corner, then find the content bounds by scanning inward.
function Crop-Canvas([string]$path, [string]$dest) {
  $img = [System.Drawing.Bitmap]::FromFile($path)
  $bg = $img.GetPixel(2, 2)
  $same = { $c = $args[0]; [Math]::Abs($c.R - $bg.R) -le 6 -and [Math]::Abs($c.G - $bg.G) -le 6 -and [Math]::Abs($c.B - $bg.B) -le 6 }

  $top = 0; while ($top -lt $img.Height - 1) { $rowClear = $true; for ($x = 0; $x -lt $img.Width; $x += 4) { if (-not (& $same $img.GetPixel($x, $top))) { $rowClear = $false; break } }; if (-not $rowClear) { break }; $top++ }
  $bot = $img.Height - 1; while ($bot -gt $top) { $rowClear = $true; for ($x = 0; $x -lt $img.Width; $x += 4) { if (-not (& $same $img.GetPixel($x, $bot))) { $rowClear = $false; break } }; if (-not $rowClear) { break }; $bot-- }
  $left = 0; while ($left -lt $img.Width - 1) { $colClear = $true; for ($y = $top; $y -le $bot; $y += 4) { if (-not (& $same $img.GetPixel($left, $y))) { $colClear = $false; break } }; if (-not $colClear) { break }; $left++ }
  $right = $img.Width - 1; while ($right -gt $left) { $colClear = $true; for ($y = $top; $y -le $bot; $y += 4) { if (-not (& $same $img.GetPixel($right, $y))) { $colClear = $false; break } }; if (-not $colClear) { break }; $right-- }

  $w = $right - $left + 1; $h = $bot - $top + 1
  $crop = $img.Clone((New-Object System.Drawing.Rectangle($left, $top, $w, $h)), $img.PixelFormat)
  $crop.Save($dest, [System.Drawing.Imaging.ImageFormat]::Png)
  $crop.Dispose(); $img.Dispose()
  "{0}: {1}x{2} from {3}" -f (Split-Path $dest -Leaf), $w, $h, (Split-Path $path -Leaf)
}

if (-not (Test-Path $Out)) { New-Item -ItemType Directory -Path $Out -Force | Out-Null }
Crop-Canvas "$shots\screen_box.png" "$Out\screen_box.png"
Crop-Canvas "$shots\screen_deposit.png" "$Out\screen_deposit.png"
Write-Output "README images written to $Out"
