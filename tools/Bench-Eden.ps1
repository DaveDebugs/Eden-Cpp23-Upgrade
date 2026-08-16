<#
.SYNOPSIS
    Build-agnostic FPS benchmark for Eden, by sampling the window title.

.DESCRIPTION
    Both official Eden and this fork report live FPS in the main window title
    ("... | FPS: 60 (100%)"). Sampling that gives a metric that needs no
    instrumentation in either binary, so an unmodified upstream build and a
    modified one can be compared on equal terms.

    Reports mean, median, min, max, 1% low and 5% low, plus samples collected.

.EXAMPLE
    .\Bench-Eden.ps1 -Exe "P:\...\eden-official\eden.exe" -Label official -Seconds 90
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Exe,
    [Parameter(Mandatory)][string]$Label,
    [string]$Rom = "G:\Games (Master Folder)\Nintendo\Switch\Super Mario Bros. Wonder (XCI)\Super Mario Bros. Wonder [010015100B514000][v0][Base][nxbrew.com].xci",
    [int]$Seconds = 90,
    [int]$WarmupSeconds = 20,
    [int]$IntervalMs = 250,
    [switch]$ClearCache,
    [string]$TitleId = "010015100b514000",
    [string]$OutJson
)

$ErrorActionPreference = 'Stop'

if ($ClearCache) {
    $cacheDir = Join-Path $env:APPDATA "eden\cache\shader\$TitleId"
    if (Test-Path $cacheDir) {
        Remove-Item "$cacheDir\*" -Force -ErrorAction SilentlyContinue
        Write-Host "[$Label] shader cache cleared (cold run)" -ForegroundColor Yellow
    }
}

Write-Host "[$Label] launching $Exe" -ForegroundColor Cyan
$proc = Start-Process -FilePath $Exe -ArgumentList "-g `"$Rom`"" -PassThru

# Let it boot and settle before sampling, so shader preload / startup cost
# doesn't pollute the steady-state numbers.
Write-Host "[$Label] warmup ${WarmupSeconds}s..." -ForegroundColor DarkGray
$bootStart = Get-Date
$firstFps = $null
while (((Get-Date) - $bootStart).TotalSeconds -lt $WarmupSeconds) {
    Start-Sleep -Milliseconds 500
    if ($proc.HasExited) { Write-Warning "[$Label] exited during warmup (code $($proc.ExitCode))"; return }
    $proc.Refresh()
    if (-not $firstFps -and $proc.MainWindowTitle -match 'FPS:\s*([\d.]+)') {
        $firstFps = [double]$matches[1]
        $timeToFps = ((Get-Date) - $bootStart).TotalSeconds
        Write-Host "[$Label] first FPS reading after ${timeToFps}s" -ForegroundColor DarkGray
    }
}

Write-Host "[$Label] sampling ${Seconds}s..." -ForegroundColor DarkGray
$samples = New-Object System.Collections.Generic.List[double]
$deadline = (Get-Date).AddSeconds($Seconds)
while ((Get-Date) -lt $deadline) {
    if ($proc.HasExited) { Write-Warning "[$Label] exited during sampling (code $($proc.ExitCode))"; break }
    $proc.Refresh()
    if ($proc.MainWindowTitle -match 'FPS:\s*([\d.]+)') {
        $samples.Add([double]$matches[1])
    }
    Start-Sleep -Milliseconds $IntervalMs
}

if (-not $proc.HasExited) {
    $proc.CloseMainWindow() | Out-Null
    Start-Sleep -Seconds 8
    if (-not $proc.HasExited) { $proc.Kill() }
}

if ($samples.Count -eq 0) {
    Write-Warning "[$Label] no FPS samples captured - is FPS shown in the title?"
    return
}

$sorted = $samples | Sort-Object
$n = $sorted.Count
function Pct($p) { $sorted[[Math]::Max(0, [int][Math]::Floor($n * $p) - 1)] }

$result = [ordered]@{
    label       = $Label
    exe         = $Exe
    samples     = $n
    mean        = [Math]::Round(($samples | Measure-Object -Average).Average, 2)
    median      = [Math]::Round((Pct 0.50), 2)
    min         = [Math]::Round(($samples | Measure-Object -Minimum).Minimum, 2)
    max         = [Math]::Round(($samples | Measure-Object -Maximum).Maximum, 2)
    low_1pct    = [Math]::Round((Pct 0.01), 2)
    low_5pct    = [Math]::Round((Pct 0.05), 2)
    stdev       = [Math]::Round([Math]::Sqrt((($samples | ForEach-Object { [Math]::Pow($_ - ($samples | Measure-Object -Average).Average, 2) } | Measure-Object -Sum).Sum) / $n), 2)
}

Write-Host ""
Write-Host "===== $Label =====" -ForegroundColor Green
$result.GetEnumerator() | ForEach-Object { "  {0,-10} {1}" -f $_.Key, $_.Value } | Write-Host

if ($OutJson) {
    $result | ConvertTo-Json | Set-Content $OutJson
    Write-Host "  -> $OutJson" -ForegroundColor DarkGray
}
$result
