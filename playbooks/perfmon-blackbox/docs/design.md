# perfmon-blackbox: design (for Emre's approval, PLAN GATE)

Status: **DRAFT for approval**, 2026-10-11. Nothing here is built. Emre's decisions are in `../decisions.md`
(P1–P10); this file turns them into a design. Choices that Emre has **not** made yet are marked **[CHOICE n]** and
listed together at the end, each with a recommendation.

## 1. What it does, in one picture

```
 Windows server (Azure VM or Arc)                          Azure
 ┌────────────────────────────────────────┐
 │ Machine Configuration agent (LocalSystem)│  every 15 min: test, set if drifted
 │  └ package PerfmonBlackbox (AuditAndSet) │◄──── guest assignment ◄── Policy (VM)  or  Policy (Arc)
 │      1 files in C:\ProgramData\PerfmonBlackbox\        (DINE, two definitions, P2)
 │      2 Data Collector Set "PerfmonBlackbox" imported from the template
 │      3 collector Running                │
 │      4 task "PerfmonBlackbox-Boot"    (at startup, SYSTEM): logman start
 │      5 task "PerfmonBlackbox-Export"  (daily, SYSTEM): roll .blg → relog CSV → zip → upload
 └──────────────────────────┬─────────────┘
                            │ HTTPS PUT Blob, bearer token of the MACHINE's system identity
                            ▼                      (Azure VM: IMDS · Arc: HIMDS on localhost:40342)
              private storage account  ── container perfmon/  ── <machine-prefix>/yyyy/mm/dd/<file>.zip
                 (Entra only, no shared key, no anonymous, network-restricted, lifecycle: delete after N days)
                            ▲
                            │ read + list (agent identity, read-only)
              Azure SRE Agent ── skill perfmon-triage v2.1: find LATEST zip of a machine → download → unzip
                                 → CSV→SQLite → triage → report in the agent thread (manual trigger, P3)
```

Phase 2 (P4, decided, not in v1): an Azure Monitor alert starts the analysis instead of a person.

## 2. On the machine: the Machine Configuration package

**Name** `PerfmonBlackbox`, **type** `AuditAndSet`, Windows only. Built with the `GuestConfiguration` module
(PowerShell 7, `PSDesiredStateConfiguration` 2.0.x) from a DSC configuration in `package/`. The package holds no
secret and no environment value; everything environment-specific is a **policy parameter** (machine configuration
supports string/boolean/number parameters set at assignment time):

| Parameter | Example | Meaning |
|---|---|---|
| `StorageAccountName` | `stperfmonbb01` | the private storage account |
| `ContainerName` | `perfmon` | container for all machines |
| `SampleIntervalSeconds` | `15` | collector interval **[CHOICE 1]** |
| `ExportTimeLocal` | `00:10` | daily task start (local time) |
| `LocalRetentionDays` | `3` | how long `.blg`/zip stay on the disk after a good upload |
| `MaxLocalMB` | `2048` | hard cap on the collector folder (oldest files go first) |

DSC resources (one class-based resource module `PerfmonBlackboxDsc` shipped inside the package; each resource has
a real `Test` so the guest assignment reports drift per item):

