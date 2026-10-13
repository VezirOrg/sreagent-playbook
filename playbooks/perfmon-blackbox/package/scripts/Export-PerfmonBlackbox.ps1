<#
Export-PerfmonBlackbox.ps1: export the window since the last successful export, with no gap and no overlap
(design sec. 2.2, decisions P15, P21, P26). Run by the Export task as SYSTEM every ExportEveryHours, and with -RollOnly
by the Roll task every 15 min (P62: close the ring into pending\ so a bad shutdown loses at most 15 min).

  1 roll the collector (stop -> move the ring to pending\ -> start): a running circular .blg cannot be read
  2 relog every pending buffer to CSV, merge them in time order, keep only samples after last_ts
  3 find holes and their causes (buffer_overrun, collector_restart, machine_off, local_cap, missing_samples,
    unreadable_ring: a ring relog could not read in 3 runs is deleted and reported, P54)
  4 validate the CSV; 5 zip CSV + manifest.json (.NET ZipFile); 6 token from IMDS or HIMDS (machine identity)
  7 upload (Put Blob, or Put Block + Put Block List); 8 only then move last_ts forward and delete what was exported

Windows PowerShell 5.1 (P25); only what ships with Windows Server (P26). Exit 0 = exported (or nothing new),
1 = failed (state unchanged, the next run exports a longer window from the same last_ts).
  -NoUpload   build the zip in outbox\ and stop before the upload (lab and Pester use)
  -RollOnly   only close the ring into pending\ (stop, move, start); no relog, no upload (the Roll task)
#>
param([switch]$NoUpload, [switch]$RollOnly)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'PerfmonBlackbox.Common.ps1')
try {
    if ($RollOnly) {
        $r = Invoke-BbRollOnly
        Write-Output ("roll: {0}" -f $r.Result)
        exit 0
    }
    $r = Invoke-BbExport -NoUpload:$NoUpload
    Write-Output ("export: {0}, {1} rows" -f $r.Result, $r.Rows)
    exit 0
} catch {
    Write-Output "export failed: $($_.Exception.Message)"
    exit 1
}
