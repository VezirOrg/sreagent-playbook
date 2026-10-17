# sql-mcp: tests

One command per test: `tests/run.sh <ID>` from the playbook folder. Lab tests run from the repo root through direnv:
`direnv exec . playbooks/sql-mcp/tests/run.sh T14`. Synthetic values only; lab evidence (masked) goes to the gitignored
lab folder, never into the repo.

Lab tests never edit the live DAB configuration and never stop a SQL Server: the checks that need a changed
configuration (T14, T21, T22, T24) run on a **copy** on `localhost:5001` with anonymous read added to the copy only
(`tests/lab/guest/dab-copy.ps1`), which is deleted afterwards.

## Local (no Azure)

| ID | What | Last result |
|---|---|---|
| L01 | `04-dab-config.ps1`: placeholder root, one file per server, 7 views, only the app role reads, v2 issuer, backup on rerun, comma lists under `-File`, `-AppId` required (PowerShell 7 and, in CI, Windows PowerShell 5.1) | PASS 2026-10-17 |
| L02 | Windows PowerShell 5.1 compatibility of every `.ps1` in `package/` and `tests/lab/guest/` (Server 2016/2019 profiles) | PASS 2026-10-17 |
| L03 | `build.sh` deterministic, exactly the package files, no GUID or private IPv4 | PASS 2026-10-17 |
| L04 | pinned DAB = latest stable; pinned SHA-256 = GitHub's digest (local only) | PASS 2026-10-17 (2.1.5) |

## Lab (lab21, pending)

| ID | What | Hand step | Last result |
|---|---|---|---|
| T10 | `lab-up.sh` builds the lab (phase A, admin step, phase B): VMs run, agent egress AzureVNet with remote MCP access off, connector exists, DAB listens | the admin runs `entra-setup.sh` | — |
| T11 | steps 1–4 rerun change nothing (gMSA, login + role, no new download, same configuration content, task runs) | | — |
| T12 | on each SQL Server: the gMSA has exactly `##MS_ServerPerformanceStateReader##`, is not sysadmin, owns no database, has no user in any database | | — |
| T13 | DAB runs as the gMSA (task and process), pinned version, listens on 5000; firewall exactly the agent and VM subnets | | — |
| T14 | the live configuration (copy) has 7 entities per server with all columns and the key columns described; each server answers a read | | — |
| T15 | connector on the system identity; `connect-agent.sh` rerun succeeds | the admin reruns `entra-setup.sh`: "already assigned" | — |
| T16 | V4: the agent's token for the app has `aud` = app ID, `ver` 2.0, `roles` [MCP.Read] (claims only, read in the agent's sandbox) | | — |
| T17 | V5: vm1's managed identity is refused a token (AADSTS501051); an ARM token gets 401 | | — |
| T18 | V3: without the role header the agent sees no entities; with it back, 14 | | — |
| T19 | the agent's top wait on sql2 = sqlcmd's; user sessions on sql1 printed next to sqlcmd's | | — |
| T20 | the calls come from the agent subnet (WFP audit on for the test only, then off) | | — |
| T21 | a server's file renamed to `.off`: DAB starts without it, 7 entities, the other server reads (copy) | | — |
| T22 | an unreachable server at start: DAB does not start, the log names it (copy; no SQL Server stopped) | | — |
| T23 | vm1 restarts: DAB comes back as the gMSA by itself | | — |
| T24 | the placeholder root starts with the pinned build (root 0 entities, 7 per server); `T24.sh <version> <sha256>` for an upgrade | | — |
| T25 | after `lab-down.sh`: no resource group, no role assignment scoped in it; then the template's lab audit | | — |

T16, T18, T19 and T20 ask the agent (about 2 minutes and a few AAU each).
