$dir = "P:\Programming Repositories\eden\build\gpl_pipeline2"
$files = Get-ChildItem $dir -Filter *.log | Sort-Object Name
Write-Output ("logs: {0}" -f $files.Count)
Write-Output ""
Write-Output "=========== PIPELINE BUILD COST (eden cache + NVIDIA GLCache cleared every boot) ==========="
Write-Output ""

$rows = @()
foreach ($f in $files) {
    $lines = Select-String -Path $f.FullName -Pattern 'PIPELINE_BUILD path=(\w+) us=(\d+)'
    if (-not $lines) { Write-Output ("{0,-18} : no data" -f $f.BaseName); continue }
    $us = @(); $ts = @(); $paths = @{}
    foreach ($h in $lines) {
        $m = [regex]::Match($h.Line, 'path=(\w+) us=(\d+)')
        if (-not $m.Success) { continue }
        $us += [int]$m.Groups[2].Value
        $k = $m.Groups[1].Value
        if ($paths.ContainsKey($k)) { $paths[$k]++ } else { $paths[$k] = 1 }
        $t = [regex]::Match($h.Line, '^\[\s*([0-9.]+)\]')
        if ($t.Success) { $ts += [double]$t.Groups[1].Value }
    }
    $n = $us.Count
    if ($n -eq 0) { continue }
    $sorted = $us | Sort-Object
    $sum = ($us | Measure-Object -Sum).Sum
    $span = if ($ts.Count -gt 1) { ($ts | Measure-Object -Maximum).Maximum - ($ts | Measure-Object -Minimum).Minimum } else { 0 }
    $arm = if ($f.BaseName -like 'gpl_on*') { 'gpl_on' } else { 'gpl_off' }
    Write-Output ("{0,-18} n={1,3}  cpu_total={2,7:N1} ms  wall_span={3,6:N2} s  median={4,7:N0} us  p95={5,8:N0} us  [{6}]" -f `
        $f.BaseName, $n, ($sum/1000.0), $span, $sorted[[int][Math]::Floor($n/2)],
        $sorted[[Math]::Max(0,[int][Math]::Floor($n*0.95)-1)],
        (($paths.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ','))
    $rows += [pscustomobject]@{ arm=$arm; total=($sum/1000.0); span=$span; n=$n }
}

function Stat($vals) {
    $m = ($vals | Measure-Object -Average).Average
    if ($vals.Count -lt 2) { return @($m, 0.0) }
    $v = 0.0; foreach ($x in $vals) { $v += [Math]::Pow($x - $m, 2) }
    return @($m, [Math]::Sqrt($v / ($vals.Count - 1)))
}

Write-Output ""
Write-Output "=========== SUMMARY ==========="
$agg = @{}
foreach ($arm in @('gpl_on','gpl_off')) {
    $a = @($rows | Where-Object { $_.arm -eq $arm })
    if ($a.Count -eq 0) { continue }
    $tot = @($a | ForEach-Object { $_.total })
    $spn = @($a | ForEach-Object { $_.span })
    $st = Stat $tot
    $ss = Stat $spn
    $agg[$arm] = $st[0]
    Write-Output ("{0,-8} runs={1}  cpu_total {2,7:N1} +/- {3,5:N1} ms   wall_span {4,5:N2} +/- {5,4:N2} s" -f `
        $arm, $a.Count, $st[0], $st[1], $ss[0], $ss[1])
    Write-Output ("         values: {0}" -f (($tot | ForEach-Object { "{0:N1}" -f $_ }) -join ', '))
}
if ($agg.ContainsKey('gpl_on') -and $agg.ContainsKey('gpl_off')) {
    $d = 100.0 * ($agg['gpl_on'] / $agg['gpl_off'] - 1.0)
    Write-Output ""
    Write-Output ("GPL vs monolithic pipeline build cost: {0:+0.0;-0.0}%  (positive = GPL costs MORE)" -f $d)
}
