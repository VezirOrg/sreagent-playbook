# sql-mcp: v1.0.0 RELEASED 2026-10-17 (SqlMcp.zip F3B2BD2A…09DB, not Latest); next: fresh-eyes install (S8), then v1.0.x / v1.1.0 skill.

Playbook: **sql-mcp**. Read `../../CLAUDE.md`, `CLAUDE.md` here, this file, then `decisions.md` (S1–S19).
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
- **Drive:** `files/sql-mcp/plan-v1.md`, `quick-install-v1.0.0.tr.md`, `quick-install-v1.0.0.en.md` (point at the v1.0.0 tag).
- azd signs in through az (S15; undo `azd config unset auth.useAzCliAuth`).

## Next

1. **Released:** `sql-mcp/v1.0.0` (S19): https://github.com/VezirOrg/sreagent-playbook/releases/tag/sql-mcp/v1.0.0,
   `SqlMcp.zip` SHA-256 `F3B2BD2AFF1F787363C880D7D16A88101B24035E60F249347013032480F909DB`, tag on `62f2db3`, not Latest.
   Quick installs (Drive): `files/sql-mcp/quick-install-v1.0.0.tr.md`, `.en.md`.
2. Fresh-eyes install (S8), after the release as for perfmon-blackbox: a separate session, README only, on a lab
   rebuilt with `lab-up.sh` (Lab build ~30 min, Admin consent by Emre, MCP connect). Needs the vezir's go (cost,
   Emre's admin login). Findings go into v1.0.x.
3. Later: the agent skill (v1.1.0, S13), the user-assigned identity path (S5), a repo-wide rule for which playbook's
   release is "Latest" (root decision, Emre's call).

## Not yet done or verified

- The Entra app `sql-mcp-api` stays after a teardown (reusable); an admin removes it with
  `entra-setup.sh --remove`.
- Untested by design (README says so): SQL Server < 2022, on-premises hosts, HTTPS, a proxy, a user-assigned identity
  (S5, after v1.0.0).
- `pwsh` is not installed on this Mac; L01/L02 used PowerShell 7.6.7 unpacked in the session scratchpad (SHA-256
  checked). A later session: download it again, or set `PWSH`.
