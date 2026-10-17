# Changelog: sql-mcp

Tags: `sql-mcp/vX.Y.Z`. The package zip of each release is a GitHub Release asset.

## sql-mcp/v1.0.0 (2026-10-17)

First release. Asset `SqlMcp.zip`, SHA-256 `F3B2BD2AFF1F787363C880D7D16A88101B24035E60F249347013032480F909DB`.

- A read-only MCP server for SQL Server DMVs on Data API builder **2.1.5** (pinned with the SHA-256 of its zip): seven
  DMV views per SQL Server, all columns described; `describe_entities`, `read_records`, `aggregate_records` only.
- **Nothing on the SQL Servers** but a login for a gMSA with `##MS_ServerPerformanceStateReader##`.
- **Only the SRE Agent gets in:** its managed identity, an Entra app with the app role `MCP.Read` and assignment
  required, the role header on the connector. No secret anywhere; plain HTTP inside the VNet.
- Install steps 1–6 as scripts: `01-ad-prep.ps1`, `02-sql-login.sql`, `03-dab-install.ps1`,
  `admin/entra-setup.{sh,ps1}` (the Entra admin step), `04-dab-config.ps1` (placeholder root, one file per server),
  `agent/connect-agent.{sh,ps1}`; `tools/mcp-call.ps1` for checks. Server-side scripts are Windows PowerShell 5.1.
- **Tested end to end** on 2026-10-17 in a lab built from scratch (Azure VMs in the agent's VNet, SQL Server 2025,
  Windows Server 2025): T10–T25 all pass ([docs/tests.md](docs/tests.md)).
- Known limits: DMV functions and server configuration are not exposed; one unreachable SQL Server at startup stops
  DAB (manual recovery, [docs/operations.md](docs/operations.md)); SQL Server before 2022, on-premises hosts, HTTPS and
  a proxy are documented, not tested; the agent skill comes in v1.1.0.
