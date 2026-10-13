# Changelog: perfmon-blackbox

Tags: `perfmon-blackbox/vX.Y.Z`. The package zip of each release is a GitHub Release asset.

## Unreleased (v1.0.1, P70; found by the fresh-eyes deploy on the second lab)

- **Fix B1 (storage mode):** the definitions' existenceCondition checks `contentManagedIdentity = system` instead of
  `contentUri`, which Azure returns as null with a managed identity. In v1.0.0 the Policy view of a storage-mode
  assignment stayed NonCompliant while every server was Compliant, and each remediation redeployed. GitHub mode is
  unchanged. The package zip is unchanged (only the generated definitions change): re-create the storage-mode
  definitions with the v1.0.1 generator.
- **deploy.md:** step 2 passes the definition's metadata and display name (storage mode needs the metadata); remediations
  use `--resource-discovery-mode ReEvaluateCompliance` (a new assignment has no compliance results yet); 2b says how the
  package gets into a private-endpoint-only account and who needs Blob Data Contributor; the Machine Configuration agent
  version check uses the folder name; which subnet for the private endpoint; the `packageContainerResourceId` output.
- **parameters.md:** the numeric parameters are strings.

## perfmon-blackbox/v1.0.0 (2026-10-13)

First release (decisions P66). The package is the rc.11 zip, unchanged (SHA-256
`806BCADB69F556401DE19754AEB649B7611EB1AE18AA106A5BF0A537A99363DD`); pass `--version 1.0.0` to the policy generator.

