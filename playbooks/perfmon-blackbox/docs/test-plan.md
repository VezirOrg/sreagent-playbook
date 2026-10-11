# perfmon-blackbox: test plan (for Emre's approval, PLAN GATE)

Status: **DRAFT rev 2 for approval**, 2026-10-11 (rev 2: Emre's 36 counters, circular file, `MaxSizeMB`,
export window; new tests T06b, T06c, T07b, T10b, T10c; P17: T06d, T06e; P18: T06f). Implements P5 (success criterion: **the latest zip can be analysed**;
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
| T02 | 2 | Policy definitions | `perfmon-blackbox-vm` and `perfmon-blackbox-arc` exist; each targets only its resource type; `contentUri` = expected release URL; `contentHash` = SHA-256 of the T01 zip; version matches; **both** expose the same parameters (`MaxSizeMB` default 512, `SampleIntervalSeconds`, `ExportEveryHours`, `StorageAccountName`, `ContainerName`, `LocalKeepMB`) mapped to the package's configuration parameters | subscription |
| T03 | 2 | Policy assignments | one assignment of each definition on the lab RG, system identity present, its roles exactly as designed (Guest Configuration Resource Contributor; RBAC admin on the storage account with the delegation condition if CHOICE 4 = policy); `arc1`'s Compute VM is in the VM assignment's `notScopes`; VM prerequisites initiative assigned | RG |
| T04 | 3 | Guest assignment Compliant | `Microsoft.GuestConfiguration/guestConfigurationAssignments/PerfmonBlackbox` on the machine has `complianceStatus = Compliant`, `lastComplianceStatusChecked` < 30 min old, all 5 resources compliant | vm1, arc1 |
| T05 | 4 | Extension and identity | vm1: extension `AzurePolicyforWindows` provisioning Succeeded, system-assigned identity present. arc1: machine status Connected, agent version ≥ 1.10, system identity present, **IMDS blocked** (169.254.169.254 unreachable), so its tokens come from HIMDS | vm1, arc1 |
| T06 | 5 | Collector running | `logman query PerfmonBlackbox`: status **Running**; its counter list **equals** 36 + G1 + G2 (+ G3 where its objects exist) from the files in `package/collector/` (P20); format **binary circular**; interval = parameter; max size = `MaxSizeMB`; no duration limit; the `.blg` **grows** until it reaches the maximum | vm1, arc1 |
| T06b | P14 | **Never exceeds, really wraps** | with `MaxSizeMB=16`, run until the file has been full for ≥ 10 min: the file size is **≤ 16 MB at every check** (polled every 30 s, max printed); relog of the file shows the **oldest sample time moving forward** between two checks (oldest samples gone) while the **newest sample is ≤ 2 × interval old** (newest present) | vm1, arc1 |
| T06c | P14 | **Changed parameter reaches the machine** | change `MaxSizeMB` 16 → 32 on the policy assignment (and remediate): within 30 min the guest assignment reports the new value, the collector's max size = 32, the file then grows past 16 MB and stays ≤ 32 MB, and **no samples were lost** across the re-create (the old buffer was kept as pending and the next export has no `collector_restart` gap longer than the re-create itself) | vm1, arc1 |
| T06d | P17 | **Changed interval reaches the machine** | change `SampleIntervalSeconds` on the assignment (e.g. 15 → 1): within 30 min the guest assignment reports the new value, `logman query` shows it, and the **timestamps in the `.blg`** (relog of the last minutes) step by the new interval (median step = new interval ± 10 %); the switch-over is a `collector_restart` gap no longer than the re-create in the next manifest | vm1 |
| T06e | P17 | **Capacity misfit is reported** | set `MaxSizeMB` so small that the measured buffer is < 1.5 × the export window (e.g. 16 MB at 1 s with a fixed 24 h export): the guest assignment turns **NonCompliant**, resource R6, and its **reason** names the measured buffer hours, the interval, `MaxSizeMB` and the export window; back to a fitting value → Compliant | vm1 |
| T06f | P18 | **No event-log storm from G3 without IIS; auto-detect** | (1) on a machine without IIS/ASP.NET, G3 forced in, 1 s, ≥ 30 min: new events per log (Application, System, Diagnosis-PLA/Operational) and per ID, at start and per minute, vs. a 10-min baseline; the collector starts and records every other counter. Pass = no per-sample or per-minute event growth attributable to the set. (2) auto-detect: on the same machine G3 is **not** configured; after installing IIS + ASP.NET, within 30 min G3 is configured and recorded, with no sample lost | vm1 (no IIS); a web box |
| T07 | 6 | Every scheduled task | `\PerfmonBlackbox\Boot`: trigger AtStartup, principal SYSTEM, run level Highest, action `Start-PerfmonBlackbox.ps1`. `\PerfmonBlackbox\Export`: Daily trigger repeating every `ExportEveryHours`, principal SYSTEM, `StartWhenAvailable`. Each one **run on demand** by the test, then `LastTaskResult = 0` and `LastRunTime` after the test start. No other task under `\PerfmonBlackbox\` | vm1, arc1 |
| T07b | P15 | **Buffer hours measured** | with `MaxSizeMB=512` and the chosen interval, after the file is full: bytes per sample = file size / samples in it; **hours held** = oldest-to-newest span; printed per machine with the process count. Pass = the measured hours ≥ 1.5 × `ExportEveryHours`; the value goes into the README | vm1, arc1 (and once at 1 s and once at 15 s on vm1, for the README table) |
| T08 | 7 | Reboot | restart the machine; within 3 min of boot the collector is **Running**, the Boot task's `LastRunTime` > boot time with result 0, the pre-reboot buffer is in `pending\`, and the next export contains the samples from before the reboot (only a `machine_off` gap for the downtime) | vm1, arc1 |
| T09 | 8 | Export: CSV and zip, **no gap, no overlap** | run the export **twice** with load in between: each zip holds one CSV + `manifest.json`; PDH header; the 36 counters present; rows = (window span / interval) ± 1 % when `complete: true`; manifest SHA-256 = CSV SHA-256; export 2's first sample is **exactly one interval after** export 1's last sample (no gap) and no timestamp appears in both (no overlap) | vm1, arc1 |
| T10 | 8 | Live snapshot | the export reads the circular file **while the collector runs**: the collector stays Running through the export and the CSV's last sample is ≤ 2 × interval before the snapshot time; if the snapshot method had to fall back to stop/move/start, the gap it causes is ≤ 10 s and is in the manifest | vm1, arc1 |
| T10b | P15 | **Overrun detected** | with `MaxSizeMB=16`, suspend the export (disable the task) until the ring has wrapped past `last_ts`, then run it: the zip uploads, the manifest has `complete: false` and a `buffer_overrun` gap whose from = `last_ts` and to = the oldest sample left (± 1 interval); an event-log warning exists | vm1, arc1 |
| T10c | P15 | **Failed upload, no gap** | block storage for one export run (firewall rule on the machine): export exits ≠ 0, `state.json` unchanged; unblock: the next export covers both windows in one zip, `complete: true` | vm1 |
| T11 | 9 | Blob landed | blob at `perfmon/<machine-prefix>/<yyyy>/<mm>/<dd>/<name>.zip` exists; its `Content-MD5` and `sha256` metadata = local zip; uploaded **with the machine identity** (storage log / the script's log: token source IMDS on vm1, **HIMDS on arc1**) | vm1, arc1 |
| T12 | 10 | Cannot write elsewhere | from the machine, with its own token: PUT into **another** machine's prefix → **403**; PUT outside `perfmon/` → 403; GET/LIST of any blob (own included) → 403; PUT into its own prefix → 201 (control) | vm1, arc1 |
| T13 | 11 | Lifecycle rule | management policy has the rule: prefix `perfmon/`, delete after `RetentionDays`; enabled | storage |
| T14 | DoD 3 | Storage private | `allowBlobPublicAccess=false`, `allowSharedKeyAccess=false`, TLS ≥ 1.2, network as CHOICE 5 (public access disabled + private endpoint approved), container access private; an anonymous GET → fails; a shared-key request → fails | storage |
| T15 | 12 | Skill fetch + convert | `perfmon_fetch_latest.py` on the agent side (and locally with the lab reader identity): with ≥ 2 dated zips of the machine present, it picks the **newest**, downloads, checks the manifest hash, unzips, and the converter gives `unparsed_paths=0`, `bad_cells=0`, `short_rows=0`, rows = manifest rows | vm1, arc1 |
| T16 | 13 | Agent report, **scored** | the SRE Agent, asked in a new thread "analyse the latest PerfMon capture of <machine>", fetches the latest zip itself and posts its report in the thread; the report is scored against `tests/scoring/rubric.md` (below); pass = score ≥ threshold **and** the report names the latest zip it used | vm1, arc1 |
| T17 | P44 | **Range mode** | the T16 plants (leak + CPU) run across an export boundary (an extra export at +16 min splits the CPU burst over two zips); the agent, asked in a new thread for the range from the load's start to its end, fetches every zip of the range, lists them all in the Capture section, finds both plants; scored like T16 | vm1, arc1 |
| T18a | P45 | Package from GitHub | the release asset is the content (default): T02, T04, T07–T12 green on vm1 and arc1 prove it | vm1, arc1 |
| T18b | P45 | **Package from storage (Arc)** | arc1 switched to `PackageContainerResourceId`: assignment `contentUri` = …/packages/PerfmonBlackbox.zip, `contentManagedIdentity` = system, the SAME `contentHash` as the release, Compliant; the machine holds Storage Blob Data Reader on the package container only; collector running and an export works | arc1 |
| T18c | P45 | **Package from storage (Azure VM)** | the same on vm1 (the VM and Arc download through different agents), then back to GitHub (T18a checks again) | vm1 |
| T18d | P45 | No reader role → no download | storage mode without the reader role on the package container: the assignment does not turn Compliant on that content; what it shows is recorded; the machine keeps its running configuration | vm1 |
| T18e | P45 | A different zip under the same name → rejected | a different zip in the container under `PerfmonBlackbox.zip` while the hash pins the release: rejected by the hash check; the machine keeps its old configuration; with the right zip it turns Compliant | vm1 |

### T16 scoring (ground truth from planted problems)

`tests/lab/guest/make-trouble.ps1` (synthetic, no real names) plants, for 45 minutes, **only a memory leak and a CPU
burst** (decisions P43: "CPU ve memory problemini yakalaması yeterli"; stalls removed by P34, disk and network by P43);
its `truth.json` is the ground truth. Before scoring, the plants are verified in the capture (P42); a plant that did not
take effect makes the run invalid. The scorer (`tests/scoring/score.py`, rules in `tests/scoring/rubric.md`) is
deterministic: latest zip named, host, time range, the leak (process and rate within 40 %) and the CPU burst (time
± 2 min and driver) found, verdict words, nothing invented (a disk or network problem claimed counts as invented), causal
claims backed by `LINK:`, no raw data. **Pass = score ≥ 80, both plants found, nothing invented.**

## Local tests (no Azure; CI)

| ID | What | Pass when |
|---|---|---|
| L01 | Converter on a synthetic PDH-CSV (`tests/fixtures/synthetic/`, made by `tests/synth/make_capture.py`) | meta counts as expected; day-first and month-first files read right; two-part capture with overlap merged |
| L02 | perfq helpers on the synthetic DB | `triage()` finds the planted breaches and prints the right VERDICT CEILING |
| L03 | Masker (lab-side tool) | a synthetic mapping masks a synthetic CSV; a planted denylist entry makes it exit 1 without printing the name |
| L04 | `perfmon_fetch_latest.py` selection logic | on synthetic blob listings it picks the newest zip, ignores other prefixes, rejects a zip whose manifest hash does not match |
| L05 | Export script logic (Pester, Windows runner) | CSV validation rejects a bad header, an empty file and a missing counter; blob path built right from a sample resource ID; window logic on synthetic sample times: no overlap with `last_ts`, holes found and classified (`buffer_overrun`, `collector_restart`, `local_cap`), `state.json` moves only after a good upload |
| L07 | Template | `PerfmonBlackbox.template.xml` holds exactly the 36 lines of the counter list, no location, date or machine field; placeholders only `{{MaxSizeMB}}` and `{{SampleIntervalSeconds}}` |
| L06 | Repo safety | `scripts/scrub-check.sh --self-test` passes; scrub check on the tree is clean |

## End-to-end order on a fresh lab (DoD centre)

build lab → `infra/` deploy → T13, T14 → T01 → publish package (release asset of a pre-release tag) → T02, T03 →
wait for compliance → T04, T05, T06, T07 → T06b, T06c (small `MaxSizeMB`) → back to 512 → T07b →
`make-trouble.ps1` (leak + CPU) during a captured window → T08 → T09 (two exports), T10, T10b, T10c, T11, T12 → T15 → T16. All green on **both** `vm1` and
`arc1` = DoD centre met. Then README-only fresh-eyes deploy into a second clean lab, which must reach the same green
(DoD 2).

## What is not tested in v1

The Azure Monitor alert trigger (phase 2, P4) and posting to a GitHub issue (later, P3).
