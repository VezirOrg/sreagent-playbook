# perfmon-blackbox: decisions

Numbered P1, P2, …; never renumbered. A changed decision gets a new number that says which one it replaces.
Repo-wide decisions: `../../docs/decisions.md`. Design proposals that still need Emre's approval are in
`docs/design.md` (section "Design choices for approval"), not here, until approved.

## P1: what it is (Emre, 2026-10-11)

A **black-box PerfMon recorder** for Windows servers. An **Azure Machine Configuration** package (DSC):

1. imports the logman (Data Collector Set) template,
2. starts the collector set,
3. re-starts it at every boot,
4. installs a **daily task**: relog the `.blg` to CSV, zip it, upload it to a **private storage account** with
   the **machine's own identity**, each machine **only into its own prefix**.

## P2: two policies (Emre, 2026-10-11)

**Two separate Azure Policy definitions**: one for **Azure VMs**, one for **Azure Arc-enabled servers**. Adopters
choose which one(s) to assign.

## P3: the skill (Emre, 2026-10-11)

The skill (v2) **reads storage**: finds the **latest** zip of a machine, downloads it, unzips it, converts the CSV
to SQLite, analyses. The agent publishes its recommendations **in the agent thread** for now (a GitHub issue
later). The trigger is **manual** for now.

## P4: phase 2 is decided (Emre, 2026-10-11)

An **Azure Monitor alert trigger** for the analysis is **phase 2**. It is decided and will be done; it is not in
v1.

## P5: success criterion (Emre, 2026-10-11)

**The latest zip can be analysed.** There is a test for **every stage**, end to end, the last one being the
analysis. Granular list (each one its own test, runnable with one command in the lab):

1. package builds and passes the local compliance test;
2. each policy definition and assignment exists, for Azure VM and for Arc;
3. guest assignment **Compliant** per machine;
4. extension and system identity present;
5. collector set **Running** with the template's counters, and the `.blg` growing;
6. **every** scheduled task exists with the right trigger and principal, and ran with result 0;
7. after a **reboot** the collector is running again;
8. the daily export makes a valid CSV and zip (header, rows, time range);
9. the blob lands at the expected path with a matching hash;
10. a machine **cannot** write into another machine's prefix;
11. the lifecycle rule is present;
12. the skill finds the latest zip, unzips, converts;
13. the agent produces the report from the latest zip, and the report is **scored**.

DoD centre: all stages green on a fresh lab, plus README-only fresh-eyes deploy, security (no secrets, scrub
clean, private storage, least privilege), cost per server written, CI green, tag + release, lab cleaned or
registered (see `../../docs/definition-of-done.md`). The test plan is `docs/test-plan.md`.

## P6: lab (Emre, 2026-10-11)

