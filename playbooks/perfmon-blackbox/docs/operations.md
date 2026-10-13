# Operations

> **Summary.** Upgrades: update the two definitions to the new release's URL and hash, run a compliance scan, then
> remediate; machines on the old package become non-compliant for the policy and move. Troubleshooting starts with the guest assignment's
> per-resource reasons and the manifest's `complete` and `gaps[]`. Removal: assignments first, then the server side,
> storage last.
>
> Draft until v1.0.0.

## Upgrade to a new release

1. Generate the definitions with the new release's asset URL, SHA-256 and version (`policy/build_policies.py`, as in
   [deploy.md](deploy.md)) and update both definitions (`az policy definition create` on the same names updates them).
2. Run a compliance scan and wait for it to finish (`az policy state trigger-scan -g <rg>`, several minutes), so the
   policy engine evaluates the machines against the new definitions. Without it a service re-sync of the guest
   assignment can set it back to the old version (seen on Arc in storage mode, decisions P55).
3. Start a remediation per assignment. The definitions' existence condition pins the package hash (decisions P32):
   every machine still on the old package is non-compliant for the policy and the remediation moves it.
4. The agent downloads the new package at its next pull; its first cycle after that only tests, the next one applies,
   so allow about an hour per machine. Check the guest assignment's `version` after the next service re-sync (it should
   stay on the new one). The collector is only re-created if the counter set or a collector setting changed; recorded
   data is kept either way.

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

## How the export merges the pieces

Each export uploads **one zip with one CSV**, even when the data on the server sits in several files. Folder:
`C:\ProgramData\PerfmonBlackbox\`.

**The pieces.** The collector writes one circular file, `blg\PerfmonBlackbox.blg`. Windows cannot read that file
while the collector runs. So whenever the collector is stopped and started again, the file is first moved to
`pending\` under a new name, and the collector starts a fresh one. A restart therefore never overwrites data that was
not exported. A pending file is named `<yyyyMMdd-HHmmss>-<nn>-<reason>.blg`, with `-m<MaxSizeMB>` before `.blg` when
the ring's size limit is known. The reason says why it was closed:

| Reason | When |
|---|---|
| `export` | the export's own **roll**: stop the collector, move the file, start it again (a few seconds, `roll_seconds` in the manifest) |
| `boot` | after a restart of the server: the file was last written before the boot (moved by the Boot task or by Machine Configuration, whichever starts the collector first) |
| `recreate` | Machine Configuration re-created the collector (counter list, interval or size changed) |
| `start` | the collector was found stopped and started again |

**The merge.** The export (every `ExportEveryHours`) first rolls, then takes every file in `pending\`, oldest name first:

1. `relog <file> -f csv` converts each file on its own to a CSV.
2. The CSVs are joined in time order into **one** CSV with one header (all columns of all pieces). Only samples
   **after `last_ts`** are kept. `last_ts` is the last sample of the last upload that succeeded, kept in `state.json`.
   A sample that is not newer than the one before it is dropped. So nothing already uploaded is sent again (**no
   overlap**), and every sample still on the disk after `last_ts` is included (**no gap** of our own making).
3. Every step between two samples longer than 2 × the interval becomes a **gap** in the manifest, with a cause. A
   hole **between two pieces** is `machine_off` if the earlier piece was closed by a boot, `buffer_overrun` if the
   later piece had wrapped (filled and overwritten its oldest samples), otherwise `collector_restart`. A hole
   **inside one piece** is `missing_samples`. A hole **before the first sample** (from `last_ts`) is `export_roll`
   (the previous roll, seconds), `buffer_overrun`, `local_cap` or `collector_restart`. See [Manifest gaps](#manifest-gaps).
4. The CSV and `manifest.json` (window, rows, `sources[]` = the pieces used, `gaps[]`, `complete`) are zipped and uploaded.

**When pieces are deleted.**
- **After the upload succeeded**: the zip is sent with its MD5, which the storage service checks, and the service answered 201. Then `last_ts`
  moves forward and the pieces that went into the zip are deleted. If the upload fails (after its retries), nothing
  is deleted and `last_ts` stays: the next export reads the same pieces again.
- A piece with no sample after `last_ts` is deleted at once (everything in it was already uploaded).
- A piece `relog` cannot read stays for the next exports. After **3** failed reads it is deleted, and the next
  manifest reports its span as an `unreadable_ring` gap.
- If pending pieces and unsent zips together exceed `LocalKeepMB` (exports failing for a long time), the oldest
  pieces are deleted first, and the next manifest reports a `local_cap` gap.

## Manifest gaps

| Cause | Meaning | Action |
|---|---|---|
| `buffer_overrun` | the ring overwrote samples before they were exported | the export was late or failed too long, or the buffer is too small: see R6 |
| `machine_off` | the server was down between two rings | none; the time it was off |
| `export_roll` | the previous export's own collector restart (a few seconds; only visible at intervals under ~5 s) | none; it does not make `complete` false |
| `collector_restart` | the collector was restarted (re-create, start) | none if short; repeated restarts: check the event log |
| `local_cap` | closed rings were dropped by `LocalKeepMB` (exports failing for long) | fix the upload path (network, DNS, role), consider a larger `LocalKeepMB` |
| `unreadable_ring` | a ring cut by an abrupt stop (power loss, forced restart) could not be read by `relog` in 3 exports and was deleted (P54; event 2003). The gap may lie before the manifest's window: it was found only then | none; the span is as far as the file told (created .. last written) |
| `missing_samples` | holes inside one ring | the collector was starved or paused; check the system around that time |

## When the storage is unreachable (P46)

An export whose token or upload fails retries itself in the same run: again after **5 minutes**, then after another
**10** (so +5 and +15 min), each time with a fresh token. The zip is the same window, so a retry neither duplicates nor
leaves a gap. The server log (`C:\ProgramData\PerfmonBlackbox\log\perfmonblackbox.log`) shows `upload attempt N
failed (…); retry in … s` and then `uploaded on attempt N`; the event log gets an error (ID 3002) only when every attempt
has failed. If all three attempts fail, the run ends with an error; the Export task's **restart on failure** (every 15
min, 3 times) is a backstop for a run that could not start. After that the next scheduled export picks it up.

A failed upload never moves `last_ts`: the next successful export covers every missed window in one zip. Nothing is lost
as long as the outage is shorter than what the ring holds (`[BlackboxCapacity]` reports it, e.g. "buffer holds ~N h");
a longer outage shows up as a `buffer_overrun` gap in the next manifest.

## Remove

1. Delete the policy assignments (and running remediations) and the definitions.
2. Delete the guest assignments `PerfmonBlackbox` from the servers (or let them be removed with the assignment), and
   the per-server Writer role assignments on the container (description "perfmon-blackbox: write only under …").
3. On each server: `logman stop PerfmonBlackbox; logman delete PerfmonBlackbox`, `schtasks /delete /tn
   \PerfmonBlackbox\Boot /f`, the same for `\PerfmonBlackbox\Export`, then delete `C:\ProgramData\PerfmonBlackbox`.
4. Delete the storage deployment (account, private endpoint) last, after you no longer need the captures.
5. Delete the two custom roles ("PerfMon Blackbox Writer", "PerfMon Blackbox Deployer", or the names you gave them):
   `az role definition delete --name "<name>" --custom-role-only true`. A role definition is a subscription-level
   object, not a resource of the group, so deleting the resource group does not remove it, and Azure refuses to delete a
   role that still has assignments (remove those first, steps 1–2). Check with `az role definition list
   --custom-role-only true --query "[?starts_with(roleName,'PerfMon Blackbox')].roleName"`.
