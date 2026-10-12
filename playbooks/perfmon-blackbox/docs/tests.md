# Tests

> **Summary.** Local tests (L) need no Azure and run on every push in CI on synthetic data. Stage tests (T) run in the
> playbook's lab, one command each (`tests/run.sh <ID> [vm1|arc1]`), and must pass on both an Azure VM (`vm1`) and an
> Arc-enabled server (`arc1`). The last stage, T16, is the success criterion: the SRE Agent analyses the latest zip
> and its report is scored against problems planted on purpose.
>
> Status as of 2026-10-12, lab18 (down since 2026-10-11 21:45Z), packages rc.1–rc.7; rc.8 (P46) not built yet. The plan with full pass conditions: [test-plan.md](test-plan.md).

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
| T17 range mode (P44) | leak + CPU split over two zips; the agent asked for the range | pending (skill v2.2; range mode green locally in L02) | pending |
| **T16 agent report, scored** | planted problems vs the agent's report | see history below | pending |

**T16 history** (pass = score ≥ 80, every planted problem found, nothing invented; since P43 only the memory leak and the CPU burst are planted):

| Run | Package | Score | Found | Missed | Why |
|---|---|---|---|---|---|
| 1 | rc.1 | 85 → FAIL | leak, CPU, NIC (+ a memory episode) | 30-s stalls; disk | stalls are below the skill's 5-min ceiling by design → OPEN-2 closed, stalls removed (P34); disk plant never ran (P39) |
| 2 | rc.3 | 85 → FAIL | leak, CPU, NIC (+ the memory episode) | disk | the disk plant never ran (P39); the agent rightly reported the disk as fine |
| 3 | rc.5 | not valid | leak (622 MB/h), and a real full T: drive | CPU, disk, NIC | the server's own 4-hourly export ran at 16:07 between the plants and the finish, so the latest zip held only 16:07–16:24; the agent analysed that zip correctly. T16 now refuses a window cut by a scheduled export, and takes the longest agent message as the report |
| 4 | rc.5 | **100 → PASS under P43** (was 70 under the old scope) | leak (bbleak), CPU burst (bbcpu); plants verified in the capture: CPU > 85 % for 11.8 min, bbleak growing for 69 min to 797 MB | — | P43: only memory and CPU are planted and required. The run's disk plant had misfired (T: full); the memory picture in that run was partly bbdisk's error loop |

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
| T07b buffer hours measured | | green (21.7 h at 10 s) | pending |
| T08 reboot | | green (rc.7: boot ring kept, Boot task after boot, only a 67-s machine_off gap) | pending |
| T09 two exports, no gap, no overlap | | green | green |
| T10 roll gap ≤ 10 s | | green | green |
| T10b overrun detected | | pending | green |
| T10c failed upload, no gap | | green (storage blocked by a hosts entry: the lab GPO turns the firewall off) | — |
| T10d failed upload retries in the same run (P46) | block lifted after ~3 min: uploaded on attempt 2, no gap | pending (rc.8) | — |
| R1 resilience: storage unreachable for real (lab DNS down when the lab's auto-shutdown stopped dc) | the 19:03Z export failed ("remote name could not be resolved"), state unchanged; the next export (19:12Z) covered 18:15:08–19:12:47 in one zip, both rings, complete, 0 gaps: nothing lost. Up to rc.7 a failed export waited for the next scheduled run (ExportEveryHours); since rc.8 it retries in the same run (P46, T10d) | — | green |
| T11 blob path, hashes, identity | | green (IMDS) | green (HIMDS) |
| T12 cannot write elsewhere | | green | green |
| T18a package from GitHub (P45) | the release asset (default) | green (T02, T04, T07–T12) | green (same) |
| T18b package from storage, Arc (P45, P48) | system identity, reader on the package container, same hash, stays so over two refresh cycles | — | **green** (2026-10-12): storage download with the system identity; three first-party re-sync PUTs (10-11 21:22Z, 21:38Z; 10-12 07:01Z) each followed by a Compliant pull, never a flip to GitHub (P48 holds); T18 PASS after the last |
| T18c package from storage, Azure VM (P45) | then back to GitHub | pending | — |
| T18d storage mode without the reader role (P45) | no download, old config keeps running | pending | — |
| T18e a different zip under the same name (P45) | rejected by the hash, old config keeps running | pending | — |
| T18f shared key disabled, no SAS (P45) | storage download + exports + agent fetch on an account with shared key off | pending | pending |
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
- **T07** exactly the Boot and Export tasks exist as designed; both run on demand with result 0.
- **T07b** the measured buffer hours hold at least 1.5 × the export window.
- **T08** after a reboot the collector runs again, the ring from before the reboot is kept, and the next export holds
  it with only a `machine_off` gap.
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
