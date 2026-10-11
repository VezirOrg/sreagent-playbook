# Operations

> **Summary.** Upgrades: update the two definitions to the new release's URL and hash, then remediate; machines on
> the old package become non-compliant for the policy and move. Troubleshooting starts with the guest assignment's
> per-resource reasons and the manifest's `complete` and `gaps[]`. Removal: assignments first, then the server side,
> storage last.
>
> Draft until v1.0.0.

## Upgrade to a new release

1. Generate the definitions with the new release's asset URL, SHA-256 and version (`policy/build_policies.py`, as in
   [deploy.md](deploy.md)) and update both definitions (`az policy definition create` on the same names updates them).
2. Start a remediation per assignment. The definitions' existence condition pins the package hash (decisions P32):
   every machine still on the old package is non-compliant for the policy and the remediation moves it.
3. The agent applies the new package at its next cycle (≤ 15 minutes). The collector is only re-created if the counter
   set or a collector setting changed; recorded data is kept either way.

## Where to look

| Question | Where |
|---|---|
| Is the black box installed and healthy on a server? | the guest assignment `PerfmonBlackbox` of the server: Compliant, and per resource R1–R6 with reasons |
| Did the last export work? | blobs under `perfmon/<sub>/<rg>/<server>/`, the newest zip's `manifest.json`; on the server `C:\ProgramData\PerfmonBlackbox\state.json` (`last_ts`, `last_error`) and `log\perfmonblackbox.log` |
| Did we lose data? | the manifest's `complete` and `gaps[]`; event log Application, source `PerfmonBlackbox`, IDs 2001–2002 |

## Compliance reasons

| Resource | Typical reason | What to do |
|---|---|---|
| `[BlackboxFiles]Files` | `file … differs`, `config … is 'x', expected 'y'`, `folder ACL …` | nothing; the agent corrects it at its next cycle (AuditAndSet) |
| `[BlackboxFiles]Files` | `BadParameter: ExportEveryHours 5 must divide 24` | fix the assignment's parameter |
| `[BlackboxCollector]Collector` | `counter list differs`, `interval …`, `max size …` | nothing; the collector is re-created, old data kept |
| `[BlackboxRunning]Running` | `collector status is Stopped` | nothing; it is started again (check the event log if it repeats) |
| `[BlackboxBootTask]` / `[BlackboxExportTask]` | `task … is not registered` / field differs | nothing; re-registered |
| `[BlackboxCapacity]Capacity` | `buffer holds ~N h …` | raise `MaxSizeMB`, lengthen the interval or export more often: [parameters.md](parameters.md) |

## Manifest gaps

| Cause | Meaning | Action |
|---|---|---|
| `buffer_overrun` | the ring overwrote samples before they were exported | the export was late or failed too long, or the buffer is too small: see R6 |
| `machine_off` | the server was down between two rings | none; the time it was off |
| `collector_restart` | the collector was restarted (re-create, start) | none if short; repeated restarts: check the event log |
| `local_cap` | closed rings were dropped by `LocalKeepMB` (exports failing for long) | fix the upload path (network, DNS, role), consider a larger `LocalKeepMB` |
| `missing_samples` | holes inside one ring | the collector was starved or paused; check the system around that time |

A failed upload never moves `last_ts`: the next export covers both windows in one zip.

## Remove

1. Delete the policy assignments (and running remediations) and the definitions.
2. Delete the guest assignments `PerfmonBlackbox` from the servers (or let them be removed with the assignment), and
   the per-server Writer role assignments on the container (description "perfmon-blackbox: write only under …").
3. On each server: `logman stop PerfmonBlackbox; logman delete PerfmonBlackbox`, `schtasks /delete /tn
   \PerfmonBlackbox\Boot /f`, the same for `\PerfmonBlackbox\Export`, then delete `C:\ProgramData\PerfmonBlackbox`.
4. Delete the storage deployment (account, private endpoint, custom roles) last, after you no longer need the captures.
