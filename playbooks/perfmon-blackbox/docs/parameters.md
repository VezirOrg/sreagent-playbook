# Parameters and capacity

> **Summary.** Three parameters set how much a server records and how often it exports: `MaxSizeMB` (512),
> `SampleIntervalSeconds` (10) and `ExportEveryHours` (4). Every 15 minutes the ring is closed into a piece that waits
> on the disk for the export, so `LocalKeepMB` (1024) must hold at least 1.5 times the export window, and the ring at least
> 1.5 times 15 minutes; how long they hold depends mostly on the number of processes. The package measures this on every server and reports a
> misfit as a NonCompliant reason before any data is lost.
>
> As of v1.0.0 (the table is measured on lab servers and real captures; see decisions P27).

## All parameters (same on both definitions)

| Parameter | Default | Meaning |
|---|---|---|
| `MaxSizeMB` | 512 | size of the circular `.blg` (16–8192); since rc.10 it is closed every 15 min, so it only has to hold 15 minutes (a safety margin if the Roll task does not run) |
| `SampleIntervalSeconds` | 10 | collector interval (1–300) |
| `ExportEveryHours` | 4 | export cadence; one of 1, 2, 3, 4, 6, 8, 12, 24 |
| `StorageAccountResourceId` | required | the private storage account |
| `ContainerName` | `perfmon` | container for all servers |
| `LocalKeepMB` | 1024 | cap for the closed 15-minute pieces and unsent zips on the server; they wait here until the export (and longer while the storage is unreachable); the oldest go first and the loss is reported (`local_cap`) |
| `WriterRoleDefinitionId` | required | the custom Writer role (infra output) |

The package source (GitHub or your storage) is not a parameter: it is chosen when the definitions are generated, see
[architecture.md](architecture.md#why-the-package-source-is-fixed-when-the-definitions-are-generated).

A changed value reaches the server at the next evaluation (≤ 30 minutes after remediation). A change of
`MaxSizeMB`, the interval or the counter set re-creates the collector; what was recorded is kept as a pending ring and
exported, so nothing is lost.

## How long 512 MB lasts

A binary log costs about 45–54 bytes per value per sample. The full counter set has 10 per-process counters, so:

**bytes per sample ≈ 4.5 KB + 0.53 KB × processes** (the 36 base counters alone: 3.5 KB + 0.43 KB × processes)

Measured: 68.8 KB per sample at 120 processes on a lab VM (the formula gives 67.6 KB).

| Processes | KB per sample | 512 MB at 10 s | at 5 s | at 1 s |
|---|---|---|---|---|
| 100 | ≈ 58 | ≈ 26 h | ≈ 13 h | ≈ 2.6 h |
| 200 | ≈ 110 | ≈ 13.5 h | ≈ 6.8 h | ≈ 1.4 h |
| 300 | ≈ 164 | ≈ 9 h | ≈ 4.5 h | ≈ 0.9 h |
| 400 | ≈ 216 | ≈ 6.9 h | ≈ 3.4 h | ≈ 0.7 h |
| 500 | ≈ 270 | ≈ 5.5 h | ≈ 2.8 h | ≈ 0.6 h |

The same numbers apply to `LocalKeepMB`: 1024 MB holds twice the hours of the 512 MB column.

Rule of thumb (since rc.10): keep **`LocalKeepMB` hours ≥ 1.5 × ExportEveryHours** and **ring hours ≥ 1.5 × 15 min**.
With the defaults both hold up to about 900 processes at 10 s; at 1 s, `LocalKeepMB` hours limit it (about 5.2 h at
100 processes, enough for an export every 3 h, not every 4 h).

## The capacity check (resource R6)

- After every export the server stores its **measured** bytes per sample (from the ring it just closed) and the buffer
  hours they give at the current `MaxSizeMB` and interval. Before the first export it uses the formula above with the
  current process count and says "estimated".
- R6 is **NonCompliant** when `LocalKeepMB` holds < 1.5 × `ExportEveryHours`, or the ring holds < 1.5 × 15 min (rc.10,
  decisions P62; before rc.10 the ring alone had to hold 1.5 × the export window). The reason shows the numbers for both.
- It shows in Azure Policy (guest assignment report, resource `[BlackboxCapacity]Capacity`) before data is lost. It is
  audit only: nothing is changed on the server.
- If data is lost anyway (exports failed for longer than `LocalKeepMB` holds: `local_cap`; the Roll task did not run
  for longer than the ring holds: `buffer_overrun`), the next manifest reports the gap and `complete: false`: see
  [operations.md](operations.md).
