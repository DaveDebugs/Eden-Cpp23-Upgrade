<#
    GPL A/B on pipeline build cost, with BOTH shader caches cleared per boot.

    The first attempt cleared only Eden's cache and produced a 15x gap in rep 1
    that vanished in rep 2 -- an ordering artifact, because NVIDIA keeps its own
    Vulkan shader cache in %LOCALAPPDATA%\NVIDIA\GLCache and whichever path ran
    second inherited warm driver state. Both caches are cleared before every
    boot here, and the arms run counterbalanced (on, off, off, on) so any
    residual warm-up effect cancels instead of loading onto one arm.

    Clearing GLCache makes other titles recompile their shaders once; the cache
    rebuilds itself automatically.
#>
param([int]$BootSeconds = 70, [int]$SeqOffset = 0, [string]$Order = 'gpl_on,gpl_off,gpl_off,gpl_on')

$ErrorActionPreference = 'Continue'
$exe = "P:\Programming Repositories\eden\build\bin\eden.exe"
$rom = "G:\Games (Master Folder)\Nintendo\Switch\Super Mario Bros. Wonder (XCI)\Super Mario Bros. Wonder [010015100B514000][v0][Base][nxbrew.com].xci"
$cacheDir = Join-Path $env:APPDATA "eden\cache\shader\010015100b514000"
$glCache  = "$env:LOCALAPPDATA\NVIDIA\GLCache"
$edenLog  = Join-Path $env:APPDATA 'eden\log\eden_log.txt'
$outDir   = "P:\Programming Repositories\eden\build\gpl_pipeline2"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

function Invoke-Boot {
    param([string]$Name, [string]$Disable, [int]$Seq)

    Get-Process eden -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep 4

    if (Test-Path $cacheDir) { Remove-Item "$cacheDir\*" -Recurse -Force -ErrorAction SilentlyContinue }
    if (Test-Path $glCache)  { Remove-Item "$glCache\*"  -Recurse -Force -ErrorAction SilentlyContinue }
    Remove-Item $edenLog -Force -ErrorAction SilentlyContinue

    $env:EDEN_DISABLE_GPL = $Disable
    $p = Start-Process $exe -ArgumentList "-g `"$rom`"" -PassThru
    Start-Sleep $BootSeconds
    if (-not $p.HasExited) { $p.CloseMainWindow() | Out-Null; Start-Sleep 10 }
    if (-not $p.HasExited) { $p.Kill() }
    Remove-Item Env:\EDEN_DISABLE_GPL -ErrorAction SilentlyContinue
    Start-Sleep 2

    $dest = Join-Path $outDir ("{0}_seq{1}.log" -f $Name, $Seq)
    if (Test-Path $edenLog) { Copy-Item $edenLog $dest -Force }
    Write-Output ("  boot {0} ({1}) done" -f $Seq, $Name)
    return $dest
}

function Measure-Log {
    param([string]$Path, [string]$Label)
    if (-not (Test-Path $Path)) { Write-Output ("{0,-14} : no log" -f $Label); return $null }
    $hits = Select-String -Path $Path -Pattern 'PIPELINE_BUILD path=(\w+) us=(\d+)'
    if (-not $hits) { Write-Output ("{0,-14} : no PIPELINE_BUILD lines" -f $Label); return $null }
    $us = @(); $paths = @{}
    foreach ($h in $hits) {
        $m = [regex]::Match($h.Line, 'path=(\w+) us=(\d+)')
        if ($m.Success) {
            $us += [int]$m.Groups[2].Value
            $k = $m.Groups[1].Value
            if ($paths.ContainsKey($k)) { $paths[$k]++ } else { $paths[$k] = 1 }
        }
    }
    $sorted = $us | Sort-Object; $n = $sorted.Count
    $sum = ($us | Measure-Object -Sum).Sum
    Write-Output ("{0,-14} n={1,4}  total={2,8:N1} ms  mean={3,7:N0} us  median={4,7:N0} us  p95={5,8:N0} us  [{6}]" -f `
        $Label, $n, ($sum/1000.0), ($sum/$n), $sorted[[int][Math]::Floor($n/2)],
        $sorted[[Math]::Max(0,[int][Math]::Floor($n*0.95)-1)],
        (($paths.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ','))
    return [pscustomobject]@{ label=$Label; arm=($Label -split ' ')[0]; n=$n; total_ms=($sum/1000.0) }
}

$plan = @()
foreach ($nm in ($Order -split ',')) {
    $nm = $nm.Trim()
    $plan += ,@($nm, $(if ($nm -eq 'gpl_off') { '1' } else { '' }))
}
$logs = @()
for ($i = 0; $i -lt $plan.Count; $i++) {
    $seq = $i + 1 + $SeqOffset
    Write-Output ("=== boot {0}/{1}: {2} (both caches cleared) ===" -f ($i+1), $plan.Count, $plan[$i][0])
    Invoke-Boot -Name $plan[$i][0] -Disable $plan[$i][1] -Seq $seq | Out-Null
}
Write-Output "all boots complete; run Analyze-GplPipelines.ps1"
