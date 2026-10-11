<#
Run-L05.ps1: L05 on a lab VM (P24, P25), under Windows PowerShell 5.1, from the scratch folder C:\BbDev.
  1 Pester 5 and PSScriptAnalyzer are saved into C:\BbDev\modules (lab VM only; never an adopter requirement)
  2 Pester: tests\pester\*.Tests.ps1
  3 lint every server-side script: PSUseCompatibleSyntax (5.1) and PSUseCompatibleCommands (Windows Server
    2016/2019/2022 profiles, PowerShell 5.1), plus the default rules at Error severity
Prints a summary; exit 0 = all green. -Clean removes C:\BbDev at the end.
#>
param([string]$Src = 'C:\BbDev\src', [switch]$Clean, [switch]$LintOnly)
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -ne 5) { throw "L05 runs under Windows PowerShell 5.1, not $($PSVersionTable.PSVersion)" }
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$mods = 'C:\BbDev\modules'
$null = New-Item -ItemType Directory -Force -Path $mods
$env:PSModulePath = "$mods;$env:PSModulePath"
foreach ($m in @(@{ n = 'Pester'; v = '5.6.1' }, @{ n = 'PSScriptAnalyzer'; v = '1.23.0' })) {
    if (-not (Test-Path (Join-Path $mods "$($m.n)\$($m.v)"))) {
        if (-not (Get-PackageProvider -ListAvailable -Name NuGet -ErrorAction SilentlyContinue | Where-Object { $_.Version -ge '2.8.5.201' })) {
            $null = Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser
        }
        Save-Module -Name $m.n -RequiredVersion $m.v -Path $mods -Force -Repository PSGallery
    }
}
Import-Module (Join-Path $mods 'Pester\5.6.1\Pester.psd1') -Force
Import-Module (Join-Path $mods 'PSScriptAnalyzer\1.23.0\PSScriptAnalyzer.psd1') -Force
$fail = 0
if (-not $LintOnly) {
    $cfg = New-PesterConfiguration
    $cfg.Run.Path = Join-Path $Src 'tests\pester'
    $cfg.Run.PassThru = $true
    $cfg.Output.Verbosity = 'Normal'
    $r = Invoke-Pester -Configuration $cfg
    "pester: passed $($r.PassedCount) failed $($r.FailedCount) skipped $($r.SkippedCount)"
    foreach ($t in $r.Failed) { "  FAILED: $($t.ExpandedPath): $($t.ErrorRecord[0].Exception.Message)" }
    if ($r.FailedCount -or -not $r.PassedCount) { $fail = 1 }
}
$settings = @{
    Rules = @{
        PSUseCompatibleSyntax   = @{ Enable = $true; TargetVersions = @('5.1') }
        PSUseCompatibleCommands = @{ Enable = $true; TargetProfiles = @(
                'win-8_x64_10.0.14393.0_5.1.14393.2791_x64_4.0.30319.42000_framework',
                'win-8_x64_10.0.17763.0_5.1.17763.316_x64_4.0.30319.42000_framework',
                'win-48_x64_10.0.17763.0_5.1.17763.316_x64_4.0.30319.42000_framework') }
    }
}
$files = @(Get-ChildItem (Join-Path $Src 'package') -Recurse -Include *.ps1, *.psm1 | Where-Object { $_.Name -notin 'build.ps1', 'PerfmonBlackbox.config.ps1' })  # authoring side, not server code
$issues = @()
foreach ($f in $files) {
    foreach ($rule in 'PSUseCompatibleSyntax', 'PSUseCompatibleCommands', '*') {
        try {
            if ($rule -eq '*') { $issues += @(Invoke-ScriptAnalyzer -Path $f.FullName -Severity Error -ErrorAction Stop) }
            else { $issues += @(Invoke-ScriptAnalyzer -Path $f.FullName -Settings $settings -IncludeRule $rule -ErrorAction Stop) }
        } catch {
            $e = $_.Exception; while ($e.InnerException) { $e = $e.InnerException }
            $issues += [pscustomobject]@{ RuleName = "RULE_ERROR($rule)"; ScriptPath = $f.FullName; Line = 0; Message = $e.Message }
        }
    }
}
"lint: $($files.Count) files, $($issues.Count) findings (5.1 compatibility + errors)"
foreach ($i in $issues) { "  $($i.RuleName) $(Split-Path -Leaf $i.ScriptPath):$($i.Line) $($i.Message)" }
if ($issues.Count) { $fail = 1 }
$warn = @()
foreach ($f in $files) { $warn += @(Invoke-ScriptAnalyzer -Path $f.FullName -Severity Warning) }
"lint warnings (not gating): $($warn.Count)"
$warn | Group-Object RuleName | ForEach-Object { "  $($_.Name): $($_.Count)" }
if ($Clean) { Set-Location C:\; Remove-Item C:\BbDev -Recurse -Force }
if ($fail) { 'L05 RESULT: FAIL' } else { 'L05 RESULT: PASS' }
exit $fail
