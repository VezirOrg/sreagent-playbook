#!/usr/bin/env python3
r"""Generate the two perfmon-blackbox policy definitions (design sec. 3.1-3.2; decisions P2, P14, P17, P19, P23).

  perfmon-blackbox-vm.json   Microsoft.Compute/virtualMachines (Windows)    -> guest assignment on the VM
  perfmon-blackbox-arc.json  Microsoft.HybridCompute/machines (Windows)     -> guest assignment on the Arc machine

Both are DeployIfNotExists with the same parameters. The deployment does two things:
  1 the Azure Machine Configuration guest assignment PerfmonBlackbox (ApplyAndAutoCorrect, contentUri + contentHash pinned), with
    the six parameters as configurationParameter of [BlackboxFiles]Files (P23)
  2 a nested deployment at the storage account's resource group: one role assignment of the custom write-only role
    on the container for the machine's system identity, with an ABAC condition that allows writes only under
    '<subscriptionId>/<resourceGroup>/<machine>/' (lower case; CHOICE 3, CHOICE 4)
The assignment identity needs: Guest Configuration Resource Contributor and Reader on the machines' scope; on the storage
account's resource group the right to deploy (custom "PerfMon Blackbox Deployer", infra) and Role Based Access
Control Administrator limited by a delegation condition to the writer role (policy/README section in the playbook
README; tests/lab/lab-policy.sh does it in the lab).

Usage:
  build_policies.py --content-uri <https://.../PerfmonBlackbox.zip> --content-hash <sha256> --version 1.0.0 [--out policy/out]
    -> perfmon-blackbox-vm.json, perfmon-blackbox-arc.json: the package from the GitHub release asset (contentUri)
  ... --package-container-id <blob container resource ID>
    -> perfmon-blackbox-vm-storage.json, perfmon-blackbox-arc-storage.json: the same zip from your container, downloaded
       with the machine's system identity (no SAS), plus Storage Blob Data Reader on that container per machine (P48).
       The mode is fixed in the definition (metadata and deployment): the service syncs the guest assignment from the
       metadata. Never assign both modes over the same machine (both write the guest assignment PerfmonBlackbox).
Standard library only.
"""
import argparse
import json
import os

NAME = 'PerfmonBlackbox'
GC_CONTRIBUTOR = '088ab73d-1256-47ae-bea9-9de8e7131f31'   # built-in: Guest Configuration Resource Contributor
RBAC_ADMIN = 'f58310d9-a9f6-439a-9e8d-f62e7b41a168'       # built-in: Role Based Access Control Administrator
READER = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'           # built-in: Reader (to read the machine's identity)
BLOB_READER = '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1'      # built-in: Storage Blob Data Reader (package container, P45)


def package_container(resource_id):
    """P48: storage mode. '/subscriptions/<s>/resourceGroups/<rg>/providers/Microsoft.Storage/storageAccounts/<a>/
    blobServices/default/containers/<c>' -> (subscription, resource group, account, container, package URI)."""
    parts = resource_id.strip('/').split('/')
    if (len(parts) != 12 or parts[0].lower() != 'subscriptions' or parts[2].lower() != 'resourcegroups'
            or parts[5].lower() != 'microsoft.storage' or parts[6].lower() != 'storageaccounts' or parts[10].lower() != 'containers'):
        raise ValueError('not a blob container resource ID')
    sub, rg, account, container = parts[1], parts[3], parts[7], parts[11]
    return sub, rg, account, container, f'https://{account}.blob.core.windows.net/{container}/{NAME}.zip'


def reader_template():
    """Nested template (storage mode only): Storage Blob Data Reader on the package container for the machine."""
    return {
        '$schema': 'https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#',
        'contentVersion': '1.0.0.0',
        'parameters': {k: {'type': 'string'} for k in ('principalId', 'storageAccountName', 'containerName')},
        'resources': [{
            'type': 'Microsoft.Storage/storageAccounts/blobServices/containers/providers/roleAssignments',
            'apiVersion': '2022-04-01',
            'name': "[concat(parameters('storageAccountName'), '/default/', parameters('containerName'), '/Microsoft.Authorization/', "
                    "guid(parameters('storageAccountName'), parameters('containerName'), parameters('principalId'), 'package-reader'))]",
            'properties': {
                'roleDefinitionId': f"[subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '{BLOB_READER}')]",
                'principalId': "[parameters('principalId')]",
                'principalType': 'ServicePrincipal',
                'description': 'perfmon-blackbox: read the Machine Configuration package (system identity download)',
            },
        }],
    }

