<#
    GPL A/B by direct in-process measurement of pipeline build cost.

    Boot-only: no synthetic input, no window focus, no ETW. Each arm clears the
    shader cache so every pipeline is built from scratch, boots the title once,
    and the emulator logs one PIPELINE_BUILD line per pipeline with the
    microseconds it took and which path built it.
#>
param(
    [int]$BootSeconds = 70,
    [int]$Reps = 2
)
$ErrorActionPreference = 'Continue'
$exe = "P:\Programming Repositories\eden\build\bin\eden.exe"
$rom = "G:\Games (Master Folder)\Nintendo\Switch\Super Mario Bros. Wonder (XCI)\Super Mario Bros. Wonder [010015100B514000][v0][Base][nxbrew.com].xci"
$titleId = "010015100b514000"
$cacheDir = Join-Path $env:APPDATA "eden\cache\shader\$titleId"
$edenLog = Join-Path $env:APPDATA 'eden\log\eden_log.txt'
$outDir = "P:\Programming Repositories\eden\build\gpl_pipeline"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

function Invoke-Arm {
    param([string]$Name, [string]$Disable, [int]$Rep)

    Get-Process eden -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep 3

    # Cold cache every time: the driver must actually build each pipeline.
    if (Test-Path $cacheDir) { Remove-Item "$cacheDir\*" -Recurse -Force -ErrorAction SilentlyContinue }
    Remove-Item $edenLog -Force -ErrorAction SilentlyContinue

    $env:EDEN_DISABLE_GPL = $Disable
    $p = Start-Process $exe -ArgumentList "-g `"$rom`"" -PassThru
    Start-Sleep $BootSeconds
    if (-not $p.HasExited) { $p.CloseMainWindow() | Out-Null; Start-Sleep 10 }
    if (-not $p.HasExited) { $p.Kill() }
    Remove-Item Env:\EDEN_DISABLE_GPL -ErrorAction SilentlyContinue
    Start-Sleep 2

    $dest = Join-Path $outDir "$Name`_rep$Rep.log"
    if (Test-Path $edenLog) { Copy-Item $edenLog $dest -Force }
    return $dest
}

function Measure-Log {
    param([string]$Path, [string]$Label)
    if (-not (Test-Path $Path)) { Write-Output "$Label : no log"; return }
    $hits = Select-String -Path $Path -Pattern 'PIPELINE_BUILD path=(\w+) us=(\d+)'
    if (-not $hits) { Write-Output "$Label : no PIPELINE_BUILD lines"; return }
    $us = @(); $paths = @{}
    foreach ($h in $hits) {
        $m = [regex]::Match($h.Line, 'path=(\w+) us=(\d+)')
        if ($m.Success) {
            $us += [int]$m.Groups[2].Value
            $k = $m.Groups[1].Value
            if ($paths.ContainsKey($k)) { $paths[$k]++ } else { $paths[$k] = 1 }
        }
    }
    $sorted = $us | Sort-Object
    $n = $sorted.Count
    $sum = ($us | Measure-Object -Sum).Sum
    $median = $sorted[[int][Math]::Floor($n/2)]
    $p95 = $sorted[[Math]::Max(0,[int][Math]::Floor($n*0.95)-1)]
    Write-Output ("{0,-16} n={1,4}  total={2,8:N1} ms  mean={3,7:N0} us  median={4,7:N0} us  p95={5,8:N0} us  paths={6}" -f `
        $Label, $n, ($sum/1000.0), ($sum/$n), $median, $p95, (($paths.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ','))
}

$results = @()
for ($r = 1; $r -le $Reps; $r++) {
    Write-Output "=== rep $r : GPL ON ==="
    $results += ,@('gpl_on', (Invoke-Arm -Name 'gpl_on' -Disable '' -Rep $r), $r)
    Write-Output "=== rep $r : GPL OFF ==="
    $results += ,@('gpl_off', (Invoke-Arm -Name 'gpl_off' -Disable '1' -Rep $r), $r)
}

Write-Output ""
Write-Output "================= PIPELINE BUILD COST ================="
foreach ($e in $results) { Measure-Log -Path $e[1] -Label ("{0} rep{1}" -f $e[0], $e[2]) }
