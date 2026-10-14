# Security

> **Summary.** Each server writes only into its own folder and cannot read or list anything; the storage has no keys
> and no public network access; the policy identity can grant only the one Writer role. Nothing is installed on the
> servers and nothing secret is in the package. The SRE Agent reads with a data-reader role on the container only.
>
> As of v1.0.1 (agent roles: Author + Standard User, tested; decisions P64).

## Identities and rights

| Identity | Right | Scope | Why |
|---|---|---|---|
| each server (system-assigned) | **PerfMon Blackbox Writer** (custom: `blobs/write`, `blobs/add/action` only) **with an ABAC condition** | the `perfmon` container | upload its own zips |
| each server (system-assigned), storage mode only (P48) | Storage Blob Data Reader | the package container (e.g. `packages`) | download the package with its own identity, no SAS |
| policy assignment identity | Guest Configuration Resource Contributor | the servers' scope | create the guest assignment |
| policy assignment identity | Reader | the servers' scope | read each server's identity (to grant it the Writer role) |
| policy assignment identity | **PerfMon Blackbox Deployer** (custom: `Microsoft.Resources/deployments/*`, resource group read) | the storage's resource group | deploy the per-server role assignment there; every resource in that deployment is still checked against the identity's own rights |
| policy assignment identity | Role Based Access Control Administrator **with a delegation condition** (may assign and delete only the Writer role) | the storage account | create the per-server Writer role assignment |
| SRE Agent identities | Storage Blob Data Reader | the `perfmon` container | read the captures |

The Writer role's condition, per server:

```text
((!(ActionMatches{'…/blobs/write'}) AND !(ActionMatches{'…/blobs/add/action'}))
 OR (@Resource[Microsoft.Storage/storageAccounts/blobServices/containers/blobs:path] StringStartsWith '<sub>/<rg>/<server>/'))
```

The trailing `/` matters: a server named `vm1` cannot write into `vm10/`. Tested on an Azure VM and on an Arc server
(T12): another server's folder, a look-alike folder, outside any folder, list, read and delete are all refused (403);
its own folder works (201).

## Storage

**Works with shared key access disabled; no SAS anywhere** (T14, T18f): no shared-key access (no keys anywhere), public network access disabled (private endpoint only), no anonymous
access, TLS 1.2, container private, blob soft delete 7 days, lifecycle delete after 30 days (T13, T14).

## On the servers

- Nothing is installed: no PowerShell 7, no agent, no module. Scripts run in Windows PowerShell 5.1; the DSC resources
  run in the Machine Configuration agent's own PowerShell 7, which ships with the agent. Tools used: `logman`, `relog`,
  `schtasks`, `icacls`, .NET, `Invoke-WebRequest`.
- `C:\ProgramData\PerfmonBlackbox` is readable by SYSTEM and Administrators only (captures hold process and instance
  names).
- Tokens come from the server's own identity at run time (IMDS on Azure VMs, the HIMDS challenge on Arc) and are never
  written to disk or logs. The package holds no secret and no environment value; everything comes from policy
  parameters.

## The agent role (note)

Deploying the skill and asking the agent need **SRE Agent Author + SRE Agent Standard User on the agent resource
only**: tested in the lab without SRE Agent Administrator (decisions P64). Learn's *SRE Agent MCP server* page says
the data plane (threads, skills and more) needs SRE Agent Administrator; our test says Author + Standard User is enough
for `deploy-skill.sh`. Grant Administrator only if your agent answers 403. The identity
that deploys skills should never be used to approve agent actions.
