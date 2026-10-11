# perfmon-blackbox: test plan (for Emre's approval, PLAN GATE)

Status: **DRAFT for approval**, 2026-10-11. Implements P5 (success criterion: **the latest zip can be analysed**;
a test for every stage, end to end, the last one being the analysis). Design: `design.md`.

## How tests run

- **One command per test**, from the repo root, in the lab:
  `direnv exec . playbooks/perfmon-blackbox/tests/run.sh <ID> [machine]` → prints `PASS`/`FAIL <ID>` with its
  evidence lines (numbers, times, paths; never a secret, never a real name) and exits 0/1.
  `run.sh all` runs the stages in order and stops at the first FAIL; `run.sh all --keep-going` runs them all.
- `[machine]` is `vm1` (Azure VM path) or `arc1` (Arc path). Every machine-level test runs **on both**.
- In-guest checks go through **Run Command**: `az vm run-command` for `vm1`, Arc Run Command
  (`az connectedmachine run-command`) for `arc1` (its Azure guest agent is disabled on purpose). No RDP needed.
- Evidence of each full run is saved under `files/test-runs/<date>-<lab>/` (Drive, never committed) and summarised
  in the playbook HANDOVER.
- **Local tests** (`L..`) need no Azure and run in CI on **synthetic data only** (`tests/fixtures/synthetic/`).

## Stage tests (lab)

