# The analysis: what the SRE Agent does with a capture

> **Summary.** This is the part that gives the value. Ask the SRE Agent about a server; its `perfmon-triage` skill
> fetches the server's latest capture from your storage, checks it, converts it to SQLite, runs a fixed checklist over
> every resource, digs into the worst problems, and writes a ranked report with times, drivers and next steps, quoting
> any gap in the capture. It follows strict rules: no raw data, a verdict ceiling, and no cause without a test in time.
>
> Draft until v1.0.0. Skill: [`skill/perfmon-triage/SKILL.md`](../skill/perfmon-triage/SKILL.md) (v2.1).

## How to ask

In a new thread of the agent:

> *Analyse the latest PerfMon capture of `<server>`. The captures are in the storage account `<name>`.*

Variations: "the last 3 captures of `<server>`" (consecutive zips are merged into one database), "what happened on
`<server>` between 14:00 and 15:00" (the agent picks the capture and narrows the window), "which servers have captures"
(`--list-machines`). The trigger is manual in v1.0.0; an Azure Monitor alert as trigger is decided for phase 2.

## What the skill does, step by step

1. **Fetch** (`perfmon_fetch_latest.py`): list `perfmon/<sub>/<rg>/<server>/`, pick the newest zip by its window end,
   download it, check the CSV against the manifest's SHA-256, unzip. Read access comes from the agent's identity.
2. **Convert** (`perfmon_csv_to_sqlite.py`): the wide PerfMon CSV becomes an indexed SQLite database (samples,
   counters with min/max/avg, values); it reports unparsed paths, bad cells and short rows (all 0 when healthy).
3. **Orient**: time range and zone, interval, gaps and restarts, CPU count (from `Processor Information`), a RAM
   estimate, which applications are present.
4. **Breadth** (`triage()`): a fixed checklist over CPU, memory, disk, network, application queues and .NET GC, ranked
   by the longest continuous breach, ending with a **VERDICT CEILING** line; plus growth trends (`movers()`), pools,
   per-process CPU and I/O.
5. **Depth** (top 1–3 problems): timeline and worst window, the driving process (`top_at`, `delta`, `pid_changes`),
   load or not (`link_test`, `leak_rate`), the chain from cause to symptom, one alternative explanation.
6. **Report** (≤ 60 lines): capture (with the zip, `complete` and every gap), verdict, ranked problems, root-cause
   chain, what is fine or not checked, next steps.

## What a report looks like

A verbatim excerpt from the lab (T16 run 2, synthetic `bb*` load; subscription masked). Note the disk is reported
fine: in that run the disk plant had failed (decisions P39), and the agent correctly saw no disk problem but a memory
episode instead.

```text
| **Zip**      | `perfmon/<sub>/rg-lab18/vm1/2026/10/11/vm1_20261011-134118_20261011-145348.zip` |
| **Complete** | True — no gaps |
| **Window**   | 2026-10-11 13:41:18 – 14:53:48 (72.5 min), UTC+00:00 |
| **Interval** | 10 s, 436 samples |

| Rank | Area | Signal | Worst value & time | Longest breach | Verdict |
| 1 | CPU | `% Processor Time (_Total)` > 85% | 100% at 13:52:28 | 11.8 min (13:51:58–14:03:38) | critical |
| 4 | CPU / kernel | `% Privileged Time (_Total)` > 30% | 43.3% at 14:32:28 | 6 min (14:26:58–14:32:58) | warning |
| 5 | Memory leak | `bbleak` Private Bytes linear growth | 64 MB → 816 MB (643 MB/h) over 70 min | No threshold breach yet | warning |
| — | Disk, Network, Paging File, PTEs, Context Switches | All within thresholds | — | — | fine |

Episode A — CPU saturation (13:51–14:03), driver: `bbcpu`
- `bbcpu` (PID 7832) appeared at 13:51:48 and ran ~12 min.
```

The planted truth for that run: CPU burst 13:51:45–14:03:46 by `bbcpu`; leak 600 MiB/h by `bbleak` (the report's
643 MB/h is within the scorer's tolerance); network burst 14:26:45–14:32:46 by `bbnic` (reported through the kernel
time it caused).

## The rules it keeps

- **No raw data** in the thread: every query is an aggregate, every printout capped.
- **Evidence = number + time + duration**, quoting the exact sample time the helper printed.
- **Verdict ceiling**: if no check breached for 5 continuous minutes, nothing may be called critical; trends are at most
  warnings. "No critical problem" is a valid answer.
- **A cause needs a test in time** (`link_test`: does X still grow after Y stopped?). Without it the report says
  "coincides with", not "caused by".
- **No invented problems**: the T16 scorer checks this.

## Known limits (v1.0.0)

- **Short recurring stalls** (for example 20–40 s every half hour) are treated as blips below the 5-minute ceiling and
  are not flagged as a problem (OPEN-2, closed for v1.0.0 by Emre; decisions P34).
- **Counters not in the set**: no `PhysicalDisk`, no `% DPC Time` / `% Interrupt Time`, no HTTP.sys queues; on servers
  without IIS/ASP.NET the web counters (G3) are absent, so request rates and app queues are "not checked".
- Process instance names are reused by Windows (`svchost#3`); the skill follows PIDs, but a report about a short-lived
  process can still name the instance only.
- The analysis is as fresh as the latest export (default every 4 hours); a problem happening now is in the next zip.

## How it is proven

- **T15**: the agent, in its own terminal, fetches the newest zip of a server with the skill, checks the hash and
  converts it with zero errors (green on the Azure VM and the Arc server).
- **T16**: known problems are planted on the server for 70 minutes ([load-generation.md](load-generation.md)); the agent
  is asked in a new thread; its report is scored against the ground truth ([tests.md](tests.md#analysis)).
