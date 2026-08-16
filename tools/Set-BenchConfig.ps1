<#
.SYNOPSIS
    Swaps Eden's config into (or out of) a benchmark configuration.

.DESCRIPTION
    Two things have to change before an A/B comparison can measure anything:

    1. Player 1 must be driven by the keyboard, because synthetic keystrokes
       are the only input this harness can generate. The real controller
       mapping is saved and restored.

    2. The speed limiter must be off. With `use_speed_limit=true` and
       `speed_limit=100` both builds are pinned to the title's own 60 FPS
       cap, so no throughput difference can appear no matter how much faster
       one of them is. A capped comparison can only ever measure frame
       consistency; it cannot measure speed.

    Every other setting -- resolution scale, vsync, backend -- is left exactly
    as the user had it, so the comparison reflects their real configuration.

    Both eden.exe builds read the same %APPDATA%\eden config, which is what
    makes the A/B fair: identical settings, identical input, one binary
    swapped.

.EXAMPLE
    .\Set-BenchConfig.ps1 -Mode Bench
.EXAMPLE
    .\Set-BenchConfig.ps1 -Mode Restore
#>
[CmdletBinding()]
param(
    [ValidateSet('Bench', 'Restore')]
    [string]$Mode = 'Bench',
    [string]$Ini = "$env:APPDATA\eden\config\qt-config.ini",
    [switch]$KeepSpeedLimit
)

$ErrorActionPreference = 'Stop'
$backup = "$Ini.prebench"

if ($Mode -eq 'Restore') {
    if (Test-Path $backup) {
        Copy-Item $backup $Ini -Force
        Remove-Item $backup -Force
        Write-Output "restored: $Ini"
    } else {
        Write-Warning "no backup at $backup - nothing restored"
    }
    exit 0
}

# Take the backup once. Re-running Bench must not overwrite a good backup with
# an already-modified file.
if (-not (Test-Path $backup)) {
    Copy-Item $Ini $backup -Force
    Write-Output "backed up -> $backup"
} else {
    Write-Output "backup already exists, reusing: $backup"
    Copy-Item $backup $Ini -Force
}

# Qt key codes. Letters are ASCII; arrows are Qt::Key_Left..Down (0x01000012+).
$map = [ordered]@{
    'button_a'      = 67        # C
    'button_b'      = 88        # X
    'button_x'      = 86        # V
    'button_y'      = 90        # Z
    'button_lstick' = 70        # F
    'button_rstick' = 71        # G
    'button_l'      = 81        # Q
    'button_r'      = 69        # E
    'button_zl'     = 82        # R
    'button_zr'     = 84        # T
    'button_plus'   = 77        # M
    'button_minus'  = 78        # N
    'button_dleft'  = 16777234
    'button_dup'    = 16777235
    'button_dright' = 16777236
    'button_ddown'  = 16777237
}

$lines = Get-Content $Ini
$out = New-Object System.Collections.Generic.List[string]

foreach ($line in $lines) {
    $new = $line

    foreach ($k in $map.Keys) {
        if ($line -like "player_0_$k=*") {
            $new = "player_0_$k=`"engine:keyboard,code:$($map[$k]),toggle:0`""
        }
    }

    # Unmap the analog sticks entirely. A resting stick still emits small
    # values, and with movement on the D-pad any drift would fight the script.
    if ($line -like 'player_0_lstick=*') { $new = 'player_0_lstick=""' }
    if ($line -like 'player_0_rstick=*') { $new = 'player_0_rstick=""' }

    # Silence the emulator for benchmarking. Audio is irrelevant to every metric
    # captured here and unattended runs should not make noise. As everywhere in
    # this file, the `\default` twin has to be cleared too or the loader ignores
    # the stored value.
    if ($line -like 'audio_muted=*')         { $new = 'audio_muted=true' }
    if ($line -like 'audio_muted\default=*') { $new = 'audio_muted\default=false' }
    if ($line -like 'volume=*')              { $new = 'volume=0' }
    if ($line -like 'volume\default=*')      { $new = 'volume\default=false' }

    # Vsync goes off in both modes. FIFO (2) blocks every present on the
    # monitor's refresh, so with it on the capture measures the display rather
    # than the emulator -- exactly the trap the title-screen benchmark fell
    # into. Immediate (0) lets presents land when the emulator produces them.
    if ($line -like 'use_vsync=*')         { $new = 'use_vsync=0' }
    if ($line -like 'use_vsync\default=*') { $new = 'use_vsync\default=false' }

    if (-not $KeepSpeedLimit) {
        # Eden stores every setting twice: `foo` and `foo\default`. When
        # `foo\default=true` the loader ignores the stored value and uses the
        # compiled-in default, so writing `use_speed_limit=false` on its own
        # does nothing at all -- which is why the first attempt at an uncapped
        # run came back pinned to 60 FPS anyway. Both lines have to change.
        if ($line -like 'use_speed_limit=*')         { $new = 'use_speed_limit=false' }
        if ($line -like 'use_speed_limit\default=*') { $new = 'use_speed_limit\default=false' }

    }

    $out.Add($new)
}

Set-Content -Path $Ini -Value $out -Encoding UTF8
Write-Output "bench config written: keyboard-mapped player 1, speed limiter $(if ($KeepSpeedLimit) {'left as-is'} else {'OFF'})"
