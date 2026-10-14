# Deploy

> **Summary.** Four steps: (1) the private storage with `infra/main.bicep`, (2) the policy definitions from the
> release's package, (3) the assignments with the rights their identity needs, then remediation, (4) the skill on your
> SRE Agent. Prerequisites first: servers and agent must both reach the storage's private endpoint.
>
> As of v1.0.1. Every numbered step was run in the lab on an Azure VM and an Arc-enabled server ([tests.md](tests.md)).
> 1b (an existing storage account) and 3b (the portal route) come from a first install outside the lab; what was not
> verified is marked.

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
- **Rights for the deployer** (Contributor + Role Based Access Control Administrator is **not** enough: Contributor
  cannot write `Microsoft.Authorization` objects and RBAC Administrator writes only role assignments):
  - policy definitions (step 2): **Owner** or **Resource Policy Contributor** at **subscription** scope (the
    definitions live there);
  - the custom roles (step 1): **Owner** or **User Access Administrator** on the storage resource group;
  - the storage, private endpoint and DNS zone group (step 1): Contributor on the storage resource group, plus join
    rights on the subnet and the DNS zone if they live elsewhere;
  - the assignments and their role grants (step 3): **Owner**, or **Resource Policy Contributor + User Access
    Administrator** (or Role Based Access Control Administrator), on the machines' resource group **and** on the
    storage (account and resource group).
  - Under Privileged Identity Management, make the role assignments you grant **Active** and **Permanent**, not
    Eligible: the assignment identity cannot activate a role (seen at a first install outside the lab, P89; not
    tested in the lab).
- **Tools**: Azure CLI, Python 3 (to generate the policy definitions), git.

All commands run from `playbooks/perfmon-blackbox` in a clone of this repository at the release tag, with the Azure CLI
signed in to the right subscription:

```sh
git clone --branch perfmon-blackbox/v1.0.1 https://github.com/VezirOrg/sreagent-playbook.git
cd sreagent-playbook/playbooks/perfmon-blackbox
```

**Azure VMs only, once per scope: the Machine Configuration prerequisites.** Assign the built-in initiative (it gives
each VM a system-assigned identity and the Machine Configuration extension), give its identity Contributor, and
remediate each of its policies:

```sh
prereq=$(az policy set-definition list --query "[?displayName=='Deploy prerequisites to enable Guest Configuration policies on virtual machines'].name | [0]" -o tsv)
az policy assignment create -n gc-prereq --policy-set-definition "$prereq" --scope <scope> --mi-system-assigned --location <region>
pp=$(az policy assignment show -n gc-prereq --scope <scope> --query identity.principalId -o tsv)
az role assignment create --assignee-object-id $pp --assignee-principal-type ServicePrincipal --role Contributor --scope <scope>
for ref in $(az policy set-definition show -n "$prereq" --query "policyDefinitions[].policyDefinitionReferenceId" -o tsv); do
  az policy remediation create -n "gc-prereq-$ref" --policy-assignment gc-prereq --definition-reference-id "$ref" -g <rg> \
    --resource-discovery-mode ReEvaluateCompliance
done
```

A new assignment has no compliance results yet, so a plain remediation finds nothing ("Succeeded", 0 deployments):
`--resource-discovery-mode ReEvaluateCompliance` evaluates first (a few minutes; the same in step 3). Wait until the
extension `AzurePolicyforWindows` is on each VM before step 3 applies anything.

## Names: a second deployment in the same tenant or subscription

Two kinds of names are not local to your resource group:

- **Custom role display names are unique in the whole Microsoft Entra tenant** (Learn, *Azure custom roles*:
  `roleName`). `infra/main.bicep` creates "PerfMon Blackbox Writer" and "PerfMon Blackbox Deployer". A second
  deployment anywhere in the same tenant (another resource group or subscription) must pass other names, for example
  `-p writerRoleName='PerfMon Blackbox Writer (team-b)' deployerRoleName='PerfMon Blackbox Deployer (team-b)'`, and
  use those names in step 3.
