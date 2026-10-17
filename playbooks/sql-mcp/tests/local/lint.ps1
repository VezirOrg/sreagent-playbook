<#
L02: every server-side script is Windows PowerShell 5.1 compatible: PSUseCompatibleSyntax (5.1) and
PSUseCompatibleCommands (Windows Server 2016 and 2019 profiles, PowerShell 5.1; no client profile: the MCP host is a
Windows Server and step 3 uses Server-only cmdlets such as Install-WindowsFeature), plus the default rules at Error
severity. Runs on the authoring machine (PowerShell 7) or in CI. PSScriptAnalyzer is saved into -Modules (default: a
temp folder), never installed on a server. Exit 0 = clean.
#>
param([string]$Src = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)), [string]$Modules = (Join-Path ([IO.Path]::GetTempPath()) 'sqlmcp-lint-modules'))
$ErrorActionPreference = 'Stop'
$v = '1.23.0'
$psd = Join-Path $Modules "PSScriptAnalyzer\$v\PSScriptAnalyzer.psd1"
if (-not (Test-Path $psd)) {
  New-Item -ItemType Directory -Force $Modules | Out-Null
  Save-Module -Name PSScriptAnalyzer -RequiredVersion $v -Path $Modules -Force -Repository PSGallery
}
Import-Module $psd -Force
$settings = @{
  Rules = @{
    PSUseCompatibleSyntax   = @{ Enable = $true; TargetVersions = @('5.1') }
    PSUseCompatibleCommands = @{ Enable = $true; TargetProfiles = @(
        'win-8_x64_10.0.14393.0_5.1.14393.2791_x64_4.0.30319.42000_framework',
        'win-8_x64_10.0.17763.0_5.1.17763.316_x64_4.0.30319.42000_framework') }
  }
}
# The package (the admin and agent scripts run on an admin's machine, but are linted too) and the lab test helpers
# that run on the lab VMs (tests/lab/guest).
$files = @(Get-ChildItem (Join-Path $Src 'package'), (Join-Path $Src 'tests\lab\guest') -Recurse -Include *.ps1)
$issues = @()
foreach ($f in $files) {
  foreach ($rule in 'PSUseCompatibleSyntax', 'PSUseCompatibleCommands', '*') {
    if ($rule -eq '*') { $issues += @(Invoke-ScriptAnalyzer -Path $f.FullName -Severity Error) }
    else { $issues += @(Invoke-ScriptAnalyzer -Path $f.FullName -Settings $settings -IncludeRule $rule) }
  }
}
$issues | ForEach-Object { "{0}:{1} {2} {3}" -f (Split-Path -Leaf $_.ScriptPath), $_.Line, $_.RuleName, $_.Message }
"files: $($files.Count), issues: $($issues.Count)"
if ($issues.Count) { exit 1 }
