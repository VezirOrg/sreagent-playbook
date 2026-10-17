# sql-mcp: plan v1 approved (S3–S13); package scripts, lab-up/down and local tests L01–L04 green; lab21 NOT cleared yet.

Playbook: **sql-mcp**. Read `../../CLAUDE.md`, `CLAUDE.md` here, this file, then `decisions.md` (S1–S13).
The owner is the vezir; every answer from Emre comes through it.

## Where it stands (2026-10-17, session 1)

- **Plan v1** (`files/sql-mcp/plan-v1.md`, Drive, Turkish) is **approved** (S3–S10, S13). The agent skill is v1.1.0 (S13).
- **lab21 is approved but NOT cleared** (S3): no lab build and no Azure call until the vezir says so (the lab SP secret
  was being rotated on 2026-10-17).
- **Repo-side work done (S12):**
  - `package/`: `01-ad-prep.ps1`, `02-sql-login.sql`, `03-dab-install.ps1` (DAB 2.1.5 pinned with its SHA-256),
    `04-dab-config.ps1` (placeholder root, production auth only), `tools/mcp-call.ps1` (+ `-Role`),
    `admin/entra-setup.{sh,ps1}`, `agent/connect-agent.{sh,ps1}`, `build.sh` (deterministic `SqlMcp.zip`).
  - `tests/run.sh` with L01–L04 (all PASS on 2026-10-17; L01/L02 need `pwsh`, see below), `tests/lab/common.sh`,
    `lab-up.sh` (phase A, admin step, phase B with `--app-id`), `lab-down.sh`. **None of the lab scripts has run yet.**
- `pwsh` is not installed on this Mac. This session used PowerShell 7.6.7 unpacked into its scratchpad (SHA-256 checked
  against GitHub's digest). A later session: download it again, or set `PWSH`.
- `lab-up.sh` reads the private template from `SQLMCP_LAB_TEMPLATE` / `SQLMCP_LAB_TAG` (values in
  `files/private-refs.md`).

## Next

1. Root change R21 (CI runs the sql-mcp local tests), its own commit.
2. Lab tests T10–T25 as `tests/lab/T*.sh`, and `docs/tests.md`.
3. When the vezir clears lab21: register it in the template's lab register, then `lab-up.sh` (T10), the admin step
   by Emre (S4), phase B, T11–T24.
4. Then the README guide, the TR/EN quick install (Drive), rc, fresh-eyes install (S8), teardown (T25), release.

## Not yet done or verified

- Untested until lab21: whether the lab SP may PUT the connector (else it needs SRE Agent Administrator on the
  lab21 agent only, perfmon-blackbox P30 pattern: ask first); the agent-subnet lookup in `common.sh`; sqlcmd as the
  lab's member admin being sysadmin on the SQL members (it was in the source lab).
