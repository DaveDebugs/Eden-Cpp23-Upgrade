<#
.SYNOPSIS
    Per-thread CPU profile of Eden taken during actual gameplay.

.DESCRIPTION
    The earlier thread profile that showed HostTiming burning 99.3% of a core
    was taken on a title screen, the same flawed condition as the original
    benchmark. A polling loop should burn a core regardless of scene, but that
    is a prediction, not a measurement -- and the interesting question is what
    the ratio between HostTiming and the guest CPU cores looks like once there
    is real work to do.

    This drives the emulator into a level exactly as the benchmark harness
    does, then samples per-thread CPU while the workload keeps running.
#>
[CmdletBinding()]
param(
    [string]$Exe = "P:\Programming Repositories\eden\build\bin\eden.exe",
    [string]$Rom = "G:\Games (Master Folder)\Nintendo\Switch\Super Mario Bros. Wonder (XCI)\Super Mario Bros. Wonder [010015100B514000][v0][Base][nxbrew.com].xci",
    [int]$BootSeconds = 45,
    [int]$ProfileSeconds = 40,
    [switch]$LockedSpeed,
    [string]$OutFile = "P:\Programming Repositories\eden\build\bench\thread_profile_gameplay.txt"
)

$ErrorActionPreference = 'Stop'
$tools = "P:\Programming Repositories\eden\tools"
Import-Module "$tools\EdenAutomation.psm1" -Force

& "$tools\cleanup_bench.ps1" | Out-Null

$cfgArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "$tools\Set-BenchConfig.ps1", '-Mode', 'Bench')
if ($LockedSpeed) { $cfgArgs += '-KeepSpeedLimit' }
& powershell @cfgArgs | Out-Null

$saveDir = "$env:APPDATA\eden\nand\user\save\0000000000000000\100CD2D277EABCA37ADECD26D3BD8B41\010015100B514000"
$snap    = "P:\Programming Repositories\eden\build\bench\save_snapshot"
if (Test-Path $snap) {
    Remove-Item "$saveDir\*" -Recurse -Force -ErrorAction SilentlyContinue
    Copy-Item "$snap\*" $saveDir -Recurse -Force
}

$proc = Start-Process -FilePath $Exe -ArgumentList "-g `"$Rom`"" -PassThru
Start-Sleep $BootSeconds
$h = Get-EdenWindow -ProcessId $proc.Id
Set-EdenFocus -Handle $h | Out-Null

$nav = 'wait:2, L+R, wait:5, A, wait:4, A, wait:4, DRight*10, wait:1, A, wait:6, A, wait:5, DUp:600, wait:2, A, wait:7, A, wait:9'
& "$tools\Step-Nav.ps1" -Sequence $nav -ShotName "profile_entered" | Out-Null

# Keep the game moving from a separate process while this one samples threads.
# Synthetic keystrokes go to whatever window has focus, so the injector does
# not need to be the profiler.
$job = Start-Job -ScriptBlock {
    param($tools, $secs)
    Import-Module "$tools\EdenAutomation.psm1" -Force
    $end = (Get-Date).AddSeconds($secs)
    Set-EdenButtonState -Button 'DRight' -Down
    while ((Get-Date) -lt $end) {
        Set-EdenButtonState -Button 'B' -Down
        Start-Sleep -Milliseconds 130
        Set-EdenButtonState -Button 'B'
        Start-Sleep -Milliseconds 620
    }
    Set-EdenButtonState -Button 'DRight'
} -ArgumentList $tools, ($ProfileSeconds + 10)

Start-Sleep 3
$mode = if ($LockedSpeed) { 'locked to 100% speed' } else { 'speed limiter off' }
$report = & "$tools\Get-EdenThreadNames.ps1" -Seconds $ProfileSeconds

Save-EdenFrame -Handle $h -Path "P:\Programming Repositories\eden\build\bench_shots\profile_during.png" | Out-Null

Stop-Job $job -ErrorAction SilentlyContinue
Remove-Job $job -Force -ErrorAction SilentlyContinue

$header = @(
    "Eden per-thread CPU during gameplay",
    "build : $Exe",
    "mode  : $mode",
    "window: $ProfileSeconds s, sampled while the level was running",
    ""
)
($header + $report) | Set-Content $OutFile
($header + $report) | Write-Output

if (-not $proc.HasExited) { $proc.CloseMainWindow() | Out-Null; Start-Sleep 10 }
if (-not $proc.HasExited) { $proc.Kill() }
& powershell -NoProfile -ExecutionPolicy Bypass -File "$tools\Set-BenchConfig.ps1" -Mode Restore | Out-Null
