---
name: perfmon-triage
description: Triage a Windows Performance Monitor (PerfMon) capture, either the latest perfmon-blackbox capture of a machine fetched from its storage account or raw CSV file(s) given directly, when the cause of a slow or unresponsive machine is unknown. The skill converts the CSV into a SQLite database with its own script, then checks CPU, memory, disk, network, processes and application counters against a fixed checklist, ranks what would make the machine hard to use, and digs into the top problems (timeline, driver, root-cause chain). Use for PerfMon / perfmon / BLG-exported / relog CSV / performance counter captures, "server is slow", "machine is sluggish".
compatibility: Python 3 standard library only (csv, sqlite3, urllib, zipfile). No pandas, no package installs. Runs in a terminal with python3. Fetching from storage needs read access (Storage Blob Data Reader) on the perfmon container.
metadata:
  version: "2.1"
---

# PerfMon triage: CSV → SQLite → analysis

You get the name of a machine whose capture the perfmon-blackbox recorder uploads (fetch it first, step −1), or one
or more PerfMon CSV files, and nothing else: no time window, no symptom, no suspect. First **convert**
the CSV into a SQLite database with this skill's converter; then work in two phases over that database: **breadth**
(every resource against a fixed checklist, ranked by impact on usability), then **depth** (only the problems that
would make the machine hard to use). The data is large; your context is not. **Never look at raw data**: not the
CSV, not raw rows of the database. Every query returns an aggregate, and the helpers in `perfq.py` cap every
printout.

## Rules

1. **No raw data.** Never `cat`, `head`, `less` or `grep` a CSV (its header line alone is tens of kilobytes) and
   never `SELECT` from `vals` or `perf` without `GROUP BY` or a helper. At most **20 rows** per table, **30 points**
   per time series (bucket it). Do not print the whole counter list; filter it.