| # | Resource | Test (compliant when…) | Set |
|---|---|---|---|
| R1 | `BlackboxFiles` | template XML, `Export-PerfmonBlackbox.ps1` and `config.json` in `C:\ProgramData\PerfmonBlackbox\` match the package (hash) | copy; ACL: SYSTEM + Administrators full, Users none |
| R2 | `BlackboxCollector` | a Data Collector Set `PerfmonBlackbox` exists and its counters and interval equal the template | `logman import -n PerfmonBlackbox -xml <template>` (delete + re-import if different) |
| R3 | `BlackboxRunning` | the set's status is Running | `logman start PerfmonBlackbox` |
| R4 | `BlackboxBootTask` | task `\PerfmonBlackbox\Boot` exists, trigger AtStartup, principal `SYSTEM`, highest, action as expected | register |
| R5 | `BlackboxExportTask` | task `\PerfmonBlackbox\Export` exists, trigger Daily at `ExportTimeLocal`, principal `SYSTEM`, action as expected, `StartWhenAvailable` on | register |

Why a boot task when machine configuration re-applies every 15 minutes anyway: it starts the recorder within
about a minute of boot, instead of up to 15 minutes later, and it does not depend on the agent being healthy. It
is the "re-starts it at every boot" of P1; the 15-minute check is the safety net.

### 2.1 The collector template

`package/files/PerfmonBlackbox.xml`, a Data Collector Set exported from logman, binary log (`.blg`) in
`C:\ProgramData\PerfmonBlackbox\blg\`, file name with a date-time version suffix. The counter list is derived from
what the skill needs (`perfq.py` CHECKLIST plus the objects SKILL.md phase 0–2 uses), so that every check of
`triage()` can run:

- `\Processor(*)\% Processor Time`, `% Privileged Time`, `% DPC Time`, `% Interrupt Time`
- `\System\Processor Queue Length`, `Context Switches/sec`, `System Up Time`
- `\Memory\Available MBytes`, `% Committed Bytes In Use`, `Committed Bytes`, `Commit Limit`, `Pages Input/sec`,
  `Free System Page Table Entries`, `Pool Nonpaged Bytes`, `Pool Paged Bytes`
- `\Paging File(_Total)\% Usage`
- `\PhysicalDisk(*)\` and `\LogicalDisk(*)\`: `Avg. Disk sec/Read`, `Avg. Disk sec/Write`,
  `Current Disk Queue Length`, `% Idle Time`, `Disk Reads/sec`, `Disk Writes/sec`; LogicalDisk also `% Free Space`
- `\Network Interface(*)\Bytes Total/sec`, `Current Bandwidth`, `Output Queue Length`
- `\Process(*)\% Processor Time`, `Private Bytes`, `Working Set`, `Handle Count`, `Thread Count`, `ID Process`,
  `IO Data Operations/sec`
- `\TCPv4\Connections Established`, `Connection Failures`
- application objects **when present** (logman records only what exists): `\ASP.NET\Requests Queued`,
  `\ASP.NET Applications(*)\Requests/Sec`, `Requests In Application Queue`,
  `\HTTP Service Request Queues(*)\CurrentQueueSize`, `\.NET CLR Memory(*)\% Time in GC`, `# Bytes in all Heaps`,
  `\Web Service(*)\Current Connections`

The list is one file; the T05 test reads the same file, so the template and the test cannot drift apart.

### 2.2 The daily export (`Export-PerfmonBlackbox.ps1`, run by task R5 as SYSTEM)

