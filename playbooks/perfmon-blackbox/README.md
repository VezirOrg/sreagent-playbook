# perfmon-blackbox

A **black-box PerfMon recorder** for Windows servers (Azure VMs and Azure Arc-enabled servers), plus the **Azure SRE
Agent skill** that analyses the latest capture of a server.

> Not an official Microsoft product. Working and versioned, no support promise. See the
> [repo README](../../README.md).

**Status: release candidate in lab testing** (`perfmon-blackbox/v1.0.0-rc.1` is a lab test build, not for use). This
guide becomes final with `perfmon-blackbox/v1.0.0`.

## What it does

- An **Azure Machine Configuration** package (`PerfmonBlackbox`, AuditAndSet) keeps a PerfMon Data Collector Set
  running on every targeted server, as a **binary circular log** (default 512 MB, sampled every 10 s), and restarts it
  after every reboot. The last `MaxSizeMB` of data is always on the disk.
- Every `ExportEveryHours` (default 4) a scheduled task exports the window **since the last successful export** (no
  gap, no overlap) to CSV, zips it with a `manifest.json`, and uploads it with the **server's own managed identity**
  into **its own folder** of **your private storage account**. A server cannot write anywhere else, and cannot read.
- Any loss (the ring overwrote data before an export, the machine was off, the collector restarted, the local cap
  dropped data) is **written into the manifest** (`gaps[]`, `complete: false`) and the event log. Never silent.
- If a server's buffer cannot hold the export window (many processes, short interval, small buffer), the guest
  assignment turns **NonCompliant** with the numbers in its reason, before data is lost.
- Two Azure Policy definitions (DeployIfNotExists): `perfmon-blackbox-vm` for Azure VMs and `perfmon-blackbox-arc`
  for Arc-enabled servers. Assign the one(s) you need.
- The SRE Agent skill **perfmon-triage** fetches the latest zip of a server, checks it, converts it to SQLite and
  triages it; the report quotes the zip and every gap.

Nothing is installed on the servers beyond the package's own files: the scripts run in **Windows PowerShell 5.1**
(built in) and use `logman`, `relog`, `schtasks` and .NET only. The Machine Configuration agent runs the package's DSC
resources in its own PowerShell 7, which ships with the agent.

Design: [docs/design.md](docs/design.md). Tests: [docs/test-plan.md](docs/test-plan.md). Decisions:
[decisions.md](decisions.md).

## Counters

A 36-counter PerfMon template (LogicalDisk, Memory, Process ×8, Network Interface, Processor Information, TCP),
plus 12 system-wide counters (G1: queue, context switches, up time, hard faults, paging file, disk idle/queue, …),
2 per-process pool counters (G2), and 6 web counters (G3: ASP.NET, .NET CLR Memory, Web Service) **only where those
counter objects exist** (re-checked every 15 minutes). Files: [package/collector/](package/collector/).

## How long the buffer lasts

A `.blg` costs about 45–54 bytes per value per sample; the per-process counters dominate. Measured on lab servers and
counted on real captures (decisions P27): **bytes per sample ≈ 4.5 KB + 0.53 KB × processes** (full set).

| Processes | KB per sample | Hours in 512 MB at 10 s |
|---|---|---|
| 100 | ≈ 58 | ≈ 26 h |
| 200 | ≈ 110 | ≈ 13.5 h |
| 300 | ≈ 164 | ≈ 9 h |
| 400 | ≈ 216 | ≈ 6.9 h |
| 500 | ≈ 270 | ≈ 5.5 h |

With the default 4-hour export the guest assignment stays Compliant up to about 460 processes (it needs ≥ 1.5 × the
export window). Above that, raise `MaxSizeMB`, lengthen the interval or export more often.

## Prerequisites

- Windows Server 2016 or later (Azure VM or Azure Arc-enabled server), Windows PowerShell 5.1 (built in).
- Azure VMs: the built-in initiative *Deploy prerequisites to enable Guest Configuration policies on virtual machines*
  (system-assigned identity + the Machine Configuration extension). Arc servers: Connected Machine agent ≥ 1.10.
- Network: every server must reach the storage account's **private endpoint** (DNS `privatelink.blob.core.windows.net`
  resolving to it), and the package URL (GitHub, HTTPS) for the Machine Configuration agent.
- **The SRE Agent needs VNet integration** that can resolve and reach the same private endpoint (its sandbox egress
  in your VNet with private DNS resolution). Without it the skill cannot read the captures.
- Permissions to deploy the storage, create custom roles and policy definitions, and assign roles.

## Deploy

Step by step, with every command and role: **[docs/deploy.md](docs/deploy.md)** (storage, the two policies, the rights
of the policy identity, remediation, the skill).

## On each server

`C:\ProgramData\PerfmonBlackbox\` (SYSTEM and Administrators only): `bin\` (scripts, counter lists, template),
`blg\` (the live ring), `pending\` (closed rings not yet exported), `outbox\`, `log\`, `config.json`, `state.json`.
Tasks `\PerfmonBlackbox\Boot` and `\PerfmonBlackbox\Export`. Event log source `PerfmonBlackbox` (1000s info, 2000s data
loss, 3000s errors). Captures live at `perfmon/<subscriptionId>/<resourceGroup>/<server>/<yyyy>/<mm>/<dd>/` in storage.

## Cost

Azure VM ≈ 0.01–0.03 USD a month (storage); Arc server + 6.00 USD a month (Machine Configuration on Arc); ≈ 7.30 USD a
month per deployment (private endpoint). Details and price source: [docs/cost.md](docs/cost.md).

## Documentation

| Doc | For |
|---|---|
| [docs/architecture.md](docs/architecture.md) | how it fits together (diagram) |
| [docs/deploy.md](docs/deploy.md) | deploying it |
| [docs/parameters.md](docs/parameters.md) | parameters, buffer hours, the capacity check |
| [docs/operations.md](docs/operations.md) | upgrades, troubleshooting, removal |
| [docs/security.md](docs/security.md) | identities, roles, the prefix condition, what runs on servers |
| [docs/cost.md](docs/cost.md) | cost per server and per deployment |
| [docs/tests.md](docs/tests.md) | every test and its status |
| [docs/load-generation.md](docs/load-generation.md) | how the lab plants problems for the end-to-end test |

## Remove

See [docs/operations.md](docs/operations.md#remove).
