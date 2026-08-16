<#
.SYNOPSIS
    A/B the graphics-pipeline-library path against itself, same binary.

.DESCRIPTION
    Tests whether GPL explains the fork's two regressions: GPU busy +9.7%
    (locked) and the ~7% cold-cache loss. Both arms run the SAME eden.exe,
    switched by EDEN_DISABLE_GPL, so no codegen difference can leak in.
    Requires the EDEN_DISABLE_GPL gate in vk_graphics_pipeline.cpp.
#>
[CmdletBinding()]
param(
    [int]$Runs = 3,
    [int]$CaptureSeconds = 60,
    [string]$Root = "P:\Programming Repositories\eden"
)

$ErrorActionPreference = 'Continue'
$tools = Join-Path $Root 'tools'
$baseSnapshot = Join-Path $Root 'build\bench\save_snapshot'
if (-not (Test-Path $baseSnapshot)) { throw "no save snapshot at $baseSnapshot" }

function Invoke-Arm {
    param([string]$Name, [string]$DisableGpl)

    $outDir  = Join-Path $Root "build\bench_$Name"
    $shotDir = Join-Path $Root "build\bench_shots_$Name"
    New-Item -ItemType Directory -Force -Path $outDir, $shotDir | Out-Null

    # Seed each arm with the same save so Bench-Gameplay's Backup-Save finds one
    # already present and both arms start the identical level and position.
    $armSnapshot = Join-Path $outDir 'save_snapshot'
    if (-not (Test-Path $armSnapshot)) {
        New-Item -ItemType Directory -Force -Path $armSnapshot | Out-Null
        Copy-Item "$baseSnapshot\*" $armSnapshot -Recurse -Force
    }

    $env:EDEN_DISABLE_GPL = $DisableGpl
    Write-Output "===== arm '$Name'  EDEN_DISABLE_GPL='$DisableGpl' ====="
    & "$tools\cleanup_bench.ps1" | Out-Null

    & "$tools\Bench-Gameplay.ps1" -OursOnly -Runs $Runs -CaptureSeconds $CaptureSeconds `
        -OutDir $outDir -ShotDir $shotDir
    & "$tools\Bench-Gameplay.ps1" -OursOnly -Runs $Runs -CaptureSeconds $CaptureSeconds `
        -LockedSpeed -OutDir $outDir -ShotDir $shotDir

    Remove-Item Env:\EDEN_DISABLE_GPL -ErrorAction SilentlyContinue
}

Invoke-Arm -Name 'gpl_on'  -DisableGpl ''
Invoke-Arm -Name 'gpl_off' -DisableGpl '1'

# ------------------------------------------------------------------ summary
function Read-Arm {
    param([string]$Name, [string]$Mode)
    $p = Join-Path $Root "build\bench_$Name\gameplay_results_$Mode.json"
    if (-not (Test-Path $p)) { return @() }
    return @(Get-Content $p -Raw | ConvertFrom-Json | Where-Object { $null -eq $_.error })
}

$rep = New-Object System.Collections.Generic.List[string]
foreach ($mode in @('uncapped','locked')) {
    $rep.Add(""); $rep.Add("=== $mode ===")
    foreach ($arm in @('gpl_on','gpl_off')) {
        $rows = Read-Arm -Name $arm -Mode $mode
        if (-not $rows) { $rep.Add(("{0,-8} no results" -f $arm)); continue }
        $cold = $rows | Select-Object -First 1
        $warm = $rows | Select-Object -Skip 1
        $rep.Add(("{0,-8} cold: {1,6:N2} fps  {2,4} f>20ms  gpu {3,5:N3}" -f `
            $arm, $cold.mean_fps, $cold.frames_over_20ms, $cold.gpu_busy_ms))
        if ($warm) {
            $mf  = ($warm | Measure-Object mean_fps -Average).Average
            $gpu = ($warm | Measure-Object gpu_busy_ms -Average).Average
            $lo  = ($warm | Measure-Object low_1pct_fps -Average).Average
            $s20 = ($warm | Measure-Object frames_over_20ms -Sum).Sum
            $rep.Add(("{0,-8} warm: {1,6:N2} fps  {2,4} f>20ms  gpu {3,5:N3}  1%low {4,6:N2}" -f `
                $arm, $mf, $s20, $gpu, $lo))
        }
    }
}
$rep.Add("")
$rep.Add("Read: if gpl_off recovers BOTH gpu-busy and the cold-cache figure, GPL is the")
$rep.Add("cause -> make it opt-in per driver. If only gpu-busy recovers, keep fast-linking")
$rep.Add("for the first draw and re-link with link-time-optimization in the background.")
$rep.Add("If neither moves, the hypothesis is wrong; next suspects are P1 and P3.")

$out = Join-Path $Root 'build\gpl_ab_summary.txt'
$rep | Set-Content $out
$rep | Write-Output
Write-Output ""
Write-Output "summary -> $out"
