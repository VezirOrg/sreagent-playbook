<#
build.ps1: build the PerfmonBlackbox Machine Configuration package (test plan T01). AUTHORING SIDE ONLY: the CI
Windows runner or a lab VM's scratch folder (decisions P24, P25), never a customer server. Needs PowerShell 7 with
the GuestConfiguration and PSDesiredStateConfiguration 2.0.7 modules (installed here if missing, -Install).

  pwsh -File build.ps1 [-OutputPath <dir>] [-Install]

Output: <OutputPath>\PerfmonBlackbox.zip and its SHA-256 (the policy's contentHash).
#>
param([string]$OutputPath = (Join-Path $PSScriptRoot 'out'), [switch]$Install)
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSEdition -ne 'Core') { throw 'build.ps1 runs in PowerShell 7 (authoring side)' }
if ($Install) {
    Set-PSRepository PSGallery -InstallationPolicy Trusted
    if (-not (Get-Module -ListAvailable GuestConfiguration)) { Install-Module GuestConfiguration -Scope CurrentUser -Force }
    if (-not (Get-Module -ListAvailable PSDesiredStateConfiguration | Where-Object Version -eq '2.0.7')) {
        Install-Module PSDesiredStateConfiguration -RequiredVersion 2.0.7 -Scope CurrentUser -Force
    }
}
Import-Module PSDesiredStateConfiguration -RequiredVersion 2.0.7
Import-Module GuestConfiguration

$stage = Join-Path $OutputPath 'stage'
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
$mod = Join-Path $stage 'modules\PerfmonBlackboxDsc'
New-Item -ItemType Directory -Force -Path (Join-Path $mod 'Files\collector') | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'PerfmonBlackboxDsc\*') $mod -Recurse
Copy-Item (Join-Path $PSScriptRoot 'scripts\*.ps1') (Join-Path $mod 'Files')
Copy-Item (Join-Path $PSScriptRoot 'collector\*') (Join-Path $mod 'Files\collector')

$env:PSModulePath = (Join-Path $stage 'modules') + [IO.Path]::PathSeparator + $env:PSModulePath
. (Join-Path $PSScriptRoot 'PerfmonBlackbox.config.ps1')
$mofDir = Join-Path $stage 'mof'
PerfmonBlackbox -OutputPath $mofDir | Out-Null
$mof = Join-Path $mofDir 'PerfmonBlackbox.mof'
Move-Item (Join-Path $mofDir 'localhost.mof') $mof -Force

$pkg = New-GuestConfigurationPackage -Name 'PerfmonBlackbox' -Configuration $mof -Type AuditAndSet -Path $OutputPath -Force
$hash = (Get-FileHash $pkg.Path -Algorithm SHA256).Hash
"package: $($pkg.Path)"
"sha256: $hash"
