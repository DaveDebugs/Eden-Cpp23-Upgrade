$ps = Get-Process eden -ErrorAction SilentlyContinue
foreach ($p in $ps) { $p.CloseMainWindow() | Out-Null }
Start-Sleep 12
Get-Process eden -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep 2
Write-Output "eden stopped"
