# Tests

> **Summary.** Local tests (L) need no Azure and run on every push in CI on synthetic data. Stage tests (T) run in the
> playbook's lab, one command each (`tests/run.sh <ID> [vm1|arc1]`), and must pass on both an Azure VM (`vm1`) and an
> Arc-enabled server (`arc1`). The last stage, T16, is the success criterion: the SRE Agent analyses the latest zip
> and its report is scored against problems planted on purpose.
>
> Status as of 2026-10-12 17:30Z, lab18, package **rc.9** on both machines (rc.8: P46 retry, P49 LOCK-A; rc.9: P54
> RING-A). Green today: T16 and T17 on both, T18b–f, T10d, T10e, T07b (arc1, computed). Open for v1.0.0: T08 and
> T06f part 2 on arc1, the P30 least-privilege trial (2026-10-13), the second-lab fresh-eyes deploy (2026-10-14). The plan with full pass conditions: [test-plan.md](test-plan.md).

## Summary

The tests fall into two groups: **collection** (the input: the recorder, the policies, the storage) and **analysis**
(the value: the agent fetching and analysing the latest capture).

### Analysis

| Test | What | vm1 (Azure VM) | arc1 (Arc) |
|---|---|---|---|
| L01 converter | CSV → SQLite on synthetic data | green (Mac + CI) | — |
| L02 perfq triage | checklist finds planted breaches, ceiling; range mode over two zips (P44) | green | — |
| L04 fetch-latest selection | newest zip, other servers ignored, bad hash rejected | green | — |
| L09 T16 scorer | the scoring rules | green | — |
| T15 agent fetches and converts | the agent's own terminal, skill v2.1 | green | green |
| T17 range mode (P44) | leak + CPU split over two zips; the agent asked for the range | **green** (rc.9, skill v2.2, 2026-10-12): load 16:20Z, boundary export 16:36:40Z; **100/100**, leak + CPU found, both zips of the range named | **green** (same run, boundary 16:36:26Z): **95/100**, leak + CPU found, both zips named; R1 −5: unmarked causal claims ("CPU saturated because bbcpu…", "MsSense … driving Committed Bytes") without a `LINK:` |
| **T16 agent report, scored** | planted problems vs the agent's report | **green** (run 5b, rc.8: 100) | **green** (run 5, rc.8: 100) |

**T16 history** (pass = score ≥ 80, every planted problem found, nothing invented; since P43 only the memory leak and the CPU burst are planted):

| Run | Package | Score | Found | Missed | Why |
|---|---|---|---|---|---|
| 1 | rc.1 | 85 → FAIL | leak, CPU, NIC (+ a memory episode) | 30-s stalls; disk | stalls are below the skill's 5-min ceiling by design → OPEN-2 closed, stalls removed (P34); disk plant never ran (P39) |
| 2 | rc.3 | 85 → FAIL | leak, CPU, NIC (+ the memory episode) | disk | the disk plant never ran (P39); the agent rightly reported the disk as fine |
| 3 | rc.5 | not valid | leak (622 MB/h), and a real full T: drive | CPU, disk, NIC | the server's own 4-hourly export ran at 16:07 between the plants and the finish, so the latest zip held only 16:07–16:24; the agent analysed that zip correctly. T16 now refuses a window cut by a scheduled export, and takes the longest agent message as the report |
| 4 | rc.5 | **100 → PASS under P43** (was 70 under the old scope) | leak (bbleak), CPU burst (bbcpu); plants verified in the capture: CPU > 85 % for 11.8 min, bbleak growing for 69 min to 797 MB | — | P43: only memory and CPU are planted and required. The run's disk plant had misfired (T: full); the memory picture in that run was partly bbdisk's error loop |
| 5 | rc.8 (arc1) | **100 → PASS** | leak (bbleak), CPU burst (bbcpu); window 10:37–11:26Z, no scheduled export inside it; zip seq 24 uploaded with the himds identity | — | the agent also listed one C: read-latency sample (133 ms, 0.2 min) as **info**, correctly not a finding; disks were on the template SKUs that day, so not an HDD artefact (P51). vm1: row 5b |
| 5b | rc.8 (vm1) | **100 → PASS** | leak (bbleak), CPU burst (bbcpu); window 12:23–13:13Z, no scheduled export inside it; zip seq 43 uploaded with the imds identity | — | disk latency reported as fine (9.3 ms max read). **T16 green on both machines** |

