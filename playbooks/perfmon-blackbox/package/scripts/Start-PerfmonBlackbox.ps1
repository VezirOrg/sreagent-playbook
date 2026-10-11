<#
Start-PerfmonBlackbox.ps1: start the PerfmonBlackbox collector, keeping the old ring as a pending buffer first
(design sec. 2.2 step 0). Run by the Boot task at startup (-Reason boot) and by the DSC resource BlackboxRunning.
Windows PowerShell 5.1 (P25). Exit 0 = running.
#>
param([ValidateSet('boot', 'start')][string]$Reason = 'start')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'PerfmonBlackbox.Common.ps1')
$lock = Lock-Bb
try {
    $c = Get-BbCollector
    if (-not $c) { throw 'collector set PerfmonBlackbox does not exist (the DSC resource BlackboxCollector creates it)' }
    if ($c.Status -eq 'Running') { Write-BbLog "start ($Reason): already running"; exit 0 }
    $moved = Move-BbBufferToPending -Reason $Reason
    Limit-BbLocalKeep
    $null = Start-BbCollector
    Write-BbLog "start ($Reason): started; pending kept: $($moved -join ', ')"
    Write-BbEvent "PerfmonBlackbox collector started ($Reason); buffers kept as pending: $($moved.Count)" 'Information' 1001
    exit 0
} catch {
    Write-BbLog "start ($Reason) failed: $($_.Exception.Message)" 'ERROR'
    Write-BbEvent "PerfmonBlackbox collector start failed: $($_.Exception.Message)" 'Error' 3001
    exit 1
} finally {
    Unlock-Bb $lock
}