# policy parameter -> (default, description); all strings (Machine Configuration parameters must be strings)
PARAMS = [
    ('MaxSizeMB', '512', 'Maximum size of the circular .blg in MB (16..8192).'),
    ('SampleIntervalSeconds', '10', 'Sample interval of the collector in seconds (1..300).'),
    ('ExportEveryHours', '4', 'Export every N hours; N divides 24 (1, 2, 3, 4, 6, 8, 12, 24).'),
    ('StorageAccountResourceId', None, 'Resource ID of the private storage account that receives the captures.'),
    ('ContainerName', 'perfmon', 'Container for all machines.'),
    ('LocalKeepMB', '1024', 'Cap for pending buffers and not yet uploaded zips on the machine, in MB.'),
]
KIND = {
    'vm': {
        'type': 'Microsoft.Compute/virtualMachines',
        'assignment_type': 'Microsoft.Compute/virtualMachines/providers/guestConfigurationAssignments',
        'api': '2023-03-01',
        'if': [{'field': 'type', 'equals': 'Microsoft.Compute/virtualMachines'},
               {'field': 'Microsoft.Compute/virtualMachines/storageProfile.osDisk.osType', 'like': 'Windows*'}],
        'display': 'Azure VMs',
    },
    'arc': {
        'type': 'Microsoft.HybridCompute/machines',
        'assignment_type': 'Microsoft.HybridCompute/machines/providers/guestConfigurationAssignments',
        'api': '2022-12-27',
        'if': [{'field': 'type', 'equals': 'Microsoft.HybridCompute/machines'},
               {'field': 'Microsoft.HybridCompute/imageOffer', 'like': 'windows*'}],
        'display': 'Azure Arc-enabled servers',
    },
}
WRITE = 'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/write'
ADD = 'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/add/action'
PATH = '@Resource[Microsoft.Storage/storageAccounts/blobServices/containers/blobs:path]'


def cfg_name(p):
    return f'[BlackboxFiles]Files;{p}'


def parameter_hash():
    # same order and form as the configurationParameter list below (as New-GuestConfigurationPolicy generates it)
    parts = []
    for i, (p, _, _) in enumerate(PARAMS):
        if i:
            parts.append("','")
        parts.append(f"'{cfg_name(p)}', '=', parameters('{p}')")
    return '[base64(concat(' + ', '.join(parts) + '))]'


def abac_condition_expr():
    """ARM expression building the ABAC condition for the machine's prefix (template parameter 'prefix')."""
    head = f"((!(ActionMatches{{'{WRITE}'}}) AND !(ActionMatches{{'{ADD}'}})) OR ({PATH} StringStartsWith '"
    # the condition ends with  <prefix>/'))  : as an ARM string literal that is  '/''))'
    return "[concat('" + head.replace("'", "''") + "', parameters('prefix'), '/''))')]"


def role_template():
    """Nested template, deployed at the storage account's resource group (inner expression scope)."""
    return {
        '$schema': 'https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#',
        'contentVersion': '1.0.0.0',
        'parameters': {k: {'type': 'string'} for k in ('principalId', 'prefix', 'storageAccountName', 'containerName', 'writerRoleDefinitionId')},
        'resources': [{
            'type': 'Microsoft.Storage/storageAccounts/blobServices/containers/providers/roleAssignments',
            'apiVersion': '2022-04-01',
            'name': "[concat(parameters('storageAccountName'), '/default/', parameters('containerName'), '/Microsoft.Authorization/', "
                    "guid(parameters('storageAccountName'), parameters('containerName'), parameters('principalId')))]",
            'properties': {
                'roleDefinitionId': "[parameters('writerRoleDefinitionId')]",
                'principalId': "[parameters('principalId')]",
                'principalType': 'ServicePrincipal',
                'description': "[concat('perfmon-blackbox: write only under ', parameters('prefix'), '/')]",
                'condition': abac_condition_expr(),
                'conditionVersion': '2.0',
            },
        }],
    }


