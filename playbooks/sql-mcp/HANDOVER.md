# sql-mcp: tested end to end (lab21, T10–T25 all PASS, lab torn down 2026-10-17); docs and TR/EN quick install done; v1.0.0 waits for Emre's preview.

Playbook: **sql-mcp**. Read `../../CLAUDE.md`, `CLAUDE.md` here, this file, then `decisions.md` (S1–S17).
The owner is the vezir (its session name changes when it respawns: always re-check with ListAgents); every answer
from Emre comes through it. **Rig rule:** never keep a Bash background task of this session running longer than ~4 min
(the keepalive may judge the session dead): run long jobs (`lab-up.sh`, lab tests) with `nohup … & disown` and a log
file in `.lab/sql-mcp/`, and watch the log with a Monitor.

## Where it stands (2026-10-17 ~10:10Z, session 1)

- **Plan v1 approved** (`files/sql-mcp/plan-v1.md`, Drive; S3–S10, S13: the agent skill is v1.1.0).
- **Repo side:** `package/` (install steps as Windows PowerShell 5.1 scripts, `admin/entra-setup`,
  `agent/connect-agent`, `tools/mcp-call.ps1`, `build.sh`); `tests/` (local L01–L04 PASS, CI R21 green; lab
  `lab-up.sh` with the phases Lab build / Admin consent / MCP connect (S16), `lab-down.sh`, `T10.sh`–`T25.sh`);
  `README.md` (adopter guide; status "tested end to end, not released yet"), `docs/design.md`, `docs/operations.md`,
  `docs/tests.md` (all results).
- **lab21: built, tested, torn down** (S14, S17, S18). T10–T25 all PASS; one product fix (`connect-agent` waits for
  the agent around the egress PATCH); the lab SP needed no extra role. Torn down 09:46:40Z, lab audit CLEAN, register
  row DOWN (template `98219be`, `bb04a59`). The Entra app `sql-mcp-api` is kept (S18).
- The earlier research lab rg-sqlmcp1 was torn down by the vezir (09:40Z, Emre's word); its register row DOWN
  (`78cf4ac`); its hand-made Entra app deleted.
- **Drive:** `files/sql-mcp/plan-v1.md`, `quick-install-v1.0.0.tr.md`, `quick-install-v1.0.0.en.md` (drafts, before rc).
- azd signs in through az (S15; undo `azd config unset auth.useAzCliAuth`).

## Next

1. **STOP before any release or tag:** the vezir asked Emre whether he wants to preview v1.0.0 first.
2. Then: `CHANGELOG.md` entry, `v1.0.0-rc.1` (build `SqlMcp.zip`, SHA-256), the fresh-eyes install (S8) on a lab
   rebuilt with `lab-up.sh` (~30 min plus Admin consent), release `sql-mcp/v1.0.0` (the vezir publishes), the quick
   install renamed from draft.

## Not yet done or verified

- The Entra app `sql-mcp-api` stays after a teardown (reusable); an admin removes it with
  `entra-setup.sh --remove`.
- Untested by design (README says so): SQL Server < 2022, on-premises hosts, HTTPS, a proxy, a user-assigned identity
  (S5, after v1.0.0).
- `pwsh` is not installed on this Mac; L01/L02 used PowerShell 7.6.7 unpacked in the session scratchpad (SHA-256
  checked). A later session: download it again, or set `PWSH`.
