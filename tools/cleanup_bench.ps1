Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like '*Bench-Gameplay*' } |
    ForEach-Object { Write-Output "killing harness $($_.ProcessId)"; Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

Get-Process presentmon -ErrorAction SilentlyContinue |
    ForEach-Object { Write-Output "killing presentmon $($_.Id)"; Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }

Get-Process eden -ErrorAction SilentlyContinue |
    ForEach-Object { Write-Output "killing eden $($_.Id)"; Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }

# Killing PresentMon does not close the ETW session it opened. Those sessions
# keep running, keep consuming the shared trace buffers, and the symptom is not
# an error -- the next capture reports "N ETW events were lost" and writes no
# CSV at all. Six of them had accumulated before this was spotted.
# Split on any whitespace and take the first field. Splitting on runs of two
# or more spaces looks tidier but fails on the long session names, where the
# name and the "Trace" column run together with a single space between them.
$sessions = & logman query -ets 2>$null |
    ForEach-Object { ($_.Trim() -split '\s+')[0] } |
    Where-Object { $_ -like 'edenbench*' -or $_ -like 'PresentMon*' }

foreach ($s in $sessions) {
    Write-Output "stopping ETW session $s"
    & logman stop $s -ets 2>&1 | Out-Null
}

Start-Sleep 3
Write-Output "cleanup done"
