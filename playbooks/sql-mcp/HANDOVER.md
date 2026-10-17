# sql-mcp: lab21 UP, T10–T24 all PASS (2026-10-17); next: design.md, quick install TR/EN, README ✅ from lab21, rc.

Playbook: **sql-mcp**. Read `../../CLAUDE.md`, `CLAUDE.md` here, this file, then `decisions.md` (S1–S17).
The owner is the vezir (its session name changes when it respawns: always re-check with ListAgents); every answer
from Emre comes through it. **Rig rule:** never keep a Bash background task of this session running longer than ~4 min
(the keepalive may judge the session dead): run long jobs (`lab-up.sh`, lab tests) with `nohup … & disown` and a log
file in `.lab/sql-mcp/`, and watch the log with a Monitor.

## Where it stands (2026-10-17 ~09:45Z, session 1)

- **Plan v1 approved** (`files/sql-mcp/plan-v1.md`, Drive; S3–S10, S13: the agent skill is v1.1.0).
- **Repo side:** `package/` (install steps 1–3 and 5 as Windows PowerShell 5.1 scripts, `admin/entra-setup`,
  `agent/connect-agent`, `tools/mcp-call.ps1`, `build.sh`); `tests/` (local L01–L04 PASS, CI R21 green; lab
  `lab-up.sh`, `lab-down.sh`, `T10.sh`–`T25.sh`, guest helpers); `README.md` (adopter guide, status "in development"),
  `docs/operations.md`, `docs/tests.md` (results).
- **lab21 is UP** (rg-lab21, ~32 $/day, registered in the private template's lab register, its audit CLEAN). Built
  07:30–07:57Z (azd up 27 min), Admin consent by Emre (device code, the admin login folder `$HOME/.azure-sqlmcp-admin`
  was logged out and deleted), MCP connect 09:05Z. **The lab day must end before 21:45Z** (nightly stop).
- **T10–T24: all 15 PASS** (S17). Four passed after test-side fixes; one product fix (`connect-agent` waits for the
  agent to be `Succeeded` around the egress PATCH). The lab SP needed **no** extra role.
- **S16 done:** `lab-up.sh` phases are **Lab build** (README steps 1–3) → **Admin consent** (step 4) → **MCP connect**
  (`--connect --app-id <id>`, steps 5–6; `--app-id` alone still works).
- azd signs in through az (S15; undo `azd config unset auth.useAzCliAuth`).
- Lab files (gitignored): `.lab/sql-mcp/` (`lab-up-A.log`, `lab-up-B.log`, `entra-setup*.log` with the app ID,
  `sqlmcp-lab21.appid`, `tests-run1.log`, `tests-run2.log`, `evidence/`).

## Next

1. Ask the vezir: tear lab21 down today (T25, `lab-down.sh --yes`, then the template's audit and register in one
   commit), or keep it for the fresh-eyes install (S8)?
2. `docs/design.md` (auth evidence from the source design note, with the lab21 results), README ✅ marks from lab21,
   the TR/EN quick install in Drive (S9), `v1.0.0-rc.1`.
3. Fresh-eyes install (S8), teardown (T25), release.

## Not yet done or verified

- T25 (teardown) has not run. The Entra app `sql-mcp-api` stays after a teardown (reusable); an admin removes it with
  `entra-setup.sh --remove`.
- Untested by design (README says so): SQL Server < 2022, on-premises hosts, HTTPS, a proxy, a user-assigned identity
  (S5, after v1.0.0).
- `pwsh` is not installed on this Mac; L01/L02 used PowerShell 7.6.7 unpacked in the session scratchpad (SHA-256
  checked). A later session: download it again, or set `PWSH`.
