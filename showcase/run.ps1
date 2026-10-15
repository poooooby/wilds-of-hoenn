# Plays the trailer reel from PowerShell: .\showcase\run.ps1 emerald [shot number | shot name]
# (or showcase\run.cmd ..., which bypasses the execution policy). Same as run.sh: needs this
# repo linked into a sibling ..\gen1recomp checkout (scripts\bootstrap.sh) with the game's
# ROM imported; your gen1recomp options.lua is backed up first and put back afterwards.
param(
  [string]$Game = "emerald",
  [string]$Start = "1"
)
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = if ($env:GEN1RECOMP_ROOT) { $env:GEN1RECOMP_ROOT } else { Join-Path $here "..\..\gen1recomp" }
$love = if ($env:LOVE) { $env:LOVE } else { "C:\Program Files\LOVE\lovec.exe" }
if (-not (Test-Path (Join-Path $root "main.lua"))) { Write-Error "no gen1recomp checkout at $root"; exit 9 }
$backup = Join-Path $env:TEMP "showcase_options_backup.lua"
Copy-Item (Join-Path $root "options.lua") $backup -Force
$only = ""
if ($Start -notmatch '^\d+$') { $only = $Start; $Start = "1" }
Push-Location $root
try {
  $env:POKEPORT_VERSION = $Game
  $env:POKEPORT_DRIVER = Join-Path $here "director.lua"
  # a driver run steps the game once per rendered frame; paced (plus the director's
  # 60 fps cap) it runs at 1x on any display
  $env:POKEPORT_DRIVER_PACED = "1"
  $env:SHOWCASE_DIR = $here
  $env:SHOWCASE_START = $Start
  $env:SHOWCASE_ONLY = $only
  & $love .
  $rc = $LASTEXITCODE
} finally {
  Copy-Item $backup (Join-Path $root "options.lua") -Force
  Pop-Location
  Remove-Item Env:POKEPORT_VERSION, Env:POKEPORT_DRIVER, Env:POKEPORT_DRIVER_PACED, Env:SHOWCASE_DIR, Env:SHOWCASE_START, Env:SHOWCASE_ONLY -ErrorAction SilentlyContinue
}
Write-Host "showcase exited ($rc); options.lua restored"
