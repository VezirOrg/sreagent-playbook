# Changelog: perfmon-blackbox

Tags: `perfmon-blackbox/vX.Y.Z`. The package zip of each release is a GitHub Release asset.

## Unreleased

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
