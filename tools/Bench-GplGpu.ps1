<#
    Second half of the GPL question: do fast-linked pipelines EXECUTE slower?

    The +9.7% GPU-busy figure in the report compared the fork against official
    v0.2.1, which differ in compiler, LTO, AVX2 and every source change -- so it
    could never attribute the cost to GPL. This runs the SAME binary both ways,
    so the library path is the only variable.

    No synthetic input and no focus stealing: the title screen is a fixed scene
    and both arms see exactly the same one. MsGPUBusy is a direct measure of GPU
    time per frame, so it does not need gameplay to be meaningful.
#>
param([int]$BootSeconds = 60, [int]$CaptureSeconds = 30,
      [string]$Order = 'gpl_on,gpl_off,gpl_off,gpl_on', [int]$SeqOffset = 0)

$ErrorActionPreference = 'Continue'

# Push the emulator behind other windows without minimizing it. Under DWM an
# occluded window still renders and presents, so the capture is unaffected -- but
# a MINIMIZED window stops presenting entirely and the capture silently comes
# back empty. Background yes, minimized no.
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class Zorder {
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
}
'@
function Send-ToBack([IntPtr]$h) {
    if ($h -eq [IntPtr]::Zero) { return }
    # HWND_BOTTOM=1, SWP_NOMOVE=0x2 | SWP_NOSIZE=0x1 | SWP_NOACTIVATE=0x10
    [Zorder]::SetWindowPos($h, [IntPtr]1, 0, 0, 0, 0, 0x13) | Out-Null
}
$tools = "P:\Programming Repositories\eden\tools"
$exe = "P:\Programming Repositories\eden\build\bin\eden.exe"
$rom = "G:\Games (Master Folder)\Nintendo\Switch\Super Mario Bros. Wonder (XCI)\Super Mario Bros. Wonder [010015100B514000][v0][Base][nxbrew.com].xci"
$pm  = (Get-Content "$env:TEMP\pm_path.txt").Trim()
$cacheDir = Join-Path $env:APPDATA "eden\cache\shader\010015100b514000"
$glCache  = "$env:LOCALAPPDATA\NVIDIA\GLCache"
$outDir   = "P:\Programming Repositories\eden\build\gpl_gpu"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

# Speed limiter off / vsync immediate, so frames are not display-paced.
& powershell -NoProfile -ExecutionPolicy Bypass -File "$tools\Set-BenchConfig.ps1" -Mode Bench | Out-Null

$seq = $SeqOffset
foreach ($nm in ($Order -split ',')) {
    $seq++
    $arm = $nm.Trim()
    $disable = if ($arm -eq 'gpl_off') { '1' } else { '' }
    Write-Output ("=== boot {0}: {1} ===" -f $seq, $arm)

    Get-Process eden,presentmon -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep 4
    if (Test-Path $cacheDir) { Remove-Item "$cacheDir\*" -Recurse -Force -ErrorAction SilentlyContinue }
    if (Test-Path $glCache)  { Remove-Item "$glCache\*"  -Recurse -Force -ErrorAction SilentlyContinue }

    $env:EDEN_DISABLE_GPL = $disable
    $p = Start-Process $exe -ArgumentList "-g `"$rom`"" -PassThru
    Start-Sleep $BootSeconds
    if ($p.HasExited) { Write-Output "  eden exited early"; continue }

    $p.Refresh()
    Send-ToBack $p.MainWindowHandle
    if ([Zorder]::IsIconic($p.MainWindowHandle)) {
        Write-Output "  WARNING: window is minimized; presents stop and the capture will be empty"
    }

    # Write to a temp path (no spaces) then move; keeps the capture path simple.
    $tmp = "$env:TEMP\gplgpu_$seq.csv"
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    $pp = Start-Process $pm -ArgumentList "--process_id $($p.Id) --timed $CaptureSeconds --output_file `"$tmp`" --no_console_stats --stop_existing_session --terminate_after_timed --session_name gplgpu" -PassThru -NoNewWindow
    $pp.WaitForExit(($CaptureSeconds + 25) * 1000) | Out-Null
    if (-not $pp.HasExited) { $pp.Kill() }

    if (Test-Path $tmp) {
        $dest = Join-Path $outDir ("{0}_seq{1}.csv" -f $arm, $seq)
        Move-Item $tmp $dest -Force
        Write-Output ("  captured -> {0}" -f (Split-Path $dest -Leaf))
    } else {
        Write-Output "  NO CAPTURE"
    }

    if (-not $p.HasExited) { $p.CloseMainWindow() | Out-Null; Start-Sleep 8 }
    if (-not $p.HasExited) { $p.Kill() }
    Remove-Item Env:\EDEN_DISABLE_GPL -ErrorAction SilentlyContinue
    Start-Sleep 2
}

& powershell -NoProfile -ExecutionPolicy Bypass -File "$tools\Set-BenchConfig.ps1" -Mode Restore | Out-Null
Write-Output "done; config restored"
