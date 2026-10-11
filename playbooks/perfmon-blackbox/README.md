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

All commands run from this folder (`playbooks/perfmon-blackbox`) with the Azure CLI signed in.

### 1. Private storage

```sh
az deployment group create -g <storage-rg> -f infra/main.bicep \
  -p storageAccountName=<name> privateEndpointSubnetId=<subnet id> \
     blobPrivateDnsZoneId=<id of privatelink.blob.core.windows.net> \
     readerPrincipalIds='["<SRE Agent system identity>","<SRE Agent user-assigned identity>"]'
```

It creates the storage account (no shared key, no public network access, no anonymous access, TLS 1.2), the
container `perfmon`, a lifecycle rule (delete after 30 days), the private endpoint, two custom roles
(**PerfMon Blackbox Writer**: blob write only; **PerfMon Blackbox Deployer**: deployments only) and Storage Blob Data
Reader on the container for the agent. Note the outputs `storageAccountResourceId` and `writerRoleDefinitionId`.

### 2. The policy definitions

The package is the release asset `PerfmonBlackbox.zip` of the release you use; its SHA-256 is in the release notes.

```sh
python3 policy/build_policies.py --content-uri <asset URL> --content-hash <sha256> --version <x.y.z> --out policy/out
for kind in vm arc; do
  f=policy/out/perfmon-blackbox-$kind.json
  az policy definition create -n perfmon-blackbox-$kind --mode Indexed \
    --rules  "$(python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))["properties"]["policyRule"]))' $f)" \
    --params "$(python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))["properties"]["parameters"]))' $f)"
done
```

### 3. Assign, with the rights the assignment identity needs

For each definition you use, at the scope of your servers (management group, subscription or resource group):

```sh
az policy assignment create -n pbb-vm --policy perfmon-blackbox-vm --scope <scope> \
  --mi-system-assigned --location <region> \
  --params '{"StorageAccountResourceId":{"value":"<storageAccountResourceId>"},"WriterRoleDefinitionId":{"value":"<writerRoleDefinitionId>"}}'
```

Then give its identity (`az policy assignment show -n pbb-vm --scope <scope> --query identity.principalId`):

| Role | Scope | Why |
|---|---|---|
| Guest Configuration Resource Contributor | the servers' scope | create the guest assignment |
| Reader | the servers' scope | read each server's identity |
| PerfMon Blackbox Deployer | the storage account's resource group | deploy the per-server role assignment |
| Role Based Access Control Administrator, **with a condition** | the storage account | assign only the Writer role (below) |

The condition limits the RBAC Administrator role to the Writer role (`<writer guid>` = last segment of
`writerRoleDefinitionId`):

```text
((!(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})) OR (@Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {<writer guid>}))
AND ((!(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})) OR (@Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {<writer guid>}))
```

```sh
az role assignment create --assignee-object-id <principalId> --assignee-principal-type ServicePrincipal \
  --role "Role Based Access Control Administrator" --scope <storageAccountResourceId> \
  --condition "<condition above>" --condition-version 2.0
```

Start a remediation task for existing servers (`az policy remediation create --policy-assignment pbb-vm -g <rg>`).
For each server the policy creates the guest assignment and one role assignment of the Writer role on the container,
with an ABAC condition that allows writes only under `<subscriptionId>/<resourceGroup>/<server>/`.

**Parameters** (both definitions): `MaxSizeMB` (512), `SampleIntervalSeconds` (10), `ExportEveryHours` (4; one of 1,
2, 3, 4, 6, 8, 12, 24), `StorageAccountResourceId` (required), `ContainerName` (`perfmon`), `LocalKeepMB` (1024),
`WriterRoleDefinitionId` (required). A changed value reaches the servers at the next evaluation; the collector is
re-created without losing what it recorded.

Scale note: one role assignment per server counts toward the subscription's role-assignment limit.

### 4. The skill

```sh
SRE_AGENT_ID=<agent resource ID> scripts/deploy-skill.sh skill/perfmon-triage            # dry run
SRE_AGENT_ID=<agent resource ID> scripts/deploy-skill.sh skill/perfmon-triage --apply    # needs SRE Agent Administrator
```

Ask the agent, in a new thread: *"Analyse the latest PerfMon capture of `<server>`. The captures are in the storage
account `<name>`."*

## On each server

`C:\ProgramData\PerfmonBlackbox\` (SYSTEM and Administrators only): `bin\` (scripts, counter lists, template),
`blg\` (the live ring), `pending\` (closed rings not yet exported), `outbox\`, `log\`, `config.json`, `state.json`.
Tasks `\PerfmonBlackbox\Boot` and `\PerfmonBlackbox\Export`. Event log source `PerfmonBlackbox` (1000s info, 2000s data
loss, 3000s errors). Captures live at `perfmon/<subscriptionId>/<resourceGroup>/<server>/<yyyy>/<mm>/<dd>/` in storage.

## Cost

Prices: Azure Retail Prices API (`prices.azure.com`), retail USD, queried 2026-10-11 (Sweden Central for storage).

| Item | Price | Per server per month |
|---|---|---|
| Machine Configuration on an **Azure VM** | free | 0 |
| Machine Configuration on an **Arc-enabled server** ("Guest Configuration Policy/Server") | 6.00 USD / server / month | **6.00 USD** |
| Blob storage, Hot LRS | 0.0184 USD / GB / month | ≈ 0.01 USD (100 processes) to ≈ 0.03 USD (350 processes) |
| Write operations | 0.05 USD / 10,000 | < 0.01 USD (6 exports a day) |
| Private endpoint data processed | 0.01 USD / GB in and out | < 0.01 USD |

Per deployment: the private endpoint, 0.01 USD / hour ≈ **7.30 USD / month**, plus the storage account itself (no fixed
charge). Storage volume, measured in the lab: a zipped capture costs ≈ 1.9 KB per sample at ~117 processes and 10 s
(≈ 16 MB a day, ≈ 0.5 GB held under the 30-day lifecycle rule); it grows with the process count like the buffer does.

**So: an Azure VM costs ≈ 0.01–0.03 USD a month, an Arc server ≈ 6.03 USD, plus ≈ 7.30 USD a month per deployment.**

## Remove

Delete the policy assignments (and their remediation), then on each server the guest assignment is removed by the
agent; delete the collector set (`logman stop PerfmonBlackbox; logman delete PerfmonBlackbox`), the two tasks and
`C:\ProgramData\PerfmonBlackbox`. Delete the storage deployment last.
