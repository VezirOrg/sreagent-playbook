# Parameters and capacity

> **Summary.** Three parameters set how much a server records and how often it exports: `MaxSizeMB` (512),
> `SampleIntervalSeconds` (10) and `ExportEveryHours` (4). The buffer must hold at least 1.5 times the export window;
> how long it holds depends mostly on the number of processes. The package measures this on every server and reports a
> misfit as a NonCompliant reason before any data is lost.
>
> Draft until v1.0.0 (the table is measured on lab servers and real captures; see decisions P27).

## All parameters (same on both definitions)

| Parameter | Default | Meaning |
|---|---|---|
| `MaxSizeMB` | 512 | size of the circular `.blg` (16–8192); the newest `MaxSizeMB` of data is always on the disk |
| `SampleIntervalSeconds` | 10 | collector interval (1–300) |
| `ExportEveryHours` | 4 | export cadence; one of 1, 2, 3, 4, 6, 8, 12, 24 |
| `StorageAccountResourceId` | required | the private storage account |
| `ContainerName` | `perfmon` | container for all servers |
| `LocalKeepMB` | 1024 | cap for closed rings and unsent zips on the server; the oldest go first and the loss is reported |
| `WriterRoleDefinitionId` | required | the custom Writer role (infra output) |

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

Rule of thumb: keep **buffer hours ≥ 1.5 × ExportEveryHours**. With the defaults that holds up to about 460 processes.

## The capacity check (resource R6)

- After every export the server stores its **measured** bytes per sample (from the ring it just closed) and the buffer
  hours they give at the current `MaxSizeMB` and interval. Before the first export it uses the formula above with the
  current process count and says "estimated".
- R6 is **NonCompliant** when buffer hours < 1.5 × `ExportEveryHours`. The reason shows the numbers, for example:
  `buffer holds ~0.1 h at 1 s with MaxSizeMB=16 (measured, 66600 bytes/sample), export every 24 h: less than 1.5 x the
  export window, data will be lost; raise MaxSizeMB, lengthen the interval or export more often`.
- It shows in Azure Policy (guest assignment report, resource `[BlackboxCapacity]Capacity`) before data is lost. It is
  audit only: nothing is changed on the server.
- If data is lost anyway (an export failed for longer than the ring holds), the next manifest reports a
  `buffer_overrun` gap and `complete: false`: see [operations.md](operations.md).
