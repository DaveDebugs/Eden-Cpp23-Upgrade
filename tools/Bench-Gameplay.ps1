<#
.SYNOPSIS
    A/B frametime benchmark for Eden, measured during actual gameplay.

.DESCRIPTION
    Replaces Bench-Compare.ps1, which was invalid: it launched the emulator,
    slept, and captured with no input at any point, so every number it produced
    described a static title screen sitting against the title's own 60 FPS cap.
    Two builds both failing to exceed a cap they are both pinned to is not a
    comparison.

    This harness fixes the three things that made that measurement meaningless:

      1. It drives the emulator into a level with synthetic keyboard input and
         screenshots the window mid-capture, so every reported run has visual
         proof it was in gameplay and not on a menu.
      2. It runs with Eden's speed limiter disabled, so the frame rate is
         bounded by how fast the two builds actually are rather than by the
         100% speed cap. A capped run cannot show a throughput difference.
      3. It repeats each configuration N times and reports the spread, so a
         difference can be distinguished from run-to-run variance.

    Both builds read the same %APPDATA%\eden config, rewritten from the same
    backup before every run, so settings cannot drift between them.

.EXAMPLE
    .\Bench-Gameplay.ps1 -Runs 3
#>
[CmdletBinding()]
param(
    [string]$OursExe     = "P:\Programming Repositories\eden\build\bin\eden.exe",
    [string]$OfficialExe = "P:\Programming Repositories\eden-official\eden.exe",
    [string]$Rom = "G:\Games (Master Folder)\Nintendo\Switch\Super Mario Bros. Wonder (XCI)\Super Mario Bros. Wonder [010015100B514000][v0][Base][nxbrew.com].xci",
    [string]$TitleId = "010015100b514000",
    [int]$Runs = 3,
    [int]$BootSeconds = 45,
    [int]$CaptureSeconds = 60,
    [switch]$ClearShaderCache,
    [switch]$OursOnly,
    # Leave Eden's 100% speed limiter on. Both builds then advance the emulated
    # game at the same rate, so the host-timed input script produces genuinely
    # identical gameplay in each -- which is what makes a frame-consistency
    # comparison meaningful. It cannot measure throughput, because both builds
    # are held at the same speed by definition; use the uncapped mode for that.
    [switch]$LockedSpeed,
    [string]$OutDir = "P:\Programming Repositories\eden\build\bench",
    [string]$ShotDir = "P:\Programming Repositories\eden\build\bench_shots"
)

$ErrorActionPreference = 'Continue'
$tools = "P:\Programming Repositories\eden\tools"
Import-Module "$tools\EdenAutomation.psm1" -Force

New-Item -ItemType Directory -Force -Path $OutDir  | Out-Null
New-Item -ItemType Directory -Force -Path $ShotDir | Out-Null

$pm = Get-Content "$env:TEMP\pm_path.txt" -ErrorAction SilentlyContinue
if (-not $pm) { throw "PresentMon path not found in $env:TEMP\pm_path.txt" }

$cacheDir = Join-Path $env:APPDATA "eden\cache\shader\$TitleId"

# The game autosaves its position on the world map, so without this every run
# would start from wherever the previous run left off and the menu path below
# would walk into a different level -- or into no level at all. Restoring the
# same save before each run is what makes the runs comparable: identical level,
# identical starting position, identical workload.
$saveDir    = Join-Path $env:APPDATA "eden\nand\user\save\0000000000000000\100CD2D277EABCA37ADECD26D3BD8B41\$($TitleId.ToUpper())"
$saveBackup = Join-Path $OutDir 'save_snapshot'

function Backup-Save {
    if (-not (Test-Path $saveDir)) { Write-Warning "no save dir at $saveDir"; return }
    if (Test-Path $saveBackup) { return }   # take it once, never overwrite
    New-Item -ItemType Directory -Force -Path $saveBackup | Out-Null
    Copy-Item "$saveDir\*" $saveBackup -Recurse -Force
    Write-Output "save snapshot taken -> $saveBackup"
}

function Restore-Save {
    if (-not (Test-Path $saveBackup)) { return }
    Remove-Item "$saveDir\*" -Recurse -Force -ErrorAction SilentlyContinue
    Copy-Item "$saveBackup\*" $saveDir -Recurse -Force
}

Backup-Save

