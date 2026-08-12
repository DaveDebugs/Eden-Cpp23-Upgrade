<#
.SYNOPSIS
    Window focus, synthetic keyboard input, and window capture for the Eden
    gameplay benchmark harness.

.DESCRIPTION
    Eden reads the keyboard through Qt key events, so SendInput-generated
    keystrokes are indistinguishable from real ones as far as the emulator is
    concerned. That is what makes a scripted in-game workload possible at all:
    the alternative -- an SDL gamepad -- cannot be synthesised without a
    virtual HID driver.

    Window capture uses PrintWindow with PW_RENDERFULLCONTENT so it works on a
    Vulkan swapchain surface, which plain BitBlt does not reliably do.
#>

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Drawing;
using System.Drawing.Imaging;

public static class EdenNative {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdc, uint flags);
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr hWnd, out RECT r);
    [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
    [DllImport("user32.dll")] public static extern uint MapVirtualKey(uint uCode, uint uMapType);

    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }

    const uint KEYEVENTF_KEYUP = 0x0002;
    const uint KEYEVENTF_EXTENDEDKEY = 0x0001;

    // Arrow keys and a few others are "extended"; without the flag some
    // applications see the numpad equivalent instead.
    static bool IsExtended(byte vk) {
        return vk == 0x25 || vk == 0x26 || vk == 0x27 || vk == 0x28 ||
               vk == 0x2D || vk == 0x2E || vk == 0x24 || vk == 0x23 ||
               vk == 0x21 || vk == 0x22;
    }

    public static void KeyDown(byte vk) {
        uint f = IsExtended(vk) ? KEYEVENTF_EXTENDEDKEY : 0;
        keybd_event(vk, (byte)MapVirtualKey(vk, 0), f, UIntPtr.Zero);
    }
    public static void KeyUp(byte vk) {
        uint f = (IsExtended(vk) ? KEYEVENTF_EXTENDEDKEY : 0) | KEYEVENTF_KEYUP;
        keybd_event(vk, (byte)MapVirtualKey(vk, 0), f, UIntPtr.Zero);
    }

    public static bool Capture(IntPtr hWnd, string path) {
        RECT r;
        if (!GetClientRect(hWnd, out r)) return false;
        int w = r.R - r.L, h = r.B - r.T;
        if (w <= 0 || h <= 0) return false;
        using (Bitmap bmp = new Bitmap(w, h, PixelFormat.Format32bppArgb))
        using (Graphics g = Graphics.FromImage(bmp)) {
            IntPtr hdc = g.GetHdc();
            // 0x00000002 = PW_RENDERFULLCONTENT, required for GPU-composited surfaces.
            bool ok = PrintWindow(hWnd, hdc, 0x00000002);
            g.ReleaseHdc(hdc);
            if (!ok) return false;
            bmp.Save(path, ImageFormat.Png);
        }
        return true;
    }
}
"@ -ReferencedAssemblies System.Drawing, System.Drawing.Primitives -ErrorAction SilentlyContinue

# Eden's default keyboard map, read from
# src/qt_common/config/qt_config.cpp (QtConfig::default_buttons / default_analogs).
# Switch button -> Windows virtual-key code.
$script:VK = @{
    'A'      = 0x43  # C
    'B'      = 0x58  # X
    'X'      = 0x56  # V
    'Y'      = 0x5A  # Z
    'LStick' = 0x46  # F
    'RStick' = 0x47  # G
    'L'      = 0x51  # Q
    'R'      = 0x45  # E
    'ZL'     = 0x52  # R
    'ZR'     = 0x54  # T
    'Plus'   = 0x4D  # M
    'Minus'  = 0x4E  # N
    'DLeft'  = 0x25
    'DUp'    = 0x26
    'DRight' = 0x27
    'DDown'  = 0x28
    'Up'     = 0x57  # W  (left analog)
    'Down'   = 0x53  # S
    'Left'   = 0x41  # A
    'Right'  = 0x44  # D
}

function Get-EdenWindow {
    param([int]$ProcessId)
    for ($i = 0; $i -lt 60; $i++) {
        $p = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
        if (-not $p) { return [IntPtr]::Zero }
        $p.Refresh()
        if ($p.MainWindowHandle -ne [IntPtr]::Zero) { return $p.MainWindowHandle }
        Start-Sleep -Milliseconds 500
    }
    return [IntPtr]::Zero
}

function Set-EdenFocus {
    param([IntPtr]$Handle)
    [EdenNative]::ShowWindow($Handle, 5) | Out-Null   # SW_SHOW
    [EdenNative]::SetForegroundWindow($Handle) | Out-Null
    Start-Sleep -Milliseconds 300
    return ([EdenNative]::GetForegroundWindow() -eq $Handle)
}

function Send-EdenButton {
    param([string]$Button, [int]$HoldMs = 60, [int]$AfterMs = 250)
    $vk = $script:VK[$Button]
    if ($null -eq $vk) { throw "unknown button '$Button'" }
    [EdenNative]::KeyDown([byte]$vk)
    Start-Sleep -Milliseconds $HoldMs
    [EdenNative]::KeyUp([byte]$vk)
    Start-Sleep -Milliseconds $AfterMs
}

function Set-EdenButtonState {
    param([string]$Button, [switch]$Down)
    $vk = [byte]$script:VK[$Button]
    if ($Down) { [EdenNative]::KeyDown($vk) } else { [EdenNative]::KeyUp($vk) }
}

function Save-EdenFrame {
    param([IntPtr]$Handle, [string]$Path)
    return [EdenNative]::Capture($Handle, $Path)
}

Export-ModuleMember -Function Get-EdenWindow, Set-EdenFocus, Send-EdenButton,
                              Set-EdenButtonState, Save-EdenFrame
