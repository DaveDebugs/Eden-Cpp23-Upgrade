<#
    Attaches to a running eden.exe, plays a token sequence into it, and
    captures the window afterwards.

    Token grammar:
      A            press button A briefly
      L+R          press L and R together
      A*5          press A five times
      Right:1500   hold Right for 1500 ms
      wait:3       sleep 3 seconds
      shot:name    capture the window to <ShotDir>\name.png
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Sequence,
    [string]$ShotDir = "P:\Programming Repositories\eden\build\bench_shots",
    [string]$ShotName = "step"
)

$ErrorActionPreference = 'Stop'
Import-Module "P:\Programming Repositories\eden\tools\EdenAutomation.psm1" -Force
New-Item -ItemType Directory -Force -Path $ShotDir | Out-Null

$proc = Get-Process eden -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $proc) { throw "eden.exe is not running" }
$h = Get-EdenWindow -ProcessId $proc.Id
if ($h -eq [IntPtr]::Zero) { throw "no main window" }
if (-not (Set-EdenFocus -Handle $h)) { Write-Warning "could not bring eden to the foreground" }

foreach ($tok in ($Sequence -split ',')) {
    $t = $tok.Trim()
    if (-not $t) { continue }

    if ($t -like 'wait:*') {
        Start-Sleep -Seconds ([double]($t -replace '^wait:', ''))
        continue
    }
    if ($t -like 'shot:*') {
        $n = $t -replace '^shot:', ''
        $p = Join-Path $ShotDir "$n.png"
        Write-Output "shot $n -> $(Save-EdenFrame -Handle $h -Path $p)"
        continue
    }
    if ($t -match '^([A-Za-z+]+):(\d+)$') {
        # hold
        $btns = $Matches[1] -split '\+'
        $ms   = [int]$Matches[2]
        foreach ($b in $btns) { Set-EdenButtonState -Button $b -Down }
        Start-Sleep -Milliseconds $ms
        foreach ($b in $btns) { Set-EdenButtonState -Button $b }
        Start-Sleep -Milliseconds 150
        continue
    }
    if ($t -match '^([A-Za-z+]+)\*(\d+)$') {
        $btns = $Matches[1] -split '\+'
        for ($i = 0; $i -lt [int]$Matches[2]; $i++) {
            foreach ($b in $btns) { Set-EdenButtonState -Button $b -Down }
            Start-Sleep -Milliseconds 70
            foreach ($b in $btns) { Set-EdenButtonState -Button $b }
            Start-Sleep -Milliseconds 400
        }
        continue
    }
    # plain press, possibly a chord
    $btns = $t -split '\+'
    foreach ($b in $btns) { Set-EdenButtonState -Button $b -Down }
    Start-Sleep -Milliseconds 90
    foreach ($b in $btns) { Set-EdenButtonState -Button $b }
    Start-Sleep -Milliseconds 450
}

$final = Join-Path $ShotDir "$ShotName.png"
Write-Output "final shot -> $(Save-EdenFrame -Handle $h -Path $final) : $final"