# Menu path from launch to gameplay, established by screenshotting each step.
# Title -> L+R -> user select -> player count -> character -> world map ->
# level card -> level.
#
# The ten DRight presses move the character cursor from Luigi, where the
# restored save leaves it, to Nabbit. Nabbit cannot take damage, which the
# character screen states outright. That matters more than it sounds: with a
# damageable character the scripted "hold right and jump" workload ran the
# player into enemies and spent a large part of each capture on the near-black
# death screen -- a low-load scene that rewards whichever build dies more.
$NavToLevel = 'wait:2, L+R, wait:5, A, wait:4, A, wait:4, DRight*10, wait:1, A, wait:6, A, wait:5, DUp:600, wait:2, A, wait:7, A, wait:9'

function Invoke-Nav {
    param([string]$Sequence, [IntPtr]$Handle)
    foreach ($tok in ($Sequence -split ',')) {
        $t = $tok.Trim()
        if (-not $t) { continue }
        if ($t -like 'wait:*') { Start-Sleep -Seconds ([double]($t -replace '^wait:', '')); continue }
        if ($t -match '^([A-Za-z+]+):(\d+)$') {
            $btns = $Matches[1] -split '\+'
            foreach ($b in $btns) { Set-EdenButtonState -Button $b -Down }
            Start-Sleep -Milliseconds ([int]$Matches[2])
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
                Start-Sleep -Milliseconds 380
            }
            continue
        }
        $btns = $t -split '\+'
        foreach ($b in $btns) { Set-EdenButtonState -Button $b -Down }
        Start-Sleep -Milliseconds 90
        foreach ($b in $btns) { Set-EdenButtonState -Button $b }
        Start-Sleep -Milliseconds 450
    }
}

# The workload. Holding right with a jump on a fixed cadence keeps the level
# scrolling -- new geometry, new enemies, new effects streaming in -- which is
# the thing a title screen never does. The periodic A press is a recovery
# measure: it dismisses a death or level-complete prompt so a run that goes
# badly still spends its time in a level rather than parked on a dialog.
function Start-Workload {
    param([IntPtr]$Handle, [int]$Seconds, [string]$ShotPrefix)

    $deadline = (Get-Date).AddSeconds($Seconds)
    $shots = @()
    $i = 0
    Set-EdenButtonState -Button 'DRight' -Down
    try {
        while ((Get-Date) -lt $deadline) {
            $i++
            # jump
            Set-EdenButtonState -Button 'B' -Down
            Start-Sleep -Milliseconds 130
            Set-EdenButtonState -Button 'B'
            Start-Sleep -Milliseconds 620

            # every ~6 s: release right briefly and tap A, then resume
            if ($i % 8 -eq 0) {
                Set-EdenButtonState -Button 'DRight'
                Set-EdenButtonState -Button 'A' -Down
                Start-Sleep -Milliseconds 90
                Set-EdenButtonState -Button 'A'
                Start-Sleep -Milliseconds 200
                Set-EdenButtonState -Button 'DRight' -Down
            }

            # proof-of-gameplay screenshots spread through the capture
            if ($i % 20 -eq 0) {
                $p = Join-Path $ShotDir "$ShotPrefix`_t$([int]$i).png"
                if (Save-EdenFrame -Handle $Handle -Path $p) { $shots += $p }
            }
        }
    }
    finally {
        Set-EdenButtonState -Button 'DRight'
        Set-EdenButtonState -Button 'B'
        Set-EdenButtonState -Button 'A'
    }
    return $shots
}

