<#
    Interactive helper: launch a build, then drive it a step at a time while
    capturing the window so the exact menu path into a level can be worked out
    before it is baked into the benchmark harness.
#>
[CmdletBinding()]
param(
    [string]$Exe = "P:\Programming Repositories\eden\build\bin\eden.exe",
    [string]$Rom = "G:\Games (Master Folder)\Nintendo\Switch\Super Mario Bros. Wonder (XCI)\Super Mario Bros. Wonder [010015100B514000][v0][Base][nxbrew.com].xci",
    [int]$BootSeconds = 45,
    [string]$ShotDir = "$env:TEMP\edenshots"
)

$ErrorActionPreference = 'Stop'
Import-Module "P:\Programming Repositories\eden\tools\EdenAutomation.psm1" -Force

New-Item -ItemType Directory -Force -Path $ShotDir | Out-Null
Get-ChildItem $ShotDir -Filter *.png -ErrorAction SilentlyContinue | Remove-Item -Force

Get-Process eden -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep 3

$proc = Start-Process -FilePath $Exe -ArgumentList "-g `"$Rom`"" -PassThru
Write-Output "launched pid $($proc.Id), waiting $BootSeconds s for boot..."
Start-Sleep $BootSeconds

if ($proc.HasExited) { throw "eden exited during boot with $($proc.ExitCode)" }

$h = Get-EdenWindow -ProcessId $proc.Id
if ($h -eq [IntPtr]::Zero) { throw "no main window" }
Write-Output "window handle: $h"

$focused = Set-EdenFocus -Handle $h
Write-Output "focused: $focused"

$p = Join-Path $ShotDir "00_boot.png"
$ok = Save-EdenFrame -Handle $h -Path $p
Write-Output "capture 00_boot: $ok -> $p"
Write-Output "PID=$($proc.Id) HWND=$h"
