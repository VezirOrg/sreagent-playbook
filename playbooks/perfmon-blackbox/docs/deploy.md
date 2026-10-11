# Deploy

> **Summary.** Four steps: (1) the private storage with `infra/main.bicep`, (2) the two policy definitions from the
> release's package, (3) the assignments with the rights their identity needs, then remediation, (4) the skill on your
> SRE Agent. Prerequisites first: servers and agent must both reach the storage's private endpoint.
>
> Draft until v1.0.0: the README-only fresh-eyes deploy at release validates these steps.

## Prerequisites

- **Servers**: Windows Server 2016 or later. Windows PowerShell 5.1 (built in). Nothing else is installed.
  - Azure VMs: assign the built-in initiative *Deploy prerequisites to enable Guest Configuration policies on virtual
    machines* (system-assigned identity + the Machine Configuration extension) on the same scope.
  - Arc-enabled servers: Connected Machine agent 1.10 or later (it brings Machine Configuration and the identity).
- **Network, servers**: each server must resolve `<account>.blob.core.windows.net` to the storage's **private
  endpoint** (private DNS zone `privatelink.blob.core.windows.net` linked to its VNet, or your DNS forwarding for
  on-premises Arc servers) and reach it on 443; and reach the package URL (GitHub release asset, HTTPS) and the
  Machine Configuration service endpoints.
- **Network, agent**: the SRE Agent needs **VNet integration** (sandbox egress in your VNet with private DNS
  resolution) that resolves and reaches the same private endpoint. Without it the skill cannot read any capture.
- **Rights for the deployer**: create a resource group deployment with custom role definitions, policy definitions and
  assignments, and role assignments (Owner, or Contributor + Role Based Access Control Administrator).
- **Tools**: Azure CLI, Python 3 (to generate the policy definitions).

All commands run from `playbooks/perfmon-blackbox` with the Azure CLI signed in to the right subscription.

## 1. Private storage

```sh
az deployment group create -g <storage-rg> -f infra/main.bicep \
  -p storageAccountName=<name> \
     privateEndpointSubnetId=<subnet resource ID> \
     blobPrivateDnsZoneId=<resource ID of privatelink.blob.core.windows.net> \
     readerPrincipalIds='["<agent system identity object ID>","<agent user-assigned identity object ID>"]'
```

Creates: StorageV2 (no shared key, public network access disabled, no anonymous access, TLS 1.2), container `perfmon`,
lifecycle delete after 30 days, blob soft delete, the private endpoint with its DNS zone group, the custom roles
**PerfMon Blackbox Writer** and **PerfMon Blackbox Deployer**, and Storage Blob Data Reader on the container for the
agent. Keep the outputs `storageAccountResourceId` and `writerRoleDefinitionId`.

## 2. Policy definitions

Pick a release; its notes give the asset URL of `PerfmonBlackbox.zip` and its SHA-256.

```sh
python3 policy/build_policies.py --content-uri <asset URL> --content-hash <sha256> --version <x.y.z> --out policy/out
for kind in vm arc; do
  f=policy/out/perfmon-blackbox-$kind.json
  az policy definition create -n perfmon-blackbox-$kind --mode Indexed \
    --rules  "$(python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))["properties"]["policyRule"]))' $f)" \
    --params "$(python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))["properties"]["parameters"]))' $f)"
done
```

`perfmon-blackbox-vm` targets `Microsoft.Compute/virtualMachines` (Windows), `perfmon-blackbox-arc` targets
`Microsoft.HybridCompute/machines` (Windows). Create only the one(s) you need.

## 2b. Where the servers get the package: GitHub or your storage (P45)

Two modes, chosen per assignment with the parameter **`PackageContainerResourceId`**:

| Mode | Parameter | The server downloads from | Needs |
|---|---|---|---|
| GitHub (default) | empty | the release asset on github.com | outbound HTTPS to github.com (and its download host) |
| **Storage** | the resource ID of a blob container, e.g. the `packages` container that `infra/main.bicep` creates | `https://<account>.blob.core.windows.net/<container>/PerfmonBlackbox.zip`, with **its own system-assigned identity** (no SAS) | the private endpoint (same as for the uploads): **no internet at all** for the package |

In storage mode the policy also grants each server **Storage Blob Data Reader on that container only**; the capture
container stays write-only. The `contentHash` is the release's SHA-256 in both modes, so it is the same zip either way:
copy the release zip **unchanged** into the container and check the hash.