function Measure-Csv {
    param([string]$Csv, [string]$Label, [int]$ProcessId)
    if (-not (Test-Path $Csv)) { return [pscustomobject]@{ label = $Label; error = 'no capture' } }

    $all = Import-Csv $Csv
    if (-not $all) { return [pscustomobject]@{ label = $Label; error = 'empty csv' } }

    # The capture covers every process on the machine, so keep only Eden's.
    # Match on PID: the Application column reads <unknown> for a process that
    # was already running when PresentMon attached.
    $pidCol = @('ProcessID', 'ProcessId', 'PID') |
              Where-Object { $all[0].PSObject.Properties.Name -contains $_ } |
              Select-Object -First 1
    if (-not $pidCol) { return [pscustomobject]@{ label = $Label; error = 'csv has no process id column' } }

    $rows = @($all | Where-Object { [int]($_.$pidCol) -eq $ProcessId })
    if ($rows.Count -eq 0) {
        $seen = ($all | Group-Object $pidCol | Sort-Object Count -Descending |
                 Select-Object -First 5 | ForEach-Object { "$($_.Name)x$($_.Count)" }) -join ' '
        return [pscustomobject]@{ label = $Label; error = "no rows for pid $ProcessId (saw: $seen)" }
    }

    $ft = @($rows | ForEach-Object {
        $v = 0.0
        if ([double]::TryParse($_.MsBetweenPresents, [ref]$v)) { $v }
    } | Where-Object { $_ -gt 0 })

    if ($ft.Count -lt 100) { return [pscustomobject]@{ label = $Label; error = "only $($ft.Count) frames" } }

    $gpu = @($rows | ForEach-Object { $v = 0.0; if ([double]::TryParse($_.MsGPUBusy, [ref]$v)) { $v } } | Where-Object { $_ -ge 0 })
    $cpu = @($rows | ForEach-Object { $v = 0.0; if ([double]::TryParse($_.MsCPUBusy, [ref]$v)) { $v } } | Where-Object { $_ -ge 0 })

    $sorted = $ft | Sort-Object
    $n = $sorted.Count
    # Percentile lows come from the SLOW tail of the frametime distribution.
    $p99  = $sorted[[Math]::Max(0, [int][Math]::Floor($n * 0.99) - 1)]
    $p999 = $sorted[[Math]::Max(0, [int][Math]::Floor($n * 0.999) - 1)]
    $mean = ($ft | Measure-Object -Average).Average

    [pscustomobject]@{
        label            = $Label
        frames           = $n
        mean_fps         = [Math]::Round(1000.0 / $mean, 2)
        mean_frametime   = [Math]::Round($mean, 3)
        low_1pct_fps     = [Math]::Round(1000.0 / $p99, 2)
        low_01pct_fps    = [Math]::Round(1000.0 / $p999, 2)
        worst_frame_ms   = [Math]::Round(($ft | Measure-Object -Maximum).Maximum, 2)
        frames_over_20ms = @($ft | Where-Object { $_ -gt 20 }).Count
        frames_over_50ms = @($ft | Where-Object { $_ -gt 50 }).Count
        gpu_busy_ms      = if ($gpu.Count) { [Math]::Round(($gpu | Measure-Object -Average).Average, 3) } else { $null }
        cpu_busy_ms      = if ($cpu.Count) { [Math]::Round(($cpu | Measure-Object -Average).Average, 3) } else { $null }
        error            = $null
    }
}

