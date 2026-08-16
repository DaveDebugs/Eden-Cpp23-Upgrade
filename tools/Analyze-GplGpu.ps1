$dir = "P:\Programming Repositories\eden\build\gpl_gpu"
$files = Get-ChildItem $dir -Filter *.csv -ErrorAction SilentlyContinue | Sort-Object Name
Write-Output ("captures: {0}" -f $files.Count)
Write-Output ""
Write-Output "=========== GPU TIME PER FRAME, same binary, GPL on vs off ==========="
Write-Output ""
$rows = @()
foreach ($f in $files) {
    $csv = Import-Csv $f.FullName
    $gpu = @(); $ft = @()
    foreach ($r in $csv) {
        $v = 0.0
        if ([double]::TryParse($r.MsGPUBusy, [ref]$v)) { if ($v -ge 0) { $gpu += $v } }
        $w = 0.0
        if ([double]::TryParse($r.MsBetweenPresents, [ref]$w)) { if ($w -gt 0) { $ft += $w } }
    }
    if ($gpu.Count -lt 50) { Write-Output ("{0,-20} too few rows ({1})" -f $f.BaseName, $gpu.Count); continue }
    $gs = $gpu | Sort-Object
    $mean = ($gpu | Measure-Object -Average).Average
    $med  = $gs[[int][Math]::Floor($gs.Count/2)]
    $fps  = if ($ft.Count) { 1000.0 / (($ft | Measure-Object -Average).Average) } else { 0 }
    $arm = if ($f.BaseName -like 'gpl_on*') { 'gpl_on' } else { 'gpl_off' }
    Write-Output ("{0,-20} frames={1,5}  gpu_mean={2,6:N3} ms  gpu_median={3,6:N3} ms  fps={4,7:N2}" -f `
        $f.BaseName, $gpu.Count, $mean, $med, $fps)
    $rows += [pscustomobject]@{ arm=$arm; gpu=$mean; fps=$fps }
}
function Stat($v) {
    $m = ($v | Measure-Object -Average).Average
    if ($v.Count -lt 2) { return @($m,0.0) }
    $s = 0.0; foreach ($x in $v) { $s += [Math]::Pow($x-$m,2) }
    return @($m, [Math]::Sqrt($s/($v.Count-1)))
}
Write-Output ""
Write-Output "=========== SUMMARY ==========="
$agg = @{}
foreach ($arm in @('gpl_on','gpl_off')) {
    $a = @($rows | Where-Object { $_.arm -eq $arm })
    if ($a.Count -eq 0) { continue }
    $g = Stat @($a | ForEach-Object { $_.gpu })
    $ff = Stat @($a | ForEach-Object { $_.fps })
    $agg[$arm] = $g[0]
    Write-Output ("{0,-8} runs={1}  gpu {2,6:N3} +/- {3,5:N3} ms   fps {4,7:N2} +/- {5,5:N2}" -f $arm, $a.Count, $g[0], $g[1], $ff[0], $ff[1])
    Write-Output ("         gpu values: {0}" -f (($a | ForEach-Object { "{0:N3}" -f $_.gpu }) -join ', '))
}
if ($agg.ContainsKey('gpl_on') -and $agg.ContainsKey('gpl_off')) {
    Write-Output ""
    Write-Output ("GPU time per frame, GPL vs monolithic: {0:+0.0;-0.0}%  (positive = GPL costs MORE)" -f (100.0*($agg['gpl_on']/$agg['gpl_off']-1.0)))
}