def definition(kind, content_uri, content_hash, version, package_container_id=None):
    k = KIND[kind]
    storage = package_container(package_container_id) if package_container_id else None
    if storage:
        content_uri = storage[4]
    params = {}
    for p, default, desc in PARAMS:
        params[p] = {'type': 'String', 'metadata': {'displayName': p, 'description': desc}}
        if default is not None:
            params[p]['defaultValue'] = default
    params['WriterRoleDefinitionId'] = {'type': 'String', 'metadata': {
        'displayName': 'WriterRoleDefinitionId',
        'description': 'Resource ID of the custom role "PerfMon Blackbox Writer" (infra output writerRoleDefinitionId).'}}
    params['effect'] = {'type': 'String', 'defaultValue': 'DeployIfNotExists', 'allowedValues': ['DeployIfNotExists', 'Disabled'],
                        'metadata': {'displayName': 'Effect'}}
    dep_params = {p: {'type': 'string'} for p, _, _ in PARAMS}
    dep_params.update({'machineName': {'type': 'string'}, 'location': {'type': 'string'}, 'WriterRoleDefinitionId': {'type': 'string'}})
    machine_id = f"[resourceId('{k['type']}', parameters('machineName'))]"
    gc_assignment = {
        'apiVersion': '2024-04-05',  # contentManagedIdentity exists only from 2024-04-05 (P47)
        'type': k['assignment_type'],
        'name': f"[concat(parameters('machineName'), '/Microsoft.GuestConfiguration/{NAME}')]",
        'location': "[parameters('location')]",
        'properties': {'guestConfiguration': {
            'name': NAME, 'version': version, 'contentUri': content_uri, 'contentHash': content_hash,
            'contentType': 'Custom', 'assignmentType': 'ApplyAndAutoCorrect',
            'configurationParameter': [{'name': cfg_name(p), 'value': f"[parameters('{p}')]"} for p, _, _ in PARAMS],
        }},
    }
    role = {
        'apiVersion': '2022-09-01',
        'type': 'Microsoft.Resources/deployments',
        'name': "[concat('perfmon-blackbox-writer-', uniqueString(parameters('machineName'), resourceGroup().id))]",
        'subscriptionId': "[split(parameters('StorageAccountResourceId'), '/')[2]]",
        'resourceGroup': "[split(parameters('StorageAccountResourceId'), '/')[4]]",
        'properties': {
            'mode': 'Incremental',
            'expressionEvaluationOptions': {'scope': 'inner'},
            'parameters': {
                'principalId': {'value': f"[reference({machine_id[1:-1]}, '{k['api']}', 'full').identity.principalId]"},
                'prefix': {'value': "[toLower(concat(subscription().subscriptionId, '/', resourceGroup().name, '/', parameters('machineName')))]"},
                'storageAccountName': {'value': "[last(split(parameters('StorageAccountResourceId'), '/'))]"},
                'containerName': {'value': "[parameters('ContainerName')]"},
                'writerRoleDefinitionId': {'value': "[parameters('WriterRoleDefinitionId')]"},
            },
            'template': role_template(),
        },
    }
    if storage:
        # P48: the system identity downloads the package; the same literal is in the metadata (the service syncs from it)
        gc_assignment['properties']['guestConfiguration']['contentManagedIdentity'] = 'system'
    reader = {
        'apiVersion': '2022-09-01',
        'type': 'Microsoft.Resources/deployments',
        'name': "[concat('perfmon-blackbox-pkgreader-', uniqueString(parameters('machineName'), resourceGroup().id))]",
        'subscriptionId': storage[0] if storage else '',
        'resourceGroup': storage[1] if storage else '',
        'properties': {
            'mode': 'Incremental',
            'expressionEvaluationOptions': {'scope': 'inner'},
            'parameters': {
                'principalId': {'value': f"[reference({machine_id[1:-1]}, '{k['api']}', 'full').identity.principalId]"},
                'storageAccountName': {'value': storage[2] if storage else ''},
                'containerName': {'value': storage[3] if storage else ''},
            },
            'template': reader_template(),
        },
    }
    deployment_parameters = {p: {'value': f"[parameters('{p}')]"} for p, _, _ in PARAMS}
    deployment_parameters.update({'machineName': {'value': "[field('name')]"}, 'location': {'value': "[field('location')]"},
                                  'WriterRoleDefinitionId': {'value': "[parameters('WriterRoleDefinitionId')]"}})
    meta_gc = {'name': NAME, 'version': version, 'contentType': 'Custom', 'contentUri': content_uri,
               'contentHash': content_hash, 'assignmentType': 'ApplyAndAutoCorrect',
               'configurationParameter': {p: cfg_name(p) for p, _, _ in PARAMS}}
    if storage:
        meta_gc['contentManagedIdentity'] = 'system'
    return {
        'properties': {
            'displayName': f'perfmon-blackbox: PerfMon black-box recorder on Windows {k["display"]}'
                           + (' (package from your storage)' if storage else ''),
            'policyType': 'Custom',
            'mode': 'Indexed',
            'description': ('Keeps a PerfMon Data Collector Set running as a black box (binary circular log) and exports the '
                            'capture every few hours to a private storage account with the machine\'s own identity, into its '
                            'own prefix only. Machine Configuration package PerfmonBlackbox (perfmon-blackbox playbook, '
                            'sreagent-playbook). Not an official Microsoft product.'),
            'metadata': {
                'category': 'Guest Configuration',
                'version': version,
                'requiredProviders': ['Microsoft.GuestConfiguration'],
                'guestConfiguration': meta_gc,
            },
            'parameters': params,
            'policyRule': {
                'if': {'allOf': k['if']},
                'then': {
                    'effect': "[parameters('effect')]",
                    'details': {
                        'type': 'Microsoft.GuestConfiguration/guestConfigurationAssignments',
                        'name': NAME,
                        'roleDefinitionIds': [f'/providers/Microsoft.Authorization/roleDefinitions/{GC_CONTRIBUTOR}',
                                              f'/providers/Microsoft.Authorization/roleDefinitions/{READER}',
                                              f'/providers/Microsoft.Authorization/roleDefinitions/{RBAC_ADMIN}'],
                        'existenceCondition': {'allOf': [
                            {'field': 'Microsoft.GuestConfiguration/guestConfigurationAssignments/complianceStatus', 'equals': 'Compliant'},
                            {'field': 'Microsoft.GuestConfiguration/guestConfigurationAssignments/parameterHash', 'equals': parameter_hash()},
                            # P32: a new package (release) makes machines on the old one non-compliant -> remediated
                            {'field': 'Microsoft.GuestConfiguration/guestConfigurationAssignments/guestConfiguration.contentHash', 'equals': content_hash},
                            # P45: a machine still on the other mode's source is redeployed
                            {'field': 'Microsoft.GuestConfiguration/guestConfigurationAssignments/guestConfiguration.contentUri', 'equals': content_uri},
                        ]},
                        'deployment': {'properties': {
                            'mode': 'incremental',
                            'parameters': deployment_parameters,
                            'template': {
                                '$schema': 'https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#',
                                'contentVersion': '1.0.0.0',
                                'parameters': dep_params,
                                'resources': [gc_assignment, role] + ([reader] if storage else []),
                            },
                        }},
                    },
                },
            },
        },
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--content-uri', required=True)
    ap.add_argument('--content-hash', required=True)
    ap.add_argument('--version', default='1.0.0')
    ap.add_argument('--package-container-id', help='storage mode (P48): resource ID of the blob container that holds the '
                    'same PerfmonBlackbox.zip; the machines download it with their system identity')
    ap.add_argument('--out', default=os.path.join(os.path.dirname(os.path.abspath(__file__)), 'out'))
    a = ap.parse_args()
    if not a.content_uri.startswith('https://'):
        ap.error('contentUri must be https')
    if a.package_container_id:
        try:
            package_container(a.package_container_id)
        except ValueError as e:
            ap.error(str(e))
    os.makedirs(a.out, exist_ok=True)
    suffix = '-storage' if a.package_container_id else ''
    for kind in ('vm', 'arc'):
        path = os.path.join(a.out, f'perfmon-blackbox-{kind}{suffix}.json')
        with open(path, 'w', encoding='utf-8') as f:
            json.dump(definition(kind, a.content_uri, a.content_hash.upper(), a.version, a.package_container_id), f, indent=2)
            f.write('\n')
        print(path)


if __name__ == '__main__':
    main()