function Invoke-Run {
    param([string]$Exe, [string]$Label)

    Get-Process eden -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    # PresentMon does not always exit when --timed elapses; a leftover instance
    # keeps its ETW session open and the next run's capture then comes back
    # empty with no error at all. Clear them before every run.
    Get-Process presentmon -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep 4

    # Rewrite the config from the pristine backup every run. Both builds write
    # their settings back on exit, so without this the second build would
    # inherit whatever the first one persisted.
    $cfgArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "$tools\Set-BenchConfig.ps1", '-Mode', 'Bench')
    if ($LockedSpeed) { $cfgArgs += '-KeepSpeedLimit' }
    & powershell @cfgArgs | Out-Null
    Restore-Save

    if ($ClearShaderCache -and (Test-Path $cacheDir)) {
        Remove-Item "$cacheDir\*" -Force -Recurse -ErrorAction SilentlyContinue
    }

    $csv = Join-Path $OutDir "$Label.csv"
    Remove-Item $csv -Force -ErrorAction SilentlyContinue

    # Start each run from an empty emulator log so the log copied out
    # afterwards belongs to this run only. Eden's own speed counter in that
    # log is an independent check on the PresentMon numbers.
    $edenLog = Join-Path $env:APPDATA 'eden\log\eden_log.txt'
    Remove-Item $edenLog -Force -ErrorAction SilentlyContinue

    $proc = Start-Process -FilePath $Exe -ArgumentList "-g `"$Rom`"" -PassThru
    Start-Sleep $BootSeconds
    if ($proc.HasExited) { return [pscustomobject]@{ label = $Label; error = "exited during boot ($($proc.ExitCode))" } }

    $h = Get-EdenWindow -ProcessId $proc.Id
    if ($h -eq [IntPtr]::Zero) { return [pscustomobject]@{ label = $Label; error = 'no main window' } }
    if (-not (Set-EdenFocus -Handle $h)) { Write-Warning "$Label : window did not take focus" }

    Invoke-Nav -Sequence $NavToLevel -Handle $h
    Save-EdenFrame -Handle $h -Path (Join-Path $ShotDir "$Label`_entered.png") | Out-Null

    # PresentMon runs alongside the workload rather than instead of it: with
    # --timed it blocks, so it has to be a separate process while this one
    # keeps the game moving.
    # Start-Process joins an argument array with spaces and does NOT quote the
    # elements, so an output path under "Programming Repositories" arrives at
    # PresentMon split in two and the capture silently never appears. Quote it
    # here rather than relying on the array form.
    # A fresh session name per run. Reusing the default "PresentMon" session
    # means each run has to tear down the previous one, and a capture started
    # during that teardown comes back empty with no error -- it just reports
    # "Started recording / Stopped recording" and writes no file.
    # One fixed session name for the whole harness. Unique-per-run names sound
    # safer but leak: PresentMon's session outlives the process when it is
    # killed, and a pile of orphaned sessions starves the shared ETW buffers
    # until captures come back empty. One name plus --stop_existing_session
    # means at most one can ever be stranded.
    $session = 'edenbench'

    # Target by PID, not by exe name. Without elevation PresentMon cannot
    # resolve the name of a process that was already running when it attached
    # -- it shows as <unknown>, never matches --process_name, and the capture
    # silently records nothing. Removing the filter entirely is worse: an
    # unfiltered trace overran the ETW buffers (232,213 events lost) and still
    # produced no CSV. A PID needs no name lookup.
    # --terminate_after_timed makes PresentMon exit when the timer expires;
    # without it instances pile up, each holding an ETW session open.
    $pmArgs = "--process_id $($proc.Id) --timed $CaptureSeconds --output_file `"$csv`" " +
              "--no_console_stats --stop_existing_session --terminate_after_timed --session_name $session"
    $pmLog = Join-Path $OutDir "$Label`_presentmon.log"
    $pmProc = Start-Process -FilePath $pm -ArgumentList $pmArgs -PassThru -WindowStyle Hidden `
                            -RedirectStandardOutput $pmLog -RedirectStandardError "$pmLog.err"

    Start-Sleep 2
    Set-EdenFocus -Handle $h | Out-Null
    Start-Workload -Handle $h -Seconds ($CaptureSeconds - 2) -ShotPrefix $Label | Out-Null

    # Give it a moment past --timed to flush the CSV, then make sure it is gone.
    $pmProc.WaitForExit(20000) | Out-Null
    if (-not $pmProc.HasExited) { $pmProc.Kill(); Start-Sleep 2 }
    & logman stop $session -ets 2>&1 | Out-Null

    if (-not $proc.HasExited) {
        $proc.CloseMainWindow() | Out-Null
        Start-Sleep 12
        if (-not $proc.HasExited) { $proc.Kill() }
    }
    Start-Sleep 3

    if (Test-Path $edenLog) { Copy-Item $edenLog (Join-Path $OutDir "$Label`_eden.log") -Force }

    return (Measure-Csv -Csv $csv -Label $Label -ProcessId $proc.Id)
}

# All runs of one build back to back, rather than alternating. The two builds
# use different pipeline-cache versions, so each rejects and rebuilds the
# other's cache; alternating would leave every single run cold and hide the
# warm-cache behaviour entirely. Grouped this way, run 1 of each block is the
# cold case and runs 2..N are warm, for both builds equally.
$results = @()
$mode = if ($LockedSpeed) { 'locked' } else { 'uncapped' }
$jsonOut = Join-Path $OutDir "gameplay_results_$mode.json"
Write-Output "mode: $mode  runs: $Runs  capture: ${CaptureSeconds}s"

if (-not $OursOnly) {
    for ($r = 1; $r -le $Runs; $r++) {
        Write-Output "=== official run $r/$Runs ($mode) ==="
        $results += Invoke-Run -Exe $OfficialExe -Label "official_${mode}_r$r"
        $results | ConvertTo-Json -Depth 4 | Set-Content $jsonOut
    }
}

for ($r = 1; $r -le $Runs; $r++) {
    Write-Output "=== fork run $r/$Runs ($mode) ==="
    $results += Invoke-Run -Exe $OursExe -Label "fork_${mode}_r$r"
    $results | ConvertTo-Json -Depth 4 | Set-Content $jsonOut
}

# Put the user's real controller mapping and speed limiter back.
& powershell -NoProfile -ExecutionPolicy Bypass -File "$tools\Set-BenchConfig.ps1" -Mode Restore | Out-Null

$results | ConvertTo-Json -Depth 4 | Set-Content $jsonOut
$results | Format-Table -AutoSize | Out-String -Width 220 | Set-Content (Join-Path $OutDir "gameplay_results_$mode.txt")
'DONE' | Set-Content (Join-Path $OutDir "gameplay_done_$mode.flag")
$results | Format-Table -AutoSize | Out-String -Width 220
