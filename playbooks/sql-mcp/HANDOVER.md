# sql-mcp: v1.0.0 RELEASED 2026-10-17 (SqlMcp.zip F3B2BD2A…09DB); next: fresh-eyes install (S8) in a new session.

Playbook: **sql-mcp**. Read `../../CLAUDE.md`, `CLAUDE.md` here, this file, then `decisions.md` (S1–S19).
The owner is the vezir (its session name changes when it respawns: always re-check with ListAgents); every answer
from Emre comes through it. **Rig rule:** never keep a Bash background task of this session running longer than ~4 min
(the keepalive may judge the session dead): run long jobs (`lab-up.sh`, lab tests) with `nohup … & disown` and a log
file in `.lab/sql-mcp/`, and watch the log with a Monitor.

## Where it stands (closed 2026-10-17 ~10:05Z, session 1)

- **Released:** tag `sql-mcp/v1.0.0` on `62f2db3`,
  https://github.com/VezirOrg/sreagent-playbook/releases/tag/sql-mcp/v1.0.0, only asset `SqlMcp.zip`, SHA-256
  `F3B2BD2AFF1F787363C880D7D16A88101B24035E60F249347013032480F909DB` (verified from the public URL). **Not "Latest"**
  (root R22: "Latest" stays where it is; each playbook is found by its own tag).
- **What it is** (S1): a read-only MCP server for SQL Server DMVs on Data API builder 2.1.5 (pinned), run as a gMSA on a
  Windows member server; the SRE Agent calls it over the VNet with its managed identity, locked by the Entra app
  `sql-mcp-api` with the app role `MCP.Read`. Nothing on the SQL Servers but a login.
- **Tested end to end** on lab21 (S14, S17, S18): T10–T25 all PASS, local L01–L04 PASS, CI green. lab21 was built
  (Lab build 27 min, Admin consent by Emre, MCP connect), tested and **torn down** (09:46:40Z; register row DOWN,
  template audit CLEAN). No lab is up.
- **Docs:** `README.md` (adopter guide), `docs/design.md` (design and evidence), `docs/operations.md`, `docs/tests.md`,
  `CHANGELOG.md`. **Drive:** `files/sql-mcp/plan-v1.md` (approved plan), `quick-install-v1.0.0.tr.md` and `.en.md`
  (point at the tag).
- **Lab tooling:** `tests/lab/lab-up.sh`: **Lab build** (README steps 1–3) → **Admin consent** (step 4, an admin
  runs `package/admin/entra-setup.sh`) → **MCP connect** (`--connect --app-id <id>`, steps 5–6) (S16).
  `lab-down.sh --yes`, tests `tests/run.sh T10 … T25`. The private template comes from `SQLMCP_LAB_TEMPLATE` /
  `SQLMCP_LAB_TAG` (values in `files/private-refs.md`).
- **Kept on purpose:** the Entra app `sql-mcp-api` (tenant object, no cost; S18). Its role assignment went with the
  lab21 agent. Removal, if ever: an admin runs `entra-setup.sh --app-name sql-mcp-api --remove`.
- The earlier research lab and its hand-made Entra app were removed by the vezir on 2026-10-17 (register `78cf4ac`,
  `9bfe699`).

## Next

1. **Fresh-eyes install (S8)**, later (tomorrow or a weekday), in a **new session** opened as
   `pj-open sreagent-playbook PLAYBOOK=sql-mcp`:
   - a separate session installs from the README of the v1.0.0 tag only;
   - on a lab rebuilt with `lab-up.sh` Lab build (~30 min) + Admin consent (Emre's device-code login, via the vezir,
     into `$HOME/.azure-sqlmcp-admin`, outside any repo; S15);
   - register the lab first; tear it down after (T25); the lab day ends before 21:45Z;
   - findings go into v1.0.x. Needs the vezir's go.
2. Later: the agent skill (v1.1.0, S13); the user-assigned identity path (S5).

## Not yet done or verified

- Untested by design (README says so): SQL Server < 2022, on-premises hosts, HTTPS, a proxy, a user-assigned identity.
- The portal path for the connector (only the ARM path was run).
- `pwsh` is not installed on this Mac; L01/L02 used PowerShell 7.6.7 unpacked in the session scratchpad (SHA-256
  checked). A later session: download it again, or set `PWSH`.
