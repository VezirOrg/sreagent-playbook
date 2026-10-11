<#
T01 (test plan): the package builds and passes the local compliance test. AUTHORING SIDE: runs on dc from the scratch
folder C:\BbDev under a PORTABLE PowerShell 7 (zip extracted to C:\BbDev\pwsh, not installed, not on PATH; P24, P25),
never on vm1/arc1, which must stay pwsh-free.
  1 build.ps1 -> PerfmonBlackbox.zip + SHA-256
  2 Get-GuestConfigurationPackageComplianceStatus: NonCompliant on a clean box
  3 Start-GuestConfigurationPackageRemediation, then the status again: Compliant, all 6 resources
  4 clean up: the collector set, the two tasks, the package files (C:\ProgramData\PerfmonBlackbox\bin etc.)
#>
param([string]$Src = 'C:\BbDev\src', [string]$StorageAccountResourceId = '/subscriptions/synthsub/resourceGroups/rg-synth/providers/Microsoft.Storage/storageAccounts/stsynth', [switch]$KeepApplied)
$ErrorActionPreference = 'Stop'
$mods = 'C:\BbDev\modules7'
$null = New-Item -ItemType Directory -Force -Path $mods
$env:PSModulePath = "$mods;$env:PSModulePath"
Set-PSRepository PSGallery -InstallationPolicy Trusted
foreach ($m in @(@{ n = 'PSDesiredStateConfiguration'; v = '2.0.7' }, @{ n = 'GuestConfiguration'; v = $null })) {
    if (-not (Get-ChildItem (Join-Path $mods $m.n) -ErrorAction SilentlyContinue)) {
        if ($m.v) { Save-Module $m.n -RequiredVersion $m.v -Path $mods -Force } else { Save-Module $m.n -Path $mods -Force }
    }
}
"pwsh $($PSVersionTable.PSVersion); GuestConfiguration $((Get-ChildItem (Join-Path $mods 'GuestConfiguration')).Name)"
$out = 'C:\BbDev\out'
$b = & (Join-Path $Src 'package\build.ps1') -OutputPath $out
$b
$zip = Join-Path $out 'PerfmonBlackbox.zip'
Import-Module GuestConfiguration
$params = @(
    @{ ResourceType = 'BlackboxFiles'; ResourceId = 'Files'; ResourcePropertyName = 'StorageAccountResourceId'; ResourcePropertyValue = $StorageAccountResourceId },
    @{ ResourceType = 'BlackboxFiles'; ResourceId = 'Files'; ResourcePropertyName = 'MaxSizeMB'; ResourcePropertyValue = '512' },
    @{ ResourceType = 'BlackboxFiles'; ResourceId = 'Files'; ResourcePropertyName = 'SampleIntervalSeconds'; ResourcePropertyValue = '10' })
function Show($s, $label) {
    "$label`: complianceStatus=$($s.complianceStatus)"
    foreach ($r in $s.resources) {
        $why = ($r.reasons | ForEach-Object { $_.phrase }) -join ' | '
        "  $($r.properties.ResourceId) complianceStatus=$($r.complianceStatus) $why"
    }
}
$fail = 0
$s1 = Get-GuestConfigurationPackageComplianceStatus -Path $zip -Parameter $params
Show $s1 'before'
if ($s1.complianceStatus -ne $false) { "EXPECTED NonCompliant before remediation"; $fail = 1 }
$null = Start-GuestConfigurationPackageRemediation -Path $zip -Parameter $params
$s2 = Get-GuestConfigurationPackageComplianceStatus -Path $zip -Parameter $params
Show $s2 'after'
if ($s2.complianceStatus -ne $true -or @($s2.resources).Count -ne 6) { "EXPECTED Compliant with 6 resources after remediation"; $fail = 1 }
"logman: " + ((& logman query PerfmonBlackbox) -match '^(Status|Sample Interval|Max Size|Output Location):' -join ' | ')
"tasks: " + ((& schtasks /query /tn '\PerfmonBlackbox\' /fo csv /nh) -join ' | ')
if (-not $KeepApplied) {
    & logman stop PerfmonBlackbox 2>&1 | Out-Null; & logman delete PerfmonBlackbox 2>&1 | Out-Null
    foreach ($t in 'Boot', 'Export') { & schtasks /delete /tn "\PerfmonBlackbox\$t" /f 2>&1 | Out-Null }
    $root = 'C:\ProgramData\PerfmonBlackbox'
    foreach ($d in 'bin', 'blg', 'pending', 'work', 'outbox', 'log', 'config.json', 'state.json') { Remove-Item (Join-Path $root $d) -Recurse -Force -ErrorAction SilentlyContinue }
    "cleaned up (collector, tasks, package files); measurement files left as they were"
}
if ($fail) { 'T01 RESULT: FAIL' } else { 'T01 RESULT: PASS' }
exit $fail
