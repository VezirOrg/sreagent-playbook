# perfmon-blackbox: design (for Emre's approval, PLAN GATE)

Status: **rev 3 APPROVED (PLAN-OK, decisions P19)**, 2026-10-11, with Emre's change: interval default 10 s.
Defaults decided in P19 override the "Recommendation" column of §8. History (rev 3: P16–P18: interval parameter, capacity check, counter
groups G1–G3 with web auto-detect). Nothing here is built. Emre's decisions are in `../decisions.md`
(P1–P15); this file turns them into a design. Choices Emre has **not** made yet are marked **[CHOICE n]** and listed
together in §8, each with a recommendation.

Rev 2 (Emre's input, P11–P15): exactly his 36 counters; binary circular file with `MaxSizeMB` (default 512) as a
policy parameter on both policies; the export reworked around the circular file (no gap, no overlap, loss
detected); buffer hours estimated; the skill's gaps with this counter set listed; sample interval is now an open
choice.

## 1. What it does, in one picture

```
 Windows server (Azure VM or Arc)
 ┌──────────────────────────────────────────────┐
 │ Machine Configuration agent (LocalSystem)      │  every 15 min: test, set if drifted
 │  └ package PerfmonBlackbox (AuditAndSet)       │◄── guest assignment ◄── Policy (VM)  or  Policy (Arc)
 │      parameters: MaxSizeMB, SampleInterval, …  │      (DINE, two definitions, P2, P14)
 │      1 files in C:\ProgramData\PerfmonBlackbox\
 │      2 Data Collector Set "PerfmonBlackbox": 36 + G1 + G2 (+ G3 where web objects exist), BINARY CIRCULAR, max MaxSizeMB
 │      3 collector Running, continuously
 │      4 task Boot   (at startup, SYSTEM): keep the old buffer as "pending", then logman start
 │      5 task Export (scheduled, SYSTEM): window since last good export → CSV → zip(+manifest) → upload
 └──────────────────────┬───────────────────────┘
                        │ HTTPS PUT Blob, token of the MACHINE's system identity
                        ▼                        (Azure VM: IMDS · Arc: HIMDS on localhost:40342)
          private storage account ── perfmon/<machine-prefix>/yyyy/mm/dd/<file>.zip   (lifecycle delete)
                        ▲
                        │ read + list (agent identity, read-only)
          Azure SRE Agent ── skill perfmon-triage v2.1: LATEST zip of a machine → download → unzip
                             → CSV→SQLite → triage → report in the agent thread (manual trigger, P3)
```

Phase 2 (P4, decided, not in v1): an Azure Monitor alert starts the analysis instead of a person.

## 2. On the machine: the Machine Configuration package

**Name** `PerfmonBlackbox`, **type** `AuditAndSet`, Windows only. Built with the `GuestConfiguration` module
(PowerShell 7, `PSDesiredStateConfiguration` 2.0.x). The package holds no secret and no environment value; every
environment-specific value is a **policy parameter**, the **same set on both definitions** (P14), passed to the
package as Machine Configuration configuration parameters:

| Parameter | Default | Meaning |
|---|---|---|
| `MaxSizeMB` | **512** | maximum size of the circular `.blg` (P13, P14) |
| `SampleIntervalSeconds` | **10** (P19) | collector interval (P17) |
| `ExportEveryHours` | **4** (P19; a fixed parameter, guarded by R6) | how often the export runs |
| `StorageAccountName` | — (required) | the private storage account |
| `ContainerName` | `perfmon` | container for all machines |
| `LocalKeepMB` | `1024` | cap for pending buffers + not-yet-uploaded zips on the disk (oldest go first, and that loss is reported) |

DSC resources (class-based module `PerfmonBlackboxDsc` inside the package; each with a real `Test`, so the guest
assignment shows drift per item):

| # | Resource | Test (compliant when…) | Set |
|---|---|---|---|
| R1 | `BlackboxFiles` | template, counter list, `Export-PerfmonBlackbox.ps1`, `Start-PerfmonBlackbox.ps1`, `config.json` (holds the parameters) in `C:\ProgramData\PerfmonBlackbox\` match the package and the current parameters | copy; ACL SYSTEM + Administrators only |
| R2 | `BlackboxCollector` | set `PerfmonBlackbox` exists; counters **equal** the 36 of the counter list; format binary circular; interval = `SampleIntervalSeconds`; max size = `MaxSizeMB`; no duration limit | if absent: fill the template from the parameters, `logman import`. If interval or size differ: keep the current buffer as pending (§2.2 step 0), delete, re-import, start |
| R3 | `BlackboxRunning` | status Running | `Start-PerfmonBlackbox.ps1` (keeps the old buffer as pending, then `logman start`) |
| R4 | `BlackboxBootTask` | task `\PerfmonBlackbox\Boot`: AtStartup, SYSTEM, highest, action `Start-PerfmonBlackbox.ps1` | register |
| R6 | `BlackboxCapacity` | the **measured** buffer hours on this machine (§2.6) ≥ 1.5 × the export window | none (audit only). NonCompliant **reason**, e.g. `buffer holds ~7 h at 1 s with MaxSizeMB=512 (148 processes), export window 24 h: data will be lost; raise MaxSizeMB, lengthen the interval or export more often` |
| R5 | `BlackboxExportTask` | task `\PerfmonBlackbox\Export`: Daily trigger repeating every `ExportEveryHours` (24 = once a day), SYSTEM, `StartWhenAvailable` | register |

A changed `MaxSizeMB` or interval on the assignment reaches the machine at the next evaluation (≤ 15 min): R1 and
R2 become non-compliant, Set re-creates the collector with the new values, and nothing recorded so far is lost
(it is kept as a pending buffer and exported).

### 2.1 The collector template (P11, P12, P13, P18)

Counter set = Emre's **36** (unchanged) + **G1** system-wide (12) + **G2** per process (2) = **50 lines**, plus **G3**
web (6) **only where its counter objects exist** (CHOICE 10, below). One file per group in `package/files/`.
All of it is deployed by Azure Policy + Machine Configuration; nothing is Group Policy.

**G3 auto-detect (vezir's proposal, CHOICE 10).** R2's `Test` builds the expected list as 36 + G1 + G2 + the G3
lines whose object exists now (`Get-Counter -ListSet` for `ASP.NET`, `ASP.NET Applications`, `.NET CLR Memory`,
`Web Service`). A machine that gains IIS later no longer matches the expected list at the next Machine
Configuration check (≤ 15 min); `Set` re-creates the collector through the pending-buffer path (§2.2 step 0), so no
sample is lost. Missing counters are never configured; there is no G3 parameter. Whether configuring missing
counters would even hurt (event-log storm) is measured in the lab (P18 question, T06f).


- `package/files/PerfmonBlackbox.counters.txt`: Emre's **36 counters, verbatim**; `…-g1-system.txt`, `…-g2-process.txt`,
  `…-g3-web.txt`: the groups of P18 (LogicalDisk ×6, Memory ×8,
  Process ×8, Network Interface ×3, Processor Information ×5, TCPv4 ×3, TCPv6 ×3). The tests read the same file.
- `package/files/PerfmonBlackbox.template.xml`: sanitized Data Collector Set: those counters; binary log
  (`LogFileFormat=3`), circular (`LogCircular`), overwrite, `Duration=0` (continuous), no schedule, no
  subdirectory pattern, run as SYSTEM, file `%ProgramData%\PerfmonBlackbox\blg\PerfmonBlackbox.blg`;
  `{{MaxSizeMB}}` and `{{SampleIntervalSeconds}}` filled in on the machine. Which XML field carries the circular
  maximum (the set's `SegmentMaxSize` is assumed) is proven by T01/T06; the fallback is to create the same set with
  `logman create counter -cf <counter list> -f bincirc -max <MB> -si <s>`, which is the documented form.
- Emre's original (with a real machine name, dated paths, `SampleInterval=1`, `Duration=10800`) stays in
  `files/emre-inputs/`, never in the repo.

### 2.2 The export around the circular file (P15)

State on the machine: `state.json` = time of the **last sample of the last successful export** (`last_ts`, local
time as PerfMon writes it, plus UTC offset) and the export sequence number. It moves forward **only after** the blob
is uploaded and verified.

0. **Pending buffers.** Whenever the collector is (re)started (boot, R2 re-create, R3), `Start-PerfmonBlackbox.ps1`
   first renames the existing `.blg` to `pending\<yyyymmdd-hhmmss>.blg`, so a restart never overwrites unexported
   data. (A circular log restarted with overwrite would wipe it.)
1. **Snapshot.** Copy the live `.blg` (the collector keeps running; the file is opened read-share) to
   `work\live.blg`. If a copy of a file in use proves unreliable in the lab, fall back to a short
   `logman stop` → move → `start` (gap = seconds, reported like any gap). T10 decides.
2. **Window.** Sources = all pending buffers + the snapshot, in time order. The window is **from the first sample
   after `last_ts` to the last sample in the snapshot**. `relog <sources> -f csv -b <last_ts + 1 s> -e <end>
   -o export.csv` (relog's begin/end filter). **No overlap**: every sample ≤ `last_ts` is excluded by construction.
   **No gap**: every sample after `last_ts` still on the disk is included.
3. **Loss detection.** The CSV is scanned for holes: any step between consecutive samples > 2 × interval, and the
   step from `last_ts` to the first exported sample. Each hole gets a cause:
   - `buffer_overrun`: the oldest sample in the circular file is newer than `last_ts + interval` while the
     collector ran without a restart in between: the window outgrew the buffer and the ring overwrote it;
   - `collector_restart` / `machine_off`: the hole lines up with a pending-buffer boundary or a boot time
     (event log, boot time from `Win32_OperatingSystem`);
   - `local_cap`: pending buffers or zips dropped by `LocalKeepMB`.
   All holes go into the **manifest** (`gaps[]`: from, to, seconds, cause) with `complete: true|false`, and an
   event-log warning (source `PerfmonBlackbox`). A loss is **never silent**.
4. **Validate** the CSV: PDH header; ≥ 1 row; the 36 template counters present (wildcard counters as at least one
   instance); first/last time inside the window. A failed check → nothing uploaded, error event, exit ≠ 0.
5. **Zip** `export.csv` + `manifest.json`: machine prefix, resource ID, export sequence, window from/to, first/last
   sample, rows, columns, interval, `MaxSizeMB`, package version, `gaps[]`, `complete`, SHA-256 of the CSV.
6. **Token** for `https://storage.azure.com/` from the machine's **system-assigned identity**: Azure VM → IMDS
   `169.254.169.254` (`Metadata: true`); Arc → `IDENTITY_ENDPOINT` (localhost:40342): first call returns 401 with
   a challenge-file path under `C:\ProgramData\AzureConnectedMachineAgent\Tokens\`, which SYSTEM (a local
   administrator) may read; the call is repeated with `Authorization: Basic <content>`. Never written to disk or
   logs.
7. **Upload** with REST `PUT Blob` (`BlockBlob`, `Content-MD5`, metadata `sha256`, `seq`, `complete`), no Az
   module. Path `perfmon/<machine-prefix>/<yyyy>/<mm>/<dd>/<machineName>_<from yyyymmdd-hhmmss>_<to hhmmss>.zip`.
8. **Commit**: on HTTP 201 with the echoed MD5 → write `state.json` (`last_ts` = last exported sample), delete
   pending buffers fully exported and the local zip. On failure → keep everything; the next run exports a longer
   window from the same `last_ts` (no gap), as long as the ring still holds it (otherwise step 3 reports it).

### 2.3 How many hours does the buffer hold? (P15; estimate now, measured by T07b and the P16 lab run)

**Rev 3:** with G1 + G2 the per-process part grows from 8 to 10 counters (≈ +25 % per sample), so the hours below
shrink by about a fifth for the full set. The lab measures both sets side by side (P16, P18); the measured formula
`bytes/sample ≈ a + b × processes` replaces this estimate.

A binary log stores, per sample, a raw value per counter instance plus, for wildcard objects, the instance
names. Rough size per sample on a typical 4-vCPU Windows Server 2022 VM:

| Object | Counters | Instances (typical) | Values / sample |
|---|---|---|---|
| Process(*) | 8 | 100–150 | 800–1,200 |
| Processor Information(*) | 5 | 6 (4 cores + 2 totals) | 30 |
| LogicalDisk(*) | 6 | 3–4 | 18–24 |
| Network Interface(*) | 3 | 1–3 | 3–9 |
| Memory, TCPv4, TCPv6 | 14 | 1 | 14 |
| **Total** | **36** | | **≈ 0.9k–1.3k** |

At roughly **40–80 bytes per value** in a `.blg` (raw counter record + instance-name strings), one sample is
**≈ 40–100 KB** (central ≈ 60 KB). Then 512 MB holds:

| Interval | Samples in 512 MB | **Hours in 512 MB** (central, range) | Export cadence that never overruns |
|---|---|---|---|
| **1 s** | ≈ 5k–13k | **≈ 2.4 h** (1.5–3.6 h) | every **1 h** (≥ 1.5× margin even at the low end) |
| 5 s | same | ≈ 12 h (7–18 h) | every 4–6 h |
| **15 s** | same | **≈ 36 h** (22–55 h) | daily **only at the central estimate**; the low end (22 h) is < 24 h, so every **12 h** is safe |

The process count dominates: a busy IIS/SQL server with 300 processes halves these hours. T07b measures the real
bytes per sample on both lab machines and the README then states measured hours. The export task also writes the
measured **buffer hours** into each manifest (oldest-to-newest span of the ring at snapshot time), so an adopter sees
the margin per machine.

**If the window outgrows the buffer** (the export was late, failed for longer than the ring holds, or the machine
is busier than estimated): the oldest part of the window is gone; the export uploads what is left, the manifest has
a `buffer_overrun` gap with its from/to and `complete: false`, and an event-log warning is written. T10b forces this
case and checks the manifest.

### 2.6 Capacity check reported in Azure Policy (P17; vezir's proposal, for Emre: CHOICE 9)

Azure Policy cannot check one parameter against another (`MaxSizeMB` vs `SampleIntervalSeconds` vs the export
window), and the right answer depends on the machine (its process count). So the package checks it on the machine:

- The export task (and R6's `Test`) measures the **fill rate**: bytes per sample = ring size ÷ samples in the ring
  once it has wrapped (before that: file size ÷ samples so far), and **buffer hours** = `MaxSizeMB` ÷ bytes per
  sample × interval. It keeps the last value in `state.json` and writes it into each manifest.
- R6 is **NonCompliant** when buffer hours < 1.5 × the export window, with the numbers in the **reason** text, so a
  misfit shows in the Azure Policy compliance view **before** any data is lost (and is visible per machine).
- Until the first measurement exists (fresh install), R6 uses the formula `a + b × processes` from the P16
  measurement with the machine's current process count, and says "estimated" in the reason.
- The export still reports any real loss in the manifest (§2.2 step 3); R6 is the early warning.

**Export cadence, parameter or derived (CHOICE 2).** Recommendation: **derived by default**: `ExportEveryHours = 0`
(auto) means the export task runs every `floor(buffer hours ÷ 2)` hours, at least 1 and at most 24, recomputed after
each export from the measured fill rate (the task trigger is re-registered only when the value changes). A positive
value is an adopter override; with an override, R6 guards it. Derived cannot drift out of fit when a machine grows
more processes; an override can, and R6 then says so.

### 2.4 Machine prefix

**[CHOICE 3]** recommended: `<subscriptionId>/<resourceGroup>/<machineName>` lower case, from the machine's own
resource ID (IMDS/HIMDS metadata). Unique across Azure VMs and Arc servers of the same name. §3.2 uses the same string.

### 2.5 What the skill loses with this counter set (P11: listed for Emre, not filled)

**Rev 3 (P18):** G1 restores the System checks (queue, context switches, up time), hard faults, paging file and
LogicalDisk idle/queue; G3 (on web boxes) restores ASP.NET queueing, request rate (so request-based `leak_rate`
works again) and the managed heap. Still missing after P18: the `Processor` object (the template has
`Processor Information`; skill change, CHOICE 8), `% DPC Time` / `% Interrupt Time`, `PhysicalDisk`, `HTTP Service
Request Queues`. The table below is the 36-only view.

The skill (v2.0, copied, P7) was written for a wider capture. With exactly these 36 counters:

| Skill part | Needs | In the 36? | Effect |
|---|---|---|---|
| `n_cpu()`, all `Processor` checks of `triage()` (total, per core, privileged), CPU-count thresholds | object `Processor` | **No**: the template uses `Processor Information` (instances `_Total`, `0,_Total`, `0,0`, …) | CPU checks print "not in capture"; CPU count = 0. **A skill change** (read `Processor Information`, which holds the same counters) fixes it without new counters. |
| `% DPC Time`, `% Interrupt Time` checks | Processor | No | lost |
| `System\Processor Queue Length`, `Context Switches/sec` | System | No | lost (CPU queueing not visible) |
| restarts via `System\System Up Time` (phase 0) | System | No | restarts seen only as sample gaps and `ID Process` changes |
| `Memory\Pages Input/sec` (hard faults) | Memory | No | paging pressure not visible; Available MBytes and commit still are |
| `Paging File\% Usage` | Paging File | No | lost |
| all `PhysicalDisk` checks | PhysicalDisk | No | only LogicalDisk; latency and free space still checked |
| `LogicalDisk\% Idle Time`, `Current Disk Queue Length` | LogicalDisk | No (has `Avg. Disk Write Queue Length`) | saturation checks lost; write queue only |
| ASP.NET, HTTP.sys queue checks | ASP.NET, HTTP Service Request Queues | No | app queueing not visible |
| `.NET CLR Memory` (`% Time in GC`, `# Bytes in all Heaps`) | .NET CLR Memory | No | **managed-heap checks and the managed-vs-native split are lost** |
| `leak_rate(db, X, LOAD)` per 1,000 requests | a request-rate counter | **No** (no ASP.NET / Web Service) | **request-based leak rate is lost**; growth per hour (`movers`, per PID) still works |
| `link_test(db, X, LOAD)` | a load counter | partly | only with what is here (CPU, network bytes, disk transfers, IO ops) |
| `movers`, `pid_changes`, `top_procs`, `top_at`, `delta`, `series` | Process, Memory, … | **Yes** | work |
| Memory available / commit / pools / PTEs, LogicalDisk latency + free space, NIC output queue + % of bandwidth | | **Yes** | work |

Not used by the skill today but present: `% Processor Performance`, `Parking Status`, `% User Time`,
`System Cache Resident Bytes`, `Disk Bytes/sec`, `Disk Transfers/sec`, `Working Set - Private`, TCP connections
active/reset. **Open for Emre** (CHOICE 8): adapt the skill to this set (at least `Processor Information`) in v2.1,
or keep the skill as is and accept the "not in capture" lines. Adding counters is not an option unless he says so.

## 3. In Azure

### 3.1 Two policy definitions (P2, P14)

`New-GuestConfigurationPolicy` produces one `DeployIfNotExists` definition for both resource types; the build splits
it into two, each with one resource type in its `if`. **Both expose the same parameters** (§2, `MaxSizeMB` default
512), mapped to the package's configuration parameters.

| Definition | Targets | Prerequisites the adopter assigns too |
|---|---|---|
| `perfmon-blackbox-vm` | `Microsoft.Compute/virtualMachines` (Windows) | built-in initiative *Deploy prerequisites to enable Guest Configuration policies on virtual machines* |
| `perfmon-blackbox-arc` | `Microsoft.HybridCompute/machines` (Windows) | none (the Connected Machine agent includes machine configuration and the identity) |

`contentUri` = the package's GitHub Release asset URL **[CHOICE 7]**, `contentHash` pinned. Machine configuration
needs a public HTTPS URI, a SAS, or (Azure VMs only) a user-assigned identity; a public URL serves VM and Arc alike.
The package holds no secret.

### 3.2 Per-machine write access, only into its own prefix

- Custom role `PerfMon Blackbox Writer`: data actions `blobs/write` and `blobs/add/action` only (no read, list,
  delete).
- One role assignment per machine (its system identity) on the container, with an **ABAC condition**: allowed only
  when container = `perfmon` and blob path `StringStartsWith '<machine-prefix>/'`.
- Who creates it **[CHOICE 4]**: recommended, the same DINE policy (nested deployment at the storage account; the
  assignment identity holds *Role Based Access Control Administrator* on that account only, with a delegation
  condition that allows assigning only `PerfMon Blackbox Writer`). Alternative: an adopter script per machine.
- README scale note: one role assignment per machine counts toward the subscription's role-assignment limit.

### 3.3 Storage account (private)

Bicep in `infra/`: StorageV2, Standard LRS, `allowBlobPublicAccess=false`, `allowSharedKeyAccess=false`, TLS 1.2,
network per **[CHOICE 5]**, container `perfmon` private, **lifecycle rule** delete after `RetentionDays`
**[CHOICE 6]**, soft delete on.

### 3.4 SRE Agent side

- Agent identity: **Storage Blob Data Reader** on the container only.
- Skill **v2.1** = v2.0 + step −1 `perfmon_fetch_latest.py`: list `perfmon/<machine-prefix>/`, pick the newest zip
  by the window-end time in its name (ties: `Last-Modified`), download, verify the manifest hash, unzip, hand the CSV
  to step 0, and **quote the manifest's `complete` flag and `gaps[]`** in the report's capture section. With an
  hourly export (CHOICE 2), "latest" can also mean "the last N zips" (the converter already merges consecutive parts
  of one host); default N = 1, the user can ask for more.
- How the helper authenticates inside the agent's terminal is checked in the lab first.
- Report in the agent thread (P3). OPEN-1/OPEN-2 (P8) untouched. Skill gaps: §2.5, CHOICE 8.

## 4. Repository layout of the playbook (target)

```
playbooks/perfmon-blackbox/
  README.md CHANGELOG.md HANDOVER.md decisions.md CLAUDE.md
  docs/design.md docs/test-plan.md
  package/   files/ (PerfmonBlackbox.counters.txt, PerfmonBlackbox.template.xml, scripts), PerfmonBlackboxDsc/, build.ps1
  policy/    build-policies.ps1 (splits -vm and -arc), the two generated definitions
  infra/     main.bicep (storage, container, lifecycle, custom role, agent reader role)
  skill/perfmon-triage/   SKILL.md perfq.py perfmon_csv_to_sqlite.py (+ perfmon_fetch_latest.py in v2.1)
  scripts/   deploy-skill.sh (+ grant-machine.sh if CHOICE 4 = script)
  lab-tools/ perfmon_mask_csv.py (lab side only, never shipped)
  tests/     run.sh (lab tests), local/ (no Azure), fixtures/synthetic/, scoring/
```

## 5. Lab (built only after approval, P6/P9)

- From the private lab template (latest release), registered in its lab register in the same commit. Env name: the
  next free `rg-labN` (today `rg-lab18`).
- `vm1` (Windows Server 2022, Azure VM path) and `arc1` (Windows Server 2022 Azure VM prepared per Learn *Evaluate
  Azure Arc-enabled servers on an Azure VM*: extensions removed, guest agent disabled, IMDS blocked,
  `MSFT_ARC_TEST=true`, Connected Machine agent onboarded), plus the template's SRE Agent.
- IMDS is blocked on `arc1`, so its uploads must use HIMDS: the Arc path is really tested.
- `arc1`'s Compute resource is in the VM policy's and the VM prerequisites' `notScopes`.
- Arc onboarding uses a service principal from the lab `.env` (never printed, never committed).
- Synthetic load generator `tests/lab/make-trouble.ps1` plants known problems that **this counter set can show**
  (a process leaking private bytes per hour, a CPU burst ≥ 10 min, a disk-latency episode ≥ 5 min, a NIC burst,
  and short 20–40 s stalls for OPEN-2) and logs the ground truth for T16.
- Wrap and resize tests use a small `MaxSizeMB` (e.g. 16 → 32) so they finish in minutes; the 512 MB default is
  measured separately (T07b).

## 6. Security summary

| Item | How |
|---|---|
| No secrets in the package | parameters only; tokens fetched at run time, never on disk or in logs |
| Machine writes only its own prefix | write-only custom role + ABAC path condition per machine; negative test T12 |
| No key access | shared key disabled; no SAS anywhere |
| Storage not public | anonymous off; network restricted (CHOICE 5); T14 |
| Agent reads only | Storage Blob Data Reader on the container |
| Files on the machine | ACL SYSTEM + Administrators only (captures carry process and instance names) |
| Repo | scrub check + hooks (R10, R13); synthetic data only (R7); Emre's original template never committed (P11) |

## 7. Feasibility and risks (stop conditions, P10)

| Risk | Status | If it fails |
|---|---|---|
| Upload with the machine identity on **Arc** | On paper OK: the SYSTEM task may read the HIMDS challenge. Proven by T11 on `arc1`. | **STOP** and report |
| Arc in a lab | Learn documents it for evaluation. Proven when `arc1` is Connected and T04 is green. | **STOP** and report |
| Reading the live circular `.blg` while it is written (§2.2 step 1) | Not yet tried. T10 decides. | short stop/move/start (gap of seconds, reported) |
| Circular max field in the XML (§2.1) | Assumed `SegmentMaxSize`. T01/T06. | `logman create counter -f bincirc -max` |
| Buffer hours at 1 s (§2.3) | estimate 1.5–3.6 h | export cadence from the measured value |
| DINE nested role assignment (CHOICE 4) | not yet tried | script fallback; ask Emre |
| Agent terminal access to storage | to check in the lab | agent downloads via a tool call; skill text adapts |
| Machine configuration pricing on Arc | billed per Arc server per month (Azure Policy pricing); free on Azure VMs | — (README cost, DoD 4) |

## 8. Choices for Emre (rev 2)

| # | Choice | Options | Recommendation |
|---|---|---|---|
| **CHOICE 1** | **Default of the `SampleIntervalSeconds` parameter** (P17; his template: 1 s) | **1 s** (≈ 2.4 h in 512 MB; 20–40 s stalls are 20–40 points) · **5 s** (≈ 12 h; stalls 4–8 points) · **15 s** (≈ 36 h; stalls 1–3 points, i.e. blips under SKILL rule 4) | **1 s**, as in his template, because OPEN-2 is about 20–40 s stalls and only 1 s shows them clearly. Requires CHOICE 2 = 1 h. If a daily export is preferred: 15 s with a 12 h export. |
| **CHOICE 2** | **Export cadence: third parameter or derived** | fixed parameter (1/4/12/24 h) · **derived** (`0` = auto: every ⌊buffer h ÷ 2⌋ h, 1–24) with optional override | **derived by default**, override allowed and guarded by R6 (§2.6). If a fixed value is wanted: 1 h for 1 s, 4 h for 5 s, 12 h for 15 s |
| CHOICE 3 | Machine prefix | `<sub>/<rg>/<machine>` · `vmId` GUID | `<sub>/<rg>/<machine>` |
| CHOICE 4 | Who grants the per-machine write role | DINE policy · adopter script | DINE policy |
| CHOICE 5 | Storage network | private endpoint + public access disabled · selected networks | private endpoint (lab default); selected networks documented for Arc servers without private connectivity |
| CHOICE 6 | Blob retention | 7 · 30 · 90 days | 30 days |
| CHOICE 7 | Package hosting | public GitHub Release asset · adopter-hosted | Release asset (+ self-host section in README) |
| **CHOICE 8** | **Skill vs. this counter set** (§2.5) | adapt skill v2.1 to the 36 counters (at least `Processor Information`) · keep the skill, accept "not in capture" | **adapt the skill** (no new counters); the lost checks (System, PhysicalDisk, paging, .NET, ASP.NET, request-based leak rate) are listed in the report's "not checked" section |
| **CHOICE 9** | **Capacity check as compliance reason** (vezir's proposal, §2.6) | R6 audit resource with the numbers in the NonCompliant reason · no check (loss only in the manifest) | **R6**: a misfit shows in Azure Policy before data is lost |
| **CHOICE 10** | **G3 web counters** (P18; vezir's proposal) | **auto-detect**: G3 only where its objects exist, re-checked every 15 min (no parameter) · always configured · parameter | **auto-detect**, if the lab shows no event-log harm either way it is still the cleaner choice (missing counters never configured) |
