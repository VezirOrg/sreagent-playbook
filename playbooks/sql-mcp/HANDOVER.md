# sql-mcp: lab21 UP (phase A done 07:57Z); waiting for Emre's Entra admin step, then phase B and T10–T24.

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
    `lab-up.sh` (phase A, admin step, phase B with `--app-id`), `lab-down.sh`, lab tests `T10.sh`–`T25.sh` with the
    guest helpers `guest/dab-copy.ps1` (copy of the live config on localhost:5001) and `guest/host-state.ps1`.
    **None of the lab scripts has run yet.**
  - CI (R21) runs L01–L03, plus L01 under Windows PowerShell 5.1.
  - Docs: `README.md` (adopter guide, status "in development"), `docs/operations.md`, `docs/tests.md`.
- `pwsh` is not installed on this Mac. This session used PowerShell 7.6.7 unpacked into its scratchpad (SHA-256 checked
  against GitHub's digest). A later session: download it again, or set `PWSH`.
- `lab-up.sh` reads the private template from `SQLMCP_LAB_TEMPLATE` / `SQLMCP_LAB_TAG` (values in
  `files/private-refs.md`).

## Next

State (2026-10-17 07:57Z): **lab21 UP** (rg-lab21, ~32 $/day, registered in the template's lab register, its audit
CLEAN). Phase A done (azd up 27 min; gMSA; logins on sql1/sql2, not sysadmin; DAB 2.1.5 on vm1, task registered,
not started). **Waiting for the admin step** (Emre, device code on this Mac, started by the vezir into
`$HOME/.azure-sqlmcp-admin` (S15): after the vezir's "giriş tamam", run entra-setup.sh with that AZURE_CONFIG_DIR, then
`az logout` and `rm -rf` it). Then `lab-up.sh --app-id <APP_ID>` and T10–T24. The lab day
ends before 21:45Z. Logs: `.lab/sql-mcp/lab-up-A.log`, `azd-up-lab21.log`.
- azd's cached SP login was stale after the secret rotation (AADSTS7000215); the repo's `.azd-config` now uses az's
  login (`azd config set auth.useAzCliAuth true`; undo with `azd config unset auth.useAzCliAuth`; S15). Nothing is half done; the tree is clean except perfmon-blackbox's untracked
`package/files/` (not ours, left alone on the vezir's word).


1. When the vezir clears lab21: register it in the template's lab register, then `lab-up.sh` (T10), the admin step
   by Emre (S4), phase B, T11–T24.
2. Fix what the lab finds; mark ✅ from lab21 in the README; then `docs/design.md` (auth evidence, from the source design
   note). The vezir agreed (2026-10-17): design.md and the quick install wait for the lab, so they carry lab21 results.
3. The TR/EN quick install (Drive, S9), rc, fresh-eyes install (S8), teardown (T25), release.

## Not yet done or verified

- Untested until lab21: whether the lab SP may PUT the connector (else it needs SRE Agent Administrator on the
  lab21 agent only, perfmon-blackbox P30 pattern: ask first); the agent-subnet lookup in `common.sh`; sqlcmd as the
  lab's member admin being sysadmin on the SQL members (it was in the source lab).