### Collection

| Test | What | vm1 (Azure VM) | arc1 (Arc) |
|---|---|---|---|
| L03 masker | lab-side name masking | green | — |
| L05 export logic (Pester, 5.1) + lint | merge, gaps, validation, export end to end | green (lab dc + CI Windows runner) | — |
| L06 repo safety (scrub) | no secret, no real name | green | — |
| L07 template, ASCII, no lab names | the 36 + groups, shipped files | green | — |
| L08 policy generator | definitions, hashes, ABAC condition | green | — |
| T01 package builds, local compliance | build + apply on a clean box | green (dc; build also in CI) | — |
| T02 policy definitions | type, URL, hash, parameters | green | green |
| T03 policy assignments and roles | exactly the designed roles | green | green |
| T04 guest assignment Compliant | all six resources | green | green |
| T05 extension/agent, identity, no pwsh | | green | green (IMDS blocked) |
| T06 collector running as configured | counters, format, size, interval | green | green |
| T06b never exceeds, really wraps | 16 MB ring at 1 s | wrap proven by the 512 MB runs (P34) | green |
| T06c changed MaxSizeMB reaches the server | 16 → 32 MB | pending | green (re-create export complete, 0 gaps, 260/260 rows; file grew to 19.4 MB, ≤ 32 MB) |
| T06d changed interval reaches the server | 10 → 1 s and back | pending | green (rc.6: 1 → 10 s, clean manifest, P37) |
| T06e capacity misfit reported | R6 NonCompliant with the numbers | pending | green |
| T06f G3 without IIS: no storm; auto-detect | | storm part green (dc, P27); auto-detect pending | pending |
| T07 scheduled tasks | | green | green |
| T07b buffer hours measured | | green (21.7 h at 10 s) | **green, computed** (P56, 2026-10-12): 56,562 bytes/sample measured by the 12:07Z export (241 samples, 40 min, no planted load, 94 processes); 512 MB at 10 s = **26.4 h** (P27 formula: 56,440 at 98 processes, 26.4 h), ≥ 6 h |
| T08 reboot | | green (rc.7: boot ring kept, Boot task after boot, only a 67-s machine_off gap) | **red** (rc.9, 2026-10-13 05:00Z: `az vm restart`, clean shutdown (event 1074, 6006), collector Running and Boot task result 0 after boot, but the pre-reboot ring (6 min, 2 MB) is unreadable: kept in `pending\`, and the export shows a 405-s `collector_restart` gap instead of the samples plus a `machine_off` gap. Fixed by rc.10 (P62). **rc.10: green on both**, 2026-10-13: arc1 restart 08:58Z and vm1 09:03Z, the pre-reboot pieces readable and exported, the only gap `machine_off` (51 s and 69 s), the first sample after the boot has an empty rate value; evidence `rc10-T08-*.txt`) |
| T09 two exports, no gap, no overlap | | green | green |
| T10 roll gap ≤ 10 s | | green | green |
| T10b overrun detected | | pending | green |
| T10c failed upload, no gap | | green (storage blocked by a hosts entry: the lab GPO turns the firewall off) | — |
| T10d failed upload retries in the same run (P46) | block lifted after ~3 min: uploaded on attempt 2, no gap | **green** (rc.8, 2026-10-12: attempt 1 failed 08:18:22Z, uploaded on attempt 2 08:23:22Z, task result 0, seq 30 complete and continuous) | — |
| T10e unreadable ring reported and removed (P54) | 3 exports: kept, kept, deleted + event 2003 + `unreadable_ring` gap | **green** (vm1, rc.9, 2026-10-12, evidence; the script's first run reported FAIL on two test-scope defects, since fixed) | — (no cut ring on arc1; the logic is covered by L05 on synthetic rings) | vm1's real ring 20261011-191221-00-boot.blg: read 1 of 3 at 15:40:14Z (rc.9's first export, before the test started), 2 of 3 at 15:43:24Z, 3 of 3 at 15:43:48Z → deleted, event 2003, manifest seq 46 complete=False with gap 2026-10-11 11:43:47.611 .. 19:02:29.734 (26,322 s, `unreadable_ring`), seq 47 clean (gap carried once). Script fixed: export until the ring is gone, whole log tail, last 3 manifests (it had expected all 3 reads after its start and only the latest manifest) |
| R1 resilience: storage unreachable for real (lab DNS down when the lab's auto-shutdown stopped dc) | the 19:03Z export failed ("remote name could not be resolved"), state unchanged; the next export (19:12Z) covered 18:15:08–19:12:47 in one zip, both rings, complete, 0 gaps: nothing lost. Up to rc.7 a failed export waited for the next scheduled run (ExportEveryHours); since rc.8 it retries in the same run (P46, T10d) | — | green |
| T11 blob path, hashes, identity | | green (IMDS) | green (HIMDS) |
| T12 cannot write elsewhere | | green | green |
| T18a package from GitHub (P45) | the release asset (default) | green (T02, T04, T07–T12) | green (same) |
| T18b package from storage, Arc (P45, P48) | system identity, reader on the package container, same hash, stays so over two refresh cycles | — | **green** (2026-10-12): storage download with the system identity; three first-party re-sync PUTs (10-11 21:22Z, 21:38Z; 10-12 07:01Z) each followed by a Compliant pull, never a flip to GitHub (P48 holds); T18 PASS after the last |
| T18c package from storage, Azure VM (P45) | then back to GitHub | **green** (2026-10-12, rc.8): switched by the P48 procedure; first storage download 09:21Z (403s 08:53–09:21Z until the remediation granted the reader role, old config kept); stayed in storage mode across a service PUT (09:27Z); back to GitHub 09:46Z, Compliant 10:28Z; no flapping in 7 service PUTs; T18 vm1 storage and github PASS | — |
| T18d storage mode without the reader role (P45) | no download, old config keeps running | — | **green** (arc1, P56, 2026-10-12): reader role removed, assignment moved to rc.9 (re-PUT 12:53:26Z) with rc.8 in the container: downloads 12:56:58Z and 13:01:59Z → 403, assignment Pending / "Failed to download assignment" (never Compliant), collector Running on rc.8. Also: an unchanged re-PUT does not download again (stays Compliant without the role, P56); a service re-sync put rc.8 back at 12:58Z (P55: scan first) |
| T18e a different zip under the same name (P45) | rejected by the hash, old config keeps running | — | **green** (arc1, P56, 2026-10-12): reader role back, assignment pins rc.9 (re-PUT 13:19:44Z), the container holds rc.8 under the same name: every download (13:22:11Z, 13:32:16Z) "Failed to validate package" (hash 8ada… ≠ the pinned one), assignment Pending, collector Running on rc.8. One read at 13:30Z returned Compliant with the old hash (a stale report), the next read 13:31Z Pending with the rc.9 hash. **Restore** (rc.9 into `packages`, re-PUT 13:33:31Z): arc1 on rc.9, `T18.sh arc1 storage` PASS ~15:35Z (own identity, reader only on the container, export works); vm1 on rc.9 from GitHub, `T18.sh vm1 github` PASS |
| T18f shared key disabled, no SAS (P45) | storage download + exports + agent fetch on an account with shared key off | **green** (2026-10-12, rc.8: shared key off, public access off, no key/SAS in code; storage download T18c, T11, T15) | **green** (same run: T18 storage, T11) |
| T13 lifecycle rule | | green | — |
| T14 storage private | | green | — |

## Local tests

- **L01 converter.** A synthetic PerfMon CSV (made by `tests/synth/make_capture.py`) converts with the right row and
  column counts, no bad cells; day-first and month-first dates read alike; two overlapping parts merge without repeats.
- **L02 perfq.** `triage()` finds the planted CPU and disk breaches with their start times and minutes, reads the CPU
  count from `Processor Information`, prints the right VERDICT CEILING; `movers()` finds the leak and its rate.
- **L03 masker.** A synthetic mapping masks the names; a denylist hit fails without printing the name.
- **L04 fetch-latest.** On a synthetic listing it picks the newest zip of a server, ignores other servers (including
  `synth010` next to `synth01`) and non-capture blobs, and rejects a zip whose CSV hash does not match its manifest.
- **L05 export logic.** Pester 5 under Windows PowerShell 5.1: CSV merge without overlap, validation, gap causes,
  blob path, template filling, collector and task comparison, ACL check, capacity check, and the whole export on
  synthetic `.blg` files with a mocked upload (state moves only after a good upload; a failed upload leaves it). Plus
  PSScriptAnalyzer with the Windows PowerShell 5.1 compatibility rules on every server script.
- **L06 repo safety.** The scrub check's self-test and a clean tree.
- **L07 template and shipped code.** The template holds exactly the 36 counters and only the two placeholders; the
  three groups have 12/2/6 counters; shipped files are pure ASCII and name no lab.
- **L08 policy generator.** Two definitions, one resource type each, the same parameters, the parameter hash in step
  with the configuration parameters, the package hash pinned, and the ABAC condition evaluates to the exact expected
  text.
- **L09 scorer.** A report naming both planted problems scores 100; a missing CPU burst, a wrong leak rate or an
  invented problem (also a network or disk problem claimed) lose points; a negated cause or an area called fine does not.

## Stage tests (lab)

- **T01** builds the package and runs it on a clean Windows box: NonCompliant before, all six resources Compliant after.
- **T02** both definitions exist with the right type, package URL, hash, version and default parameters.
- **T03** both assignments exist with a system identity and exactly the designed roles (including the delegation
  condition); the Arc server's Azure VM and the build box are outside the VM policy.
- **T04** the server's guest assignment is Compliant, recently checked, with all six resources Compliant.
- **T05** the Azure VM has the extension and its identity; the Arc server is Connected, agent ≥ 1.10, identity, IMDS
  blocked; neither has PowerShell 7 on its path.
- **T06** the collector runs with exactly the expected counters (36 + G1 + G2 + present G3), binary circular, the
  configured interval and size, and its file grows.
- **T06b/T10b** with a 16 MB buffer at 1 s and exports suspended: the file reaches 16 MB and never exceeds it; the next
  export is marked incomplete with a `buffer_overrun` gap, the ring is marked wrapped, an event-log warning exists.
- **T06c** MaxSizeMB 16 → 32 reaches the server: the file grows past 16 MB, stays ≤ 32 MB, and no samples are lost.
- **T06d** a new interval reaches the server: the newest samples step by the new interval.
- **T06e** a buffer too small for the export window turns the assignment NonCompliant with the numbers in the reason.
- **T06f** G3 counters on a server without IIS cause no event storm (one error per missing counter at start, nothing
  per sample); G3 appears by itself after IIS is installed.
- **T07** exactly the Boot, Export and (since rc.10) Roll tasks exist as designed; each runs on demand with result 0.
- **T07b** the measured buffer hours hold at least 1.5 × the export window.
- **T08** after a reboot the collector runs again, the ring from before the reboot is kept, and the next export holds
  it with only a `machine_off` gap. A shutdown that leaves the open piece unclosed loses at most that piece (≤ 15 min
  since rc.10, P62), reported as a gap: it is not a test failure of the product but the accepted loss.
- **T09** two exports in a row: each zip has one CSV and a manifest with matching hash, PDH header, the 36 counters,
  the expected number of rows; the second starts right after the first (no gap, no overlap).
- **T10** the export's collector restart lasts ≤ 10 s and leaves no hole.
- **T10c** with storage blocked the export fails and changes nothing; once unblocked one zip covers both windows.
- **T11** the newest blob is at the expected path, its Content-MD5 and sha256 metadata match, and it was uploaded with
  the server's own identity (IMDS on the VM, HIMDS on Arc).
- **T12** with its own token the server cannot write into another server's folder, a look-alike folder or outside any
  folder, cannot list, read or delete; it can write its own folder.
- **T13** the lifecycle rule deletes after 30 days. **T14** the storage is private (no anonymous, no shared key, TLS
  1.2, public network access disabled, approved private endpoint).
- **T15** the agent, in its own terminal, fetches the newest zip with the skill, checks the hash and converts it with
  zero errors.
- **T16** a memory leak and a CPU burst are planted for 45 minutes ([load-generation.md](load-generation.md)); the
  agent, asked in a new thread to analyse the latest capture, names the zip, finds the leak (rate within 40 %) and the
  CPU burst at its time with its driver, invents nothing (a disk or network problem claimed counts as invented), and
  keeps to the skill's rules. The plants are verified in the capture first. Pass = score ≥ 80, both found (P43).

## T08 on arc1, red on rc.9: why the pre-reboot ring could not be read (research, 2026-10-13)

Research only (Emre via the vezir, 08:35 +03): logs read on arc1 and vm1, `relog` run on a **copy** of the ring (the
original's SHA-256 was the same before and after the copy), no reboot, no test run, no package change. Evidence (masked):
`files/test-runs/261013-lab18/` (`T08-arc1.txt`, `research-*.txt`). **[O]** = observed, **[L]** = Learn, **[G]** = guess.

**What the file is.** `pending\20261013-050116-00-boot.blg`, 2,097,152 B, last written 05:00:23Z. `relog -q` on
the copy: "Unable to read counter information and data from input binary log files", exit 0xC0000BF7 [O], which is
`PDH_BINARY_LOG_CORRUPT` [L: *Performance Data Helper Error Codes*]. A running circular `.blg` cannot be read
either, not even as a copy (P21 [O]). So the ring was **never closed**: PLA did not stop the collector before the OS went down.

**What happened at the shutdown.** `az vm restart` (issued by T08) produced a clean, planned shutdown: 05:00:00 event
1074 "CleanShutdown by wvchelper … Shutdown Type: shutdown", 05:00:32 event 6006, 05:00:33 Kernel-Power 109, boot
05:00:39 [O]. Normal reboot = 1074 then 6006/6009; unexpected = 41/6008 [L: *Troubleshoot unexpected reboots using
system event logs*]. No 41/6008 here.

**The difference from every shutdown that left a readable ring** (7 clean shutdowns on lab18 since 10-11 [O]):

| Shutdown | Preshutdown phase (1074 → services stop) | 7043 "did not shut down properly after a preshutdown control" | PLA Operational 1005 "set stopped" | Ring |
|---|---|---|---|---|
| arc1 10-11 21:45, 10-12 21:46; vm1 10-11 18:22 (rc.7 T08), 19:01, 21:45, 10-12 21:46 (deallocate, auto-shutdown, restart) | ≈ 16 s | Defender ATP (`Sense`) only | **yes**: PerfmonBlackbox and the Azure agent's own sets (GAEvents, RTEvents), at the second the services stop | readable |
| **arc1 10-13 05:00 (T08)** | **≈ 32 s** | `Sense` (05:00:16) **and Windows Update** (05:00:32) | **none, for any set**, although the PLA service logs "stopped" at 05:00:32.652 | **unreadable** |
| vm1 10-11 19:10 (P54's ring) | — (no 1074) | — | none | unreadable (41/6008: an abrupt stop) |

At 04:59:21, 39 s before the restart, Windows Update had started installing a Defender security-intelligence
update (KB2267602) [O]. arc1 had booted at 04:48 after the night deallocated it [O].

**How shutdown treats services [L: *Service Control Handler Function*; *SERVICE_PRESHUTDOWN_INFO*].** Services that
accept PRESHUTDOWN get it first; the SCM waits until each stops or its preshutdown timeout ends (default 10 s since
build 15063). Then SERVICE_CONTROL_SHUTDOWN goes to the services that accept it, and after the shutdown time limit
(`WaitToKillServiceTimeout`; arc1: 5000 ms [O]) "system shutdown proceeds regardless of whether service shutdown is
complete". Learn does not say how PLA closes a running counter log at shutdown, and whether it does so in
PRESHUTDOWN or SHUTDOWN (nothing found).

**Likely cause [G, strongest supported].** PLA closes its running sets as part of the normal service shutdown (1005
for every set, every time, at the moment the services stop). On 05:00 the Windows Update preshutdown overran (7043),
the preshutdown phase took twice as long, and PLA went to "stopped" 16 ms after the phase ended without stopping
any set; the circular file was left open, unclosed, so `relog` sees `PDH_BINARY_LOG_CORRUPT`. Why PLA skipped its set
stop is not documented [G: the shutdown ran out of time after the long preshutdown]. Not the cause [O]: `az vm restart` as such
(the same "CleanShutdown by wvchelper" path left readable rings 6 times), or Arc (arc1 is an Azure VM with the Arc
agent; the shutdown path is the Azure guest shutdown, `himds` stopped normally; an on-premises Arc server's shutdown
path was not observed). Not excluded: the ring's age (6 min here; arc1's readable nightly ring had run ≈ 1.7 h since
the 20:07 roll; vm1's ages were not measured) [G: unlikely, since no set at all was stopped, not only this one]. One case only: the Windows Update link is a correlation, not a proof.

**Why it matters [G].** Reboots during or right after Windows Update (patch nights) are exactly when the preshutdown
phase is long. The loss is bounded by the time since the last roll: here 6 min because an export had run at 04:54;
it can be up to `ExportEveryHours` (4 h). It is never silent: the hole is in the next manifest (here as
`collector_restart`), and after 3 failed reads RING-A deletes the ring and reports `unreadable_ring` (P54).

**Docs and tests this contradicts (listed, not resolved):**
1. `docs/operations.md` (`unreadable_ring` row) and `docs/design.md` (`unreadable_ring`): "a ring cut by an abrupt
   stop (power loss, forced restart)". Observed: a clean, planned restart can leave one.
2. `decisions.md` P54: "A normal deallocate … left a readable ring, so only abrupt stops cause this."
3. `docs/test-plan.md` T08 and this file's T08 description: "the next export holds it with only a `machine_off` gap";
   not met on arc1.
4. `docs/design.md` §gaps: `machine_off` when "the hole lines up with … a boot time". The 04:54:32–05:01:17 hole
   contains the 05:00:39 boot but is labelled `collector_restart`; the code labels `machine_off` only when the
   earlier **readable** part was closed by a boot (`PerfmonBlackbox.Common.ps1`), and the unreadable ring is not a part.

**Salvage attempts (Emre via the vezir, 2026-10-13, research only).** Every variant ran on its own fresh copy of the
ring on arc1; the original's SHA-256 was the same before and after (`research-salvage-arc1.txt`). Only documented
tools: `relog` [L: *relog*, Windows commands] and `Import-Counter` (Windows PowerShell 5.1, PDH). Machine time zone UTC.

| Variant | Result [O] |
|---|---|
| `relog -q` | 0xC0000BF7, "Unable to read counter information and data from input binary log files" |
| `-b 04:54:43 -e` +1, +2, +3, +5 min, and up to 05:00:20 (csv) | 0xC0000BF7, 0 rows, each |
| `-b 04:40 -e 04:56` (begin before the ring) | 0xC0000BF7, 0 rows |
| `-t 2`, `-t 30` | 0xC0000BF7, 0 rows |
| `-c "\Memory\Available MBytes"` (one counter) | 0xC0000BF7, 0 rows |
| `-f bin`, `-f tsv` | 0xC0000BF7, no output |
| `Import-Counter -Summary`; `-Counter`; `-StartTime/-EndTime` (3 min) | same PDH message, no samples |

**No variant recovers a single sample.** Even `-q`, which only lists the counters and the time range, fails: the PDH
reader rejects the file before any time or counter filter applies [O]. The time bounds (`-b`/`-e`) select records
in a file PDH can open [L: *relog*: "the beginning time to copy the first record"]; they do not get past a file it
cannot open [G]. So a time-bounded relog is **not** a usable export fallback for this kind of ring: it would add
retries and no data. Reading the raw records ourselves would need the undocumented `.blg` layout (out of scope).

## RELOG-DENE: one multi-input relog instead of the per-piece join? (side test, 2026-10-13)

Emre: "if relog can merge, I prefer it (Windows' own tool), but an unreadable .blg must never be fed into it." Candidate:
`relog -q` per piece as a probe (unreadable or < 2 samples → the RING-A path as today), then **one**
`relog <good pieces> -f csv` for the merge. Tested on dc with the lab's own short probe sets (2 counters vs 3, 1 s and
2 s, sequential, overlapping and identical files) in `C:\BbDev`, no product file touched. Evidence:
`files/test-runs/261013-lab18/research-relog-merge-dc.txt`. rc.10 is unchanged.

| Question | Result [O] |
|---|---|
| (1) pieces with different counter lists | works: **union header**, blank cells where a piece lacks a counter, rows in time order whatever the input order (A+B = B+A) |
| (2a) identical pieces (A + a copy of A) | **wrong**: 8 rows instead of 7 (the first timestamp twice) and the rate counter (`% Processor Time`) has values that differ from the single-file relog of A (0 / 2.31 where A alone gives 4.46 / 0.19) |
| (2b) overlapping pieces (two sets 3 s apart, 1 s) | rows interleaved by time (27 = 12 + 15, no de-duplication); the second set's rate values come out **0** |
| (2c) a 2 s piece then a 1 s piece | both cadences kept as recorded (no resampling) |
| **rate counters across a piece boundary** | **differs from the per-piece relog**: per piece, the first sample of every piece has an empty rate value (a rate needs two samples); merged, relog **computes** that first value from the previous piece's last sample (A+B: 15.8 % over the 5 s between the pieces; A+C: 7.9 % over 22 s) |
| (3) per-piece facts from `-q` + file metadata | `-q` gives samples, begin and end per piece (**to the second**, no milliseconds); interval = (end − begin)/(samples − 1) (P37), wrapped = file size vs `MaxSizeMB` (P40), bytes per sample = size/samples (R6): all available. The source piece of each row must then be **inferred** from the second-resolution begin/end ranges (today it is exact: each row comes from its own piece's CSV) |
| (4) `-b` and no overlap with `last_ts` | `-b` takes whole seconds and is **inclusive**: `-b` = the second of `last_ts` re-includes the `last_ts` sample; `-b` = that second + 1 starts strictly after it (here: first row 2 s after). So `-b ceil(last_ts)` keeps no overlap at intervals ≥ 1 s; the first exported sample's rate value is empty, as in the per-piece path |

**Reading [G].** The merge works for the plain case. The real difference is the rate counters at the piece boundaries:
- **Across a roll** (a few seconds, same boot, the raw counters keep counting), relog's computed value is a true
  average over the boundary. The per-piece path leaves it empty instead, and with the 15-min roll (rc.10) that is one
  empty rate sample per piece: about 1 in 90 rows at 10 s.
- **Across a restart** of Windows the raw counters start again from zero, and what relog computes there is not tested.
  It would need a reboot test.
- **Duplicates or overlaps** make relog produce wrong rate values, without an error. The pieces never overlap by
  design, so the merge would also need a guard that refuses overlapping ranges, known only to the second.
- If the merged call fails anyway, the export needs the per-piece path as a fallback, so there would be **two** paths
  to maintain.

## rc.10 on lab18 (2026-10-13)

Rollout per P55 (definitions → scan → remediation): vm1 on 1.0.9 Compliant 08:15Z, arc1 08:50Z.

| Test | vm1 | arc1 |
|---|---|---|
| T04 (7 resources) | green; R6: ring ≈ 22 h, LocalKeepMB ≈ 44 h | green; ring ≈ 26.5 h, LocalKeepMB ≈ 53 h |
| T07 (Boot, Roll, Export) | green; the roll took 2.8 s | green; 2.6 s |
| T08 | green (see the T08 row) | green |

When arc1's rc.9 ring (`20261013-050116-00-boot.blg`) was deleted at its third failed read (08:57Z, RING-A), its
`unreadable_ring` gap was reported as 2026-10-11 12:34 → 2026-10-13 05:00. That span is too long: it is the
CreationTime problem fixed in rc.10 (P62 item 4), and the piece had been moved by rc.9. T09, T10, T11, T19 and T15 run
on rc.11, which changes the merge (P63).

## rc.11 on lab18 (2026-10-13)

rc.11 (1.0.10, the relog merge per segment and DST-A, P63). Rollout per P55: vm1 (GitHub mode) Compliant on 1.0.10
at 10:48Z. arc1 (storage mode) did **not** apply it in the first 70 minutes (see below).

| Test | vm1 | arc1 |
|---|---|---|
| T04 (7 resources) | green (re-run at 11:59Z; the first run at 11:51Z failed only on report age, 63 min > 30) | pending |
| T06 | green | pending |
| T07 (Boot, Roll, Export) | green: 12 pieces merged in **1 relog call**, 990 rows, 0 gaps | pending |
| T08 (rate across the boot, P63 a) | green: the restart at 11:53Z split the export into **2 relog calls** (the boot segments); only gap `machine_off` 64 s; `rate-after=empty` (no rate computed across the boot) | pending |
| T09, T10, T11 | green | pending |
| T19 (15-min roll merged) | green: one zip from 3 roll pieces + the export piece, 233 rows, 0 gaps, `pending\` empty | pending |

**arc1 rollout (open).** The rc.11 remediation (10:39Z) wrote the guest assignment, but the deployment failed on the
package-reader role assignment (`RoleAssignmentExists`: the reader assignment exists under another name, most likely
the one restored by hand after T18d, P56; the rc.10 remediation at 08:00Z failed the same way). The agent downloaded the
container's zip (already rc.11) at 10:56Z while the assignment still carried the rc.10 hash (validation failed,
11:01–11:17Z); at 11:22Z the assignment carried 1.0.10 but with `assignmentType` **Audit** (agent: `custom_inguest`),
so the agent only tests (`Common.ps1 differs from the package`) and never applies. The definition says
ApplyAndAutoCorrect. A second scan + remediation (P55) is running.