- Machine Configuration package `PerfmonBlackbox` (AuditAndSet, 7 DSC resources): a binary circular PerfMon log
  (default 512 MB, 10 s), restarted after every boot, closed into `pending\` every 15 minutes, exported every 4 hours
  with `relog` (probe, merge per segment, UTC times) to CSV + `manifest.json` (every gap named), zipped and uploaded
  with the server's own managed identity into its own folder of a private storage account.
- Azure Policy (DeployIfNotExists) for Azure VMs and Arc-enabled servers, the package from the GitHub release or from
  your own container; `infra/main.bicep` for the private storage and the two custom roles.
- SRE Agent skill **perfmon-triage v2.2**: fetches the newest zip (or a time range), checks it, converts it to SQLite
  and writes a ranked report (lab score 95–100 of 100).
- Tested on an Azure VM and an Arc-enabled server ([docs/tests.md](docs/tests.md)); known limits in
  [docs/analysis.md](docs/analysis.md#known-limits-v100).

## Development history (rc.1 to rc.11)

- 2026-10-11: playbook created. Design and test plan drafted for approval. Skill v2.0, `deploy-skill.sh` and the
  CSV masker copied in verbatim (provenance in `decisions.md` P7).
- 2026-10-11: design and test plan rev 2 (P11–P15): Emre's 36 counters as a sanitized template, binary circular
  log with `MaxSizeMB` (default 512) on both policies, export around the circular file, buffer-hour estimate.
- 2026-10-11: P16–P19: lab18 measurement (partial), counter groups G1–G3, interval parameter, capacity check; PLAN-OK
  for design rev 3 (defaults 10 s / 512 MB / export 4 h).
- 2026-10-11: session 2: P20 collector files committed under `package/collector/` (they never entered git under `package/files/`); P21 the export rolls the collector.
- 2026-10-11: skill **v2.1**: `perfmon_fetch_latest.py` (step −1: newest zip of a machine, manifest hash check, gaps
  quoted in the report); `perfq.py` reads `Processor Information` when there is no `Processor` object (CPU count and
  CPU checks; no false System breaches from a CPU count of 0). Rule 6 and the VERDICT CEILING unchanged (P8).
- 2026-10-11: synthetic capture generator `tests/synth/make_capture.py`, local tests L01–L04, L07 (`tests/run.sh`).
- 2026-10-11: P22 (Process set stays), P23 (implementation choices), P24 (Windows dev over SSH on lab VMs), P25
  (Windows PowerShell 5.1 on servers, runtime split), P26 (export uses only what ships with Windows Server).
- 2026-10-11: package code: `PerfmonBlackboxDsc` (R1–R6, class-based), `PerfmonBlackbox.Common.ps1`,
  `Start-PerfmonBlackbox.ps1`, `Export-PerfmonBlackbox.ps1` (Windows PowerShell 5.1, ASCII), `PerfmonBlackbox.config.ps1`,
  `build.ps1`; Pester L05 (24 tests incl. export end to end on synthetic `.blg`) and PSScriptAnalyzer 5.1 rules,
  run on a lab VM by `tests/run.sh L05`. P27: storm answered (none), bytes-per-sample formula.
- 2026-10-11: `infra/main.bicep` (private storage, PE, lifecycle 30 d, write-only custom role, agent readers); T01, T13, T14 green on lab18.
- 2026-10-11: `build.ps1` neutralises the MOF's build host/user/paths; pre-release `perfmon-blackbox/v1.0.0-rc.1` (P29) for the lab.
- 2026-10-11: **lab18 vm1, policy-deployed (rc.1): T04, T06, T07, T09, T10, T11, T12 green**; first export uploaded with the
  VM's own identity (201), roll gap 1.7–2.7 s, consecutive exports continuous (no gap, no overlap), a machine cannot
  write elsewhere or read. T04/T06e read the assignment report API; verifier decodes the list response's BOM under 5.1.
- 2026-10-11: P31 standing permission for lab rc.N; rc.2 (boot reason from the boot time).
- 2026-10-11: **arc1 (Arc, HIMDS) policy-deployed: T04, T05, T06, T07, T09, T10, T11, T12 green** (upload with the Arc machine's identity: P10 risk cleared); T07b green on vm1; CI green with the new jobs.
- 2026-10-11: rc.3 (P33: R1's ACL no longer empties existing files' DACLs); lab size polls through a handle; wrap proven on lab18 (BbWrap1).
- 2026-10-11: P34: OPEN-2 closed for v1.0.0 (no stall plant, rubric P5 dropped, disk rule tightened); wrap proven (BbWrap1/2); T16 run 1 evidence kept as run1.
- 2026-10-11: rc.4 (P36: a resource's Test never throws; self-heals ACL-locked files).
- 2026-10-11: rc.5 (P37: gaps and 'wrapped' judged per ring, bounded event text).
- 2026-10-11: rc.6 (P40: a hole before a wrapped ring is reported as buffer_overrun).
- 2026-10-11: rc.7 (P41: the export's own short roll is an expected export_roll gap).
- 2026-10-11: skill **v2.2** (P44): range mode — every zip overlapping a requested time range, one database restricted to the range, coverage holes reported; default still the latest zip.
- 2026-10-12: package (rc.8): the export releases its lock while it waits between upload attempts (P49, LOCK-A);
  the cleanup tolerates a part dropped by `LocalKeepMB` meanwhile. Tests: T10d (P46 retry, lab), L05 +2 Pester cases.
- 2026-10-12: package (rc.9): a pending ring that relog cannot read 3 times (cut by an abrupt stop) is deleted,
  reported as an `unreadable_ring` gap in the next manifest and as event 2003 (P54, RING-A); L05 39/39. Lab: T10e, T18de.
- 2026-10-12: docs: name uniqueness for a second deployment (custom role names tenant-wide, policy definition names
  per subscription), custom roles deleted explicitly on removal, the SRE Agent's cost (always-on 4 AAU/h), test status.
- 2026-10-13: **rc.10** (package 1.0.9, P62, T08-FIX): a `\PerfmonBlackbox\Roll` task (DSC resource R7) closes the
  ring into `pending\` every 15 min, so a shutdown that leaves the open file unclosed loses at most 15 min; R6 checks
  `LocalKeepMB` against the export window and the ring against the roll; a hole that contains a recorded boot is
  `machine_off`; an unreadable ring's span starts at its recorded start (not the file's CreationTime); a piece with
  fewer than 2 samples is deleted, not counted as unreadable. Adopter docs: "How it works on the server".
- 2026-10-13: **rc.11** (package 1.0.10, P63): the export probes every piece with `relog -q` (unreadable and too-small
  pieces never enter a merge) and merges the good ones with one multi-input `relog` per segment (a boot, an overlap or a
  UTC offset change starts a new segment; a merge that does not add up falls back to one call per piece). Every sample
  gets a UTC time (DST-A): a daylight-saving fall-back keeps its repeated hour, the join, `last_ts_utc` and the gap
  search run on UTC; `clock_back` / `clock_forward` name the change (not a loss), `clock_reset` a clock set back by hand
  (a loss). Manifest: `first_sample_utc`, `last_sample_utc`.
