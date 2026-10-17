# sql-mcp: operating it

Legend: ✅ proven in a lab · 📄 documented, not tested. Names as in the [README](../README.md): MCP host `vm1`, SQL
Servers `sql1`, `sql2`, task `DAB-sqlmcp`, port 5000. Every command runs on the MCP host as admin unless it says
otherwise.

## DAB does not start

If any SQL Server listed in the configuration is unreachable when DAB starts, DAB does not start at all and does not
come back by itself ✅. The scheduled task's restart setting never fires: `cmd.exe` starts fine and DAB exits with -1,
which Task Scheduler records as "completed" ✅. Recovery is manual, by design.

| Where | What you see | Meaning | |
|---|---|---|---|
| Application log, **.NET Runtime** 1000, **Error** | `Microsoft.Extensions.Hosting.Internal.Host` · `Hosting failed to start` | DAB did not start; the event names no server | ✅ |
| `C:\dab\logs\dab.log` | `Cannot obtain Schema for entity sql2_wait_stats … A network-related or instance-specific error` | The entity's prefix is the server. **Only here**, and every start overwrites the file: read it first | ✅ |
| Task Scheduler / Operational, **201** for `\DAB-sqlmcp` | `return code 4294967295` (a normal stop is 330, then 201 with 2147943691) | DAB exited with an error | ✅ |
| `Get-ScheduledTaskInfo DAB-sqlmcp` | `LastTaskResult` 4294967295, state **Ready** (healthy: **Running**, 267009) | same | ✅ |
| Application log, **.NET Runtime** 1000, **Warning**, `…BuiltInTools.ReadRecordsTool` | `MCP Tool error InternalServerError` | DAB runs, but one server does not answer (one event per failed call; `HttpsRedirectionMiddleware` warnings are noise) | ✅ |

```powershell
# 1. Did DAB fail to start in the last 24 h?
Get-WinEvent -FilterHashtable @{LogName='Application'; ProviderName='.NET Runtime'; Id=1000; Level=2; StartTime=(Get-Date).AddHours(-24)} -ErrorAction SilentlyContinue |
  Where-Object Message -match 'Hosting failed to start' | Select-Object TimeCreated
# 2. Which server? Read BEFORE restarting: every task start overwrites dab.log
Select-String C:\dab\logs\dab.log -Pattern 'Cannot obtain Schema for entity (\S+)' | ForEach-Object { $_.Matches[0].Groups[1].Value } | Select-Object -Unique
# 3. Task state and exit code
(Get-ScheduledTask DAB-sqlmcp).State; Get-ScheduledTaskInfo DAB-sqlmcp | Select-Object LastRunTime, LastTaskResult
# 4. Task history (enable the Operational log once; it can be off)
wevtutil sl Microsoft-Windows-TaskScheduler/Operational /e:true
Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-TaskScheduler/Operational'; Id=201; StartTime=(Get-Date).AddHours(-24)} |
  Where-Object Message -match 'DAB-sqlmcp' | ForEach-Object { if ($_.Message -match 'return code (\d+)') { '{0:u}  {1}' -f $_.TimeCreated, $Matches[1] } }
# 5. One server failing while DAB runs (last hour)
Get-WinEvent -FilterHashtable @{LogName='Application'; ProviderName='.NET Runtime'; Id=1000; Level=3; StartTime=(Get-Date).AddHours(-1)} -ErrorAction SilentlyContinue |
  Where-Object Message -match 'BuiltInTools\.\w+Tool' | Select-Object TimeCreated
# 6. Is DAB listening?
Get-NetTCPConnection -LocalPort 5000 -State Listen -ErrorAction SilentlyContinue
```

Then either take the server out (below) or, once every SQL Server answers, `Start-ScheduledTask DAB-sqlmcp`.
After patching a SQL Server or rebooting the MCP host, check that DAB listens; restart it only when all its SQL Servers
are up.

