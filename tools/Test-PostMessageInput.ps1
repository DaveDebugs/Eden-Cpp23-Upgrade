<#
    Can we drive Eden without stealing focus?

    keybd_event/SendInput deliver to whatever window is focused, so they need
    the foreground -- which Windows refuses to hand over while the user is
    active. PostMessage delivers WM_KEYDOWN/WM_KEYUP straight to a specific
    window's message queue, no focus required. Qt handles those, so this may
    let the benchmark run in the background while the machine is in use.

    Tries the top-level window and every child, screenshotting after each so we
    can see which one the emulator actually listens to.
#>
Add-Type -TypeDefinition @'
using System; using System.Text; using System.Runtime.InteropServices;
using System.Drawing; using System.Drawing.Imaging;
public static class PM {
  public delegate bool EnumProc(IntPtr h, IntPtr p);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr h, EnumProc cb, IntPtr p);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern uint MapVirtualKey(uint c, uint t);
  [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint f);
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out R r);
  [StructLayout(LayoutKind.Sequential)] public struct R { public int L,T,Ri,B; }

  public static System.Collections.Generic.List<IntPtr> Children(IntPtr parent) {
    var list = new System.Collections.Generic.List<IntPtr>();
    EnumChildWindows(parent, delegate(IntPtr h, IntPtr p) { list.Add(h); return true; }, IntPtr.Zero);
    return list;
  }
  public static string Cls(IntPtr h) { var sb = new StringBuilder(256); GetClassName(h, sb, 256); return sb.ToString(); }

  public static void Key(IntPtr h, byte vk, int holdMs) {
    uint scan = MapVirtualKey(vk, 0);
    IntPtr down = (IntPtr)(1 | (int)(scan << 16));
    IntPtr up   = (IntPtr)(1 | (int)(scan << 16) | (1 << 30) | (1 << 31));
    PostMessage(h, 0x0100, (IntPtr)vk, down);   // WM_KEYDOWN
    System.Threading.Thread.Sleep(holdMs);
    PostMessage(h, 0x0101, (IntPtr)vk, up);     // WM_KEYUP
  }

  public static bool Shot(IntPtr h, string path) {
    R r; if (!GetClientRect(h, out r)) return false;
    int w = r.Ri - r.L, ht = r.B - r.T; if (w <= 0 || ht <= 0) return false;
    using (Bitmap b = new Bitmap(w, ht, PixelFormat.Format32bppArgb))
    using (Graphics g = Graphics.FromImage(b)) {
      IntPtr hdc = g.GetHdc(); bool ok = PrintWindow(h, hdc, 2); g.ReleaseHdc(hdc);
      if (!ok) return false; b.Save(path, ImageFormat.Png); return true;
    }
  }
}
'@ -ReferencedAssemblies System.Drawing, System.Drawing.Primitives

$e = Get-Process eden -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $e) { Write-Output "eden not running"; exit }
$e.Refresh()
$top = $e.MainWindowHandle
Write-Output ("top-level hwnd={0} class={1}" -f $top, [PM]::Cls($top))

$targets = @(,$top)
foreach ($c in [PM]::Children($top)) {
    Write-Output ("  child hwnd={0} class={1}" -f $c, [PM]::Cls($c))
    $targets += $c
}

$shotDir = "P:\Programming Repositories\eden\build\postmsg"
New-Item -ItemType Directory -Force -Path $shotDir | Out-Null
[PM]::Shot($top, (Join-Path $shotDir "00_before.png")) | Out-Null
Write-Output "captured 00_before.png"

# L (Q, 0x51) + R (E, 0x45) together is what the title screen wants.
$i = 0
foreach ($t in $targets) {
    $i++
    Write-Output ("--- posting L+R to hwnd {0} ({1}) ---" -f $t, [PM]::Cls($t))
    [PM]::Key($t, 0x51, 40)
    [PM]::Key($t, 0x45, 40)
    # and together
    [PM]::PostMessage($t, 0x0100, [IntPtr]0x51, [IntPtr](1 -bor (([int][PM]::MapVirtualKey(0x51,0)) -shl 16))) | Out-Null
    [PM]::PostMessage($t, 0x0100, [IntPtr]0x45, [IntPtr](1 -bor (([int][PM]::MapVirtualKey(0x45,0)) -shl 16))) | Out-Null
    Start-Sleep -Milliseconds 150
    [PM]::PostMessage($t, 0x0101, [IntPtr]0x51, [IntPtr](1 -bor (([int][PM]::MapVirtualKey(0x51,0)) -shl 16) -bor (1 -shl 30) -bor (1 -shl 31))) | Out-Null
    [PM]::PostMessage($t, 0x0101, [IntPtr]0x45, [IntPtr](1 -bor (([int][PM]::MapVirtualKey(0x45,0)) -shl 16) -bor (1 -shl 30) -bor (1 -shl 31))) | Out-Null
    Start-Sleep 3
    [PM]::Shot($top, (Join-Path $shotDir ("{0:00}_after_hwnd{1}.png" -f $i, $t))) | Out-Null
}
Write-Output "done; compare screenshots in $shotDir"
Get-ChildItem $shotDir -Filter *.png | Select-Object Name,Length | Format-Table -Auto | Out-String -Width 100 | ForEach-Object { Write-Output $_ }
