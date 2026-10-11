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
