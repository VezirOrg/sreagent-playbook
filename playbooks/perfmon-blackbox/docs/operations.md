# Operations

> **Summary.** Upgrades: update the two definitions to the new release's URL and hash, run a compliance scan, then
> remediate; machines on the old package become non-compliant for the policy and move. Troubleshooting starts with the guest assignment's
> per-resource reasons (R1–R7) and the manifest's `complete` and `gaps[]`. Removal: assignments first, then the server side,
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
| Is the black box installed and healthy on a server? | the guest assignment `PerfmonBlackbox` of the server: Compliant, and per resource R1–R7 with reasons |
| Did the last export work? | blobs under `perfmon/<sub>/<rg>/<server>/`, the newest zip's `manifest.json`; on the server `C:\ProgramData\PerfmonBlackbox\state.json` (`last_ts`, `last_error`) and `log\perfmonblackbox.log` |
| Did we lose data? | the manifest's `complete` and `gaps[]`; event log Application, source `PerfmonBlackbox`, IDs 2001–2002 |

## Compliance reasons

| Resource | Typical reason | What to do |
|---|---|---|
| `[BlackboxFiles]Files` | `file … differs`, `config … is 'x', expected 'y'`, `folder ACL …` | nothing; the agent corrects it at its next cycle (AuditAndSet) |
| `[BlackboxFiles]Files` | `BadParameter: ExportEveryHours 5 must divide 24` | fix the assignment's parameter |
| `[BlackboxCollector]Collector` | `counter list differs`, `interval …`, `max size …` | nothing; the collector is re-created, old data kept |
| `[BlackboxRunning]Running` | `collector status is Stopped` | nothing; it is started again (check the event log if it repeats) |
| `[BlackboxBootTask]` / `[BlackboxExportTask]` / `[BlackboxRollTask]` | `task … is not registered` / field differs | nothing; re-registered |
| `[BlackboxCapacity]Capacity` | `ring holds ~N h …; LocalKeepMB holds ~M h …` | raise `LocalKeepMB` or `MaxSizeMB`, lengthen the interval or export more often: [parameters.md](parameters.md) |

## How it works on the server

