# Step 3. Run on the MCP host as a local admin (Windows PowerShell 5.1). Idempotent.
# Installs the gMSA on this host, Data API builder (self-contained build, SHA-256 checked) and a scheduled task that runs
# it as the gMSA at startup, listening on all interfaces (http, -Port), plus a firewall rule that lets in only -From.
# The configuration (step 4) goes to <Root>\config; start the task after it.
#   -From <cidr,...>   REQUIRED: the SRE Agent's subnet, plus any subnet you test from. Nothing else may connect.
#   -Version, -Sha256  Data API builder version; -Sha256 is needed only for a version not pinned below.
param([Parameter(Mandatory)][string[]]$From, [string]$Gmsa = 'gmsa-sqlmcp', [string]$Version = '2.1.5', [string]$Sha256,
      [int]$Port = 5000, [string]$TaskName = 'DAB-sqlmcp', [string]$Root = 'C:\dab')
$ErrorActionPreference = 'Stop'
$From = @($From | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })   # powershell -File passes 'a,b' as one string
$Pinned = @{   # SHA-256 of dab_net10.0_win-x64-<version>.zip, as published on the GitHub release
  '2.1.5' = '3e462efa109b7c89d21468b5025d490545da65cb84155acbd300bfbb431ad4af'
}
if (-not $Sha256) { $Sha256 = $Pinned[$Version] }
if (-not $Sha256) { throw "Data API builder $Version is not pinned in this script: pass -Sha256 <hash of the zip>." }
# 1. gMSA on this host
if (-not (Get-WindowsFeature RSAT-AD-PowerShell).Installed) { Install-WindowsFeature RSAT-AD-PowerShell | Out-Null }
Import-Module ActiveDirectory
Install-ADServiceAccount $Gmsa
"Test-ADServiceAccount: $(Test-ADServiceAccount $Gmsa)"
$account = "$((Get-ADDomain).NetBIOSName)\$Gmsa$"
# 2. 'Log on as a batch job' for the gMSA (a scheduled task needs it)
$sid = (New-Object Security.Principal.NTAccount $account).Translate([Security.Principal.SecurityIdentifier]).Value
$inf = "$env:TEMP\batch.inf"; $db = "$env:TEMP\batch.sdb"
secedit /export /cfg $inf /areas USER_RIGHTS | Out-Null
$line = (Get-Content $inf | Where-Object { $_ -like 'SeBatchLogonRight*' })
if ($line -notlike "*$sid*") {
  $new = if ($line) { "$line,*$sid" } else { "SeBatchLogonRight = *$sid" }
  "[Unicode]`r`nUnicode=yes`r`n[Version]`r`nsignature=`"`$CHICAGO`$`"`r`nRevision=1`r`n[Privilege Rights]`r`n$new" | Set-Content $inf -Encoding Unicode
  secedit /configure /db $db /cfg $inf /areas USER_RIGHTS | Out-Null
}
# 3. Data API builder binaries, checked against the pinned hash before they are unpacked
$bin = Join-Path $Root 'bin'; $cfg = Join-Path $Root 'config'; $logs = Join-Path $Root 'logs'
New-Item -ItemType Directory -Force $Root, $bin, $cfg, $logs | Out-Null
$exe = Join-Path $bin 'Microsoft.DataApiBuilder.exe'
$installed = if (Test-Path $exe) { "$(& $exe --version)" } else { '' }
if ($installed -notlike "*$Version*") {
  $zip = Join-Path $Root "dab_net10.0_win-x64-$Version.zip"
  [Net.ServicePointManager]::SecurityProtocol = 'Tls12'
  Invoke-WebRequest "https://github.com/Azure/data-api-builder/releases/download/v$Version/dab_net10.0_win-x64-$Version.zip" -OutFile $zip -UseBasicParsing
  $got = (Get-FileHash $zip -Algorithm SHA256).Hash
  if ($got -ne $Sha256) { Remove-Item $zip; throw "SHA-256 mismatch for $zip ($got): not installed." }
  if (Get-Process Microsoft.DataApiBuilder -ErrorAction SilentlyContinue) { throw "Data API builder is running: stop task $TaskName and the process first." }
  Expand-Archive $zip $bin -Force
}
& $exe --version
icacls $logs /grant "${account}:(OI)(CI)M" | Out-Null
icacls $cfg /grant "${account}:(OI)(CI)RX" | Out-Null
# 4. Scheduled task: Data API builder as the gMSA, at startup; output to <Root>\logs\dab.log (overwritten at each start)
$cmd = "/c set ASPNETCORE_URLS=http://0.0.0.0:$Port&& `"$exe`" start --config dab-config.json > `"$logs\dab.log`" 2>&1"
$a = New-ScheduledTaskAction -Execute cmd.exe -Argument $cmd -WorkingDirectory $cfg
$t = New-ScheduledTaskTrigger -AtStartup
$p = New-ScheduledTaskPrincipal -UserId $account -LogonType Password
$s = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -AllowStartIfOnBatteries
Register-ScheduledTask -TaskName $TaskName -Action $a -Trigger $t -Principal $p -Settings $s -Force | Out-Null
# 5. Windows Firewall stays on: the port only from -From
$rule = "$TaskName-$Port"
Get-NetFirewallRule -Name $rule -ErrorAction SilentlyContinue | Remove-NetFirewallRule
New-NetFirewallRule -Name $rule -DisplayName "$TaskName $Port (agent subnet only)" -Direction Inbound -Protocol TCP `
  -LocalPort $Port -RemoteAddress $From -Action Allow -Profile Any | Out-Null
"task registered: $TaskName (run 04-dab-config.ps1, then Start-ScheduledTask $TaskName)"
