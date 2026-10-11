# Architecture

> **Summary.** Azure Policy installs a Machine Configuration package on every targeted Windows server (Azure VM or
> Arc). The package keeps a binary circular PerfMon log running and exports the window since the last export every few
> hours to a private storage account, with the server's own identity, into its own folder. The SRE Agent's skill
> fetches the latest zip of a server and analyses it. Nothing is installed on the servers.
>
> Draft until v1.0.0.

## Picture

```mermaid
flowchart LR
  subgraph Azure Policy
    PV[perfmon-blackbox-vm<br/>DeployIfNotExists]
    PA[perfmon-blackbox-arc<br/>DeployIfNotExists]
  end
  subgraph Server["Windows server (Azure VM or Arc)"]
    MC[Machine Configuration agent<br/>own PowerShell 7] --> R[DSC resources R1-R6]
    R --> DCS[Data Collector Set<br/>binary circular, MaxSizeMB]
    R --> T1[Task Boot<br/>Windows PowerShell 5.1]
    R --> T2[Task Export<br/>every ExportEveryHours]
    T2 -->|roll, relog, zip,<br/>manifest| Z[(zip)]
  end
  PV -->|guest assignment +<br/>writer role on the container| MC
  PA --> MC
  Z -->|PUT Blob, token from<br/>IMDS or HIMDS| ST[(Private storage<br/>perfmon/sub/rg/server/...)]
  ST -->|read, private endpoint| AG[SRE Agent<br/>skill perfmon-triage]
  AG --> REP[Report in the agent thread]
```

ASCII, for viewers without mermaid:

```
 Policy (VM) / Policy (Arc) --DINE--> guest assignment PerfmonBlackbox + Writer role (ABAC: own prefix only)
                                           |
 Server:  Machine Configuration agent ---> R1 files+config  R2 collector  R3 running  R4 boot task  R5 export task  R6 capacity
          Data Collector Set (binary circular, MaxSizeMB) <- Boot task (start, keep old ring as pending)
          Export task: stop -> move ring to pending\ -> start -> relog -> CSV window since last export -> zip + manifest
                         -> token (IMDS on Azure VMs, HIMDS on Arc) -> PUT Blob -> state.json moves forward
                                           |
 Storage (private endpoint, no keys):  perfmon/<sub>/<rg>/<server>/<yyyy>/<mm>/<dd>/<server>_<from>_<to>.zip
                                           |
 SRE Agent (VNet integrated): perfmon_fetch_latest.py -> CSV -> SQLite -> triage -> report
```

## The parts

| Part | Where | What |
|---|---|---|
| Two policy definitions | `policy/build_policies.py` | DINE: the guest assignment, and one Writer role assignment per server with an ABAC path condition |
| Package `PerfmonBlackbox` | `package/` | DSC resources R1–R6 (`PerfmonBlackboxDsc`), the collector files, two 5.1 scripts |
| Storage | `infra/main.bicep` | private, no shared key, lifecycle 30 days, the Writer and Deployer custom roles |
| Skill | `skill/perfmon-triage/` | fetch latest zip, convert, triage; quotes gaps and `complete` |

## Two runtimes on the server

| Code | Runs in |
|---|---|
| DSC resources (R1–R6) | the Machine Configuration agent's own PowerShell 7 (ships with the agent) |
| `Start-PerfmonBlackbox.ps1`, `Export-PerfmonBlackbox.ps1` | Windows PowerShell 5.1, as SYSTEM, from scheduled tasks |

Both use only what ships with Windows: `logman`, `relog`, `schtasks`, `icacls`, .NET, `Invoke-WebRequest`.

## The export, step by step

1. **Roll**: stop the collector, move the ring to `pending\`, start it again (a running circular `.blg` cannot be read;
   the restart costs a few seconds and is measured in every manifest as `roll_seconds`).
2. **Window**: relog every pending ring to CSV, merge them in time order, keep only samples after the last exported one.
3. **Holes**: every step longer than two intervals becomes a gap with a cause (`buffer_overrun`, `collector_restart`,
   `machine_off`, `local_cap`, `missing_samples`); `complete` is false if there is any.
4. **Zip** the CSV with `manifest.json`; **upload** with the server's identity; only then move `last_ts` forward.

Details: [design.md](design.md), decisions in [../decisions.md](../decisions.md).
