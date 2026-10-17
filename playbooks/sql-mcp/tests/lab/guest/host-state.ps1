<#
LAB TEST helper (never shipped), on the MCP host as admin: the state of the Data API builder install as KEY value lines
(T13, T23). Windows PowerShell 5.1.
#>
param([string]$TaskName = 'DAB-sqlmcp', [int]$Port = 5000)
$task = Get-ScheduledTask $TaskName -ErrorAction SilentlyContinue
"TASK_STATE $(if ($task) { $task.State } else { 'missing' })"
"TASK_USER $(if ($task) { $task.Principal.UserId } else { '' })"
"TASK_LOGON $(if ($task) { $task.Principal.LogonType } else { '' })"
$l = @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
"LISTEN $(($l | ForEach-Object LocalAddress | Sort-Object -Unique) -join ',')"
$p = Get-CimInstance Win32_Process -Filter "Name = 'Microsoft.DataApiBuilder.exe'" | Select-Object -First 1
if ($p) { $o = Invoke-CimMethod -InputObject $p -MethodName GetOwner; "PROCESS_USER $($o.Domain)\$($o.User)" } else { 'PROCESS_USER none' }
"DAB_VERSION $(& C:\dab\bin\Microsoft.DataApiBuilder.exe --version | Select-Object -Last 1)"
$r = Get-NetFirewallRule -Name "$TaskName-$Port" -ErrorAction SilentlyContinue
"FW_ENABLED $(if ($r) { $r.Enabled } else { 'missing' })"
"FW_REMOTE $(if ($r) { (($r | Get-NetFirewallAddressFilter).RemoteAddress | Sort-Object) -join ',' } else { '' })"
"FW_PORT $(if ($r) { ($r | Get-NetFirewallPortFilter).LocalPort } else { '' })"
"CONFIG_FILES $((Get-ChildItem C:\dab\config\*.json | ForEach-Object Name | Sort-Object) -join ',')"
$all = (Get-ChildItem C:\dab\config\*.json | Sort-Object Name | ForEach-Object { "$($_.Name)=$((Get-FileHash $_.FullName).Hash)" }) -join ';'
$sha = [Security.Cryptography.SHA256]::Create()
"CONFIG_HASH $(([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($all))) -replace '-', '').Substring(0, 16))"
