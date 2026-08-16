<#
    GPL A/B during ACTUAL GAMEPLAY, driven without stealing focus.

    Title-screen captures were a weak test: a ~1.1 ms GPU frame gives a
    pipeline-execution difference almost nothing to bite on, which is why those
    numbers came out inconsistent. This drives the emulator into a level.

    The reason gameplay was previously impossible while the machine was in use:
    keybd_event/SendInput go to the FOREGROUND window, and Windows refuses to
    hand foreground to a background script. PostMessage delivers WM_KEYDOWN and
    WM_KEYUP straight to Eden's window queue, so no focus is needed and the
    emulator can sit behind other windows while it is driven.

    Same binary in both arms, switched by EDEN_DISABLE_GPL, so the library path
    is the only variable.
#>
param(
    [int]$BootSeconds = 55,
    [int]$CaptureSeconds = 30,
    [string]$Order = 'gpl_on,gpl_off,gpl_off,gpl_on',
    [int]$SeqOffset = 0
)
$ErrorActionPreference = 'Continue'

Add-Type -TypeDefinition @'
using System; using System.Text; using System.Runtime.InteropServices;
using System.Drawing; using System.Drawing.Imaging;
public static class EP {
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern uint MapVirtualKey(uint c, uint t);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint f);
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out R r);
  [StructLayout(LayoutKind.Sequential)] public struct R { public int L,T,Ri,B; }

  static IntPtr Down(uint vk){ uint s=MapVirtualKey(vk,0); return (IntPtr)(1 | (int)(s<<16)); }
  static IntPtr Up(uint vk){ uint s=MapVirtualKey(vk,0); return (IntPtr)(1 | (int)(s<<16) | (1<<30) | (1<<31)); }
  public static void KeyDown(IntPtr h, uint vk){ PostMessage(h, 0x0100, (IntPtr)vk, Down(vk)); }
  public static void KeyUp(IntPtr h, uint vk){ PostMessage(h, 0x0101, (IntPtr)vk, Up(vk)); }

  public static void SendToBack(IntPtr h){ SetWindowPos(h,(IntPtr)1,0,0,0,0,0x13); }

  public static bool Shot(IntPtr h, string path){
    R r; if(!GetClientRect(h,out r)) return false;
    int w=r.Ri-r.L, ht=r.B-r.T; if(w<=0||ht<=0) return false;
    using(Bitmap b=new Bitmap(w,ht,PixelFormat.Format32bppArgb))
    using(Graphics g=Graphics.FromImage(b)){
      IntPtr hdc=g.GetHdc(); bool ok=PrintWindow(h,hdc,2); g.ReleaseHdc(hdc);
      if(!ok) return false; b.Save(path,ImageFormat.Png); return true; }
  }
}
'@ -ReferencedAssemblies System.Drawing, System.Drawing.Primitives

# Eden's default keyboard map (src/qt_common/config/qt_config.cpp)
$VK = @{ 'A'=0x43; 'B'=0x58; 'X'=0x56; 'Y'=0x5A; 'L'=0x51; 'R'=0x45
         'DLeft'=0x25; 'DUp'=0x26; 'DRight'=0x27; 'DDown'=0x28 }

function Press($h, [string]$btn, [int]$hold = 90, [int]$after = 420) {
    [EP]::KeyDown($h, [uint32]$VK[$btn]); Start-Sleep -Milliseconds $hold
    [EP]::KeyUp($h, [uint32]$VK[$btn]);   Start-Sleep -Milliseconds $after
}
function Chord($h, [string[]]$btns, [int]$hold = 150) {
    foreach ($b in $btns) { [EP]::KeyDown($h, [uint32]$VK[$b]) }
    Start-Sleep -Milliseconds $hold
    foreach ($b in $btns) { [EP]::KeyUp($h, [uint32]$VK[$b]) }
    Start-Sleep -Milliseconds 400
}

$tools    = "P:\Programming Repositories\eden\tools"
$exe      = "P:\Programming Repositories\eden\build\bin\eden.exe"
$rom      = "G:\Games (Master Folder)\Nintendo\Switch\Super Mario Bros. Wonder (XCI)\Super Mario Bros. Wonder [010015100B514000][v0][Base][nxbrew.com].xci"
$pm       = (Get-Content "$env:TEMP\pm_path.txt").Trim()
$cacheDir = Join-Path $env:APPDATA "eden\cache\shader\010015100b514000"
$glCache  = "$env:LOCALAPPDATA\NVIDIA\GLCache"
$saveDir  = Join-Path $env:APPDATA "eden\nand\user\save\0000000000000000\100CD2D277EABCA37ADECD26D3BD8B41\010015100B514000"
$snap     = "P:\Programming Repositories\eden\build\bench\save_snapshot"
$outDir   = "P:\Programming Repositories\eden\build\gpl_play"
$shotDir  = "P:\Programming Repositories\eden\build\gpl_play_shots"
New-Item -ItemType Directory -Force -Path $outDir, $shotDir | Out-Null

& powershell -NoProfile -ExecutionPolicy Bypass -File "$tools\Set-BenchConfig.ps1" -Mode Bench | Out-Null