On an Azure VM the same checks run from an admin machine through the VM agent, without signing in 📄:
```sh
az vm run-command invoke -g <rg> -n vm1 --command-id RunPowerShellScript --query 'value[0].message' -o tsv \
  --scripts '(Get-ScheduledTask DAB-sqlmcp).State; (Get-ScheduledTaskInfo DAB-sqlmcp).LastTaskResult'
```

### What to alert on (📄; the signals themselves ✅)

1. the Error event "Hosting failed to start";
2. the task not Running, or a 201 for `\DAB-sqlmcp` with a code other than 2147943691;
3. a probe of TCP 5000 (or an MCP `initialize`) from outside: the only check that also catches a host that is down;
4. `…BuiltInTools…Tool` warnings: one server is down while DAB stays up.

## Take a server out

DAB 2.1.5 has no `enabled` flag for a data source; `"mcp": false` or `health.enabled: false` do not help, because DAB
still reads the schema at startup ✅. Renaming the server's file works, since a listed file that does not exist is
skipped ✅:

```powershell
$s = 'sql2'                                                   # the server that is down or in maintenance
Rename-Item "C:\dab\config\$s.json" "$s.json.off"
Stop-ScheduledTask DAB-sqlmcp; Get-Process Microsoft.DataApiBuilder -ErrorAction SilentlyContinue | Stop-Process -Force; Start-ScheduledTask DAB-sqlmcp
Start-Sleep 15; [bool](Get-NetTCPConnection -LocalPort 5000 -State Listen -ErrorAction SilentlyContinue)   # True
```
Put it back with `Rename-Item "C:\dab\config\$s.json.off" "$s.json"`, the same restart and the same check. It works for
every server, the first one included, because each has its own file ✅.

> **⚠️ The skip is silent.** DAB logs nothing for a missing file ✅: a deleted, mistyped or forgotten `.off` file
> goes unnoticed and the agent simply no longer sees that server. Run this check after every change and from
> monitoring:

```powershell
$c = 'C:\dab\config'; $root = Get-Content "$c\dab-config.json" -Raw | ConvertFrom-Json
$n = 0
foreach ($f in $root.'data-source-files') { if (Test-Path "$c\$f") { $n += @((Get-Content "$c\$f" -Raw | ConvertFrom-Json).entities.PSObject.Properties).Count } else { "MISSING: $f (DAB skips it silently)" } }
"entities DAB will load: $n  (expected: 7 per server)"
Get-ChildItem "$c\*.json.off" -ErrorAction SilentlyContinue | ForEach-Object { "TAKEN OUT: $($_.Name)" }
```

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| HTTP **401** (`Bearer error="invalid_token"`) | wrong `aud`/`iss`, expired, or the host cannot reach Entra for the signing keys | DAB's audience is the app ID (a GUID, not `api://…`) and the issuer `…/<tenant>/v2.0`; check outbound 443 to Entra |
| HTTP **403** | the header names a role that is not in the token | assign the app role (`entra-setup`) |
| `NoEntitiesConfigured`, or `PermissionDenied` on a named entity | no `X-MS-API-ROLE` header: the role is `authenticated`, which has no permission | re-run `connect-agent` |
| `AADSTS501051 … not assigned to a role` | an identity other than the agent asked for a token | expected; for the agent itself, re-run `entra-setup` |
| Token has no `roles` although the role is assigned | a managed-identity token cached (up to ~24 h) from before the assignment | wait; next time assign before the first token request |
| Connector not connected / tool calls fail | name not resolvable from the agent subnet, firewall rule missing, DAB not on `0.0.0.0`, "Remote MCP server access" on, or the `Host` not in `allowed-hosts` | check each; `04-dab-config.ps1 -AllowedHosts` |
| DAB stops, **all** entities down | one bad entity (for example a view with a `sql_variant` column) | restore the last backup folder, add entities one at a time |
| `dm_exec_sessions` / `dm_exec_requests` show only one session | the login lacks the grant (older SQL Server versions, below): the views then silently show only DAB's own session | check `sys.server_permissions` for the gMSA |
| `dab.log` is empty | normal in production mode | check the listener and an MCP call instead |