1. **Roll the file:** `logman stop` then `logman start` (a new `.blg` starts; gap of a few seconds). **[CHOICE 2]**
2. **Relog** every closed `.blg` not yet exported: `relog <blg> -f csv -o <csv>` (one CSV per day; PDH-CSV, the
   format the skill's converter reads).
3. **Validate** the CSV before anything leaves the machine: PDH header present, ≥ 1 data row, first/last time,
   counter columns ⊇ template counters present on the machine. A failed check → exit code ≠ 0, nothing uploaded,
   event log entry (source `PerfmonBlackbox`).
4. **Zip** `<csv>` + `manifest.json` (machine key, resource ID, first/last timestamp, rows, columns, sample
   interval, package version, SHA-256 of the CSV).
5. **Token** for `https://storage.azure.com/` from the machine's **system-assigned identity**:
   - Azure VM: IMDS `http://169.254.169.254/metadata/identity/oauth2/token` (header `Metadata: true`).
   - Arc: `IDENTITY_ENDPOINT` (`http://localhost:40342/...`): first call returns 401 with the path of a challenge
     file under `C:\ProgramData\AzureConnectedMachineAgent\Tokens\`; the script reads it (SYSTEM is a local
     administrator, which the agent allows) and repeats the call with `Authorization: Basic <content>`.
   - Detection: `IDENTITY_ENDPOINT` set and the HIMDS service present → Arc, else IMDS.
6. **Upload** with `PUT Blob` (REST, `x-ms-version` current, `x-ms-blob-type: BlockBlob`, `Content-MD5`, metadata
   `sha256`), no Az module needed. Path:
   `perfmon/<machine-prefix>/<yyyy>/<mm>/<dd>/<machine-name>_<yyyymmdd>_<hhmm>.zip`.
7. **Verify** the upload from the response (`Content-MD5` echoed / ETag), then delete local files older than
   `LocalRetentionDays`, and always keep the collector folder under `MaxLocalMB`.
8. Missed run (machine off at the trigger time): `StartWhenAvailable` runs it at the next start; step 2 exports
   every closed file not yet exported, so no day is lost while the files are still on disk.

### 2.3 Machine prefix

**[CHOICE 3]** recommended: `<subscriptionId>/<resourceGroup>/<machineName>` in lower case, taken from the
machine's own resource ID (IMDS / HIMDS metadata). Unique across Azure VMs and Arc servers with the same name, and
readable. The role assignment of §3.2 uses the same string.

## 3. In Azure

### 3.1 Two policy definitions (P2)

`New-GuestConfigurationPolicy` produces one `DeployIfNotExists` definition that covers both resource types. The
build splits it into two definitions, each with one resource type in its `if`:

| Definition | Targets | Prerequisites the adopter assigns too |
|---|---|---|
| `perfmon-blackbox-vm` | `Microsoft.Compute/virtualMachines` (Windows) | built-in initiative *Deploy prerequisites to enable Guest Configuration policies on virtual machines* (extension + system identity) |
| `perfmon-blackbox-arc` | `Microsoft.HybridCompute/machines` (Windows) | none (the Connected Machine agent includes machine configuration and the identity) |

Both: `contentUri` = the release asset URL of the package on GitHub (the package is public and holds no secret;
machine configuration needs a public HTTPS URI, a SAS or, on Azure VMs only, a user-assigned identity, so a
public URL is the only option that serves VM and Arc alike), `contentHash` pinned. Adopters who do not want to
fetch from GitHub host the same zip themselves and pass their URL (README section).

### 3.2 Per-machine write access, only into its own prefix

- **Custom role** `PerfMon Blackbox Writer`: data actions `.../blobs/write` and `.../blobs/add/action` only (no
  read, no list, no delete). Least privilege for an uploader.
- **One role assignment per machine** on the container, for the machine's system identity, with an **ABAC
  condition**: write/add allowed only when container = `perfmon` and blob path `StringStartsWith`
  `<machine-prefix>/`. So a machine cannot write into another machine's prefix (P5 item 10), and cannot read
  anything.
- **Who creates the assignment** **[CHOICE 4]**, recommended: the same DINE policy deploys it next to the guest
  assignment (a nested deployment scoped to the storage account). The policy assignment's identity then needs
  *Role Based Access Control Administrator* on the storage account only, with a delegation condition that lets
  it assign only `PerfMon Blackbox Writer`. Alternative: an adopter-run script `grant-machine.sh <machine-id>`
  (simpler, but a manual step per machine).
- Scale note for the README: one role assignment per machine counts toward the subscription limit of role
  assignments.

### 3.3 Storage account (private)

Deployed by the playbook's Bicep (`infra/`): StorageV2, Standard LRS, `allowBlobPublicAccess=false`,
`allowSharedKeyAccess=false` (Entra only), TLS 1.2 minimum, `publicNetworkAccess` per adopter **[CHOICE 5]**
(recommended default: disabled + private endpoint; documented alternative for Arc servers that can only reach
public endpoints: selected networks with their egress IPs). Container `perfmon`, private. **Lifecycle rule**:
delete blobs under `perfmon/` older than `RetentionDays` (default 30) **[CHOICE 6]**. Soft delete on.

### 3.4 SRE Agent side

- The agent's identity gets **Storage Blob Data Reader** on the container only (read + list; no write).
- Skill **perfmon-triage v2.1** = v2.0 (copied, P7) plus a **step −1 "fetch the latest capture"**: a stdlib helper
  `perfmon_fetch_latest.py` lists `perfmon/<machine-prefix>/`, picks the newest zip by the date-time in the blob
  name (ties: `Last-Modified`), downloads it, checks the manifest SHA-256 against the CSV, unzips, and hands the
  CSV to step 0. How it authenticates inside the agent's terminal (az CLI login of the agent identity vs. a
  token from the sandbox) is checked in the lab first; the helper's selection logic is tested offline with
  synthetic blob listings.
- The user names the machine ("analyse the latest capture of vm1"); the skill maps the name to the prefix with the
  machine's resource ID (Azure Resource Graph or `az resource show`).
- The report goes into the agent thread (P3). The method questions OPEN-1/OPEN-2 (P8) are not touched.
- `scripts/deploy-skill.sh` (copied) deploys the skill folder through the data plane API.

## 4. Repository layout of the playbook (target)

```
playbooks/perfmon-blackbox/
  README.md CHANGELOG.md HANDOVER.md decisions.md CLAUDE.md
  docs/design.md docs/test-plan.md
  package/        DSC configuration, PerfmonBlackboxDsc module, files/ (template XML, export script), build.ps1
  policy/         build-policies.ps1 (splits into -vm and -arc), the two definition JSONs (generated, committed)
  infra/          main.bicep (storage, container, lifecycle, custom role, agent reader role)
  skill/perfmon-triage/   SKILL.md perfq.py perfmon_csv_to_sqlite.py (+ perfmon_fetch_latest.py in v2.1)
  scripts/        deploy-skill.sh, grant-machine.sh (if CHOICE 4 = script)
  lab-tools/      perfmon_mask_csv.py (lab side only, never shipped)
  tests/          run.sh T01..T16 (lab), local/ L01..L05 (no Azure), fixtures/synthetic/, scoring/
```

## 5. Lab (built only after approval, P6/P9)

- Built from the private lab template (its latest release), registered in its `docs/labs.md` in the same
  commit. Proposed env name: the next free `rg-labN` in the register (today `rg-lab18`). The template is private:
  it is our test bench only; adopters never need it.
- Machines: `vm1` (Windows Server 2022, Azure VM path) and `arc1` (Windows Server 2022, Azure VM prepared per
  Learn *Evaluate Azure Arc-enabled servers on an Azure VM*: extensions removed, guest agent disabled, IMDS
  169.254.169.254 blocked, `MSFT_ARC_TEST=true`, Connected Machine agent onboarded). Plus the template's SRE Agent.
  The template's `dc`/IIS members only if the template cannot build without them.
- Because IMDS is blocked on `arc1`, its uploads must go through HIMDS: the Arc path is really tested, not the VM
  path by accident.
- `arc1`'s `Microsoft.Compute/virtualMachines` resource is excluded (notScopes) from the VM policy and the VM
  prerequisites initiative, so they do not re-install the extension the Learn guide removed.
- Arc onboarding uses a service principal from the lab `.env` (never printed, never committed).
- A synthetic **load generator** on both machines (`tests/lab/make-trouble.ps1`) plants known problems in the
  capture (a process whose private bytes grow with load, a CPU-bound burst ≥ 10 min, a disk-latency episode), so
  the analysis has a ground truth to be scored against (T16). It contains no real name.
- Cost: written per day in the register and in the README once measured.

## 6. Security summary

| Item | How |
|---|---|
| No secrets in the package | nothing but parameters; machine identity tokens are fetched at run time and never written to disk or logs |
| Machine writes only its own prefix | custom write-only role + ABAC path condition, one assignment per machine; negative test T12 |
| Nobody reads with a key | shared key disabled; no SAS anywhere |
| Storage not public | anonymous access off; network restricted (CHOICE 5); test T14 |
| Agent reads only | Storage Blob Data Reader on the container only |
| Files on the machine | ACL SYSTEM + Administrators only (captures carry process and instance names) |
| Repo | scrub check + hooks (R10); synthetic data only (R7) |

## 7. Feasibility and risks (stop conditions, P10)

| Risk | Status | If it fails |
|---|---|---|
| Upload with the machine identity on **Arc** | On paper OK: the upload is done by the scheduled task as SYSTEM (a local administrator), which may read the HIMDS challenge file. Machine configuration itself only installs the task. Proven by T11 on `arc1`. | **STOP** and report (P10). |
| Arc in a lab | Learn documents Arc on an Azure VM for evaluation. Proven when `arc1` shows Connected and T04 is green. | **STOP** and report (P10). |
| DINE nested deployment of the role assignment (CHOICE 4) | Not yet tried. | fall back to the script (CHOICE 4 alternative), ask Emre. |
| `logman stop/start` gap (CHOICE 2) | Expected seconds. T10 measures it. | use a size/time rollover (`-cnf`) instead. |
| Agent terminal access to storage | To check in the lab (§3.4). | the agent downloads with a tool call; skill text adapts. |
| Machine configuration pricing on Arc | Billed per Arc server per month (Azure Policy pricing page); free on Azure VMs. Priced for the README (DoD 4). | — |

## 8. Design choices for approval

| # | Choice | Recommendation | Alternative |
|---|---|---|---|
| CHOICE 1 | Sample interval | **15 s** (≈ 5,760 rows/day; enough for the 5-minute ceiling and short stalls) | 5 s (3× size) or 60 s (misses short stalls) |
| CHOICE 2 | Daily file roll | **`logman stop`/`start`** in the export task (few seconds gap, measured) | `-cnf 24:00:00` rollover (no gap, but roll time drifts with boot time) |
| CHOICE 3 | Machine prefix | **`<subscriptionId>/<resourceGroup>/<machineName>`** lower case | machine `vmId` GUID (unique, unreadable) |
| CHOICE 4 | Who grants the per-machine write role | **the DINE policy** (automatic, condition-limited RBAC admin on the storage account) | adopter script per machine |
| CHOICE 5 | Storage network | **private endpoint, public access disabled** (lab default) | selected networks for Arc servers without private connectivity |
| CHOICE 6 | Blob retention | **30 days** lifecycle delete | 7 / 90 days |
| CHOICE 7 | Package hosting | **public GitHub Release asset** URL (+ self-host option in README) | adopter-hosted only |
