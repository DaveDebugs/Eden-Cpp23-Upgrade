<#
.SYNOPSIS
    Show which Eden threads are burning CPU, by name.

.DESCRIPTION
    Samples per-thread CPU time over a window and resolves each thread's name
    via GetThreadDescription (Eden calls SetThreadDescription through
    Common::SetCurrentThreadName). Tells you which subsystem is the bottleneck
    rather than just which numeric TID.
#>
param(
    [int]$Seconds = 30,
    [string]$ProcessName = "eden"
)

Add-Type -Namespace Win32 -Name Thr -MemberDefinition @"
[DllImport("kernel32.dll", SetLastError=true)]
public static extern IntPtr OpenThread(uint dwDesiredAccess, bool bInheritHandle, uint dwThreadId);
[DllImport("kernel32.dll", SetLastError=true)]
public static extern bool CloseHandle(IntPtr h);
[DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
public static extern int GetThreadDescription(IntPtr hThread, out IntPtr ppszThreadDescription);
[DllImport("kernel32.dll")]
public static extern IntPtr LocalFree(IntPtr h);
"@

function Get-ThreadName([uint32]$tid) {
    # THREAD_QUERY_LIMITED_INFORMATION = 0x0800
    $h = [Win32.Thr]::OpenThread(0x0800, $false, $tid)
    if ($h -eq [IntPtr]::Zero) { return "" }
    try {
        $ptr = [IntPtr]::Zero
        $hr = [Win32.Thr]::GetThreadDescription($h, [ref]$ptr)
        if ($hr -ge 0 -and $ptr -ne [IntPtr]::Zero) {
            $s = [System.Runtime.InteropServices.Marshal]::PtrToStringUni($ptr)
            [Win32.Thr]::LocalFree($ptr) | Out-Null
            return $s
        }
    } catch {}
    finally { [Win32.Thr]::CloseHandle($h) | Out-Null }
    return ""
}

$p = Get-Process $ProcessName -ErrorAction Stop | Select-Object -First 1
$p.Refresh()

$t0 = @{}
foreach ($t in $p.Threads) { try { $t0[$t.Id] = $t.TotalProcessorTime.TotalMilliseconds } catch {} }
$w0 = Get-Date
Start-Sleep -Seconds $Seconds
$p.Refresh()
$wall = ((Get-Date) - $w0).TotalMilliseconds

$rows = @()
foreach ($t in $p.Threads) {
    try {
        $prev = if ($t0.ContainsKey($t.Id)) { $t0[$t.Id] } else { 0 }
        $d = $t.TotalProcessorTime.TotalMilliseconds - $prev
        if ($d -gt 20) {
            $rows += [pscustomobject]@{
                TID    = $t.Id
                Name   = (Get-ThreadName ([uint32]$t.Id))
                CPUms  = [int]$d
                Pct    = [Math]::Round(100 * $d / $wall, 1)
            }
        }
    } catch {}
}

"threads total: $($p.Threads.Count)   window: $([int]$wall) ms"
$rows | Sort-Object CPUms -Descending | Select-Object -First 15 | Format-Table -AutoSize | Out-String -Width 90
$sum = ($rows | Measure-Object CPUms -Sum).Sum
"cores used: {0:N2} of {1}" -f ($sum / $wall), [Environment]::ProcessorCount