| ID | P5 item | Stage | Pass when | Machines |
|---|---|---|---|---|
| T01 | 1 | Package builds | `package/build.ps1` makes `PerfmonBlackbox_<ver>.zip`; `Get-GuestConfigurationPackageComplianceStatus` on a clean Windows box = **NonCompliant** before, `Start-GuestConfigurationPackageRemediation` then status = **Compliant** (all 5 resources) | CI Windows runner (`windows-latest`) or the lab's `vm1` before policy; zip SHA-256 printed |
| T02 | 2 | Policy definitions | `perfmon-blackbox-vm` and `perfmon-blackbox-arc` exist; each targets only its resource type; `contentUri` = expected release URL; `contentHash` = SHA-256 of the T01 zip; version matches | subscription |
| T03 | 2 | Policy assignments | one assignment of each definition on the lab RG, system identity present, its roles exactly as designed (Guest Configuration Resource Contributor; RBAC admin on the storage account with the delegation condition if CHOICE 4 = policy); `arc1`'s Compute VM is in the VM assignment's `notScopes`; VM prerequisites initiative assigned | RG |
| T04 | 3 | Guest assignment Compliant | `Microsoft.GuestConfiguration/guestConfigurationAssignments/PerfmonBlackbox` on the machine has `complianceStatus = Compliant`, `lastComplianceStatusChecked` < 30 min old, all 5 resources compliant | vm1, arc1 |
| T05 | 4 | Extension and identity | vm1: extension `AzurePolicyforWindows` provisioning Succeeded, system-assigned identity present. arc1: machine status Connected, agent version ≥ 1.10, system identity present, **IMDS blocked** (169.254.169.254 unreachable), so its tokens come from HIMDS | vm1, arc1 |
| T06 | 5 | Collector running | `logman query PerfmonBlackbox`: status **Running**; its counter list **equals** the template file (same file the package ships); sample interval = parameter; the current `.blg` **grows** (size at t0 < size at t0+2×interval+10 s) | vm1, arc1 |
| T07 | 6 | Every scheduled task | `\PerfmonBlackbox\Boot`: trigger AtStartup, principal SYSTEM, run level Highest, action `logman start PerfmonBlackbox`. `\PerfmonBlackbox\Export`: trigger Daily at the parameter time, principal SYSTEM, `StartWhenAvailable`. Each one **run on demand** by the test, then `LastTaskResult = 0` and `LastRunTime` after the test start. No other task under `\PerfmonBlackbox\` | vm1, arc1 |
| T08 | 7 | Reboot | restart the machine; within 3 min of boot the collector is **Running**, the Boot task's `LastRunTime` > boot time with result 0, and a **new** `.blg` grows | vm1, arc1 |
| T09 | 8 | Daily export: CSV and zip | after a forced export: the zip holds exactly one CSV + `manifest.json`; CSV first cell starts with `(PDH-CSV 4.0)`; rows ≥ expected for the covered span (span / interval × 0.95); first/last timestamps match the manifest and cover the closed `.blg`; every template counter present on the machine is a column; manifest SHA-256 = CSV SHA-256 | vm1, arc1 |
| T10 | 8 | Roll gap (CHOICE 2) | the time between the last sample of the closed file and the first sample of the new one ≤ 2 × interval + 10 s | vm1, arc1 |
| T11 | 9 | Blob landed | blob at `perfmon/<machine-prefix>/<yyyy>/<mm>/<dd>/<name>.zip` exists; its `Content-MD5` and `sha256` metadata = local zip; uploaded **with the machine identity** (storage log / the script's log: token source IMDS on vm1, **HIMDS on arc1**) | vm1, arc1 |
| T12 | 10 | Cannot write elsewhere | from the machine, with its own token: PUT into **another** machine's prefix → **403**; PUT outside `perfmon/` → 403; GET/LIST of any blob (own included) → 403; PUT into its own prefix → 201 (control) | vm1, arc1 |
| T13 | 11 | Lifecycle rule | management policy has the rule: prefix `perfmon/`, delete after `RetentionDays`; enabled | storage |
| T14 | DoD 3 | Storage private | `allowBlobPublicAccess=false`, `allowSharedKeyAccess=false`, TLS ≥ 1.2, network as CHOICE 5 (public access disabled + private endpoint approved), container access private; an anonymous GET → fails; a shared-key request → fails | storage |
| T15 | 12 | Skill fetch + convert | `perfmon_fetch_latest.py` on the agent side (and locally with the lab reader identity): with ≥ 2 dated zips of the machine present, it picks the **newest**, downloads, checks the manifest hash, unzips, and the converter gives `unparsed_paths=0`, `bad_cells=0`, `short_rows=0`, rows = manifest rows | vm1, arc1 |
| T16 | 13 | Agent report, **scored** | the SRE Agent, asked in a new thread "analyse the latest PerfMon capture of <machine>", fetches the latest zip itself and posts its report in the thread; the report is scored against `tests/scoring/rubric.md` (below); pass = score ≥ threshold **and** the report names the latest zip it used | vm1, arc1 |

### T16 scoring (ground truth from planted problems)

`tests/lab/make-trouble.ps1` (synthetic, no real names) runs on the machine during the captured day and plants:
a process whose Private Bytes grow with a synthetic request rate (leak tied to load), a CPU-bound burst
≥ 10 minutes, a disk-latency episode ≥ 5 minutes, and quiet periods. Its own log is the ground truth (times,
process, sizes). The rubric gives points for: right capture identified (latest zip, host, time range); each
planted problem found with its time ± 2 samples and its driver; correct verdict words under the VERDICT CEILING;
no invented problem; rules of SKILL.md followed (no raw data, `LINK:` lines for causal claims). The scorer
(`tests/scoring/score.py`) is deterministic: it checks the report text against the ground truth with fixed rules
and prints the points per item. Threshold proposed: **80 %**, every planted problem found. The rubric does not
take a side on OPEN-1/OPEN-2 (P8).

## Local tests (no Azure; CI)

| ID | What | Pass when |
|---|---|---|
| L01 | Converter on a synthetic PDH-CSV (`tests/fixtures/synthetic/`, made by `tests/synth/make_capture.py`) | meta counts as expected; day-first and month-first files read right; two-part capture with overlap merged |
| L02 | perfq helpers on the synthetic DB | `triage()` finds the planted breaches and prints the right VERDICT CEILING |
| L03 | Masker (lab-side tool) | a synthetic mapping masks a synthetic CSV; a planted denylist entry makes it exit 1 without printing the name |
| L04 | `perfmon_fetch_latest.py` selection logic | on synthetic blob listings it picks the newest zip, ignores other prefixes, rejects a zip whose manifest hash does not match |
| L05 | Export script logic (Pester, Windows runner) | CSV validation rejects a bad header, an empty file and a missing counter; blob path built right from a sample resource ID |
| L06 | Repo safety | `scripts/scrub-check.sh --self-test` passes; scrub check on the tree is clean |

## End-to-end order on a fresh lab (DoD centre)

build lab → `infra/` deploy → T13, T14 → T01 → publish package (release asset of a pre-release tag) → T02, T03 →
wait for compliance → T04, T05, T06, T07 → `make-trouble.ps1` during a captured window → T08 → forced export →
T09, T10, T11, T12 → second export (so "latest" is a real choice) → T15 → T16. All green on **both** `vm1` and
`arc1` = DoD centre met. Then README-only fresh-eyes deploy into a second clean lab, which must reach the same green
(DoD 2).

## What is not tested in v1

The Azure Monitor alert trigger (phase 2, P4) and posting to a GitHub issue (later, P3).