2. **One step, one Python run.** Print only what the step needs.
3. **End every step with one line:** `HYPOTHESIS: <what you now believe> | NEXT: <what the next step tests>`.
4. **Evidence = number + time + duration, and the time is the time printed for that number.** `triage()` prints
   `extreme_at` (time of the extreme) and `longest_from` (start of the longest breach); `series()` prints `peak_at`
   and `low_at` (the exact sample of each bucket's max and min). Quote those; never quote a bucket label or a
   breach start as the time of a peak. A single sample is a blip, not a problem, until you show it lasted.
5. **The verdict word follows the breach table.** `triage()` ends with a `VERDICT CEILING` line. If no check breached
   for 5 continuous minutes, nothing may be called critical or severe, and the machine was not hard to use by
   these checks: trends and leaks are at most **warning**. "No critical problem" is a valid answer; do not invent a
   crisis because the request says "performance problems".
6. **A causal claim needs a test in time.** Before you write "X is caused by Y", "Y drives X" or "X because of Y",
   run `link_test(db, X, Y)` (does X still grow after Y stopped?) and quote its `LINK:` line. Without it, write
   "coincides with".
7. **A rate needs a helper.** Growth per request (or per any unit of load) comes from `leak_rate()`; growth per hour
   comes from `leak_rate()` or `movers()` on one process (one PID). Never compute a rate from numbers read off a
   series by eye, and never across a process restart.
8. Timestamps are local to the capture (zone in `meta.pdh_header`). Say so once.

## PerfMon pitfalls (check before you claim anything)

- **Free memory is `Memory\Available MBytes`**, not `Free & Zero Page List Bytes`. Windows fills the standby cache on
  purpose; a near-zero Free & Zero list with gigabytes available is normal.
- **Cumulative counters are running totals, not rates**: e.g. `TCPv4\Connection Failures`, `RejectedRequests`,
  `# Gen 0 Collections`, `Total ... Failures`, `Total Health Pings`. Use the change over the window
  (`is_cumulative(db, counter_id)` tells you).
- **Units.** `Avg. Disk sec/*` is seconds (0.025 = 25 ms). `% Processor Time` of a *process* is per core (200 = two
  full cores; divide by the CPU count for a machine share). Counters named *Latency* in WAS/HTTP objects can be in
  100-ns ticks (156,250 = 15.6 ms). Byte counters are bytes.
- **Instance names are not processes.** `w3wp`, `w3wp#1`, `svchost#3` are re-assigned when processes start and stop
  (recycles, restarts). Before you say "process X grew", check `pid_changes(db, 'X')`; compare growth per PID.
- **Instances that come and go** can show one absurd first value (a raw count instead of a rate). Treat an extreme
  that appears only in the samples where an instance (re)appears as a counter artifact.
- **`.NET CLR Memory\Gen 0 heap size`** is the gen-0 budget, updated only at a GC; it is not memory in use. For
  managed memory use `# Bytes in all Heaps`; Private Bytes minus that ≈ native memory.
- **Correlate with load.** Growth that tracks requests/sec and stops when load stops is per-request; growth with no
  load is a background job or native growth. `link_test()` and `leak_rate()` do this; use them.
- **Saw-tooth counters** (handles, private bytes) swing up and down within minutes: compare averages over buckets,
  not two single samples.

## Step −1 — Fetch the latest capture of the machine (1 terminal command)

When the request names a machine (not a CSV), its captures are zips in the perfmon-blackbox storage account:
`perfmon/<subscriptionId>/<resourceGroup>/<machine>/<yyyy>/<mm>/<dd>/<machine>_<from>_<to>.zip`, one per export
(every few hours). The storage account name is in the request or in the agent's instructions.

```sh
python3 "$SKILL_DIR/perfmon_fetch_latest.py" --account <storage account> --machine <machine> --out /tmp/perfmon
# known prefix:          --prefix <subscriptionId>/<resourceGroup>/<machine>
# the newest N exports:  --last N   (default 1; consecutive parts go into ONE database in step 0)
# which machines exist:  --list-machines
```

It picks the newest zip by the window end in its name, checks the CSV against the manifest's SHA-256, unzips it and
prints: the zip it used, the window, `complete`, buffer hours and every gap (`buffer_overrun`, `collector_restart`,
`machine_off`, `local_cap`). **Quote the zip name, `complete` and every gap in the report's Capture section**; a gap
is a hole in the data, not an event of the machine (except `machine_off`). The last line `csv: …` lists the CSV
file(s) for step 0. Authentication: a managed identity or Azure CLI login of the agent; on HTTP 403 say that the agent
lacks Storage Blob Data Reader on the container, do not guess.

## Step 0 — Convert the CSV (1–2 terminal commands)

Find this skill's folder: it holds `SKILL.md`, `perfq.py` and `perfmon_csv_to_sqlite.py`. In Azure SRE Agent's
terminal it is usually `…/runtime-content/skills/extended/live/perfmon-triage/`; if unsure:
`find / -name perfmon_csv_to_sqlite.py -path '*perfmon-triage*' 2>/dev/null`. Call it `SKILL_DIR`. Put the CSV
file(s) and the database in one writable work folder (e.g. `/mnt/data` or `/tmp/perfmon`), fetched the way the
request says (e.g. a storage blob).

```sh
python3 "$SKILL_DIR/perfmon_csv_to_sqlite.py" /work/capture.csv /work/capture.db
# several consecutive parts of one capture of the same host go into ONE database:
python3 "$SKILL_DIR/perfmon_csv_to_sqlite.py" /work/part1.csv /work/part2.csv /work/capture.db
```

- The database path is always the **last** argument. The script prints ~15 summary lines (`meta`); read them.
- **One database per host.** Files from different hosts are refused with a list of hosts per file: convert each
  host's files separately (`host1.db`, `host2.db`, …) and triage each database on its own.
- It takes about a minute per 150 MB of CSV and needs disk for a database about 2–3 times the CSV size. If the
  terminal limits a command's run time, start it in the background (`nohup … > convert.log 2>&1 &`) and check
  `convert.log` until it prints `converter: perfmon_csv_to_sqlite.py`.
- Check `meta`: `unparsed_paths`, `bad_cells` and `short_rows` should be 0; `overlap_rows_skipped` counts rows
  dropped where parts overlapped; `timestamp_order` says how the dates were read (force with `--dayfirst` or
  `--monthfirst` if the capture's dates are ambiguous and the first/last times look wrong).

## Schema

| Table / view | Columns |
|---|---|
| `meta` | `key`, `value`: source_file, pdh_header (time zone), rows, counter_columns, first_ts, last_ts, sample_interval_s, interval_histogram, … |
| `samples` | `sample_id`, `ts` (ISO local time) |
| `counters` | `counter_id`, `path`, `host`, `object`, `instance`, `base_instance` (instance without `#N`), `counter`, `n_values`, `n_blank`, `min_value`, `max_value`, `avg_value`, `first_value`, `last_value` |
| `vals` | `counter_id`, `sample_id`, `value` (blank cells are absent) |
| `perf` (view) | `ts`, `host`, `object`, `counter`, `instance`, `value` |

`counters` already holds min/max/avg/first/last per counter: query it before you scan `vals`.

## Setup (top of every Python run)

```python
DB = '/work/capture.db'                  # the database you built in step 0
PERFQ = SKILL_DIR + '/perfq.py'          # this skill's helper file
exec(open(PERFQ).read()); db = open_db(DB)
```

Helpers (object/counter/instance arguments are SQL `LIKE` patterns; `None` = no instance; a spec `X` or `Y` is a
tuple `(object, counter, instance)` that must match exactly one counter):

| Helper | Use |
|---|---|
| `show(db, sql, params=(), limit=20)` | any aggregate query, capped |
| `triage(db)` | the whole Phase 1 checklist in one run, ranked by longest continuous breach; ends with `VERDICT CEILING` |
| `check(db, obj, counter, instance, op, threshold)` | one check per instance: avg, p95, max, %breach, longest breach |
| `events(db, obj, counter, instance, op, threshold)` | breach episodes: start, end, minutes, worst |
| `series(db, obj, counter, instance, start=None, end=None)` | ≤ 30-point time series: avg/min/max per bucket, `peak_at`, `low_at` |
| `movers(db, 'Process', counters=(...), start=None, end=None)` | top instances by growth slope per hour |
| `pid_changes(db, base_instance)` | when the process behind a name changed |
| `top_procs(db, counter, start=None, end=None)` | top processes: average over the whole window, average while present, minutes present |
| `top_at(db, obj, counter, ts_from, ts_to)` | top instances in a window |
| `delta(db, obj, counter, ts_from, ts_to)` | what changed most across a window (e.g. 15 min before onset) |
| `link_test(db, X, Y, bucket_min=60)` | does X still grow after Y stopped? busy vs quiet growth, r, and a `LINK:` line |
| `leak_rate(db, X, LOAD)` | X's growth per 1,000 units of a load rate counter and per hour, per PID segment |
| `is_cumulative(db, counter_id)` | running total or rate? |

## Phase 0 — Orient (1 run)

```python
show(db, "SELECT key, value FROM meta")
show(db, "SELECT host, count(*) FROM counters GROUP BY host")
show(db, "SELECT object, count(DISTINCT counter) counters, count(DISTINCT instance) instances FROM counters GROUP BY object ORDER BY object", limit=60)
print('CPUs', n_cpu(db))
show(db, "SELECT counter, min_value, max_value FROM counters WHERE object='Memory' AND counter IN ('Available MBytes','Commit Limit','Committed Bytes')")
show(db, "SELECT max_value FROM counters WHERE object='Process' AND counter='Working Set' AND instance='_Total'")
```

`n_cpu()` counts per-core instances of `Processor`, or of `Processor Information` (instances `_Total`, `0,_Total`,
`0,0`, …) when the capture has no `Processor` object, as perfmon-blackbox captures do; `triage()` then checks
`Processor Information` the same way.

Record: time range and zone, interval and gaps, host count, objects present (which apps: IIS, SQL, .NET, …), CPU
count, **RAM estimate** (RAM is not a counter: ≈ Available MBytes + Process(_Total) Working Set, or bounded by Commit
Limit), restarts (`System\System Up Time` dropping, or sample gaps).

## Phase 1 — Breadth triage (2–4 runs)

1. `triage(db)`: CPU (total, per core, privileged, DPC, interrupt, queue, context switches), memory (available,
   commit, hard faults, PTEs, paging file), disk (latency, queue, idle, free space), network (output queue, % of
   bandwidth), app queues (ASP.NET, HTTP.sys) and GC. It ranks by the longest continuous breach. Copy its
   `VERDICT CEILING` line into your notes: it caps every verdict word you use later.
2. Resource trends the thresholds miss: `movers(db)` (Private Bytes, Working Set, Handle Count, Thread Count),
   `series(db, 'Memory', 'Pool Nonpaged Bytes')` and `Pool Paged Bytes`, Committed Bytes.
3. Workload shape: the main request/throughput counter of the app objects present (e.g. `ASP.NET Applications\
   Requests/Sec`, `Web Service\...`, SQL batch requests) as a `series()`. You need it to tell load from leak.
4. Process CPU and I/O: `top_procs(db, '% Processor Time')` and `top_procs(db, 'IO Data Operations/sec')`. Rank by
   `avg_whole`; a process present for a few minutes is a short burst, so give its minutes present, not a daily
   average.
5. App health: errors, failures, restarts, queue counters of the app objects present (`check()` or `counters`
   min/max). Mind cumulative counters.

**Rank** in one table, worst first, by impact on usability: how long the machine would feel slow or unresponsive
(longest breach, % of capture) and how severe (saturation, allocation failure, queueing). Columns: rank, area, signal,
worst value and time, longest breach (min), verdict (**critical** / **warning** / **info** / fine). Areas that pass get
one line each. The verdict column never goes above the `VERDICT CEILING`; a trend (leak) without a breach is a
**warning** at most.

## Phase 2 — Depth (2–4 runs per problem, top 1–3 problems)

Take the problems that make the machine hard to use; if there are none, take the top warnings. For each:

1. **Timeline:** `series()` over the capture, then the worst window at a finer bucket; `events()` for episodes. Onset,
   peak (`peak_at`), end (or "still bad at end of capture").
2. **Driver:** which process or resource causes it: `top_at()` in the worst window, `movers()` over the capture,
   `delta()` over the 15 min before onset, `pid_changes()` for the processes involved. Memory: commit vs limit,
   Private Bytes per process, managed heap vs native, pools, Available. CPU: per-process CPU, privileged vs user,
   DPC/interrupt. Disk: which disk, read vs write, which process does I/O, whether paging feeds it.
3. **Load or not:** for any growth, `link_test(db, X, LOAD)` with the workload counter from Phase 1 step 3; for a
   leak tied to load, `leak_rate(db, X, LOAD)` gives the rate per 1,000 requests and per hour, per PID.
4. **Chain:** connect resources in time ("X grows 900 MB/h → Available < 200 MB from 14:20 → Pages Input/sec 2000+ →
   disk sec/Read 0.3 s → queue"). Each link needs a number and a time, and each "because" needs a `link_test()`
   (rule 6). A link you could not test is written as "coincides with".
5. **Alternative:** name one other explanation and the query that rules it in or out.

## Report (final answer, ≤ 60 lines, no raw data tables)

1. **Capture:** the zip used (step −1) with its `complete` flag and gaps, host, time range and zone, interval, gaps or restarts, CPU count, RAM estimate, workload.
2. **Verdict:** one or two sentences: was the machine hard to use, when, and why (or: not in this capture). The
   verdict word respects the `VERDICT CEILING`.
3. **Ranked problems** (at most 5): impact (when, how long), evidence (numbers with their printed times), driver,
   confidence (high / medium / low).
4. **Root-cause chain** for the top problem(s), with the `LINK:` result for each causal step.
5. **Fine / not checked:** areas that passed, counters missing, artifacts you set aside.
6. **Next steps:** what to collect or check next (event logs, a process dump, a longer capture, config).

With several hosts, write sections 1–5 per host, then one short section on what the hosts share.
