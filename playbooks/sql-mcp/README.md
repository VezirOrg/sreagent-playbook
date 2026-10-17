# sql-mcp: let Azure SRE Agent read SQL Server DMVs, read-only, over your VNet

**Ask the Azure SRE Agent "what is the top wait on sql2?" or "how many user sessions are on sql1?" and get the answer
from the server's dynamic management views (DMVs).** A read-only MCP server, built on
[Data API builder](https://learn.microsoft.com/azure/data-api-builder/) (DAB), runs on one Windows member server and
exposes seven DMV views per SQL Server. The agent calls it over your VNet with its own managed identity. No secret is
stored anywhere, and **no database or object is created on the SQL Servers**.

> Not an official Microsoft product. Working and versioned, no support promise. See the
> [repo README](../../README.md).

**Status: v1.0.0** ([release](https://github.com/VezirOrg/sreagent-playbook/releases/tag/sql-mcp/v1.0.0), package
`SqlMcp.zip`, SHA-256 `F3B2BD2AFF1F7873…`, [CHANGELOG](CHANGELOG.md)). Tested end to end on 2026-10-17 in this playbook's own
lab, built from scratch with these scripts (DAB 2.1.5, SQL Server 2025, Windows Server 2025, Azure VMs in the agent's VNet): every lab
test T10–T25 passed ([docs/tests.md](docs/tests.md)). Why it is built this way: [docs/design.md](docs/design.md).

Legend: ✅ proven in a lab (test IDs in [docs/tests.md](docs/tests.md)) · 📄 documented (Microsoft Learn or the DAB
source), not tested.

## What it does, and what it does not

- **Exposes** seven DMV views per SQL Server as MCP entities named `<server>_<view>`: `wait_stats`, `perf_counters`,
  `sys_memory`, `memory_clerks`, `sessions`, `requests`, `query_stats`. Every column is listed with a description, so
  the agent knows what it can filter and sort on.
- **Three read-only tools:** `describe_entities` (what exists), `read_records` (filter, sort, select, first N),
  `aggregate_records` (count, sum, avg, min, max, grouped). Create, update, delete and execute are off; REST and
  GraphQL are off. Cache is off (DMVs are live).
- **Least privilege on SQL Server:** DAB connects as a **gMSA** that has a login and
  `##MS_ServerPerformanceStateReader##` (SQL Server 2022+) only. It cannot read table data, change anything, or see
  security DMVs.
- **Only the agent gets in:** DAB accepts only Entra tokens for its own app that carry the app role `MCP.Read`, and the
  app requires assignment, so no other identity in the tenant can get such a token ✅.
- **Not exposed, by design:**
  - DMV **functions** (`dm_exec_sql_text`, `dm_db_index_physical_stats`, `dm_io_virtual_file_stats`): no query text,
    index fragmentation or file I/O. DAB can only serve them through a wrapper object on SQL Server, which this design
    forbids ✅.
  - **Server configuration** (version, edition, collation, MAXDOP): the views that hold it have `sql_variant` columns,
    which stop DAB 2.1.5 at startup, and `SERVERPROPERTY` / `@@VERSION` are functions 📄. Use sqlcmd or SSMS.
  - **Free SQL:** there is no "run a query" tool; the agent can only filter, sort and aggregate the entities ✅.

## How it works

```
SRE Agent ── connector "sqlmcp": token from the agent's managed identity,
   │          scope api://<appId>/.default, header X-MS-API-ROLE: MCP.Read
   ▼  http://vm1.contoso.local:5000/mcp   (over the VNet; no public endpoint)
DAB on vm1 ── checks the token (audience, v2 issuer, Entra signing keys) and the role
   │        ── entity sql2_wait_stats → the data source of sql2
   ▼  TDS 1433, Windows auth as CONTOSO\gmsa-sqlmcp$ (Kerberos), Database=master
sql2 ── SELECT … FROM sys.dm_os_wait_stats   (login + ##MS_ServerPerformanceStateReader## only)
```

- **DAB** runs on the MCP host as a **scheduled task** under the gMSA (it is not a Windows service), listening on
  port 5000 (plain HTTP inside the VNet). Windows Firewall lets in only the agent's subnet (and any test subnet you
  name) ✅.
- **Configuration layout** (written by `04-dab-config.ps1`):
  - `dab-config.json`: the runtime (MCP on, auth, `allowed-hosts`), the list `data-source-files` and a
    **placeholder** data source (an unresolvable name, no entities, health off) that DAB never contacts. It exists
    only because DAB 2.1.5 refuses a root file without a data source ✅. **Re-test it after every DAB upgrade**
    ([docs/operations.md](docs/operations.md#upgrading-dab)).
  - one file per SQL Server (`sql1.json`, `sql2.json`, …) with its connection string and entities. So any server can
    be taken out by renaming its file ([docs/operations.md](docs/operations.md#take-a-server-out)).
  - DAB loads only the root and the listed files; other files in the folder (backups) are ignored ✅. **A listed file
    that is missing is skipped silently** ✅.
- **Auth:** the agent asks Entra for a token for `api://<appId>` with its managed identity; the platform renews it.
  DAB checks `aud` = `<appId>` and the v2 issuer, with signing keys it fetches from Entra over outbound 443. The header
  `X-MS-API-ROLE: MCP.Read` makes DAB act as that role; without it the agent sees no entities ✅. Towards SQL Server,
  DAB always connects as the gMSA.

> **⚠️ One unreachable SQL Server stops DAB at startup.** If any listed SQL Server cannot be reached when DAB starts,
> DAB does not start at all, healthy servers included, and it **does not recover by itself**: the task's restart
> setting never fires for this ✅. Recovery is manual by design: read `dab.log`, then take that server out or start the
> task once all servers are up ([docs/operations.md](docs/operations.md#dab-does-not-start)). A server that dies
> **while DAB runs** only fails its own entities, which recover on their own ✅. So group servers per DAB by failure
> domain and maintenance window, at most 25 per DAB (tested ✅).

## Requirements

| Area | Requirement | |
|---|---|---|
| **SRE Agent** | Egress mode **Azure VNet**, private DNS resolution on; "Remote MCP server access" **off** (`connect-agent` sets it) | ✅ |
| | Its **system-assigned managed identity** (a user-assigned one is documented, not tested) | ✅ / 📄 |
| **Entra** | An admin (Application Administrator or equivalent) runs `admin/entra-setup` once: 1 app, 1 app role, 1 service principal, 1 assignment. No Azure resource | ✅ |
| **Active Directory** | A domain; a Domain Admin for the gMSA (step 1) | ✅ |
| **SQL Server** | 2022 or later for `##MS_ServerPerformanceStateReader##`; 2016–2019 need `VIEW SERVER STATE` ([docs/operations.md](docs/operations.md#sql-server-versions)) | ✅ 2025 / 📄 others |
| **MCP host** | Windows Server, domain member, Windows PowerShell 5.1; outbound HTTPS to GitHub (DAB download) and to Entra (`login.microsoftonline.com`, signing keys; no offline mode). No inbound internet | ✅ |
| | Behind a proxy: `HTTPS_PROXY` / `NO_PROXY` in the scheduled task's environment | 📄 |
| **Network** | Agent subnet → MCP host TCP 5000; the host's name resolves from the agent subnet (the agent uses the VNet's DNS) | ✅ |
| | On-premises servers: VPN or ExpressRoute from the agent's VNet, on-premises DNS reachable, the firewall lets in the agent subnet. An on-premises host has no managed identity, which is fine: the token always comes from the agent | 📄 |
| **HTTPS** | Not needed (the connector accepts `http://` inside the VNet). With a domain-CA certificate, whether the agent trusts a private CA is untested | ✅ / 📄 |

## Install

The release package `SqlMcp.zip` ([v1.0.0](https://github.com/VezirOrg/sreagent-playbook/releases/tag/sql-mcp/v1.0.0); check its SHA-256 against the CHANGELOG) holds every script below (plus `README.txt`). Copy it to `C:\sqlmcp` on the machines
named in each step. Names in this guide: domain `CONTOSO` / `contoso.local`, MCP host `vm1`, SQL Servers `sql1`,
`sql2`; replace them with yours.

**1. gMSA (a domain controller, Domain Admin).**
```powershell
.\01-ad-prep.ps1 -McpHost vm1
```
Creates the KDS root key if the forest has none (usable by gMSAs after ~10 h: wait before step 3) and the gMSA
`gmsa-sqlmcp`, which only `vm1` may retrieve.

**2. SQL login (each SQL Server, as sysadmin).**
```powershell
sqlcmd -E -C -i C:\sqlmcp\02-sql-login.sql -v GmsaLogin="CONTOSO\gmsa-sqlmcp$"
```
A login and one server-role membership; no database, user or object. The output must show `is_sysadmin 0`.

**3. DAB (the MCP host, local admin).**
```powershell
.\03-dab-install.ps1 -From <agent-subnet-cidr>
```
Installs the gMSA on the host, grants it "Log on as a batch job", downloads DAB 2.1.5 (self-contained, no .NET
install) and **checks its SHA-256** before unpacking, registers the task `DAB-sqlmcp` (at startup, as the gMSA) and
the firewall rule (TCP 5000 from `-From` only). Add a second subnet to `-From` if you test from your servers.

**4. Entra (an Entra admin, from any machine with Azure CLI).**
```sh
admin/entra-setup.sh --agent /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.App/agents/<agent>
```
(PowerShell: `admin\entra-setup.ps1 -Agent …`.) Idempotent. It prints `APP_ID` and `TENANT_ID`. Run it **before** the
agent first asks for a token for the app: managed-identity tokens are cached up to ~24 h.

**5. Configuration (the MCP host, local admin), then start DAB.**
```powershell
.\04-dab-config.ps1 -Servers sql1,sql2 -Domain contoso.local -TenantId <TENANT_ID> -AppId <APP_ID>
Start-ScheduledTask DAB-sqlmcp; Start-Sleep 15
(Get-NetTCPConnection -LocalPort 5000 -State Listen).LocalAddress      # 0.0.0.0
```
Existing configuration files are first copied to `C:\dab\config\backup-<time>`. `allowed-hosts` defaults to the
host's name, FQDN and IPv4 addresses (`-AllowedHosts` to change it).

**6. Connect the agent (someone with SRE Agent Administrator on the agent).**
```sh
agent/connect-agent.sh --agent <agent-resource-id> --endpoint http://vm1.contoso.local:5000/mcp --app-id <APP_ID>
```
(PowerShell: `agent\connect-agent.ps1`.) It turns "Remote MCP server access" off (keeping the rest of the agent's
egress settings) and creates the connector `sqlmcp` with the agent's managed identity, the scope and the role header.
The portal equivalent: sre.azure.com → the agent → Builder → Connectors → Add → MCP server → Streamable-HTTP,
authentication **Managed identity**, scope `api://<APP_ID>/.default`, custom header `X-MS-API-ROLE` = `MCP.Read` 📄.

## Verify

1. Ask the agent: *"What is the top wait type on sql2?"* and *"How many user sessions are on sql1 right now?"*. The
   thread shows `sqlmcp` tool calls. Compare with sqlcmd right after (waits: the same types in the same order; values
   are cumulative. Sessions: sqlcmd counts itself) ✅.
2. On SQL Server, DAB's sessions are the gMSA over Kerberos and not sysadmin ✅:
   ```sql
   SELECT s.login_name, c.auth_scheme, IS_SRVROLEMEMBER('sysadmin', s.login_name) AS is_sysadmin
   FROM sys.dm_exec_sessions s JOIN sys.dm_exec_connections c ON c.session_id = s.session_id
   WHERE s.program_name LIKE 'sqlmcp-dab%';                 -- CONTOSO\gmsa-sqlmcp$  KERBEROS  0
   ```
3. Only the agent gets in ✅: on the MCP host, its own managed identity is refused a token for `api://<APP_ID>`
   (AADSTS501051), and any other token gets HTTP 401 from DAB.

## Operating it

[docs/operations.md](docs/operations.md): DAB does not start (how to see it, which server), take a server out and
put it back, what to alert on, troubleshooting, how many servers per DAB, SQL Server versions, upgrading DAB.

## Files

| Path | What |
|---|---|
| `package/01-ad-prep.ps1`, `02-sql-login.sql`, `03-dab-install.ps1`, `04-dab-config.ps1` | the install steps (Windows PowerShell 5.1) |
| `package/admin/entra-setup.{sh,ps1}` | the Entra admin step |
| `package/agent/connect-agent.{sh,ps1}` | the agent connector |
| `package/tools/mcp-call.ps1` | a minimal MCP client for checks (Windows PowerShell 5.1) |
| `package/build.sh` | builds `SqlMcp.zip` (deterministic) |
| `tests/` | local tests L01–L04 and the lab tests ([docs/tests.md](docs/tests.md)) |
| `CHANGELOG.md`, `decisions.md` | releases and the decision log |