What the package does on each server, step by step, with the purpose of each step and why it is built this way.
Folder: `C:\ProgramData\PerfmonBlackbox\`. Everything runs as SYSTEM under Windows PowerShell 5.1 and uses only tools
that ship with Windows (`logman`, `relog`, `schtasks`).

| # | Step | Purpose | Why this way |
|---|---|---|---|
| 1 | **Collector.** Machine Configuration creates the data collector set `PerfmonBlackbox` and keeps it running: one **circular** binary file, `blg\PerfmonBlackbox.blg`, one sample every `SampleIntervalSeconds` | always have the recent past on the disk, like a flight recorder | a circular file never grows past `MaxSizeMB`: the newest data overwrites the oldest, so the disk can never fill up |
| 2 | **Boot.** At every start of Windows the Boot task moves the file from before the restart to `pending\`, records the boot time, and starts the collector again | recording resumes on its own after a restart; the boot time names the hole in the data | a circular log started again would overwrite the old file; moving it first keeps it |
| 3 | **Roll, every 15 minutes.** The Roll task stops the collector, moves the file to `pending\` and starts it again (a few seconds). No upload | the data is split into closed pieces of at most 15 minutes | Windows **cannot read a circular file while the collector writes it**, and a shutdown can leave the open file **unclosed and unreadable** for good (seen in the lab: a restart while Windows Update was finishing, T08 on arc1, 2026-10-13). Only a closed file is safe. With a roll every 15 minutes, a bad shutdown loses at most the last 15 minutes, and the loss is reported |
| 4 | **Wait in `pending\`.** The closed pieces stay on the disk until the next export | the server keeps the data while the export is not due, or while the storage is unreachable | `LocalKeepMB` caps what waits here; if it is reached, the oldest pieces go first and the next manifest says so (`local_cap`) |
| 5 | **Export, every `ExportEveryHours`: check each piece.** It rolls once more (so the last minutes are included), then asks `relog -q` about every piece: readable? how many samples, from when to when? | only good pieces go into the merge | `relog` is Windows' own tool for joining performance logs, but **one unreadable file makes a whole `relog` call fail** with no output (tested in the lab). So a piece that cannot be read is set aside (tried again by the next exports, see below), and a piece with fewer than 2 samples is deleted (`relog` rejects it; it holds nothing to lose) |
| 6 | **Merge with `relog`.** The good pieces, in the order they were closed, are merged by **one** `relog <pieces> -f csv` call into one CSV with one header (all columns of all pieces; blank where a piece lacks a counter). A restart of Windows, or pieces whose times overlap or step back (a clock change), split the pieces into separate calls (segments), which are then joined one after the other. Only samples **after `last_ts`** are kept (`last_ts` = the last sample of the last upload that succeeded, in `state.json`) | one file per export window, with **no overlap** and **no gap** | `relog` computes rates (for example `% Processor Time`) from two samples in a row. Across a roll that is right (the counters keep running). Across a restart the counters start from zero again, and with overlapping times `relog` produces wrong values without an error (tested in the lab): so it never gets those in one call. If a merge call fails, its pieces are converted one by one instead (the older, tested path), so a bad merge never blocks the export |
| 7 | **Gaps.** Every step between two samples longer than 2 × the interval goes into the manifest as a gap with a cause (see [Manifest gaps](#manifest-gaps)) | a loss of data is never silent | the cause depends on where the hole is: around a recorded boot it is `machine_off`; between two pieces, `collector_restart` (or `buffer_overrun` if the later piece had wrapped); inside one piece, `missing_samples`. A roll's own hole of a few seconds is `export_roll` and does not count |
| 8 | **Zip and upload.** The CSV and `manifest.json` (window, rows, the pieces used, gaps, `complete`) go into one zip, uploaded with the server's own identity into its own folder of the container | one file per server and window in the storage | the server's identity can write only under its own prefix (no keys on the server) |
| 9 | **Clean up.** Only after the storage service accepted the upload (HTTP 201; the zip is sent with its MD5, which the service checks), `last_ts` moves forward and the pieces that went into the zip are deleted | free the disk, and never delete data that is not in the storage | a failed upload deletes nothing: it is retried in the same run (+5 and +15 min) and by the next export, which covers the whole window since `last_ts` |

**Pieces that cannot be read.** A piece `relog` cannot read (a shutdown left it unclosed) stays in `pending\` and is
tried again by the next exports. After **3** failed reads it is deleted and the next manifest reports its time span as
an `unreadable_ring` gap. With the 15-minute roll such a piece holds at most 15 minutes. Its span starts when the
collector started writing it (recorded by the package) and ends at its last write.

**Names in `pending\`.** `<yyyyMMdd-HHmmss>-<nn>-<reason>.blg` (with `-m<MaxSizeMB>` before `.blg` when the ring's
size limit is known). The time is when the piece was closed; the reason says why: `roll` (every 15 min), `export`
(the export's own roll), `boot` (closed by a restart of Windows), `recreate` (Machine Configuration re-created the
collector after a change of counters, interval or size), `start` (the collector was found stopped and started).

**Why `relog` merges, and why it is guarded.** `relog` is Windows' own tool for joining performance logs (decisions
P63). The export checks every piece first, because one unreadable piece makes the whole call fail (`0xC0000BF7`). It
never puts a restart of Windows or overlapping times into one call, because `relog` would compute rates across them.
The facts the gap causes need per piece (its time range, interval, whether it wrapped, bytes per sample) come from
the same check (`relog -q`) and the file itself. Until rc.10 the export converted each piece on its own and joined the
CSVs itself (P62); that path is now the fallback.

**Clock changes (daylight saving time).** PerfMon writes local time without the offset. When the clock goes back one
hour, the same local times occur twice; when it goes forward, an hour of local time is skipped. The export gives every
sample its UTC time from the server's own time-zone rules (and, for a time that occurs twice, from when the piece was
written), and joins, orders and checks for gaps in UTC. So **nothing is lost and no false gap appears**. The CSV keeps
PerfMon's local timestamps, so in the zip that covers a fall-back they step back once. The manifest says so
(`clock_back` or `clock_forward`, neither counts as a loss) and carries `first_sample_utc` / `last_sample_utc`
(decisions P63). Servers in UTC (the Azure default) never see this.

## Manifest gaps

| Cause | Meaning | Action |
|---|---|---|
| `buffer_overrun` | the ring overwrote samples before they were rolled into `pending\` | the Roll task did not run for longer than the ring holds, or the ring is too small: see R6 |
| `machine_off` | the hole contains a restart of Windows (a recorded boot time) | none if expected; samples of the last minutes before the restart are in it if the shutdown left the open piece unreadable (then an `unreadable_ring` gap follows after 3 exports) |
| `export_roll` | a roll's own collector restart (the export's or the 15-minute roll; a few seconds, only visible at intervals under ~5 s) | none; it does not make `complete` false |
| `collector_restart` | the collector was restarted (re-create, start) | none if short; repeated restarts: check the event log |
| `local_cap` | closed rings were dropped by `LocalKeepMB` (exports failing for long) | fix the upload path (network, DNS, role), consider a larger `LocalKeepMB` |
| `unreadable_ring` | a piece left unclosed by a shutdown could not be read by `relog` in 3 exports and was deleted (P54, P62; event 2003). Not only power loss or a forced restart: a clean restart can cause it too (lab: a restart while Windows Update was finishing). With the 15-minute roll it is at most 15 minutes. The gap may lie before the manifest's window: it was found only then | none; the span runs from when the collector started writing the piece to its last write |
| `clock_back` / `clock_forward` | local time stepped back or jumped forward (daylight saving time); the samples are ordered by UTC, nothing is lost | none; it does not make `complete` false |
| `clock_reset` | the clock was set back by hand (not by a time-zone rule): samples at times already passed cannot be ordered and were dropped | check who changes the server's clock |
| `missing_samples` | holes inside one ring | the collector was starved or paused; check the system around that time |

## When the storage is unreachable (P46)

An export whose token or upload fails retries itself in the same run: again after **5 minutes**, then after another
**10** (so +5 and +15 min), each time with a fresh token. The zip is the same window, so a retry neither duplicates nor
leaves a gap. The server log (`C:\ProgramData\PerfmonBlackbox\log\perfmonblackbox.log`) shows `upload attempt N
failed (…); retry in … s` and then `uploaded on attempt N`; the event log gets an error (ID 3002) only when every attempt
has failed. If all three attempts fail, the run ends with an error; the Export task's **restart on failure** (every 15
min, 3 times) is a backstop for a run that could not start. After that the next scheduled export picks it up.

A failed upload never moves `last_ts`: the next successful export covers every missed window in one zip. Nothing is lost
as long as the outage is shorter than what `LocalKeepMB` holds (the 15-minute pieces wait in `pending\`;
`[BlackboxCapacity]` reports the hours); a longer outage shows up as a `local_cap` gap in the next manifest.

## Remove

1. Delete the policy assignments (and running remediations) and the definitions.
2. Delete the guest assignments `PerfmonBlackbox` from the servers (or let them be removed with the assignment), and
   the per-server Writer role assignments on the container (description "perfmon-blackbox: write only under …").
3. On each server: `logman stop PerfmonBlackbox; logman delete PerfmonBlackbox`, `schtasks /delete /tn
   \PerfmonBlackbox\Boot /f`, the same for `\PerfmonBlackbox\Export` and `\PerfmonBlackbox\Roll`, then delete `C:\ProgramData\PerfmonBlackbox`.
4. Delete the storage deployment (account, private endpoint) last, after you no longer need the captures.
5. Delete the two custom roles ("PerfMon Blackbox Writer", "PerfMon Blackbox Deployer", or the names you gave them):
   `az role definition delete --name "<name>" --custom-role-only true`. A role definition is a subscription-level
   object, not a resource of the group, so deleting the resource group does not remove it, and Azure refuses to delete a
   role that still has assignments (remove those first, steps 1–2). Check with `az role definition list
   --custom-role-only true --query "[?starts_with(roleName,'PerfMon Blackbox')].roleName"`.