```sh
curl -sL -o PerfmonBlackbox.zip <release asset URL>
shasum -a 256 PerfmonBlackbox.zip            # must equal the SHA-256 in the release notes
# from a host that reaches the storage's private endpoint, with Storage Blob Data Contributor on the container:
az storage blob upload --auth-mode login --account-name <account> -c packages -n PerfmonBlackbox.zip -f PerfmonBlackbox.zip --overwrite
```

A different file under that name is refused by the server's hash check (the server keeps its current configuration).

**Works with shared key access disabled; no SAS anywhere** (also for the package): every download and upload uses an
Entra ID token (the machine's system identity; your `az … --auth-mode login`). Policies such as "Storage accounts should
prevent shared key access" can stay enforced.

**Agent versions for storage mode** (system-identity download, GA July 2025): the Machine Configuration agent must be
**1.29.98.0 or later** (the lab ran 1.29.119.0 on the Azure VM and the Connected Machine agent 1.68 on Arc). Check:
- Azure VM: `az vm extension show -g <rg> --vm-name <vm> -n AzurePolicyforWindows --query typeHandlerVersion`, or on the
  server the folder name under `C:\Packages\Plugins\Microsoft.GuestConfiguration.ConfigurationforWindows\`;
- Arc: `az connectedmachine show -g <rg> -n <server> --query agentVersion` (keep the Connected Machine agent current;
  its machine configuration service follows it), or `azcmagent version` on the server.
Older agents: use GitHub mode.

## 3. Assign, grant, remediate

```sh
az policy assignment create -n pbb-vm --policy perfmon-blackbox-vm --scope <scope> \
  --mi-system-assigned --location <region> \
  --params '{"StorageAccountResourceId":{"value":"<storageAccountResourceId>"},
             "WriterRoleDefinitionId":{"value":"<writerRoleDefinitionId>"},
             "PackageContainerResourceId":{"value":""}}'      # or the package container's ID for storage mode
pid=$(az policy assignment show -n pbb-vm --scope <scope> --query identity.principalId -o tsv)
```

Give that identity exactly these roles (why: [security.md](security.md)):

```sh
az role assignment create --assignee-object-id $pid --assignee-principal-type ServicePrincipal \
  --role "Guest Configuration Resource Contributor" --scope <scope>
az role assignment create --assignee-object-id $pid --assignee-principal-type ServicePrincipal \
  --role Reader --scope <scope>
az role assignment create --assignee-object-id $pid --assignee-principal-type ServicePrincipal \
  --role "PerfMon Blackbox Deployer" --scope <storage resource group ID>
w=<last segment of writerRoleDefinitionId>
az role assignment create --assignee-object-id $pid --assignee-principal-type ServicePrincipal \
  --role "Role Based Access Control Administrator" --scope <storageAccountResourceId> --condition-version 2.0 \
  --condition "((!(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})) OR (@Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {$w, 2a2b9908-6ea1-4ae2-8e65-a410df84e7d1})) AND ((!(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})) OR (@Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {$w, 2a2b9908-6ea1-4ae2-8e65-a410df84e7d1}))"
az policy remediation create -n pbb-vm-1 --policy-assignment pbb-vm -g <rg>    # per resource group in scope
```

The condition allows exactly the Writer role and the built-in Storage Blob Data Reader (`2a2b9908-…`, granted only in
storage mode, on the package container). Repeat for `perfmon-blackbox-arc` (`pbb-arc`). Wait a minute after the role assignments before the remediation.

What happens per server: the guest assignment `PerfmonBlackbox` is created; one role assignment of the Writer role on
the container lets the server write only under `<subscriptionId>/<resourceGroup>/<server>/`; within 15–30 minutes the
agent applies the package and the assignment turns Compliant. Parameters: [parameters.md](parameters.md).

Check: `az rest --method get --url https://management.azure.com<server ID>/providers/Microsoft.GuestConfiguration/guestConfigurationAssignments/PerfmonBlackbox?api-version=2022-01-25 --query properties.complianceStatus`.

## 4. The skill

```sh
SRE_AGENT_ID=<agent resource ID> scripts/deploy-skill.sh skill/perfmon-triage            # dry run
SRE_AGENT_ID=<agent resource ID> scripts/deploy-skill.sh skill/perfmon-triage --apply    # create or update
```

The caller needs a role on the agent that may write skills (the lab used SRE Agent Administrator; the
least-privilege path is to be documented, see [security.md](security.md)). Then ask the agent in a new thread:
*"Analyse the latest PerfMon capture of `<server>`. The captures are in the storage account `<name>`."*