**Where do the calls come from?** Turn the Windows Filtering Platform connection audit on for a moment only (it logs
every allowed connection on the host) ✅:
```powershell
auditpol /set /subcategory:"Filtering Platform Connection" /success:enable
# ask the agent a question, then:
Get-WinEvent -FilterHashtable @{LogName='Security'; Id=5156; StartTime=(Get-Date).AddMinutes(-10)} |
  Where-Object { $_.Message -match 'Destination Port:\s+5000' -and $_.Message -match 'Inbound' } |
  ForEach-Object { [regex]::Match($_.Message, 'Source Address:\s+(\S+)').Groups[1].Value } | Group-Object | ForEach-Object { "$($_.Count) x $($_.Name)" }
auditpol /set /subcategory:"Filtering Platform Connection" /success:disable
```
The sources must be in the agent subnet.

## How many servers per DAB

Measured on one DAB 2.1.5 with up to 50 data sources (aliases of two SQL Servers) ✅:

| Servers | Startup: listener / first read | Working set | `describe_entities`: full / `nameOnly` / one entity |
|---|---|---|---|
| 2 | 2.1 s / 4.9 s | 132 MB | 74 KB / 2.3 KB / 1.5 KB |
| 10 | 2.4 s / 5.2 s | 152 MB | 368 KB / 11 KB / 1.5 KB |
| 25 | 3.5 s / 6.2 s | 161 MB | 921 KB / 27 KB / 1.5 KB |
| 50 | 5.2 s / 8.0 s | 176 MB | 1.8 MB / 54 KB / 1.5 KB |

Capacity is not the limit: with 25 servers the agent found the right entity by itself (`nameOnly` first, then one
entity) and matched sqlcmd ✅. **The limit is failure coupling** (one unreachable server at startup stops all of them):
one DAB per group of servers that share a failure domain and maintenance window, at most 25. Not measured: real
distinct servers (latency, one connection pool each) and concurrent questions.

## SQL Server versions

The minimal grant for the seven views (the same on every Learn page of the seven): 2022 and later →
`VIEW SERVER PERFORMANCE STATE` (the role `##MS_ServerPerformanceStateReader##`), older → `VIEW SERVER STATE`. DAB
supports SQL Server 2016 and later.

| Version | Grant for the gMSA | |
|---|---|---|
| SQL Server 2025, 2022 | `##MS_ServerPerformanceStateReader##` (what `02-sql-login.sql` does) | ✅ 2025 / 📄 2022 |
| SQL Server 2019, 2017, 2016 | `GRANT VIEW SERVER STATE TO [CONTOSO\gmsa-sqlmcp$];` instead of the role | 📄 |

`VIEW SERVER STATE` is broader: all server-state DMVs, including connections with client addresses and other sessions'
query text and plans (still no table data, no change, no object). Without any grant, `dm_exec_sessions` and
`dm_exec_requests` **silently** show only DAB's own session; check the grant with
`SELECT permission_name FROM sys.server_permissions WHERE grantee_principal_id = SUSER_ID(N'CONTOSO\gmsa-sqlmcp$')`.
Older versions were not tested.

## Upgrading DAB

`03-dab-install.ps1` pins DAB **2.1.5** and the SHA-256 of its Windows zip. The design depends on two DAB behaviours
that a new version may change: the placeholder root (2.1.5 refuses a root without a data source) and the silent skip of
a missing listed file. Before moving to a new version:

1. run a copy of the live configuration with the new build on another port (the playbook's lab test T24 does this:
   copy `C:\dab\config` to a test folder, start the new `Microsoft.DataApiBuilder.exe` there with
   `ASPNETCORE_URLS=http://localhost:5001`) and check that it starts and lists 7 entities per server;
2. repeat with one server's file renamed to `.off` (it must still start, without that server);
3. only then run `03-dab-install.ps1 -Version <new> -Sha256 <hash of the zip>` (stop the task first) and restart.