- **Policy definition names are unique at their definition scope** (here the subscription, the default of
  `az policy definition create`). Step 2 uses fixed names (`perfmon-blackbox-vm`, `-arc`, `-vm-storage`,
  `-arc-storage`): a second deployment in the same subscription with the same names **overwrites** the first one's
  definitions, and the first one's assignments follow the new rules at their next evaluation. Give the second
  deployment its own names (`-n perfmon-blackbox-vm-team-b`, and the same in `--policy` of step 3), or share one set of
  definitions and only add assignments.

Both outlive the resource group: on removal they are deleted explicitly ([operations.md](operations.md#remove)).

## 1. Private storage

```sh
az deployment group create -g <storage-rg> -f infra/main.bicep \
  -p storageAccountName=<name> \
     privateEndpointSubnetId=<subnet resource ID: an ordinary subnet for private endpoints, not a delegated one> \
     blobPrivateDnsZoneId=<resource ID of privatelink.blob.core.windows.net> \
     readerPrincipalIds='["<agent system identity object ID>","<agent user-assigned identity object ID>"]'
```

The agent's identities: in the portal on the agent resource (Identity), or
`az resource show --ids <agent resource ID> --query identity`.

Creates: StorageV2 (no shared key, public network access disabled, no anonymous access, TLS 1.2), container `perfmon`,
lifecycle delete after 30 days, blob soft delete, the private endpoint with its DNS zone group, the custom roles
**PerfMon Blackbox Writer** and **PerfMon Blackbox Deployer**, and Storage Blob Data Reader on the container for the
agent. Keep the outputs `storageAccountResourceId`, `writerRoleDefinitionId` and, for storage mode (2b),
`packageContainerResourceId`.

## 1b. Or: an existing storage account

You can use a storage account you already have (with its private endpoint) instead of step 1; a first install outside
the lab did (P89). Give it what `main.bicep` would:

| Needed | Why |
|---|---|
| container **`perfmon`** (or pass another name as the assignment parameter `ContainerName`) | the captures; the servers write only under their own prefix |
| container **`packages`**, exactly this name, holding the release zip unchanged (storage mode, 2b) | the definitions are generated with this container's ID |
| the two custom roles (below), in the storage account's resource group | the per-server Writer grant and the deployment that makes it |
| Storage Blob Data Reader on `perfmon` for the agent's identities | the skill reads the captures |
| a private endpoint (`blob`) whose name the **servers and the agent** both resolve and reach | uploads, the package, the skill |

Fine as they are: shared key access off, anonymous access off, public network access off, TLS 1.2. Optional: the
lifecycle rule (`main.bicep`: `perfmon-retention`, prefix `perfmon/`, delete after 30 days) and blob soft delete (7
days); without the rule, captures stay until you delete them. Not tested: an account with a hierarchical namespace (ADLS
Gen2). **Never grant the servers a storage role by hand**: the remediation grants each one (a hand-made grant of the same
role makes it fail with `RoleAssignmentExists`, step 3).

The custom roles as JSON for the portal (Access control (IAM) → Add → Add custom role → JSON; `<RG>` is the **storage
account's** resource group, the role names must be unique in the tenant, see *Names* above):

```json
{
  "properties": {
    "roleName": "PerfMon Blackbox Writer",
    "description": "perfmon-blackbox: a machine writes its capture zips into its own prefix (assigned per machine by the DINE policy with an ABAC path condition). No read, list or delete.",
    "assignableScopes": [ "/subscriptions/<SUB_ID>/resourceGroups/<RG>" ],
    "permissions": [ {
      "actions": [], "notActions": [],
      "dataActions": [
        "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/write",
        "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/add/action"
      ],
      "notDataActions": []
    } ]
  }
}
```

```json
{
  "properties": {
    "roleName": "PerfMon Blackbox Deployer",
    "description": "perfmon-blackbox: the DINE policy identity deploys the per-machine writer role assignment in this resource group. Deployments only.",
    "assignableScopes": [ "/subscriptions/<SUB_ID>/resourceGroups/<RG>" ],
    "permissions": [ {
      "actions": [ "Microsoft.Resources/deployments/*", "Microsoft.Resources/subscriptions/resourceGroups/read" ],
      "notActions": [], "dataActions": [], "notDataActions": []
    } ]
  }
}
```

Then use the account's resource ID as `storageAccountResourceId`, the Writer role's ID
(`/subscriptions/<SUB_ID>/providers/Microsoft.Authorization/roleDefinitions/<its GUID>`) as `writerRoleDefinitionId`,
and `<account ID>/blobServices/default/containers/packages` as `packageContainerResourceId`.

## 2. Policy definitions

Pick a release; its notes give the asset URL of `PerfmonBlackbox.zip` and its SHA-256. For **v1.0.1**:

| | |
|---|---|
| asset URL | `https://github.com/VezirOrg/sreagent-playbook/releases/download/perfmon-blackbox%2Fv1.0.1/PerfmonBlackbox.zip` |
| SHA-256 | `806BCADB69F556401DE19754AEB649B7611EB1AE18AA106A5BF0A537A99363DD` |
| `--version` | `1.0.1` (the guest assignment's label; a later release passes a higher one) |

```sh
python3 policy/build_policies.py --content-uri <asset URL> --content-hash <sha256> --version <x.y.z> --out policy/out
p() { python3 -c 'import json,sys; v=json.load(open(sys.argv[1]))["properties"][sys.argv[2]]; print(v if isinstance(v,str) else json.dumps(v))' "$1" "$2"; }
for kind in vm arc; do
  f=policy/out/perfmon-blackbox-$kind.json
  az policy definition create -n perfmon-blackbox-$kind --mode Indexed --display-name "$(p $f displayName)" \
    --rules "$(p $f policyRule)" --params "$(p $f parameters)" --metadata "$(p $f metadata)"
done
```

**Pass all four parts** (rules, parameters, metadata, display name): Machine Configuration builds each server's guest
assignment from the definition's `metadata.guestConfiguration` ([architecture.md](architecture.md#why-the-package-source-is-fixed-when-the-definitions-are-generated));
without it storage mode does not work.

`perfmon-blackbox-vm` targets `Microsoft.Compute/virtualMachines` (Windows), `perfmon-blackbox-arc` targets
`Microsoft.HybridCompute/machines` (Windows). Create only the one(s) you need.

## 2b. Where the servers get the package: GitHub or your storage (P45, P48)

Two modes. The mode is part of the **policy definition** (Machine Configuration builds each server's guest assignment
from the definition's metadata, so it cannot be an assignment parameter; why, with the lab evidence:
[architecture.md](architecture.md#why-the-package-source-is-fixed-when-the-definitions-are-generated)):

| Mode | Definitions | The server downloads from | Needs |
|---|---|---|---|
| GitHub (default) | `perfmon-blackbox-vm`, `perfmon-blackbox-arc` (step 2 as is) | the release asset on github.com | outbound HTTPS to github.com (and its download host) |
| **Storage** | `perfmon-blackbox-vm-storage`, `perfmon-blackbox-arc-storage`, generated with your container's ID | `https://<account>.blob.core.windows.net/<container>/PerfmonBlackbox.zip`, with **its own system-assigned identity** (no SAS) | the private endpoint (same as for the uploads): **no internet at all** for the package |

In storage mode each server also gets **Storage Blob Data Reader on that container only**; the capture container stays
write-only. The `contentHash` is the release's SHA-256 in both modes, so it is the same zip either way: copy the release
zip **unchanged** into the container and check the hash.

```sh
curl -sL -o PerfmonBlackbox.zip <release asset URL>
shasum -a 256 PerfmonBlackbox.zip            # must equal the SHA-256 in the release notes
# The storage account has no public access: upload from a host inside the network that resolves and reaches its private
# endpoint (a VM in the VNet; your Mac or a hosted CI runner cannot). That host's identity (or your signed-in account on
# it) needs Storage Blob Data Contributor on the packages container: main.bicep grants it to nobody, so grant it, e.g.
#   az role assignment create --assignee-object-id <host identity> --assignee-principal-type ServicePrincipal \
#     --role "Storage Blob Data Contributor" --scope <packageContainerResourceId>
# and on the host: az login --identity (or az login), then:
az storage blob upload --auth-mode login --account-name <account> -c packages -n PerfmonBlackbox.zip -f PerfmonBlackbox.zip --overwrite
# the storage-mode definitions (packageContainerResourceId is an output of infra/main.bicep):
python3 policy/build_policies.py --content-uri <release asset URL> --content-hash <sha256> --version <x.y.z> \
  --package-container-id <packageContainerResourceId> --out policy/out
# -> policy/out/perfmon-blackbox-vm-storage.json, perfmon-blackbox-arc-storage.json: create them as in step 2 (name = file name)
```

**Never assign both modes over the same machine**: both write the guest assignment `PerfmonBlackbox` and would keep
overwriting each other. To switch a scope: delete the old assignment (and its identity's role assignments), create the
new one with its roles (step 3), run a compliance scan, remediate. The collector keeps running through the switch.
Switching **to** storage mode, expect a window of failed downloads (HTTP 403, in the agent log) until the remediation has
granted each machine its reader role on the package container: the service points the guest assignment at the storage
URI before that (in the lab: 08:53Z → reader granted 09:17Z → first good download 09:21Z). The machine keeps running
its current configuration meanwhile; nothing to do but wait.

A different file under that name is refused by the server's hash check (the server keeps its current configuration).

**Works with shared key access disabled; no SAS anywhere** (also for the package): every download and upload uses an
Entra ID token (the machine's system identity; your `az … --auth-mode login`). Policies such as "Storage accounts should
prevent shared key access" can stay enforced.

**Agent versions for storage mode** (system-identity download, GA July 2025): the Machine Configuration agent must be
**1.29.98.0 or later** (the lab ran 1.29.119.0 on the Azure VM and the Connected Machine agent 1.68 on Arc). Check:
- Azure VM: on the server, the folder name under `C:\Packages\Plugins\Microsoft.GuestConfiguration.ConfigurationforWindows\`
  (e.g. `1.29.119.0`). The extension's `typeHandlerVersion` (e.g. `1.1`) is the handler, not the agent version;
- Arc: `az connectedmachine show -g <rg> -n <server> --query agentVersion` (keep the Connected Machine agent current;
  its machine configuration service follows it), or `azcmagent version` on the server.
Older agents: use GitHub mode.

## 3. Assign, grant, remediate

```sh
az policy assignment create -n pbb-vm --policy perfmon-blackbox-vm --scope <scope> \
  --mi-system-assigned --location <region> \
  --params '{"StorageAccountResourceId":{"value":"<storageAccountResourceId>"},
             "WriterRoleDefinitionId":{"value":"<writerRoleDefinitionId>"}}'
# storage mode: --policy perfmon-blackbox-vm-storage (and an assignment name of its own, e.g. pbb-vm-storage)
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
az policy remediation create -n pbb-vm-1 --policy-assignment pbb-vm -g <rg> \
  --resource-discovery-mode ReEvaluateCompliance                               # per resource group in scope
```

The condition allows exactly the Writer role and the built-in Storage Blob Data Reader (`2a2b9908-…`, granted only in
storage mode, on the package container). **Upgrading from a setup without storage mode:** `az role assignment
create` returns an existing assignment unchanged, with its old condition; then update the condition
(`az role assignment update`) or the reader grant fails with "does not have permission to perform action
roleAssignments/write". Repeat for `perfmon-blackbox-arc` (`pbb-arc`). Wait a minute after the role assignments before the remediation.

**A remediation marked Failed with `RoleAssignmentExists`** (storage mode): a server already holds Storage Blob Data
Reader on the package container under another assignment (for example one granted by hand). The guest assignment is
still written, but the remediation reports Failed and the next one fails again. Delete the extra assignment (keep the
one the policy made, its description starts with `perfmon-blackbox:`), then scan and remediate again. Check afterwards
that the server's guest assignment says `ApplyAndAutoCorrect` (the `Check` command below, with
`--query properties.guestConfiguration.assignmentType`); in the lab one such server stayed `Audit` until a clean
remediation (tests.md, "rc.11 on lab18").

What happens per server: the guest assignment `PerfmonBlackbox` is created; one role assignment of the Writer role on
the container lets the server write only under `<subscriptionId>/<resourceGroup>/<server>/`; the agent applies the
package and the assignment turns Compliant **within about an hour** of the remediation (its first cycle only tests, the
next one applies; the lab measured ~45 minutes). Until then the guest assignment can show no assignment type
("typically resolves within one hour", Learn, machine configuration assignments). Parameters: [parameters.md](parameters.md).

The first sign on the server is **not** an event at install: the collector is created and started without one. The
first event of source `PerfmonBlackbox` is **1002** (export uploaded, complete) after the first export: at local 00:07
and then every `ExportEveryHours`, plus a random delay of up to 10 minutes. Event 1001 (collector started) comes only
at a restart of Windows or when a stopped collector is started again. All IDs: [operations.md](operations.md#events).

Check: `az rest --method get --url https://management.azure.com<server ID>/providers/Microsoft.GuestConfiguration/guestConfigurationAssignments/PerfmonBlackbox?api-version=2024-04-05 --query properties.complianceStatus`.

## 3b. Portal route

The steps above are the lab-tested CLI. Done in the portal (a first install outside the lab did, P89; the portal route as
a whole was **not** run in the lab), four things differ:

1. **Create the definitions by a REST PUT of the generated file, not in the portal's definition editor.** The editor does
   not keep `metadata.guestConfiguration` (a Microsoft Q&A answer says "Duplicate definition" drops it; Learn documents
   no way to set it there), and without it storage mode does not work. The generated file
   (`policy/out/<name>.json`) is already the request body. In Cloud Shell, PowerShell (**verified** at that install:
   201, metadata read back):

   ```powershell
   Invoke-AzRestMethod -Method PUT -Payload (Get-Content ./perfmon-blackbox-vm-storage.json -Raw) `
     -Path "/subscriptions/<SUB_ID>/providers/Microsoft.Authorization/policyDefinitions/perfmon-blackbox-vm-storage?api-version=2021-06-01"
   ```

   Bash (the same call, **not verified**):

   ```sh
   az rest --method put --body @perfmon-blackbox-vm-storage.json \
     --url "https://management.azure.com/subscriptions/<SUB_ID>/providers/Microsoft.Authorization/policyDefinitions/perfmon-blackbox-vm-storage?api-version=2021-06-01"
   ```

   Check either way: `az policy definition show -n perfmon-blackbox-vm-storage --query metadata.guestConfiguration`
   must not be empty. Repeat for `perfmon-blackbox-arc-storage` if you have Arc servers.
2. **The assignment's identity is named by a GUID**, not by the assignment's name. Find its principal ID on the
   assignment (Managed Identity), then grant roles in Access control (IAM) with "User, group, or service principal"
   and search for that ID.
3. **The portal grants roles by itself.** Assigning with a managed identity, the portal grants every role in the
   definition's `roleDefinitionIds` at the assignment scope (Learn, *Remediate non-compliant resources*): Guest
   Configuration Resource Contributor and Reader (wanted) and **Role Based Access Control Administrator without a
   condition, on the whole assignment scope** (broader than [security.md](security.md)). Add what step 3 needs and the
   portal does not (PerfMon Blackbox Deployer on the storage resource group; RBAC Administrator **on the storage account
   with the condition** of step 3, pasted in Conditions → code editor with `$w` replaced by the Writer role's GUID),
   then **delete the unconditioned RBAC Administrator** at the assignment scope. Wait a minute.
4. **Remediate** with "Re-evaluate resource compliance before remediating" ticked (the CLI's
   `--resource-discovery-mode ReEvaluateCompliance`).

Under Privileged Identity Management, every role assignment above is **Active**, **Permanent** (prerequisites).

## 4. The skill

```sh
SRE_AGENT_ID=<agent resource ID> scripts/deploy-skill.sh skill/perfmon-triage            # dry run
SRE_AGENT_ID=<agent resource ID> scripts/deploy-skill.sh skill/perfmon-triage --apply    # create or update
```

Why a script and not Bicep like the rest: the ARM resource for skills (`Microsoft.App/agents/skills`) answered
"internal tenants only" when this was built, so the skill goes through the agent's data-plane API, which the script
calls (decisions P61).

The caller needs **SRE Agent Author + SRE Agent Standard User** on the agent resource: tested in the lab without
Administrator (decisions P64, [security.md](security.md)). Learn's *SRE Agent MCP server* page says the data plane
(threads, skills and more) needs **SRE Agent Administrator**; if Author + Standard User gets a 403 on your agent, that
is the role to try. Then ask the agent in a new thread:
*"Analyse the latest PerfMon capture of `<server>`. The captures are in the storage account `<name>`."*