$seq = $SeqOffset
foreach ($nm in ($Order -split ',')) {
    $seq++
    $arm = $nm.Trim()
    $disable = if ($arm -eq 'gpl_off') { '1' } else { '' }
    Write-Output ("=== boot {0}: {1} ===" -f $seq, $arm)

    Get-Process eden,presentmon -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    # Killing PresentMon does not close its ETW session, and a leaked session
    # starves the capture: the next run reports "Started recording" and writes
    # nothing at all. Clear any stragglers before every boot.
    $stale = & logman query -ets 2>$null | ForEach-Object { ($_.Trim() -split '\s+')[0] } |
             Where-Object { $_ -like 'gpl*' -or $_ -like 'edenbench*' -or $_ -like 'pm*' }
    foreach ($s in $stale) { & logman stop $s -ets 2>&1 | Out-Null }
    Start-Sleep 4
    if (Test-Path $cacheDir) { Remove-Item "$cacheDir\*" -Recurse -Force -ErrorAction SilentlyContinue }
    if (Test-Path $glCache)  { Remove-Item "$glCache\*"  -Recurse -Force -ErrorAction SilentlyContinue }
    if (Test-Path $snap) {
        Remove-Item "$saveDir\*" -Recurse -Force -ErrorAction SilentlyContinue
        Copy-Item "$snap\*" $saveDir -Recurse -Force
    }

    $env:EDEN_DISABLE_GPL = $disable
    $p = Start-Process $exe -ArgumentList "-g `"$rom`"" -PassThru
    Start-Sleep $BootSeconds
    if ($p.HasExited) { Write-Output "  eden exited during boot"; continue }
    $p.Refresh()
    $h = $p.MainWindowHandle
    if ($h -eq [IntPtr]::Zero) { Write-Output "  no window"; continue }

    # Navigate to a level entirely with PostMessage -- no focus required.
    # title -> user -> player count -> characters -> (Nabbit) -> map -> level card -> level
    Chord $h @('L','R'); Start-Sleep 5
    Press $h 'A'; Start-Sleep 4
    Press $h 'A'; Start-Sleep 4
    for ($k = 0; $k -lt 10; $k++) { Press $h 'DRight' 70 340 }   # Luigi -> Nabbit (no damage)
    Start-Sleep 1
    Press $h 'A'; Start-Sleep 6
    Press $h 'A'; Start-Sleep 5
    [EP]::KeyDown($h, [uint32]$VK['DUp']); Start-Sleep -Milliseconds 600; [EP]::KeyUp($h, [uint32]$VK['DUp'])
    Start-Sleep 2
    Press $h 'A'; Start-Sleep 7
    Press $h 'A'; Start-Sleep 9

    [EP]::Shot($h, (Join-Path $shotDir ("{0}_seq{1}_entered.png" -f $arm, $seq))) | Out-Null
    [EP]::SendToBack($h)
    if ([EP]::IsIconic($h)) { Write-Output "  WARNING minimized -> presents stop; capture will be empty" }

    # Capture while the workload runs: hold right, jump on a fixed cadence.
    $tmp = "$env:TEMP\gplplay_$seq.csv"
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    $pp = Start-Process $pm -ArgumentList "--process_id $($p.Id) --timed $CaptureSeconds --output_file `"$tmp`" --no_console_stats --stop_existing_session --terminate_after_timed --session_name gplplay" -PassThru -NoNewWindow

    [EP]::KeyDown($h, [uint32]$VK['DRight'])
    $deadline = (Get-Date).AddSeconds($CaptureSeconds - 2)
    $j = 0
    while ((Get-Date) -lt $deadline) {
        $j++
        [EP]::KeyDown($h, [uint32]$VK['B']); Start-Sleep -Milliseconds 130
        [EP]::KeyUp($h, [uint32]$VK['B']);   Start-Sleep -Milliseconds 620
        if ($j % 20 -eq 0) { [EP]::Shot($h, (Join-Path $shotDir ("{0}_seq{1}_t{2}.png" -f $arm, $seq, $j))) | Out-Null }
    }
    [EP]::KeyUp($h, [uint32]$VK['DRight'])

    $pp.WaitForExit(($CaptureSeconds + 25) * 1000) | Out-Null
    if (-not $pp.HasExited) { $pp.Kill() }
    & logman stop gplplay -ets 2>&1 | Out-Null

    if (Test-Path $tmp) {
        Move-Item $tmp (Join-Path $outDir ("{0}_seq{1}.csv" -f $arm, $seq)) -Force
        Write-Output ("  captured {0}_seq{1}.csv" -f $arm, $seq)
    } else { Write-Output "  NO CAPTURE" }

    if (-not $p.HasExited) { $p.CloseMainWindow() | Out-Null; Start-Sleep 8 }
    if (-not $p.HasExited) { $p.Kill() }
    Remove-Item Env:\EDEN_DISABLE_GPL -ErrorAction SilentlyContinue
    Start-Sleep 2
}

& powershell -NoProfile -ExecutionPolicy Bypass -File "$tools\Set-BenchConfig.ps1" -Mode Restore | Out-Null
Write-Output "done; config restored"