The project gets its **own lab**, built later from the **private lab template** and registered in the template repo's
`docs/labs.md`. For Arc testing, the lab follows the Learn guidance
[Evaluate Azure Arc-enabled servers on an Azure virtual machine](https://learn.microsoft.com/azure/azure-arc/servers/plan-evaluate-on-azure-virtual-machine).
No lab and no Azure change before Emre approves the design and the test plan.

## P7: code brought in, with provenance (Emre, 2026-10-11)

Copied **verbatim** on 2026-10-11; any change to them is a later, separate commit. The blog repo was not edited
(its cleanup is a separate blog task).

| Here | Source | Source version | SHA-256 as copied |
|---|---|---|---|
| `skill/perfmon-triage/SKILL.md` | `sreagent-blog`: `files/post4-files/skill-v2/SKILL.md` (the blog's private Drive folder; **not in git**) | live skill v2 (front matter `version: "2.0"`), file dated 2026-10-11 08:58 +03; blog HEAD at copy time `b8fa4fb` | `51a8c88c87255cf9090c73dfea2c006bc21532d8f54f9d9e67e574047b24b001` |
| `skill/perfmon-triage/perfq.py` | same folder | same | `0e2713148d7f3fd2b8545433269515e76625145101f44269a60a1df2fb4a85f7` |
| `skill/perfmon-triage/perfmon_csv_to_sqlite.py` | same folder | same | `5f8afae7b25415a5472042ee4199f1de547659c3f1eb0d840ac542b3e789be2f` |
| `scripts/deploy-skill.sh` | same folder | same | `29af0b5ff630f8463b0bd999a0fac1e5adfd48c19cea9c5f1be88ce52302e1d9` |
| `lab-tools/perfmon_mask_csv.py` | `sreagent-blog`: `lab/perfmon_mask_csv.py` (in git) | commit `126dab65b07adfcc8d283dcec509251dadfee3b5` (blog D71: denylist check) | `a8dc38b7047320c4dd8ddd6b433a4bd6188bdf32f7ac80fc9d4d56d14531fff6` |

Notes:
- The skill-v2 folder's `UPLOAD.md` was **not** copied (it is a private upload checklist that points at private
  backup paths). `deploy-skill.sh` skips `.sh` files and `UPLOAD.md` when it builds the skill body, so the skill
  folder here holds exactly the three skill files.
- Comments in the masker cite "D68 rule b": that is blog decision D68 (the match rule). Here the same rule is used
  by `scripts/scrub-check.sh`.
- Before the copy entered the repo, all five files were checked with `scripts/scrub-check.sh` against the blog's
  64-entry denylist: clean.
- The masker is a **lab-side tool**: it is never part of the package or the skill. With this playbook the
  analysis reads the machine's own capture from the adopter's own storage, so masking is needed only when a real
  capture leaves its owner (e.g. for the blog); see design.

## P8: open method questions (Emre, 2026-10-11): **OPEN for Emre, not decided**

These are about the skill's method (SKILL.md rules). They are listed here so they are asked; nobody changes the
skill's behaviour on them until Emre decides.

- **OPEN-1 (RULE 6).** Rule 6 says every "because" needs a `link_test()`; without one, no cause is named ("coincides
  with"). Question: is that too strict (e.g. when the cause is obvious from one counter, or `link_test` does not
  apply because Y is not a load counter), or is it right as a hard rule?
- **OPEN-2 (5-minute VERDICT CEILING).** `triage()` caps the verdict at **warning** unless a check breached for 5
  continuous minutes. A **recurring 20–40 s stall** therefore stays a warning **even when the user names that stall
  as the problem**. Question: keep the ceiling as it is, or let a user-named, recurring short stall lift it (and by
  what rule)?

## P9: no Azure this round (Emre, 2026-10-11)

Round 1 = docs and safety only. Then the **PLAN GATE**: design (`docs/design.md`) and test plan
(`docs/test-plan.md`) go to Emre for approval through the vezir. No lab, no Azure change before his approval.

## P10: stop conditions (Emre, 2026-10-11)

Stop and report instead of working around if: a real name or a secret would enter the repo; **Machine
Configuration cannot do a required step** (for example the upload with the machine identity on Arc); **Arc cannot
be tested in a lab**.

## P11: counters = exactly Emre's 36 (Emre, 2026-10-11; replaces the counter list drafted in design §2.1)

The collector records **exactly the 36 counters of Emre's PerfMon template**, no more, no fewer. **Do not add
counters.** Where the skill loses inputs because of this, the gap is listed for Emre (design §2.5), not filled.

- Original: `files/emre-inputs/VitalSigns_Template.original.xml` (Drive; UTF-16; SHA-256
  `3ff1b9c63d2088e612767c0c26a11d6c30db04f756f6d65ab213cc8dc50f2af8`). It holds a **real machine name** (in
  `LatestOutputLocation`) and dated output paths, so it **never enters the repo as it is**.
- Committed instead (generated from the original by extracting only the `<Counter>` elements):
  `package/files/PerfmonBlackbox.counters.txt` (the 36 counters, verbatim) and
  `package/files/PerfmonBlackbox.template.xml` (sanitized Data Collector Set: those counters + the settings below;
  no machine name, no dated path, no `LatestOutputLocation`; UTF-8, because the scrub check refuses binary-looking
  UTF-16; the package converts it if `logman import` needs UTF-16).
- The machine name was not on the shared denylist: it is now in `files/denylist-extra.txt` (R13), and the vezir is
  asked to get it into the shared one.

## P12: the original's run settings are not taken over (Emre, 2026-10-11)

The original has `SampleInterval=1` and `Duration=10800` (3 h). A black box runs **continuously**: the template
has `Duration=0` and no schedule. The **sample interval is OPEN** (design CHOICE 1); it is not picked silently.

## P13: binary circular file, 512 MB (Emre, 2026-10-11)

The collector writes a **binary circular** log (`bincirc`; `logman … -f bincirc -max <MB>`): when the file reaches
its maximum it overwrites the oldest samples, so the **last MaxSizeMB of data is always on disk**. Default 512 MB.

## P14: MaxSizeMB is a policy parameter on both policies (Emre, 2026-10-11)

`MaxSizeMB` (integer MB, default **512**) is a **policy parameter** on **both** definitions (VM and Arc), passed to
the package as a Machine Configuration configuration parameter. Tests must prove: the file **never exceeds**
MaxSizeMB; it **really wraps** (oldest samples gone, newest present); a **changed value reaches the machine and
resizes** the collector.

## P15: export around the circular file (Emre, 2026-10-11; replaces design CHOICE 2 of the first draft)

The export covers **the window since the last successful export, with no gap and no overlap**. The design states
how many hours 512 MB holds at 1 s and at 15 s for this counter set (estimate now, **measured in the lab**), and
what happens when the window outgrows the buffer: **data loss is detected and reported in the manifest**.

## P16: LAB-KUR, partial go for one measurement (Emre, 2026-10-11, ahead of PLAN-OK)

Build this project's **own lab now**, for **one measurement only**:
- From the private lab template, registered in its lab register in the same commit; lab-audit stays clean.
- **Azure VM only** (`vm1`); `arc1` comes after PLAN-OK. **No policy, no Machine Configuration, no storage design
  work** yet.
- **Question (Emre):** how many hours of data do the first 512 MB hold with **his** template (the 36 counters)?
- **Method:** on `vm1`, create the collector from the sanitized template as a binary circular log, max 512 MB.
  (a) run at 1 s for 20–30 min; (b) at 15 s for 20–30 min. Measure bytes written per sample and the `Process(*)`
  instance count; extrapolate to hours per 512 MB; give a formula `bytes/sample ≈ a + b × processes` (real servers
  run more processes than a lab VM). (c) leave a 1 s run until it really reaches 512 MB and wraps: record the true
  time to 512 MB and prove the wrap (size stays at the max, the oldest timestamp moves forward). Report (a) and (b)
  as soon as they exist; (c) may come later.
- Log everything in the lab log on Drive (`files/lab-log/`). Say which VM size and why.
- **Stop condition:** the template cannot be imported as is, or logman refuses bincirc with this counter set:
  report instead of changing counters.

## P17: the sample interval is a policy parameter too (Emre, 2026-10-11)

`SampleIntervalSeconds` is a **policy parameter on both policies**, passed like `MaxSizeMB` as a Machine
Configuration configuration parameter. Its **default stays OPEN** until the 1 s / 15 s measurement (P16); it is in
the choice table for Emre (CHOICE 1). Tests: a changed value reaches the machine and the running collector **really
samples at the new interval** (timestamps in the `.blg`).

Proposed by the vezir, **for Emre to decide** (design §2.6, CHOICE 9 and CHOICE 2):
- Azure Policy cannot validate one parameter against another, so the **package itself** checks whether
  `MaxSizeMB` at this interval can hold the export window, using the **measured fill rate on that machine**, and
  reports a misfit as the compliance **reason** (NonCompliant, e.g. "buffer holds ~7 h, export window 24 h"), so it
  shows in Azure Policy before data is lost.
- Export cadence: a third parameter, or derived from the measured buffer. Recommendation in design CHOICE 2.

## P18: three counter groups added (Emre, 2026-10-11; extends P11, the 36 stay unchanged)

The 36 original counters stay **exactly as they are** (`package/files/PerfmonBlackbox.counters.txt`). Added:

- **G1, system-wide** (12; `PerfmonBlackbox.counters-g1-system.txt`): `\System\Processor Queue Length`,
  `\System\Context Switches/sec`, `\System\System Up Time`, `\Memory\Pages Input/sec`, `\Memory\Pages/sec`,
  `\Paging File(_Total)\% Usage`, `\LogicalDisk(*)\% Idle Time`, `\LogicalDisk(*)\Current Disk Queue Length`,
  `\LogicalDisk(*)\Disk Reads/sec`, `\LogicalDisk(*)\Disk Writes/sec`, `\TCPv4\Segments Retransmitted/sec`,
  `\Network Interface(*)\Packets Received Discarded`.
- **G2, per process** (2; `…-g2-process.txt`): `\Process(*)\Pool Nonpaged Bytes`, `\Process(*)\Pool Paged Bytes`.
- **G3, web** (6; `…-g3-web.txt`): `\ASP.NET Applications(__Total__)\Requests/Sec`, `\ASP.NET\Requests Queued`,
  `\ASP.NET\Request Execution Time`, `\.NET CLR Memory(*)\# Bytes in all Heaps`, `\.NET CLR Memory(*)\% Time in GC`,
  `\Web Service(_Total)\Current Connections`.

Everything is deployed by **Azure Policy plus Machine Configuration. Nothing is Group Policy**; no doc may say
otherwise (checked 2026-10-11: no mention in the repo).

**Emre's question, to answer with lab data:** on a machine **without IIS or ASP.NET**, does collecting G3 cause an
event-log storm of "counter not found" (Application, System, Microsoft-Windows-Diagnosis-PLA/Operational)? Test: G3
forced in, 1 s, ≥ 30 min; new events counted per log and per ID at start and per minute; and whether the collector
still starts and records the rest. (The vezir expects at most a warning at start, nothing per sample: to be proven.)

**Proposal (vezir's recommendation, for Emre, CHOICE 10):** the package **auto-detects** the web objects: G3 is
added only where its counter objects exist; the periodic Machine Configuration check re-evaluates, so a machine that
gets IIS later gains G3 at the next check (through the pending-buffer restart path). No parameter for G3; missing
counters are never configured.

The buffer-hours measurement (P16) is re-run with the full set (36 + G1 + G2, plus G3 on a web box), because the
hours per 512 MB shrink.

## P19: PLAN-OK for design rev 3, with Emre's change (Emre, 2026-10-11)

"Do not wait for the measurement; start the project." The design rev 3 (`docs/design.md`) and the test plan rev 3
(`docs/test-plan.md`) are **approved**, with these values; the P16 measurement is evaluated later for fine-tuning.

| Choice | Decided |
|---|---|
| CHOICE 1 sample interval | `SampleIntervalSeconds` default **10 s** (Emre's change) |
| P13/P14 buffer | `MaxSizeMB` default **512** |
| CHOICE 2 export cadence | a **parameter** `ExportEveryHours`; default **4 h** (below), guarded by the capacity check R6 |
| CHOICE 3 prefix | `<subscriptionId>/<resourceGroup>/<machineName>` |
| CHOICE 4 write role | granted by the **DINE policy** (write-only custom role + ABAC path condition) |
| CHOICE 5 storage network | **private endpoint**, public access disabled |
| CHOICE 6 retention | **30 days** lifecycle delete |
| CHOICE 7 package hosting | **GitHub Release asset** |
| CHOICE 8 skill | **adapt skill v2.1** to the counter set (at least `Processor Information`); no new counters for it |
| CHOICE 9 capacity check | **R6** reports a buffer/export misfit as the NonCompliant reason |
| CHOICE 10 / P18 | **all three groups** (G1, G2, G3) with **G3 auto-detect** |

**ExportEveryHours default = 4 (this session's pick, as asked).** Measured on the lab VM (P16, 113 processes, full
56-counter set): ≈ 66.6 KB per sample → 512 MB ≈ 8,060 samples ≈ **22 h at 10 s**. 4 h leaves a 5.6× margin there,
and still ≥ 2× on a server with about 2.5× the processes (≈ 9 h buffer, if bytes scale with processes). R6 reports any
machine where the measured buffer is < 1.5 × the export window. To revisit with the formula `a + b × processes`
once measured (P16 is unfinished: the process-load step did not hold, see HANDOVER).

## P20: the collector files live in `package/collector/` (session 2, 2026-10-11; fixes a record error)

The root `.gitignore` line `files/` also matches `playbooks/perfmon-blackbox/package/files/`, so the five files
P11/P18 describe as committed (`PerfmonBlackbox.counters*.txt`, `PerfmonBlackbox.template.xml`) **never entered git**;
they existed only untracked in the main checkout. They are now committed, unchanged, under **`package/collector/`**
(no root change needed; the vezir was told the root pattern is broad). Every `package/files/` in the design, the test
plan and older decisions means `package/collector/`. SHA-256 as committed: counters.txt `84cd8325…a878a9`,
g1-system `b75523b4…ac62bd0`, g2-process `862d668c…3acb3064`, g3-web `aa52b312…f6a3695a`, template.xml
`16ac255c…7039f61`.

## P21: the export rolls the collector (session 2, 2026-10-11; replaces design §2.2 step 1 "live snapshot")

Lab fact (HANDOVER, lab18): a running circular `.blg` cannot be read by `relog`, not even as a copy. So the export
**stops the collector, moves the `.blg` to `pending\`, starts it again**, then relogs the closed files. The restart
gap (seconds) is written into the manifest as a `collector_restart` gap like any other. T10 measures the gap
(pass: ≤ 10 s). Consequence: every export makes the current `.blg` a pending buffer, so after an export the ring
starts empty and the overrun case (§2.3) applies only to the time **between two exports** (a missed export means
the ring holds MaxSizeMB of the newest data and the older part of the window is gone: `buffer_overrun`).

## P22: the per-process set stays (Emre via the vezir, 2026-10-11)

The 10 selected `Process(*)` counters (8 of the 36 + G2's 2) stay as they are, all instances, never `Process(*)\*`.
Emre considered dropping `Working Set` and kept it.

## P23: implementation choices (session 2, 2026-10-11; within PLAN-OK, no new behaviour)

- **Parameters reach one resource.** The six policy parameters map to properties of **R1 `BlackboxFiles`** only
  (`[BlackboxFiles]Files;<Name>`); R1 writes them to `config.json`, and R2–R6 read `config.json`. DSC runs the
  resources in order (Test, then Set when drifted), so a changed value reaches R2–R6 in the same evaluation. This keeps
  one policy parameter = one configuration parameter.
- **`StorageAccountResourceId` replaces `StorageAccountName`** as the policy parameter: the DINE nested deployment
  needs the account's subscription and resource group to create the per-machine role assignment (CHOICE 4); the
  account name passed to the package is the last segment of that ID. T02's parameter list changes accordingly.
- **The policy definitions are generated by `policy/build_policies.py`** (standard library), not by
  `New-GuestConfigurationPolicy` plus a split: the two definitions need a nested role assignment the cmdlet cannot
  produce, and Python runs (and is tested) on every machine and in CI. The output follows the cmdlet's format
  (`metadata.guestConfiguration`, `parameterHash` existence condition, `ApplyAndAutoCorrect`).

## P24: Windows development only over SSH into the lab VMs (Emre via the vezir, 2026-10-11)

No PowerShell on the Mac. All Windows development and testing (Pester, PSScriptAnalyzer, the package build and the
local compliance test) runs over SSH (the lab's `vmssh`) on the lab18 VMs, from a separate scratch folder
(`C:\BbDev\`), never touching the running measurement collectors (`BbWrap*`, `BbFull10`, `BbStorm`) or the paths the
stage tests check; the scratch folder is removed afterwards. The Windows CI job (root) runs the same Pester tests.

## P25: Windows PowerShell 5.1 on servers, nothing installed (Emre via the vezir, 2026-10-11: HARD RULE)

Every script that runs on a customer server is **Windows PowerShell 5.1 compatible**, and nothing is installed on
servers (no PowerShell 7, no other runtime). Concretely:

1. The scheduled-task scripts (`Start-PerfmonBlackbox.ps1`, `Export-PerfmonBlackbox.ps1`, with upload and the
   capacity measurement) run under `powershell.exe` 5.1. No PowerShell-7-only syntax (ternary, `??`, `?.`, `&&`/`||`,
   `ForEach-Object -Parallel`, `ConvertFrom-Json -AsHashtable`, …), only cmdlets that exist in 5.1.
2. Tests run under `powershell.exe` 5.1 on the lab VMs. The lint is PSScriptAnalyzer with `PSUseCompatibleSyntax`
   and `PSUseCompatibleCommands` targeting 5.1 on Windows Server. Pester 5 and PSScriptAnalyzer may be installed on
   **lab VMs only** (P24 scratch folder), never as an adopter requirement.
3. **Runtime split (verified on Learn).** The Machine Configuration agent runs the package's DSC resources in its
   **own PowerShell 7** ("As of version 1.26.33, machine configuration operates in PowerShell 7.1.2 for Windows"),
   in a dedicated session per configuration whose `PSModulePath` is limited to the extracted package
   (https://learn.microsoft.com/azure/governance/machine-configuration/whats-new/psdsc-in-machine-configuration).
   It comes with the agent (VM extension / Arc agent); no system-wide `pwsh` is installed or needed (the lab checks
   `Get-Command pwsh` is absent on vm1 and arc1). Consequence for the DSC resources: Windows modules are not
   loadable there (Learn: DSC resources may use only cmdlets of PowerShell itself or Gallery modules), so they call
   `logman.exe`, `schtasks.exe` (task XML), `icacls.exe` and .NET only, never `ScheduledTasks`/`Get-ScheduledTask`.
   The DSC module is also written in 5.1-compatible syntax, so one lint covers all server code.
4. The package **build** (GuestConfiguration module, PowerShell 7) runs on the authoring side only: the CI Windows
   runner or a lab VM's scratch folder (P24), never on a customer server.

## P26: the server-side export uses only what ships with Windows Server (Emre via the vezir, 2026-10-11)

`relog.exe` (blg → CSV), .NET `System.IO.Compression.ZipFile` (zip; `Compress-Archive` is slow on large files in
5.1, so not used), `Invoke-WebRequest` for the upload (`Put Blob` up to 32 MiB, otherwise `Put Block` in 8 MiB blocks +
`Put Block List`), bearer token from IMDS (Azure VM) or the HIMDS challenge flow (Arc). No azcopy, no az CLI, no Az
modules on servers. The lab measures zip time and size per export (T09 evidence).

## P27: P16/P18 results: no G3 event storm; bytes per sample = a + b × processes (session 2, 2026-10-11)

**Storm (P18, T06f part 1), answered:** on `dc` (no IIS, no ASP.NET), the full set with G3 forced, 1 s, 32 min
(09:53:25–10:26:13Z): Diagnosis-PLA/Operational logged **9 events, all in the start minute** (6 × ID 1010 Error, one
per G3 counter: "could not be added to collector Counters, error code 0xC0000BB8", plus 1000/1001/1003 start info)
and **nothing afterwards** (one 1005 at stop). Application: 0–2 events per minute, same sources as the 10-min baseline
(SPP, WDATP), none from the set. System: 12 Service Control Manager events in the start minute, then 0–4 per minute
(service noise, as in the baseline). The collector ran and recorded every other counter: 1,933 samples in 32 min at 1 s
(no drop), 1,449 counter instances (Process 1,360, LogicalDisk 40, Processor Information 20, NIC 8, Memory 10,
System 3, TCP 7, Paging File 1), 127 MB. **No storm: one error per missing counter at each collector start, none per
sample.**

**Finding for G3 auto-detect:** `.NET CLR Memory` *exists* as an object on `dc` (`Get-Counter -ListSet`), yet PLA
could not add its two counters (0xC0000BB8) and recorded none of them. So "object exists" is not "PLA records it".
Harmless (start-time errors only), and R2 compares against its own expected list, so there is no drift loop. To check
on a web box (T06f part 2): whether CLR counters are recorded where .NET Framework processes run.

**Formula (P16 c, from existing data only, as the vezir asked; no synthetic load step).** Inputs: lab18 vm1 (113
processes) 52.4 KB/sample with the 36, 66.6 KB with the full set; lab18 dc (118 processes, full set, G3 not
recorded) 65.7 KB; and the per-sample value counts of four real captures (counts only, in `files/`): three servers on
exactly the 36 at 1 s with **300–365 processes per sample** (median 303, 339, 349; 2,512–2,873 values per sample, of
which ~85 not per process), one web server on a 187-counter set at 10 s with ~81 processes. A `.blg` costs about
**45–54 bytes per value** per sample, and values = (Process counters × processes) + machine-wide values, so:

- **full set (36 + G1 + G2, 10 Process counters): bytes/sample ≈ 4.5 KB + 0.53 KB × processes**
- **the 36 only (8 Process counters): bytes/sample ≈ 3.5 KB + 0.43 KB × processes**

Hours held by 512 MB, full set at the 10 s default: 100 processes ≈ 26 h, 200 ≈ 13.5 h, 300 ≈ 9 h, 350 ≈ 7.8 h,
400 ≈ 6.9 h, 500 ≈ 5.5 h. **ExportEveryHours = 4 stays**: R6 (needs ≥ 1.5 × 4 = 6 h) turns NonCompliant only above
~460 processes. For comparison, the real 36-counter servers at their own 1 s would hold only ≈ 1 h in 512 MB. R6 uses
this formula before the first export (then the measured value); the README quotes the table. The wrap proof and the
10 s full-set measurement (BbWrap1/2, BbFull10 on vm1) confirm it later.

## P28: package build facts from T01 (session 2, 2026-10-11)

- **T01 green on dc** (authoring side, portable PowerShell 7.4.6 in `C:\BbDev\pwsh`, GuestConfiguration 4.12.0,
  PSDesiredStateConfiguration 2.0.7): NonCompliant on a clean box, then after `Start-GuestConfigurationPackageRemediation`
  all six resources Compliant. The portable zip is not an install (no PATH, no registry, removed with `C:\BbDev`), so
  P25 holds; vm1 and arc1 never get it.
- PowerShell 7.4 hides `DscResourcesToExport` from `Get-Module -ListAvailable` when the manifest also has empty
  `FunctionsToExport`/`CmdletsToExport`/… = `@()`; the DSC compiler then finds no class resource. The manifest has no
  such lines.
- `schtasks /query /xml` leaves out elements at their default (`<Enabled>true</Enabled>`), and `icacls` writes ACEs
  in its own order: the Tests compare accordingly.
- The package file is `PerfmonBlackbox.zip` (the name must equal the configuration name; the version lives in the
  release tag and the policy's `contentHash`), not `PerfmonBlackbox_<ver>.zip` as T01's row said.

## P29: lab package = GitHub pre-release `perfmon-blackbox/v1.0.0-rc.1` (Emre, 2026-10-11, answer (a))

For the lab runs before v1.0.0, the package is published as a GitHub **pre-release** `perfmon-blackbox/v1.0.0-rc.1`
in the public repo: `PerfmonBlackbox.zip` is its only asset; notes "lab test build, not for use"; marked prerelease,
**not latest**; deleted or superseded at v1.0.0. The vezir's condition: release assets bypass the git scrub hooks, so
before the upload the zip is extracted and `scripts/scrub-check.sh` runs over every file in it (denylist, secret
patterns, no machine names, no lab paths); the zip's SHA-256 is recorded here and is the policies' `contentHash`.
Pushing to origin/main mid-session (rebase + fast-forward) is allowed for this.
- **rc.1 package:** `PerfmonBlackbox.zip`, SHA-256 `EFE14BE1E44F6EA4C7BB908C8CE764C2396F3816FEFABF5F71451F74B80B81AA`
  (built by T01 on dc, T01 green; 12 files extracted and scrub-checked clean; `build.ps1` now neutralises the MOF's
  build host, user and source paths, which the DSC compiler writes in).

## P30: the lab SP is SRE Agent Administrator on the lab18 agent, "for now" (Emre, 2026-10-11, answer (b))

To deploy skill v2.1 for T15/T16, the lab service principal gets **SRE Agent Administrator on the lab18 agent
resource only** (never the resource group or subscription; same pattern as lab17 D63). The reason is in the lab
register row; the role is removed at teardown. **The SP never approves agent actions.** "For now": the least-privilege
path (**SRE Agent Author + Standard User**; Learn lists Author as able to edit the agent's configuration but not to
approve actions) is to be tried later and documented for adopters in the README.

## P31: standing permission for lab pre-releases rc.N (Emre, 2026-10-11, "RC-SERBEST")

Further **lab** pre-releases `perfmon-blackbox/v1.0.0-rc.N` may be published without asking each time, under
**exactly** the rc.1 conditions (P29): prerelease, not latest, a single asset `PerfmonBlackbox.zip`, every extracted
file scrub-checked clean (denylist, secret patterns, no lab host, user or path), the SHA-256 recorded here and used as
the policies' `contentHash`, notes "Lab test build, not for use". Each URL + SHA goes to the vezir right after
publishing. It does **not** cover v1.0.0 or any non-prerelease: that stays Emre's release gate.

- **rc.2** (boot reason derived from the boot time, for T08): `PerfmonBlackbox.zip` SHA-256
  `CC42AF186D13D622FA8342D8941AF079157DFCB585DA4164508103FCDDDEE7A0` (T01 green on dc; 12 files scrub-checked clean).

## P32: the DINE existence condition also pins the package hash (session 2, 2026-10-11)

The cmdlet-style existence condition (Compliant + `parameterHash`) never re-deploys a guest assignment whose machine is
Compliant, so a new package version would not reach machines that already run the old one. The definitions add a
third condition, `guestConfigurationAssignments/guestConfiguration.contentHash` equals the definition's `contentHash`:
after a definition update (new release), every machine on the old package is non-compliant for the policy and the
next remediation moves it to the new package. This is the adopter upgrade path (README).

## P33: two lab findings fixed (session 2, 2026-10-11)

1. **ACL bug in R1 (rc.1, rc.2).** `Set-BbAcl` ran `icacls <root> /inheritance:r /grant:r SID:(OI)(CI)F /T`: on files
   that already existed under the root, `/inheritance:r` removed the inherited ACEs while an `(OI)(CI)` grant does not
   apply to files, leaving an **empty DACL** that even SYSTEM cannot open (proven on dc). On a fresh machine nothing
   exists yet, so it did not show; but any later R1 Set (ACL drift) would have locked the export out of `pending\` and
   `state.json`. Fixed: the root gets the protected DACL (no `/T`), then everything below is `/reset` to inherit it;
   proven idempotent on dc. In rc.3. vm1's pre-existing measurement files are repaired with a one-off SYSTEM task.
2. **The size of a running `.blg` read from the directory is stale.** NTFS updates a file's directory-entry size
   only when the writer closes it: BbWrap1 showed 286 MB from 11:44 to 13:07, then exactly 536,870,912 B after the
   stop. Size polls (T06b/T06c `watch-size.ps1`, `measure-buffer.ps1 -Action sample`) must read the size through a
   handle (open with read/write sharing), not `Get-ChildItem`. The 11:44Z fill-rate figures used that same listing;
   they were probably fresh (R1's ACL change touched the files at 11:43), and the full-at time they predicted (13:03Z)
   agrees with the 512 MB found at the 13:08Z stop, but they are not proof on their own.
- **rc.3** (P33 ACL fix): `PerfmonBlackbox.zip` SHA-256 `2F9E19F4FF096460B6B97C5CB3B7F4ADA32063C26C84CF85D93C67A8DC92DD6F`
  (L05 26/26, T01 green on dc; 12 files scrub-checked clean before the upload; L07 now refuses lab names in shipped
  code). Recorded one commit after the publish: a failed local test broke the command chain that should have written
  this line first (the zip itself was checked before the upload).

## P34: OPEN-2 closed for v1.0.0; the wrap is proven (2026-10-11)

- **OPEN-2 (Emre, 2026-10-11): the short stalls come out of T16.** The skill stays as it is (no section for recurring
  short events; rule 6 and the VERDICT CEILING unchanged). The two 30-s stall plants leave the plant set and the T16
  success criteria; the rubric drops item P5. Not in v1.0.0; it can return in a later version. (Evidence: T16 run 1,
  the agent found everything else and did not report the 30-s stalls.)
- **Wrap proof (P14/P16 c), lab18 vm1, the 36 counters at 1 s, 512 MB circular:** BbWrap1 (recording since 10:05:05Z)
  stopped 13:08:32Z: file exactly 536,870,912 B, oldest sample 10:20:00, newest 13:08:27, 10,105 samples (none
  dropped). BbWrap2 (identical twin) stopped 13:39:53Z: exactly 536,870,912 B, oldest 10:51:43 (later than BbWrap1's:
  the oldest moves forward), newest 13:39:43. **True time to 512 MB ≈ 2.81 h** (10,105 samples ≈ 53 KB each, ~117
  processes). The file never exceeds the maximum, the oldest samples are overwritten, the newest are present.

## P35: adopter docs in `docs/` (Emre, 2026-10-11)

The playbook gets adopter documentation in `docs/`, written between the lab's Azure waits (never delaying a test):
`deploy.md`, `parameters.md`, `operations.md`, `security.md`, `cost.md`, `architecture.md`, `load-generation.md`
(how the lab plants the T16 problems, with the critical code) and `tests.md` (every test in plain words, with a
summary table whose status column is kept current). English, plain and concise, each file opening with a 3–5 line
summary; marked "draft until v1.0.0" where details may still change; the README-only fresh-eyes deploy at release
validates them. Linked from the playbook README; scrub-checked like everything else.

## P36: a resource's Test never throws (session 2, 2026-10-11)

On arc1, rc.3 could not repair the files locked by the P33 bug: R1's Test hashed each file, the hash threw "access
denied", the whole configuration failed, and R1's Set (which resets the ACLs) never ran. Rule: every resource's Test
turns any failure into a NonCompliant reason (`FileUnreadable`, `ConfigUnreadable`, `CheckFailed: …`), never an
exception, so Set always gets its chance. R1's check is now `Get-BbFilesDrift` in the common script (Pester-tested
with a locked file). In rc.4.
- **rc.4** (P36: Test never throws, so rc.4 self-heals machines locked by the P33 bug): `PerfmonBlackbox.zip` SHA-256
  `F9D4CB5BE4351A507EC16CC07ACD9132AD563839C5020F9642FB409DDDF8A736` (L05 30/30, T01 green on dc; 12 files scrub-checked
  clean before the upload).

## P37: rings are judged by their own interval and size (session 2, 2026-10-11)

T06d on arc1 (interval 10 s → 1 s, MaxSizeMB 512 → 16) produced an export with 649 false `missing_samples` gaps and a
false `buffer_overrun`: the gap rule used the NEW interval for samples recorded at the old one, and "wrapped" was judged
against the NEW size. Fix: each pending ring carries its own size limit in its name (`…-<reason>-m<MaxSizeMB>.blg`),
its interval is the median step of its own samples, inside-ring holes use that interval, holes between rings the larger
of the two. The incomplete-export event text is bounded (first 10 gaps; the manifest has all). In rc.5.
- **rc.5** (P37: rings judged by their own interval and size): `PerfmonBlackbox.zip` SHA-256
  `3E7A3D2784EB466AD28083A2751FF6CF0A0089481155E4E86B2FA1BD021E3D44` (L05 32/32, T01 green on dc; 12 files
  scrub-checked clean before the upload).

## P38: the playbook reads analysis-first (Emre, 2026-10-11)

perfmon-blackbox is a two-part solution whose **most important part is the SRE Agent analysis**: continuous capture by
policy is the input; the agent skill fetching the latest capture, analysing it and writing recommendations is the
value. The README opening and `docs/architecture.md` lead with what the agent tells you (with a short, masked or
synthetic report excerpt); `docs/analysis.md` explains how to ask, what the skill does step by step, the report
structure, its rules and known limits, and how T15/T16 prove it; `docs/tests.md` groups the tests into collection and
analysis, with the T16 score history. No rename.

## P39: the T16 disk plant really loads the disk (session 2, 2026-10-11)

In T16 runs 1–2 the disk plant never wrote a byte: `New-Object IO.FileStream` with string arguments is ambiguous in
Windows PowerShell 5.1 and threw; the loop then spun on errors (which the agent correctly reported as a memory episode
of `bbdisk`, and correctly found no disk problem). Fixed: typed enums; 8 writers × 1 MiB write-through at random
offsets; target = an **uncached** 4 GiB lab data disk `T:` on vm1 (the OS disk's host cache absorbs writes). Measured
60 s: Avg. Disk sec/Write 179 ms average (queue ≈ 8, 174 MB/s), memory flat. Lab changes (register row updated): the
data disk, and vm1's `patchMode` set to `AutomaticByPlatform`, which the template's hotpatch image requires for any VM
update. The scorer's "invented problem" rule no longer counts a line that calls the area fine (run 2: "PTEs … fine").

## P40: a hole before a wrapped ring is an overrun (session 2, 2026-10-11)

T06c on arc1 (1 s, 32 MB, 13 min without an export) showed a 212-s hole between the re-create ring and the new ring
labelled `collector_restart`; in truth the new ring had wrapped and overwritten its own first 3.5 minutes. Between two
rings the cause is now `buffer_overrun` when the later ring had wrapped, `machine_off` when the earlier one was closed by
a boot, else `collector_restart`. T06c/T06d are re-run with an export right after the change lands (at 1 s a 16–32 MB
ring holds only 5–10 minutes). In rc.6.

- **rc.6** (P40): `PerfmonBlackbox.zip` SHA-256 `5B4D37FF31E0013F8D9A4960045E90260CAE0FBAE6E443ED95BEADAAF6F9DFE3`
  (L05 33/33, T01 green on dc; 12 files scrub-checked clean before the upload).

## P41: the export's own roll is a named, expected gap (session 2, 2026-10-11)

At a 1-s interval every export marked its zip `complete: false`: the roll of P21 (stop → move → start, ≈ 2 s) exceeds
2 × interval at the start of every window. The seconds are really lost, so they stay in `gaps[]`, but with the cause
**`export_roll`**, and a roll hole of ≤ 10 s does **not** make `complete` false (`complete` means "no unexpected
loss"). A longer hole at that place keeps `collector_restart` and does. At the 10-s default nothing changes (the roll
fits within two intervals). In rc.7.
- **rc.7** (P41: `export_roll`): `PerfmonBlackbox.zip` SHA-256
  `011ABABE14A8F4D720DAE32025679821569CAE18071EE06696F2F923441B673B` (L05 34/34, T01 green on dc; 12 files
  scrub-checked clean before the upload).

## P42: T16's disk item counts only on the planted volume (the vezir, 2026-10-11)

A disk problem counts as found only if the report names the **planted volume** (`T:` in the lab) with **write
latency** (or an equivalent latency claim on that volume) in the planted window. A process name containing "disk"
plus a matching time is not enough. Before any T16 run is recorded green, the planted effect itself is checked in the
capture (the planted volume's `Avg. Disk sec/Write` really above 25 ms for minutes in the window); a run whose plant did
not take effect is **invalid** for that item, not a pass or a fail. Run 4 is under this review; run 5 follows on a
freshly formatted `T:` (rc.7).

## P43: T16 plants only memory and CPU (Emre, 2026-10-11)

"Disk gecikmesi analizi yapmamıza gerek yok, memory'yi ve CPU'yu bulması yeterli" and "CPU ve memory problemini
yakalaması yeterli": T16 plants **only the memory leak and the CPU burst**. The disk plant and the network burst are
removed entirely (not even as a control). A run **passes** when both are found, nothing is invented and the score is
≥ 80; the scorer is re-weighted so the two required items carry the problem points. Test scope only: the skill keeps
checking disk and network as it does. The plant-verification gate (P42) stays for leak and CPU. The lab18 data disks
stay as they are. Run 4 is re-scored under this rule; run 5 (arc1, then vm1) is the clean demonstration.

## P44: the skill analyses a time range across several zips when asked (Emre, 2026-10-11)

"Skill defaultta son zipe baksın ama kullanıcı belirtirse belirli aralığı kapsasın, birden fazla zipteki verileri
SQLite db'ye eklesin." Default unchanged (the latest zip). **Range mode**: when the user gives a time range, the skill
fetches every zip that overlaps it, loads all their samples into one SQLite database (duplicate timestamps dropped),
analyses only that range, shows the holes between zips as gaps (`export_roll`, a missing zip), says plainly which part
of the range is not covered (before the oldest zip — 30-day lifecycle —, after the newest, or a missing zip), and the
report's Capture section lists every zip used. A new analysis test plants leak + CPU across an export boundary and asks
with a range spanning both zips (T17). New skill version (v2.2): the current skill is backed up (zip → Drive) before
every upload; the package is not affected.

## P45: the package comes from GitHub or from the adopter's own storage (Emre, 2026-10-11)

"Hem GitHub hem de storage account seçeneğimiz olsun policy'de." Real servers often cannot reach github.com.

- **Policy parameter `PackageContainerResourceId`** (both definitions; default empty). Empty = **GitHub mode**: the
  release asset URL, as today. Set (the resource ID of a blob container) = **storage mode**: the guest assignment's
  `contentUri` is `https://<account>.blob.<suffix>/<container>/PerfmonBlackbox.zip` and `contentManagedIdentity` is
  `system`, i.e. the machine downloads the package with its **system-assigned identity** (what
  `New-GuestConfigurationPolicy -UseSystemAssignedIdentity` writes; GA on Azure VMs and Arc, Windows agent ≥ 1.29.98.0
  per the Machine Configuration Windows agent release notes, July 2025; user-assigned identities are not supported on
  Arc and are not used). **No SAS anywhere.**
- **Read access per machine**: the DINE nested deployment also assigns **Storage Blob Data Reader on the package
  container only** to the machine's system identity (the data container stays write-only). The policy identity's RBAC
  Administrator delegation condition allows exactly the Writer and the Data Reader roles. Recommended layout: a
  container `packages` in the same private-endpoint storage account (infra creates it), so servers need no internet at
  all for the package.
- **Same zip both ways**: `contentHash` is pinned to the release's SHA-256 in both modes; the adopter copies the release
  zip unchanged into the container (deploy.md shows the copy and the hash check).
- **Not a package change** (no rc): policy generator, infra, lab scripts, docs and tests only.
- **SAS is off the table** (Emre, 2026-10-11: customer environments may not allow SAS): not even as a fallback. If the
  identity download fails anywhere, it is fixed or stopped and reported; it never falls back to SAS. The whole chain is
  proven under a customer-like storage policy: **shared key access disabled** and public network access disabled (the
  lab account has both since it was built, `infra/main.bicep`; T14 checks them). **T18f**: on that account, storage-mode
  download (T18b/T18c), an export upload from each machine and the agent's fetch (T15). No lab script or infra step
  uses an account key or a SAS (all use Entra ID tokens: IMDS, HIMDS, `az … --auth-mode login`, the agent's identity).
- **Tests:** T18a GitHub mode (proven by T02/T04/T07–T12 on vm1 and arc1), T18b storage mode on arc1, T18c storage mode
  on vm1 (temporary, then back to GitHub), T18d no reader role → no download, T18e a different zip under the same name
  → rejected by the hash, the old configuration stays; T18f the whole chain with shared key access disabled. The
  fresh-eyes deploy in the second lab uses storage mode.

## P46: a failed export retries itself (the vezir for Emre, 2026-10-11; for v1.0.0, rc.8)

Why: on the real servers (300–365 processes) 512 MB at 10 s holds only ≈ 7.4–8.9 h, and R6 allows a buffer down to
1.5 × the export window; one failed export waited 4 h for the next run and could already lose data (labelled, but lost).
Seen for real on lab18 (R1: a DNS outage).

Design: the **export script retries its own upload**: on a failed token or upload it waits and tries again, at +5 min
and +15 min after the first failure (three attempts, ≤ 20 min, well inside the task's 2-h limit), each time with a fresh
token; the zip is the same (the window from `last_ts`, so nothing is duplicated and no gap is created). Only if all fail
does it exit non-zero with state unchanged; the next scheduled run then exports the longer window as before. As a
backstop the Export task also gets **RestartOnFailure (15 min, 3 times)**, and `MultipleInstancesPolicy = IgnoreNew`
stays, so a retry never overlaps a scheduled run. (Task Scheduler's restart acts on a failed start rather than on a
non-zero exit code, which is why the retry lives in the script.) Test: storage blocked by name on one machine, an
export started, the block lifted after ~3 min: the same run uploads at its +5-min attempt, 0 gaps, continuous.
- **rc.8** (P46 retries + P49 LOCK-A): `PerfmonBlackbox.zip` SHA-256
  `8ADA96B885FF8BCCD843C353B18C03D99693640AD6C8274BDBA9952AC4442320` (L05 37/37, T01 green on dc; 12 files
  scrub-checked clean before the upload).

## P47: the guest assignment is created with API 2024-04-05 (defect found in T18b, 2026-10-11)

T18b (arc1, storage mode) failed: the agent logged "Managed identity not provided, defaulting to sas uri token" and the
private storage answered 409 (public access not permitted). Cause: the policy template created the guest assignment
with `apiVersion 2022-01-25`; `contentManagedIdentity` exists only from `2024-04-05` (Learn: API change log for
guestConfigurationAssignments), so ARM dropped it without an error. Our defect, not a platform limit: no stop under
P45. Fix: the template uses `2024-04-05`; L08 asserts the version. No SAS was ever used or offered: the failed download
left the server on its current (GitHub-mode) configuration. T18b is rerun with the redeployed definitions.

Addendum (T18b second run, 2026-10-11): with 2024-04-05 the agent downloads "from private blob using managed identity";
it then got 403 because the per-server reader grant had failed. The arc assignment identity's RBAC Administrator
assignment still carried the pre-P45 condition (Writer only): `az role assignment create` returns an existing assignment
unchanged. `lab-policy.sh` now updates a differing condition in place; `deploy.md` warns adopters who upgrade.

## P48: the package mode is chosen when the definitions are generated (the vezir for Emre, 2026-10-11; replaces the P45 parameter)

Found in T18b: storage-mode download with the system identity works on Arc (agent log 21:00:40Z: "from private blob
using managed identity", downloaded, validated, applied). Ten minutes later a first-party Guest Configuration app (not the
policy identity) PUT the guest assignment again, and the agent went back to the GitHub URI with "Managed identity not
provided". Learn: the machine configuration service creates the guest assignment from the definition's
`metadata.guestConfiguration`. Ours was static (GitHub URI, no identity), so a mode chosen by an assignment parameter is
overwritten. Microsoft's `New-GuestConfigurationPolicy -UseSystemAssignedIdentity` writes `contentManagedIdentity:
"system"` and the storage `contentUri` into that metadata and the deployment alike.

Decision: `build_policies.py --package-container-id <container resource ID>` generates storage-mode definitions with
the storage URI and `system` as literals in the metadata and the deployment, plus the per-server Storage Blob Data
Reader grant on that container. The assignment parameter `PackageContainerResourceId` is removed. Conditions (the
vezir): (1) distinct definition names per mode: `perfmon-blackbox-vm` / `perfmon-blackbox-vm-storage`,
`perfmon-blackbox-arc` / `perfmon-blackbox-arc-storage`; (2) both write the same guest assignment `PerfmonBlackbox`:
never assign both modes over the same machine; to switch, unassign the old one, assign the new one, remediate. T18c
follows exactly that and shows no flapping (no first-party PUT back and forth); (3) the GitHub-mode definitions ship
prebuilt as today; storage mode is always generated with the adopter's own container ID (one command in deploy.md).
Emre's "both options in the policy" stays met: both modes ship.

## P49: the export releases its lock during the P46 retry waits (Emre via the vezir, 2026-10-12: **LOCK-A**)

Found while scripting T10d: the P46 export holds the machine-wide lock (`Lock-Bb`) through its retry waits (+5 and
+15 min, longer if a request hangs up to its 300-s timeout). A DSC `Set` of `[BlackboxCollector]` (a parameter change)
in that time waits up to 10 min for the lock and then fails; Machine Configuration retries at its next 15-min check. No
data is lost; the agent's configuration run is held up to 10 min and the machine shows NonCompliant for one cycle.
Asked through the vezir (LOCK-A / LOCK-B):

- **LOCK-A (recommended):** release the lock while waiting between attempts, take it again before the next attempt.
  Safe: a re-create only adds a new pending ring and never touches the files the export uses; a `LocalKeepMB` drop in
  the wait could remove one of them, so the cleanup after the upload must tolerate a missing file. Package change for
  rc.8 with an L05 Pester case.
- **LOCK-B:** keep the code; operations.md documents the hold and the one-cycle NonCompliant.

**Decided: LOCK-A** (Emre, 2026-10-12). The export releases the lock before each wait and takes it again before the
next attempt; the cleanup after the upload tolerates a part file already removed (a `LocalKeepMB` drop in the wait).
In rc.8, with an L05 Pester case.

## P50: lab18 restarts (Emre via the vezir, 2026-10-12 08:13, "LAB-BAŞLAT")

The lab was stopped on 2026-10-11 at 21:45Z, and at 21:56Z all five lab18 disks were set to Standard_LRS, both by the
same caller (not the lab SP; activity log). **Caller identified (Emre, 08:20):** Emre's own global lab-management automation, which deallocates lab VMs and
downgrades their disk SKUs nightly at about 21:46Z (00:46 +03); not a security incident. Plan around it: no lab run
across 21:45Z without telling the vezir; if it stops the lab again, do not restart, report. Emre's answer: restart lab18 and continue the lab tests. Order:
(1) while the VMs are deallocated, put the disks back: the three OS disks on the template's `StandardSSD_LRS`, the two
lab data disks (`bbdisk-vm1`, `bbdisk-arc1`) on `Premium_LRS` as registered in the lab register (uncached, P39);
(2) start dc first (DNS), then vm1 and arc1; check that the collectors, Arc and Machine Configuration are healthy;
(3) resume the recipe: T18b deciding pull, then rc.8 (SHA in this file before publishing, P31), then T10d. rc.8 is
not built while P49 is OPEN (decided LOCK-A the same morning). If the same caller deallocates a VM or changes a disk again: do not fight it; stop,
record the activity-log evidence, report to the vezir. Spend: lab18 only.

## P51: the nightly lab stop is accepted (Emre via the vezir, 2026-10-12 08:35, "KABUL")

Emre's lab automation stays as it is (P50). Every night at about 21:46Z (00:46 +03) lab18 is deallocated, and about
10 min later its disks go to Standard_LRS. Rules: (1) no lab test or load run crosses 21:45Z: a run that would is stopped
and rescheduled, never left to be cut off. The lab's own auto-shutdown at 19:00Z (dc and vm1) comes first, so the
practical end of a lab day is 19:00Z. (2) Restarting lab18 after the nightly stop is pre-approved: dc first, then vm1
and arc1. (3) Disk SKUs are **not** restored after a nightly downgrade (today's P50 restore stands): HDD is acceptable,
since T16 checks only memory and CPU (P43) and the collector load is light; a disk-latency finding in a result or an
analysis output is marked as an HDD lab artefact, not a product signal. (4) Any other stop or change by that
automation, outside the nightly window, is reported to the vezir.

## P52: lab18's template auto-shutdown is disabled until v1.0.0 (Emre via the vezir, 2026-10-12, "KAPANIS-19")

The template's auto-shutdown schedules of lab18 (`shutdown-computevm-<vm>` for dc and vm1, 19:00Z) are set to
**Disabled**, not deleted, so the lab day ends at Emre's nightly automation stop (~21:46Z, P50/P51; no run crosses
21:45Z). **Re-enable both at v1.0.0, or when the playbook work stops before then** (HANDOVER checklist and the v1.0.0
steps): `az resource update -g <lab rg> -n shutdown-computevm-<vm> --resource-type Microsoft.DevTestLab/schedules
--set properties.status=Enabled` for each. The lab register note is the template repo's and is changed by the vezir.

## P53: the product never changes a machine's power state (Emre via the vezir, 2026-10-12 10:35)

The package, the policies, the infra and the skill never start, stop or schedule machines and never touch their
auto-shutdown; their only relation to power state is observing it (the `machine_off` gap label). Lab power actions stay
manual one-off `az` commands, recorded in decisions/HANDOVER (P50–P52); no lab-tools helper for them (Emre: "GEREK-YOK").
No such code exists today. If a future design needs one, stop and ask.

## P54: a pending ring that can never be read (session 3, 2026-10-12): **DECIDED RING-A** (Emre, 2026-10-12 11:45Z)

Found on vm1: `20261011-191221-00-boot.blg` was cut by an abrupt restart (2026-10-11 19:12Z, right after the template's
19:00Z auto-shutdown) without being closed, so `relog` cannot read it (lab fact 1). Its ~10 min were reported as a gap
in the next manifest (nothing silent), but the export keeps the file for ever ("unreadable pending buffers kept for the
next run"), warns on every run, and the file counts toward `LocalKeepMB`. A normal deallocate (2026-10-11 21:45Z) left
a readable ring, so only abrupt stops cause this. *(Corrected by P62: a clean restart can leave one too, T08 arc1 2026-10-13.)* Asked through the vezir (RING-A / RING-B):

- **RING-A (recommended):** after N failed reads (e.g. 3 exports) record it as an `unreadable_ring` gap in the next
  manifest, delete it and write a warning event. Package change with an L05 case.
- **RING-B:** keep it; operations.md documents it and how to remove it by hand.

Nothing is changed until Emre answers.

**Decision (Emre, 11:45Z): RING-A.** After **3** failed reads of the same pending ring (3 export runs), the export
records it as an `unreadable_ring` gap in the next manifest (file name and its time span as far as known), deletes
it and writes a warning event. The failure count is kept in `state.json` per file name; a read that succeeds clears
it. Package change: L05 Pester cases (count up, third failure → gap + delete + event, success resets), then a new rc
as usual (SHA here before publishing, P31). The v1.0.0 tag stays reserved for Emre.
- **rc.9** (P54 RING-A, on top of rc.8; package version 1.0.8): `PerfmonBlackbox.zip` SHA-256
  `133B7A79890DBD0A5295387E2E76935F0DD45AED22ABF6424B589BD8980BB440` (L05 39/39, T01 green on dc 12:48Z; 12 files
  scrub-checked clean before the upload).

## P55: after a definition update, a compliance scan comes before the remediation (rc.8 rollout, 2026-10-12)

Seen on arc1 (storage mode) when rolling out rc.8: the definitions were updated (1.0.7) and remediated at once; the
remediation deployment wrote rc.8 to the guest assignment (08:01:37Z), but the next first-party re-sync PUT
(08:12:53Z) set it back to rc.7 (1.0.6) and the machine never downloaded rc.8. After a compliance scan
(`az policy state trigger-scan`, which re-evaluated the assignment against the new definition: NonCompliant) and a
second remediation, arc1 downloaded rc.8 (08:36:58Z, private blob, managed identity) and kept it across the next
service PUT (08:43:59Z → Compliant 08:47Z). vm1 (GitHub mode) kept rc.8 without a scan. One case each way: the scan is
the likely difference (the re-sync appears to use the policy engine's last evaluation of the definition), not proven.
Procedure, adopters and lab alike: update definitions → **trigger a compliance scan and wait for it** → remediate →
check the guest assignment's version after the next service re-sync. operations.md and `lab-policy.sh` do this. A
rollout takes about 45 min per machine (the first agent cycle after a new package only tests, the next applies).

## P56: T18d/e and T07b on arc1 (session 3, 2026-10-12): **DECIDED** (Emre, 11:45Z, as recommended)

- **T18D-ARC1:** T18d (no reader role on the package container) and T18e (a different zip under the same name) run
  on **arc1**, not vm1 as the test plan said: arc1 is already in storage mode, so no mode switch (and no 45-min
  rollout each way) is needed. Afterwards the reader role and the original rc.8 zip are restored and arc1 must be
  Compliant on rc.8 again. test-plan.md records the machine change.
- **T07B-HESAP:** T07b on arc1 is not run to a full 512 MB ring (that needs ~21 h of uptime, which the nightly stop
  prevents, P51). Instead bytes per sample are measured over a short window on arc1 (file growth / samples), and the
  hours held are computed with the P27 formula, the same way R6 does. That computed value is T07b's arc1 result,
  marked as computed, not observed.
- **T18d/e method (12:50Z, found while running T18d):** an unchanged re-PUT of the guest assignment does not make
  the agent download again: arc1, reader role removed 12:29Z, same assignment re-PUT 12:30:49Z → Pending, then
  Compliant 12:46:56Z with no download attempt (it keeps the package it holds, same hash). **Finding:** the reader role
  matters only when the content changes; a machine already on the package stays Compliant without it. So T18d/e need
  new content, and are run as arc1's **rc.9 rollout**: (d) the arc storage definition is updated to rc.9 without a
  remediation (a remediation would grant the reader role again) and the assignment re-PUT from it, no reader role,
  rc.8 still in the container → expect 403, rc.8 keeps running; (e) the reader role back, the container still holds
  rc.8 under the same name while the hash pins rc.9 → expect the hash check to reject it, rc.8 keeps running;
  (restore) rc.9 uploaded → Compliant on rc.9 (`T18.sh arc1 storage`). arc1 ends on rc.9 (the planned rollout)
  instead of back on rc.8.

## P57: T17 now; the second-lab build plan drafted tonight (Emre via the vezir, 2026-10-12 15:55Z, "T17-BAŞLA")

- **T17 range mode** starts now, on vm1 and arc1 (both on rc.9; skill v2.2 live and identical to the folder, checked
  with the `deploy-skill.sh` dry run at 15:57Z). Every lab run ends before 21:45Z (P51).
- **Second-lab fresh-eyes build plan:** drafted tonight in `docs/second-lab-plan.md` for Emre's approval (what is
  built, where, cost per hour, how long it runs, teardown). Drafting only: nothing is built, and no Azure change is made
  for it, until he approves the plan.

## P58: second lab = option A (Emre via the vezir, 2026-10-12 16:25Z, "LAB2-A")

- **LAB2-A:** lab18's remaining tests are finished first (planned for 2026-10-13: T08 and T06f part 2 on arc1, P30
  least-privilege path, docs pass; `second-lab-plan.md` section 0). Then lab18 is torn down **including** its policy
  assignments, policy definitions and the two custom roles, then the second lab is built.
- **Not yet:** nothing is torn down or built. Still OPEN with Emre: **CAP-500** (the agent's active-flow cap) and the
  day (the vezir recommends 2026-10-14). **Before the teardown** the exact teardown list (enumerated live from lab18)
  goes to the vezir for Emre's final go.
- P52 (re-enable lab18's auto-shutdown) is superseded by the teardown: the schedules are deleted with the resource
  group. If the teardown is not approved, P52 applies as written.
- **GÜN-14 (Emre via the vezir, 2026-10-12 16:40Z):** the second-lab day is **2026-10-14**; lab18's remaining work
  runs on 2026-10-13 as in `second-lab-plan.md` section 0. CAP-500 still OPEN; the teardown still needs Emre's final go
  on the live list.

## P59: docs pass tonight, then close (Emre via the vezir, 2026-10-12 17:40Z, "DOKUMAN-GECE")

No lab work. README: the name-uniqueness note for a second deployment (custom role display names are unique in the
whole Entra tenant, Learn *Azure custom roles*; policy definition names are unique at their definition scope, here
the subscription: the request said "tenant-wide" for both, written precisely here). `cost.md`: the SRE Agent's
always-on cost. Today's results (T16 both, T17, T18c–f, T10e, T07b, rc.9) in the docs. Then a full close: HANDOVER
rewritten so the next session starts at `second-lab-plan.md` §0; CAP-500 OPEN.

## P60: the second lab's agent cap is 1000 AAU a month (Emre via the vezir, 2026-10-12 21:00, "CAP-1000"; closes CAP-500)

The second lab's SRE Agent gets a monthly active-flow allocation of **1000 AAU** (≈ 110 USD at the 0.110 USD per AAU
lab18 was billed), **not** the proposed 500 (the Learn minimum). It is set when the agent is built (2026-10-14) and is
the guard against a runaway loop: past it the agent stops answering instead of spending more. The always-on flow
(4 AAU per agent-hour) is billed separately and is not limited by it. CAP-500 is closed by this decision.

## P61: the skill is deployed by the script, not by Bicep (Emre via the vezir, 2026-10-13, "KALSIN")

Asked: can the skill be deployed with Bicep alongside the rest? Not today: the ARM resource `Microsoft.App/agents/skills`
answers "internal tenants only" in our tenant, so `scripts/deploy-skill.sh` (the agent's data-plane API,
`/api/v2/extendedAgent/skills/<name>`) stays the way to deploy the skill. A Bicep `deploymentScript` wrapper around the
script is **rejected** for v1.0.0. `deploy.md` (section 4) and `architecture.md` say why. No follow-up item: the ARM
path is not re-tried on the second-lab day (Emre's correction, same day).

## P62: a local roll every 15 min bounds the loss of a bad shutdown (Emre via the vezir, 2026-10-13, "T08-FIX"; rc.10)

**Why.** T08 on arc1 (2026-10-13 05:00Z, rc.9) left the pre-reboot ring unreadable after a clean, planned restart
(`docs/tests.md`, T08 research): the Performance Logs & Alerts service did not stop the collector at shutdown
after a long Windows Update preshutdown, so the circular file was never closed. No documented tool reads such a
file (`relog` and `Import-Counter`, every variant: `PDH_BINARY_LOG_CORRUPT`). Until rc.9 everything since the last
export (up to `ExportEveryHours`, 4 h) sat in that one open file. Emre: "no need for repro; move to a setup that
accepts a 15-min loss." KEEP-COPY was not chosen: arc1's ring goes at RING-A's third read as designed.

**What (rc.10, package 1.0.9).**
1. **Roll task.** A third scheduled task `\PerfmonBlackbox\Roll` (SYSTEM, every 15 min, a new DSC resource R7
   `BlackboxRollTask`) closes the ring into `pending\` (reason `roll`): stop, move, start, under the export's lock.
   No relog and no upload. The export is unchanged: it rolls too, relogs every piece, joins them into one CSV, one
   zip, uploads, then deletes the pieces. Accepted loss on a bad shutdown: the open piece, at most 15 min, reported
   as a gap. 15 min is fixed in the package (no new policy parameter).
2. **Capacity (R6).** The pieces wait in `pending\` until the export, so `LocalKeepMB` (not `MaxSizeMB`) now limits
   what a server holds between exports. R6 is Compliant when `LocalKeepMB` holds ≥ 1.5 × `ExportEveryHours` **and** the
   ring holds ≥ 1.5 × 15 min. Defaults (512 MB, 1024 MB, 10 s, 4 h, ~57 KB/sample): ring ≈ 22 h, LocalKeepMB ≈ 52 h.
3. **`machine_off` label (finding d).** The Boot task records each boot time in `state.json` (last 20). A hole that
   contains a recorded boot is `machine_off` (unless the later piece wrapped: `buffer_overrun`), wherever it lies:
   between two pieces or before the first sample. rc.9 named the T08 arc1 hole `collector_restart`.
4. **Unreadable span (finding e).** A file's CreationTime is not the ring's start: Windows gives a file re-created
   under the same name the old creation time (arc1: a ring from 10-13 04:54 showed "created 10-11 12:34"; vm1's
   10-12 `unreadable_ring` gap 11:43–19:02 was too long for this reason). Each start of the collector records its
   time in `state.json`, and a closed piece gets that time as its CreationTime when it is moved to `pending\`.
5. **Roll holes.** A roll's own hole between two pieces (seconds) is `export_roll` like the export's own roll
   (P41), not counted in `complete`. It appears only at intervals under ~5 s.

**Why the export runs relog per file, not one multi-input relog (Emre's question, recorded here).** The first
design (design §2.2) planned one `relog <sources> -b -e` call; session 2 implemented one `relog` per piece and a
join in PowerShell (`Merge-BbCsv`, 56daf3d) without a decision entry: this closes that gap. Reasons:
(1) **one bad piece must not take the good ones down**: lab, arc1, 2026-10-13, on copies: two good files in one call
→ rc 0, merged; a good and the unreadable ring in one call, either order → 0xC0000BF7, **0 rows**
(`files/test-runs/261013-lab18/research-multi-input-relog-arc1.txt`); per file, only the bad piece fails and RING-A
handles it; (2) the gap causes need per-piece facts a merged output loses: which piece a row came from
(`machine_off`, `collector_restart`), each ring's own interval (P37), whether it wrapped (P40), bytes per sample (R6);
(3) pieces can carry different counter lists (G3 lines appear when IIS is installed, T06f): the join makes one union
header. Multi-input would be a shorter call, not a simpler export.

**Tests (lab18, 2026-10-13).** L05 (new cases: roll, boot list, `machine_off` in a leading hole, span from the
recorded start, R6 two-part check), T01 on dc; rollout per P55; on vm1 and arc1: T04 (7 resources), T06, T07 (3
tasks), T08, T09, T10, T11, a new T19 (15-min pieces merged into one CSV, no gap, deleted after upload); T07b
recomputed on arc1; one T15. Not re-run, with reasons in `docs/tests.md`.
- **rc.10** (P62, package version 1.0.9): `PerfmonBlackbox.zip` SHA-256
  `9508003C5BAA8E0FEC8AE292AD32FFC0936685919BDAA4202533F268D6F9C562` (L05 47/47 and lint clean on dc, T01 green on dc
  with 7 resources, 2026-10-13; 12 files extracted and scrub-checked clean before the upload). Two lab findings built
  in: a closed piece with fewer than 2 samples makes `relog` fail with `PDH_LOG_SAMPLE_TOO_SMALL` (0xC0000BF8, dc,
  `files/test-runs/261013-lab18/research-tiny-piece-dc.txt`): such a piece is deleted, not counted as unreadable,
  and a ring younger than 3 intervals is not rolled.

## P63: the export merges with relog, one call per segment (Emre via the vezir, 2026-10-13, "RELOG-RC11"; rc.11)

**Why.** Emre: "if relog can merge, I prefer it (Windows' own tool), but an unreadable .blg must never be fed into it."
He chose rc.11, before v1.0.0, knowing the conditions from the side test (`docs/tests.md`, RELOG-DENE): (a) the rate
values across a boot are tested; (b) relog never gets overlapping or unreadable pieces; (c) the per-piece path stays
only if justified.

**What (rc.11).**
1. **Probe.** `relog -q` on every piece. Unreadable → RING-A as before (P54); fewer than 2 samples → deleted (P62).
   Neither enters a merge.
2. **Order** by the piece's UTC file time (NTFS `LastWriteTimeUtc`), not by its name (the name holds local time).
3. **Segments (guard b).** Consecutive pieces form one segment only if no recorded boot lies between them and their
   local time ranges are strictly increasing (no overlap, no step back). A boot, an overlap or a clock step starts a
   new segment. So relog never computes a rate across a boot (condition a, by construction) or across overlapping data.
4. **Merge.** One `relog <pieces of the segment> -f csv` per segment, usually one call per export. Checked: the output
   is strictly increasing and holds as many rows as the probes' samples.
5. **Join.** The segments are joined as before (union header, only samples after `last_ts`, gaps). Each row's source
   piece comes from the probes' begin/end (second resolution; pieces are at least one roll apart).
6. **Fallback (condition c), kept.** If a segment's merged call fails or its output fails the check, that segment is
   relogged piece by piece: the code used since rc.1, already tested. Without it, one bad merge would block every
   export until `LocalKeepMB` starts dropping data.
7. **Test (condition a).** T08 checks that the first sample after the boot has empty rate cells in the uploaded CSV
   (nothing computed across the boot). Once, on copies of real pre- and post-boot pieces, a multi-input relog across
   the boot records what relog would compute there (evidence).

**Daylight saving time (found 2026-10-13, simulated on dc by moving the time zone back 1 h during a capture,
`files/test-runs/261013-lab18/research-dst-fallback-dc.txt`).** PerfMon writes local time with no per-sample offset.
- At a fall-back (a repeated local hour), the per-piece join of rc.1–rc.10 **drops the repeated hour silently**: it
  keeps only rows newer than the previous one, and the next kept row is one interval later, so no gap is reported.
- At a spring-forward, the 1-h jump is a **false** gap.
- A multi-input relog sorts by local time and **mis-orders** pieces across the change.
- Azure VMs default to UTC (the lab's are UTC); servers with a DST time zone are affected.

**Decided: DST-A** (Emre via the vezir, 2026-10-13 ~12:40 +03; options DST-B recommended / DST-A / DST-C). Why: it
happens once a year on every server in a DST time zone, and he wants it right, not only reported. In rc.11:
- Every sample gets a UTC time. Normally that is the server's own time-zone rule. For a local time that occurs twice,
  the piece's UTC file times (start stamped at the ring start, P62; last write) pick the right one. If they cannot, the
  order inside the piece does: daylight time before the step back, standard time after it.
- The join, the no-overlap rule (`last_ts`, now also kept as `last_ts_utc`) and the gap search run on UTC. **The repeated
  hour is kept.** The CSV keeps PerfMon's local timestamps (the skill is unchanged), so in that one zip they step back
  once.
- The manifest names the change, and neither entry counts toward `complete`:
  - `clock_back`: local time stepped back, nothing lost;
  - `clock_forward`: local time jumped forward, nothing lost (Emre kept this name).
  The manifest also carries `first_sample_utc` / `last_sample_utc`.
- A step back that the time-zone rules do not explain (a clock set back by hand) cannot be ordered. Its samples are
  dropped and reported as `clock_reset`, which counts as a loss.
- A UTC offset change still splits the relog segments (relog sorts by local time).
- Known limit, skill side, not changed in rc.11: the skill's range mode (several zips) drops rows of a later zip whose
  local time is not after the earlier zip's last one, so a zip boundary inside the repeated hour loses those rows in
  the *analysis* (not in the storage).
  **SKILL-SONRA (Emre, 2026-10-13): not fixed before v1.0.0.** A post-v1.0.0 item: a skill version bump (order the
  rows of a range by the CSV's `Utc` column) and then T15–T17 again. rc.11 and the v1.0.0 plan are unchanged.

## P64: least privilege for the skill is SRE Agent Author + Standard User (P30 trial, 2026-10-13: PASS)

The trial planned in P30 and `second-lab-plan.md` §0. On lab18 the lab service principal got **SRE Agent Author** (it
already held Standard User) on the agent resource only, and **SRE Agent Administrator was removed** (09:10Z). After
10 minutes for the role change to take effect: `deploy-skill.sh` dry run and `--apply` (PUT, read back identical,
09:20Z), then T15 on vm1 (the agent fetched the newest zip, hash checked, converter 61 rows, 0 bad cells, PASS 09:23Z).
Evidence: `files/test-runs/261013-lab18/p30-*.txt`. So adopters need **Author + Standard User** on the agent to deploy
the skill and ask it; Administrator is not needed. The README, `deploy.md`, `security.md` and the script header say
so. Administrator is **not** put back on lab18 (P30: only if the trial failed); Author and Standard User stay until the
teardown, where they are removed with the agent.
- **rc.11** (P63, package version 1.0.10): `PerfmonBlackbox.zip` SHA-256
  `806BCADB69F556401DE19754AEB649B7611EB1AE18AA106A5BF0A537A99363DD` (L05 56/56 and lint clean on dc, with the relog
  merge of real pieces in one call, the fallback, and the DST-A cases in W. Europe time around the 2026 transitions;
  T01 green on dc with 7 resources, 2026-10-13; 12 files extracted and scrub-checked clean before the upload).

## P65: lab18 is torn down (Emre via the vezir, 2026-10-13, gate TEARDOWN-LAB18: "GO")

Every planned lab18 test is green on rc.11 (vm1 and arc1, tests.md "rc.11 on lab18"; T06f part 2 green), so lab18 is
removed in this order: (1) the role assignments of the policy identities (pbb-vm, pbb-arc-storage, pbb-gc-prereq),
(2) the role assignments on the product storage account (per-machine Writer with ABAC, package and capture Readers,
lab Contributor), (3) the dc verifier's role assignments, (4) the lab SP's SRE Agent Author + Standard User on the lab
agent, (5) the three policy assignments, (6) the four `perfmon-blackbox-*` definitions (subscription scope), (7) the
two custom roles, (8) the resource group via `azd down --purge` (Key Vault purged). Then (9) the lab register row of
the private lab template goes DOWN and its audit runs. Other resource groups are not touched. Anything unexpected (a
resource that does not delete, a dependency reaching another resource group) stops the teardown and is reported.
Evidence: `files/test-runs/261013-lab18/teardown.txt` (not in the repo). The second lab (10-14) is built from the
template again (second-lab-plan.md). The v1.0.0 tag is not part of this decision (P31, Emre's gate).

**Done 2026-10-13:** steps 1–7 15:11–15:13Z (20 role assignments, 3 policy assignments, 4 definitions, 2 custom roles;
guards: nothing outside rg-lab18), `azd down --purge --force` 15:14–15:32Z (Key Vault and Log Analytics purged), no
cross-resource-group dependency; afterwards no resource or role assignment in rg-lab18, no definition or custom role,
no deleted vault; the template's register row DOWN and its lab-audit **CLEAN**.

## P66: v1.0.0 is released from rc.11, same zip (Emre via the vezir, 2026-10-13, gate P31: "GO / YAYINLANSIN")

- **What:** tag `perfmon-blackbox/v1.0.0` and a GitHub release (not a pre-release) whose only asset is the rc.11 zip,
  **unchanged**: SHA-256 `806BCADB69F556401DE19754AEB649B7611EB1AE18AA106A5BF0A537A99363DD`. Nothing that ships (package,
  policy generator, Bicep, skill v2.2, scripts) changed after rc.11 (`git diff` against the rc.11 commit is empty for
  those paths), and that zip is the one every lab18 test passed on (tests.md "rc.11 on lab18", P65).
- **Why the same zip:** a rebuild would give a new hash that no test has seen. The release notes say so.
- **Version label:** the definitions' `--version` is only the guest assignment's label (the zip is identified by its
  SHA-256); adopters pass `1.0.0` for this release and a higher one for each later release. The lab ran it as 1.0.10.
- **Known limits at v1.0.0** (in the docs): OPEN-2 (P34), the skill's range mode across a DST fall-back (P63,
  SKILL-SONRA), short recurring stalls; the README-only fresh-eyes deploy runs on the second lab (10-14) after the
  release; what it finds goes into v1.0.x.
- **Before publishing:** the zip is downloaded from rc.11, its SHA-256 checked, every file extracted and scrub-checked
  (P29/P31); the rc pre-releases stay as they are (lab history), marked superseded in the v1.0.0 notes.

**Done 2026-10-13:** tag `perfmon-blackbox/v1.0.0` on e0005bf (main), release
https://github.com/VezirOrg/sreagent-playbook/releases/tag/perfmon-blackbox/v1.0.0 (latest, not a pre-release); the
asset downloaded from the public URL hashes to `806BCADB…63DD`; zip and notes scrub-checked (65 entries, clean); local
tests L01, L02, L04, L07–L09 green and every relative docs link resolves.

## P67: the second lab is built today and shared with blog post 6 (Emre via the vezir, 2026-10-13 16:30Z)

**Why.** Emre approved the shared lab ("ORTAK-LAB": blog post 6, part 1 of the "black box for Windows servers" series,
uses this lab) and asked to start today instead of 10-14 (P58 moved).
**What.**
- A new lab from the private lab template (latest template), **dc + one IIS member (`vm1` in the record), no SQL, no
  Arc** (Arc is out of scope today; the post quotes lab18's Arc evidence). Agent active-flow cap 1000 AAU/month (P60).
  Register row in the template's lab register.
- **Fresh-eyes deploy of v1.0.0**: steps 0–4 of `docs/deploy.md` read **only at the tag** (README and the docs it
  links), storage mode (P45), timed per step. Every doc gap goes to a v1.0.x note; a gap that does not block the lab
  does not stop it.
- **`ExportEveryHours = 1` in this lab only** (an assignment parameter, `parameters.md`) so the first zip arrives within
  the day; the product default stays 4 (P19).
- Skill upload with SRE Agent Author + Standard User (P64), then one agent question in a new thread.
- For the post (blog request list, D96): timings and doc errors, seven text captures, the agent question with its
  thread ID, under `files/post6-shots/` (Drive, masked before the blog copies them). Emre takes the six portal
  screenshots; each is signalled to the vezir when ready.
- Ends before 21:45Z (P50; plan ~20:00Z). Stop and report if the template build fails or the guest assignment is not
  Compliant at 18:30Z. Other resource groups (rg-sqlmcp1, rg-lab13, rg-costexport) are not touched.
- **Teardown only on Emre's go** (list to the vezir), the same order as P65.
- The full stage suite (second-lab-plan.md §1) is not run today; DoD-1 "all stages green on a fresh lab" stays open.

## P68: lab20 keeps the template's nightly auto-shutdown; the work goes on over two days (Emre via the vezir, 2026-10-13 ~17:12Z, "KAPANMA-AÇ")

**Why.** Emre prefers the lab to stop tonight as the template does, and the deploy to continue tomorrow, over keeping the
VMs up past 19:00Z. **What.** The auto-shutdown schedules of dc and vm1 (disabled at 17:00Z to keep the VMs up for the
first zip) are **Enabled** again: 22:00 Turkey time = 19:00Z. Until then: steps 0–3, the skill, the text captures. The
first zip, the manifest capture and the agent question (S4, S6, C4, D) most likely move to 2026-10-14. When the VMs start
tomorrow, the Boot task taking the old ring into a pending piece is expected (P62); the first export covers the time
since the collector started, with the off hours reported as a gap. Emre's global lab automation (~00:46 +03, disks to
Standard_LRS) also applies and is accepted. P67 otherwise unchanged; the register row drops the "Disabled" note.

## P69: lab20's auto-shutdown is disabled again; today's plan is finished tonight (Emre via the vezir, 2026-10-13 ~18:00Z; reverses P68)

**Why.** Emre: the 22:00 +03 (19:00Z) stop is blocked so the first zip and the agent question happen this evening.
**What.** The dc and vm1 auto-shutdown schedules are **Disabled** again (verified). Today: S2+S3, the first zip (S4, C4),
the agent question (D, S6); everything ends before 21:45Z (Emre's global automation stops the lab ~21:46Z anyway). Then
the teardown list goes to the vezir; nothing is deleted without Emre's go. P68 no longer applies.

## P70: v1.0.1 after lab20 (B1 + doc fixes, Emre's gate); S2 skipped (Emre via the vezir, 2026-10-13 ~18:25Z, "V101", "S2 ATLA")

**Found on lab20 (fresh-eyes run, P67).**
- **B1 (product, storage mode):** the policy state of `perfmon-blackbox-vm-storage` stays NonCompliant while every guest
  assignment is Compliant. Evaluation details: the only failing expression is the existenceCondition's
  `guestConfiguration.contentUri` equals the storage URL; Azure returns `contentUri` = null on a guest assignment with
  `contentManagedIdentity` = system. Effect: the Policy view is wrong and every remediation redeploys; recording and
  uploads are not affected. GitHub mode is not affected.
- **Doc findings** (deploy.md / parameters.md at v1.0.0): F1 remediation right after a new assignment finds nothing
  (needs `--resource-discovery-mode ReEvaluateCompliance` or a scan first; step 0 and step 3); F2 step 2's
  `az policy definition create` drops the generated `metadata` and `displayName` (storage mode depends on the metadata);
  F3 nobody is told to grant Blob Data Contributor on `packages` to the upload host, nor that the host must reach the PE;
  F4 `ExportEveryHours` is a string parameter; F5 which subnet for the PE, and the `packageContainerResourceId` output;
  F7 the `typeHandlerVersion` check is not the agent version. Details: `files/post6-shots/A-timings-and-doc-findings.md`.

**Decided.**
1. **V101:** once lab20 is done, prepare **v1.0.1**: B1 (in storage mode the existenceCondition checks
   `contentManagedIdentity` = system and `contentHash`, not `contentUri`) and the doc fixes F1–F5 (F7 with them). The
   release is Emre's gate (P31): asked through the vezir before publishing. A package or definition change gets an rc and
   a lab test of storage mode (T18) first.
2. **S2 is skipped** in post 6 part 1: the policy view is told by S3 (guest assignment Compliant) and C6 (the
   `complianceStatus` call).

## P71: a planted problem on lab20 for post 6 part 1, and a second agent question (Emre via the vezir, 2026-10-13 ~18:30Z)

**Why.** Emre: an analysis that finds a real problem shows the product better in part 1 than "nothing critical". The
post says plainly that **the problem was created on purpose** (synthetic load, lab only).
**What.** On vm1, the T16 plant (`tests/lab/guest/make-trouble.ps1`, lab only, never shipped, P43: memory leak + CPU
burst) at `-Scale 0.5 -LeakMBPerHour 1200`: a leak in `bbleak` for ~22 min (~450 MB) and all CPUs ≥ 95 % in `bbcpu` for
6 min (above the skill's 5-minute threshold). Its `truth.json` is the ground truth (start/end times recorded). The
scheduled hourly export (~19:07Z) covers the window; then the same deploy.md question in a new thread, the report scored
against the truth with `tests/scoring/score.py` (T16 rubric). Emre may have a Bastion session on vm1 meanwhile: the CPU
burst makes it slow for 6 minutes, and his session's own processes are not part of the truth. Ends before 21:45Z;
teardown is asked afterwards.

## P72: lab20 stays for the v1.0.1 test; a morning restart is approved (Emre via the vezir, 2026-10-13 ~18:40Z, KEEP-V101)

**Why.** v1.0.1 (P70) is tested on the lab that found B1, instead of a rebuild. **What.** lab20 is **not** torn down
tonight (the teardown question is dropped for now). Emre's global automation stops the VMs ~21:46Z and moves the disks to
Standard_LRS (accepted; disk SKUs are not restored, P51). Tomorrow morning the VMs may be started and the v1.0.1 work
continued without waiting for Emre (his word). Plan: start the VMs → apply the v1.0.1 rc package/definitions in lab20 →
the Policy view turns Compliant (S2 for Emre) → storage mode checked (T18 on vm1) → the release is asked of Emre (P31).
The register row says "kept for v1.0.1". Tonight: finish the planted-load question (P71) and its score, then start the
v1.0.1 preparation (B1 fix, doc fixes F1–F5, F7); every lab run ends before 21:45Z.

## P73: for approved work, the vezir decides lab builds/teardowns and playbook releases (Emre via the vezir, 2026-10-13 ~21:55 +03, standing)

**What.** Emre's new standing permission: within work he has approved, building and tearing down a lab and publishing a
playbook release (here **v1.0.1**, P70) are done **without waiting for Emre**: the vezir decides and reports to him.
So P31's "a release is Emre's gate" and P65/P67's "teardown on Emre's go" now go to the **vezir** for approved work.
Unchanged: blog publication stays Emre's; OPEN-1/OPEN-2 (P8) stay Emre's; the release checks of P31 (SHA in decisions
before publishing, every file extracted and scrub-checked) stay.
**For tomorrow:** if the v1.0.1 tests are green, v1.0.1 goes to the vezir for the release decision; lab20's teardown,
when the work is done, is the vezir's go.

**P71 done 2026-10-13:** plant 18:31:50–18:54:20Z (leak `bbleak` 1200 MB/h; CPU `bbcpu` 18:36:50–18:42:51Z); the
19:07Z export covered it; second question in a new thread 19:27:07–19:32:29Z; scored **100/100 PASS** (both plants,
nothing invented). Note for the post: the report calls `gc_worker` a "GC exerciser"; it is the Machine Configuration
agent's worker. Evidence: `files/post6-shots/D2-*` (masked).

## P74: the v1.0.1 lab check runs on lab20; the lab tests take the lab folder from `BB_LAB` (the vezir, 2026-10-14 ~02:05Z)

**What.** The P72 plan, run by this session: the v1.0.1 storage definition (`perfmon-blackbox-vm-storage`, generator at
v1.0.1, version label `1.0.1`, the **v1.0.0 zip and hash unchanged**) replaces the v1.0.0 one in the subscription;
compliance scan, then a remediation with `--resource-discovery-mode ReEvaluateCompliance`; the Policy view must turn
Compliant (B1), the remediation must deploy nothing to Compliant machines (no needless redeploy), and T18 storage mode
must pass on vm1. Green → v1.0.1 goes to the vezir for the release (P73).
**Test harness.** `tests/lab/common.sh` hard-coded lab18's folder (`.lab/perfmon-blackbox`); lab20 lives in `.lab/lab20`
(template layout, same `scripts/vmssh`). `common.sh` now reads the lab folder from `BB_LAB` (default unchanged), and the
package hash from `PKG_SHA256` when no `pbb-package.env` exists (as before). Tests that derive the lab18 account name
(`stbb…`) are not run on lab20; T18 does not use it.

## P75: GitHub mode's Policy view is measured on lab20 before v1.0.1 (the vezir, 2026-10-14 ~03:00Z, decision A)

**Why.** P70's "GitHub mode is not affected" was never measured, and a lab result argues against it: in T18c (lab18,
2026-10-12, commit 7db0e9f) the guest assignment GET returned no `contentUri` in GitHub mode either, while the GitHub-mode
existenceCondition still compares `contentUri` with the release URL. If the policy engine sees that null too, GitHub mode
has B1 as well (Policy view NonCompliant, every remediation redeploys). The v1.0.1 storage-mode check itself is green
(P74: Policy view Compliant, 0 deployments in two remediations, T18 vm1 storage PASS).
**What.** On lab20, vm1 only, by the P48 rule (never both modes over one machine): vm1 is excluded from `pbb-vm-storage`
(`notScopes`), a GitHub-mode assignment `pbb-vm` (definition `perfmon-blackbox-vm`, v1.0.1 generator, the v1.0.0 asset
URL and hash, label 1.0.1) is created on vm1 with the four roles of deploy.md step 3, then scan → remediation
(ReEvaluateCompliance) → wait for the guest assignment Compliant from GitHub → scan → record the Policy view and a second
remediation's deployment count. Then back: `pbb-vm` and its role assignments removed, vm1's exclusion removed, scan,
remediation, vm1 Compliant in storage mode again (T18 vm1 storage). dc stays in storage mode throughout. Ends before 21:45Z.
**Then.** Clean → P70's claim is measured; the release commit is prepared and pushed, the tag waits for the vezir's
publish decision. B1 in GitHub mode too → the fix (both modes check `contentHash` and the identity, not `contentUri`) is
written here first and brought to the vezir **before** it is applied; if the zip SHA would have to change: stop.
**Lesson (2026-10-14):** a remediation must be created at or below its assignment's scope. `pbb-vm` sat on the VM, so
`az policy remediation create -g <rg>` was refused (`InvalidCreateRemediationRequest`, "out of scope"); use
`--resource <VM ID>` (and `az policy remediation show -n <name> --resource <VM ID>`). Lab poll loops stop on a create
error instead of polling a remediation that does not exist (this cost 30 minutes once).

## P76: B1 is in GitHub mode too; proposed fix (measured 2026-10-14 on lab20 under P75; fix NOT applied, awaits the vezir)

**Measured (vm1, GitHub mode, `pbb-vm`, v1.0.1 definitions):** vm1 excluded from `pbb-vm-storage` and `pbb-vm` assigned
02:55–02:56Z. The service re-synced vm1's guest assignment to GitHub mode on its own, **before any remediation**
(contentManagedIdentity null, label 1.0.1, Compliant 03:11Z; P48's metadata re-sync). The guest assignment GET returns
`contentUri` = null in GitHub mode as well (as T18c saw on lab18). Scan 03:36:55–03:44:38Z: the Policy view of `pbb-vm` on
vm1 is **NonCompliant** (03:38:08Z) and the only failing expression is `guestConfiguration.contentUri`. The remediation
(ReEvaluateCompliance, 03:44:44–03:59:20Z) **deployed 1** to a machine that was already Compliant. So P70's "GitHub mode
is not affected" was wrong: B1 is in both modes. Evidence: `.lab/lab20-logs/v101/gh/`.
**Proposed fix (generator only; the zip and its SHA do not change):** the third existenceCondition term never reads
`contentUri`. Storage mode keeps `contentManagedIdentity equals system` (P74, green); GitHub mode checks
`contentManagedIdentity notEquals system` (a GitHub-mode assignment has no identity, so null passes; a machine still on a
storage-mode assignment fails and is redeployed, which keeps P45's purpose). Which release a machine runs is still pinned
by `contentHash` (P32). L08 asserts that no definition's existenceCondition reads `contentUri`.
**Test of the fix (if approved):** while vm1 is still on `pbb-vm`: re-create `perfmon-blackbox-vm` with the fixed generator,
scan, the Policy view of `pbb-vm` on vm1 Compliant, a ReEvaluateCompliance remediation deploys 0; then vm1 back to
storage mode (P75) and T18 vm1 storage PASS. v1.0.1 then ships the fix for both modes.

## P77: v1.0.1 is not released until it is proven on an Arc machine in the lab (Emre via the vezir, 2026-10-14 07:15 +03)

**Emre:** "Arc da ekle laba mutlaka" ("add Arc to the lab, without fail"). The CHANGELOG's "Arc: not verified in the lab"
note is withdrawn: **Arc evidence is a precondition of the v1.0.1 release.**
**What.** An `arc1` is added to lab20 the way lab18 had one (Learn: "Evaluate Azure Arc-enabled servers on an Azure VM",
with the private lab template's Arc support); the template's lab register row of lab20 lists arc1 and the Arc resources
to remove at teardown. On arc1, with the P76 generator: **storage mode** (`perfmon-blackbox-arc-storage`): Policy view
Compliant, a ReEvaluateCompliance remediation deploys 0, T18 arc1 storage PASS (upload with HIMDS); **GitHub mode**
(`perfmon-blackbox-arc`, by the P48 procedure): the same measurement. If time is short, the vezir is asked which first.
The vm1 steps (P76 test, back to storage, T18) finish as planned. Everything ends before 21:45Z; if it does not fit
today, lab20 stays up tonight (KEEP) and the work goes on tomorrow, said to the vezir early. **Stop:** Arc onboarding
blocked by a subscription policy or quota. The release commit carries the Arc results; no tag.
**Addendum (the vezir for Emre, 2026-10-14 07:24–07:35 +03, ARC-ABC):** Emre takes three Arc screenshots, so arc1 **ends in
storage mode**, Compliant, with at least one export uploaded, and stays until his shots are taken (teardown on the vezir's
GO). No agent analysis on arc1. Order on arc1 therefore: **GitHub mode first** (`pbb-arc`, measured), then storage mode
(`pbb-arc-storage`, measured: it is also the final state). A first `pbb-arc-storage` (04:24Z) was removed with its role
assignments before any remediation deployed (its remediation cancelled) when this order was set (04:28Z).

## P78: our own lab machine names are not masked (Emre via the vezir, 2026-10-14 ~08:00 +03)

The names of our own lab machines (dc, the template's IIS member, arc1, SQL members) are exempt from the alias / masking
rule: they may appear as they are in the public repo, the blog and screenshots. Existing docs are **not** rewritten (they
keep `vm1`); new text does not have to translate either way. Still masked: subscription and tenant IDs, admin accounts,
and all third-party data. Note: the scrub denylist (private, shared, outside this playbook) still lists the IIS member's
name, so until the vezir changes the denylist this playbook keeps writing `vm1` in committed files.

## P79: the B1 checks become tests of their own, in v1.0.1 (Emre via the vezir, 2026-10-14 ~08:40 +03)

- **T20 Policy view agrees with the machine**: after a compliance scan, the policy state of a server whose guest
  assignment is Compliant (with the expected identity) is **Compliant**. T20a storage mode on the Azure VM, T20b GitHub
  mode on the Azure VM, T20c storage mode on Arc, T20d GitHub mode on Arc.
- **T21 No needless redeploy**: a remediation with `--resource-discovery-mode ReEvaluateCompliance` on a scope whose
  servers are Compliant deploys **0** (T21a–d, the same four cases).
- **L08** (extended): no definition's existenceCondition reads `contentUri`; storage mode checks `contentManagedIdentity
  equals system`, GitHub mode `notEquals system` (both kinds, both modes).
T20/T21 are lab steps (scan, `az policy state list`, `az policy remediation create … show`), recorded with times in
tests.md; the lab results of 2026-10-14 (lab20: vm1, arc1) go into the v1.0.1 release commit.

## P80: an `Audit` guest assignment is no longer repaired once B1 is fixed; proposed fix (lab20, 2026-10-14; NOT applied, awaits the vezir)

**Seen.** vm1 went back from GitHub to storage mode by the service re-sync (04:45–05:11Z). Its guest assignment is
Compliant with identity `system` but `assignmentType` **Audit** (05:11Z, 05:37Z, still at 06:39Z: past Learn's "may
temporarily appear … typically resolves within one hour", Learn: machine configuration assignments). dc and arc1 are
ApplyAndAutoCorrect. On lab18 (tests.md "rc.11 on lab18") an Audit assignment meant the agent **only tests, never
applies** (no auto-correct), and it was cured only by a remediation that rewrote the assignment, i.e. by B1's needless
redeploy. With B1 fixed (P76) the existenceCondition does not look at `assignmentType`, so a Compliant Audit assignment
counts as present: **T21 now prevents the cure**. The recording itself is not affected (the package is applied; vm1
records and uploads: T18 PASS 05:11Z, last upload 06:17Z).
**Proposed fix (generator only; the zip and its SHA do not change):** add
`guestConfiguration.assignmentType equals ApplyAndAutoCorrect` to the existenceCondition in both modes and both kinds; L08
asserts it. Then an Audit assignment is NonCompliant in the Policy view and the next remediation writes
ApplyAndAutoCorrect (one deployment, a needed one). Test: re-create the definitions, scan: vm1 NonCompliant (Audit);
remediation deploys 1 (vm1 only); after it, vm1 ApplyAndAutoCorrect and Compliant, T20/T21 green again on all three.
**APPROVED (the vezir under P73, 2026-10-14 ~09:15 +03).** Conditions: (1) **stability**: after the fix vm1 is watched
over at least two service refresh cycles; if the service flips it back to Audit and remediations keep redeploying
(flapping), the fix is a new B1: stop and report. (2) **new machine**: Learn says `assignmentType` may show Null for up to
an hour after a new assignment; with the new condition such a machine shows NonCompliant meanwhile and a remediation may
deploy needlessly. That window is measured (on dc or arc1 if possible, else from the evidence) and written here and in
the CHANGELOG as a known window.

## P81: in-machine screenshots on arc1 (Emre via the vezir, 2026-10-14 ~09:10 +03, "İÇ-M1-M4")

Emre takes four screenshots inside arc1 over RDP: M1 Performance Monitor → Data Collector Sets → User Defined →
PerfmonBlackbox Running; M2 Task Scheduler → the PerfmonBlackbox tasks; M3 Explorer at `C:\ProgramData\PerfmonBlackbox`;
M4 Event Viewer → the PerfmonBlackbox "export uploaded" event. This session tells the vezir how arc1 is reached and
which credential applies (by the Key Vault secret's name, never its value). Nothing on arc1 is changed for the shots.

## P82: the agent analysis shots are redone on arc1 (Emre via the vezir, 2026-10-14 ~09:15 +03, "AGENT-ARC")

After P80 is green: one idle question on arc1, then the T16 plant on arc1 (CPU burst + memory leak,
`tests/lab/guest/make-trouble.ps1`, lab only; same settings as P71) and a second question in a new thread, scored with
`tests/scoring/score.py` (T16 rubric). Emre takes the thread and consumption screens. ExportEveryHours is 1 on arc1, so
each question waits for the next hourly export after its window. Ends before 21:45Z; the plan and times go to the vezir
first.

**P80 measured (lab20, 2026-10-14).** Fix applied 06:42:15Z to `perfmon-blackbox-vm-storage` and `-arc-storage`. Scan
06:42–06:50Z: vm1 **NonCompliant** (Audit), dc and arc1 Compliant. Remediations: arc1 0 deployments (07:03Z), vm1
**1 deployment** (07:04Z); vm1's guest assignment Pending/ApplyAndAutoCorrect at 07:03:58Z, Compliant/ApplyAndAutoCorrect
07:17Z. Second scan 07:17–07:29Z: all three Compliant; second remediations 0 and 0 (07:42Z). Condition (1) (stability)
is being watched (`p80/watch2.log`, every 5 min until ~10:45Z, with each machine's last check time). Condition (2): the
deployment itself writes ApplyAndAutoCorrect (vm1 07:03:58Z, arc1 05:09Z and 06:05Z), so no Null window was seen after
a remediation. **But Null was seen on existing assignments:** at 02:10:12Z, before any change today, dc's and vm1's
guest assignments (written by v1.0.0, last check 21:32Z/21:16Z the night before, VMs stopped overnight) had
`assignmentType` **null**; after the definition update and scan (02:18Z) both read ApplyAndAutoCorrect with the same
last check time, i.e. the service filled it in, not the agent. Under P80's `equals ApplyAndAutoCorrect` a scan in such a
window marks the machine NonCompliant and a remediation then redeploys it once (needless, harmless: same content). That
is a small B1 relapse, not flapping. Proposed follow-up: P83.

**P82 done (lab20 arc1, 2026-10-14).** Idle question 08:17–08:23Z (the 08:05Z start failed before reaching the agent: the
timer ran direnv in the lab folder, which has no az login), on the zip 07:07–08:06Z: verdict "not hard to use" (a
Windows Update burst ~07:45 that resolved within ~5 min; the Machine Configuration worker as background). Plant started
08:25:03Z (5 min late; the first start attempt at 08:23Z silently did nothing because the helper's guest-script path
resolved from `$0` under `sh -c`): leak 08:25–08:47Z, CPU 08:30–08:36Z. Hourly export 09:07Z covered it
(08:07–09:06Z, complete, 0 gaps). Second question 09:10–09:17Z: "hard to use for ~6 minutes (08:30–08:36)", both
problems found, **95/100 PASS** (R1 0: a causal word without a LINK line). No P83 scan or remediation fell inside the
plant window (P83's ended 08:16:50Z; P85's scan 08:42–08:50Z is evaluation only). Evidence (masked) in the local lab
logs; thread IDs to the vezir.

## P83: P80's condition checks "not Audit/ApplyAndMonitor" instead of "equals ApplyAndAutoCorrect" (lab20, 2026-10-14; PROPOSED, NOT applied, awaits the vezir)

**Why.** P80 measured: `assignmentType` can be **null** on a healthy existing assignment for hours (02:10Z evidence above),
and Learn says it may be Null after a new assignment. `equals ApplyAndAutoCorrect` turns every such window into a
NonCompliant state and a needless redeploy. What P80 must catch is a *wrong* mode, not a missing value.
**Proposed fix (generator only; the zip and its SHA do not change):** the existenceCondition term becomes
`guestConfiguration.assignmentType notIn ["Audit", "ApplyAndMonitor"]` (Learn does not say how null meets `notIn`; null passing `notEquals` is measured: P76 GitHub mode,
identity null, Compliant 04:16Z. The lab test below checks `notIn` on null; if it fails, two `notEquals` terms) in both modes and both kinds; L08 asserts it. **Test:** re-create the two storage definitions, scan, all three
Compliant; remediation 0 deployments. The Audit case is not reproducible on demand, so the Audit branch is covered by L08
and by P80's measurement (the operator differs only in how null is treated). If the vezir prefers to keep P80 as is,
the CHANGELOG states the null window as a known window instead.
**APPROVED as (a) (the vezir under P73, 2026-10-14 ~10:45 +03).** Apply now: `notIn ["Audit", "ApplyAndMonitor"]` (fallback
two `notEquals` terms if null does not pass); re-create the two storage definitions, scan, remediate, expect 0 deployments
everywhere; condition (1) restarts on the P83 definitions (at least two refresh cycles, no flapping; stop at once on a
flap); L08 asserts the term; test-plan.md and tests.md get a test row for it (P79 style); the CHANGELOG states the null
window openly (seen after the nightly stop, filled in by the service), that P83 tolerates it, and that the null case is
"verified by logic, measurement pending". **Release timing:** v1.0.1 does not ship today. Tomorrow morning after the
nightly stop: start the VMs, scan, expect Compliant and 0 deployments (that is the null measurement); then the release
commit and the vezir tags. lab20 is not torn down today (normal nightly stop before 21:45Z; teardown after the check). If
the check fails: fix first, release after.
**AGENT-ARC (P82) GO (the vezir, same message):** idle question ~08:05Z, plant ~08:20Z, second question after the ~09:07Z
export, scored by ~09:30Z; thread IDs to the vezir; any P83 scan or remediation inside the plant window is named in the
report.

**P83 measured (lab20, 2026-10-14).** Definitions re-created 07:46:44Z; scan 07:46–07:59Z: vm1, dc and arc1 Compliant;
remediations 0 and 0 (08:16:50Z). No machine had a null `assignmentType` during the run, so the null case is still
pending (T22b, next morning). Condition (1) restarted on the P83 definitions (`p80/watch2.log`).
**P83 condition (1) CLOSED (stable).** 21 samples 07:44–09:26Z, every one Compliant/ApplyAndAutoCorrect on all three; agent
reports since the P83 definitions: vm1 08:44 and 09:16Z, dc 08:26 and 09:13Z, arc1 08:12 and 09:24Z; no remediation
needed (P85's scan 08:42–08:50Z changed nothing). No flapping. The watcher keeps running to ~10:45Z as a spare.

## P84: the repo keeps "vm1" for the lab's web member (Emre via the vezir, 2026-10-14 ~11:05 +03, "REPO-VM1")

**What.** The playbook's docs, tests and evidence keep calling the Azure VM member `vm1`; its real lab name stays on the
scrub denylist and nothing in the repo changes for this decision (P78 still lets other own lab machine names, such as
`arc1` and `dc`, appear). The blog uses the real name and links it to `vm1` in one sentence; that is the blog's business,
not this repo's.

## P85: S2-new showed pbb-arc-storage as "0 out of 0" in the portal; the backend counts arc1 (lab20, 2026-10-14 ~08:30Z)

**Seen (Emre, portal Policy → Compliance, scope rg-lab20, ~08:30Z):** pbb-vm-storage "100 % (2 out of 2)",
pbb-arc-storage "100 % (0 out of 0)". **Checked 08:36Z, without touching arc1:** the Policy Insights API (`az policy state
list` / `summarize`, latest and all records) and Azure Resource Graph (`policyresources`, the portal's source) both
hold arc1 (`Microsoft.HybridCompute/machines`) as **Compliant** under pbb-arc-storage, definition
perfmon-blackbox-arc-storage, 1 of 1, latest record 08:05:46Z. The record history is continuous (06:28, 06:43, 06:56,
07:18, 07:35, 07:48, 08:05Z): the P83 re-creation at 07:46Z did not wipe it, and the 07:46–07:59Z scan evaluated it
(07:48:05 and 07:48:23Z). The "arc1 Compliant" readings of P80/P83 come from these policy states, not from the guest
assignment. pbb-arc-storage has no notScopes; arc1 is in rg-lab20 and matched (it has states). **So it is not a product
bug and not a missing scan:** the portal row did not reflect the backend at that moment (display/caching on the portal
side; not reproducible from the APIs). **What to do:** reload the Compliance blade (or open the assignment); retake S2-new
when it shows 1 out of 1. No change to the lab or the product.
**P85 revised (~08:50Z): "the portal lagged" is withdrawn, the cause is open.** After a refresh (Emre ~08:40Z) the blade
still shows 0 of 0, and the assignment's detail page (~08:45Z) shows "No resources found" with no resource-type or
location filter. Re-checked: every API returns arc1 for pbb-arc-storage: Policy Insights `queryResults` at the
subscription (1 row), `summarize` at the subscription, the resource group and the management group (1 compliant),
Resource Graph `policyresources` (1 row, Compliant, stateWeight 200, isDeleted false, the management group set). Field by
field, arc1's record under pbb-arc-storage equals vm1's under pbb-vm-storage except the assignment, the definition, the
resource ID/type and the timestamp. Both definitions are mode Indexed, version 1.0.0; both assignments definitionVersion
1.*.*, enforcement Default, location swedencentral. Differences that remain: (1) **two resources are named arc1** in
rg-lab20, the Azure VM that hosts the Arc agent (lab only) and the Arc machine; (2) pbb-arc-storage was created today
05:37Z, pbb-vm-storage yesterday 17:07Z (no daily evaluation cycle has run for it yet); (3) the resource type. No portal
evidence ever showed arc1 counted under an Arc assignment: T20c/T20d were measured with the CLI only. **Not a definition
bug as far as the evidence goes** (the states exist, are correct, and remediation acts on them); a portal display issue
that cannot be reproduced from any API. Next: (a) Emre opens the Arc machine arc1 → Policies to see whether
pbb-arc-storage is listed there; (b) re-check the blade after the daily cycle (by ~05:37Z tomorrow), with tomorrow's
null check. No definition change.
**P85 CLOSED (the vezir, ~08:55Z).** Emre changed the portal's scope selection and the Compliance blade then showed
pbb-arc-storage "100 % (1 out of 1)" and pbb-vm-storage 2 of 2. **Cause: the portal's scope filter** (Emre's verdict);
the targeted scan started 08:42Z may have finished around the same time and is noted as a possible contributor only.
**No playbook change.** The CLI and Resource Graph were right all along; candidates 1–3 above are dropped. T20c/T20d stay
CLI measurements; Emre's S2-new shot is the first portal evidence of the Arc assignment counting arc1.

## P86: v1.0.1 ships today, before T22b (Emre via the vezir, 2026-10-14 ~12:50 +03, "YAYIN-BUGÜN")

**What.** v1.0.1 is released on 2026-10-14, not after T22b. Reverses P83's "Release timing" (release after the next
morning's null check). The release commit applies the named stash (`bbbcac9…`, the v1.0.1 doc edits), the CHANGELOG
"Unreleased" becomes `perfmon-blackbox/v1.0.1 (2026-10-14)`, and it is pushed to `main`; the vezir then tags
`perfmon-blackbox/v1.0.1` and attaches the **identical** `PerfmonBlackbox.zip` (SHA-256
`806BCADB69F556401DE19754AEB649B7611EB1AE18AA106A5BF0A537A99363DD`, P31: the v1.0.0 asset, every file scrub-checked
for v1.0.0). Between the push and the tag, deploy.md on `main` names an asset URL that does not exist yet; the vezir
tags right after the push.
**The null window in the CHANGELOG:** tolerated by P83 by logic; measurement pending (T22b, 2026-10-15 morning); if it
fails, v1.0.2. The P70 correction (GitHub mode was affected too) stays stated openly, and the B1 tests T20–T22 are
listed with their results.
**T22b becomes a post-release check.** lab20 keeps running (nightly stop as usual) for T22b on 2026-10-15 morning. Green:
tests.md and the CHANGELOG say what was measured. Red: the P83 fallback (two `notEquals` terms) ships as v1.0.2, same zip.

**P86 done (the vezir, 2026-10-14 10:32:53Z):** tag `perfmon-blackbox/v1.0.1` on 63040d9 (main), release
https://github.com/VezirOrg/sreagent-playbook/releases/tag/perfmon-blackbox/v1.0.1 (Latest, not a pre-release), only
asset `PerfmonBlackbox.zip`. The vezir downloaded it from the public URL used in deploy.md: SHA-256 `806BCADB…63DD`,
matches (P31). Before the push this session checked the same SHA on the v1.0.0 asset and the lab copy. Release notes
scrub-checked clean. T22b stays a post-release check (2026-10-15 morning); if it fails, v1.0.2.

## P87: a quick-install guide for v1.0.1 is drafted on Drive, not in the repo (the vezir for Emre, 2026-10-14)

**What.** A one-page Turkish quick-install guide for v1.0.1 (one resource group, storage mode, Azure VM and Arc
branches) is written to the project's Drive folder (`files/perfmon-blackbox/quick-install-v1.0.1.md`), for Emre to try
at a customer. It is **not committed**: `main` is public, and Emre decides later whether it enters the repo. It is
written only from deploy.md, parameters.md, operations.md and README.md at tag `perfmon-blackbox/v1.0.1`; where those
are silent or wrong it says so in a "gaps" list at its top instead of inventing.
**Gaps found that concern the repo docs** (for a later doc fix, not done here): deploy.md's "Contributor + Role Based
Access Control Administrator" cannot create policy definitions, policy assignments or custom role definitions
(Contributor's NotActions exclude `Microsoft.Authorization/*/Write`; RBAC Administrator only writes role assignments;
Learn, built-in roles, Privileged); no minimum Azure CLI version; event 1002 (export uploaded, complete) is named only in
the code; the export's clock-aligned schedule (local 00:07 + every N h, random delay ≤ 10 min) is only in the code;
operations.md "Remove" omits the storage-mode reader grant on the package container and the assignment identity's own
role assignments, and gives no command for deleting a guest assignment; the time to first Compliant is "15–30 min" in
deploy.md but "about an hour per machine" in operations.md (upgrade).

## P88: a portal version of the quick-install guide, also on Drive only (the vezir for Emre, 2026-10-14)

**What.** Emre installs by hand in the Azure portal. A portal guide (`files/perfmon-blackbox/quick-install-portal-v1.0.1.md`)
and paste-ready files (`files/perfmon-blackbox/portal-json/`: the two storage-mode definitions from `build_policies.py`
for v1.0.1 with a placeholder container ID, the same as subscription-scope ARM templates with policy expressions escaped
`[[`, the Writer and Deployer role JSONs, the RBAC Administrator condition) go to Drive, not the repo (as P87). Click paths
cite Learn; every step not verified on Learn or in the lab is marked; the portal path itself was never run in the lab.
**Findings.** (1) STOP raised to the vezir: Learn documents no way to store `metadata.guestConfiguration` through the
portal's policy definition editor (a Microsoft Q&A answer says "Duplicate definition" drops it), and storage mode needs
it; the guide creates the definitions in Cloud Shell (the lab-tested CLI) or by a custom template deployment.
(2) The portal grants the definition's `roleDefinitionIds` at the assignment scope by itself (Learn, Remediate
non-compliant resources), which includes Role Based Access Control Administrator **without** the delegation condition, at
RG scope: broader than security.md. The guide adds the conditioned one on the storage account and removes the RG-scope
one. A later repo change could drop RBAC Administrator from `roleDefinitionIds` or document this; not decided here.
**Plan change (the vezir, same session):** the full portal guide was dropped. The customer already has its storage
account with private endpoints, so main.bicep is not used, and the vezir walks Emre through the install live. The
session delivered the role JSONs, the two definitions, one combined ARM wrapper (`definitions-arm.json`) and the
condition text into `portal-json/`. The per-kind ARM files were folded into that one file.
