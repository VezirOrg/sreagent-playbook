// perfmon-blackbox: the private storage for the captures (design sec. 3.2-3.4; decisions P19 CHOICE 4-6).
// Deploy at resource-group scope:
//   az deployment group create -g <rg> -f infra/main.bicep -p storageAccountName=<name> \
//     privateEndpointSubnetId=<subnet id> blobPrivateDnsZoneId=<privatelink.blob zone id> readerPrincipalIds='["<agent principal>"]'
// Creates: StorageV2 (no shared key, no public network access, no anonymous access, TLS 1.2), container `perfmon`,
// lifecycle delete after retentionDays, blob soft delete, a private endpoint with its DNS zone group, the custom
// role "PerfMon Blackbox Writer" (blob write only; the DINE policy assigns it per machine with an ABAC path
// condition), and Storage Blob Data Reader on the container for the SRE Agent identities.

@description('Storage account name (3-24 lower-case letters and digits, globally unique).')
param storageAccountName string

param location string = resourceGroup().location

@description('Container for all machines (the policies ContainerName parameter).')
param containerName string = 'perfmon'

@description('Blobs older than this are deleted (CHOICE 6).')
@minValue(1)
param retentionDays int = 30

@description('Subnet for the storage private endpoint (CHOICE 5). Machines and the SRE Agent must reach it.')
param privateEndpointSubnetId string

@description('Resource ID of the privatelink.blob.<suffix> private DNS zone linked to the VNet(s) of the machines and the agent.')
param blobPrivateDnsZoneId string

@description('Principal IDs (object IDs) of the SRE Agent identities that read the captures (Storage Blob Data Reader on the container).')
param readerPrincipalIds array = []

@description('Name of the custom write-only role. Must be unique in the tenant if deployed to several resource groups.')
param writerRoleName string = 'PerfMon Blackbox Writer'

resource sa 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  kind: 'StorageV2'
  sku: { name: 'Standard_LRS' }
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    allowCrossTenantReplication: false
    defaultToOAuthAuthentication: true
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    publicNetworkAccess: 'Disabled'
    networkAcls: { defaultAction: 'Deny', bypass: 'None' }
  }
}

resource blobs 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: sa
  name: 'default'
  properties: {
    deleteRetentionPolicy: { enabled: true, days: 7 }
    containerDeleteRetentionPolicy: { enabled: true, days: 7 }
  }
}

resource container 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobs
  name: containerName
  properties: { publicAccess: 'None' }
}

resource lifecycle 'Microsoft.Storage/storageAccounts/managementPolicies@2023-05-01' = {
  parent: sa
  name: 'default'
  properties: {
    policy: {
      rules: [
        {
          name: 'perfmon-retention'
          enabled: true
          type: 'Lifecycle'
          definition: {
            filters: { blobTypes: [ 'blockBlob' ], prefixMatch: [ '${containerName}/' ] }
            actions: { baseBlob: { delete: { daysAfterModificationGreaterThan: retentionDays } } }
          }
        }
      ]
    }
  }
}

resource pe 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-${storageAccountName}-blob'
  location: location
  properties: {
    subnet: { id: privateEndpointSubnetId }
    privateLinkServiceConnections: [
      { name: 'blob', properties: { privateLinkServiceId: sa.id, groupIds: [ 'blob' ] } }
    ]
  }
}

resource peDns 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: pe
  name: 'default'
  properties: { privateDnsZoneConfigs: [ { name: 'blob', properties: { privateDnsZoneId: blobPrivateDnsZoneId } } ] }
}

// write only: no read, list or delete (design sec. 3.2)
resource writerRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' = {
  name: guid(resourceGroup().id, writerRoleName)
  properties: {
    roleName: writerRoleName
    description: 'perfmon-blackbox: a machine writes its capture zips into its own prefix (assigned per machine by the DINE policy with an ABAC path condition). No read, list or delete.'
    type: 'CustomRole'
    assignableScopes: [ resourceGroup().id ]
    permissions: [
      {
        actions: []
        notActions: []
        dataActions: [
          'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/write'
          'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/add/action'
        ]
        notDataActions: []
      }
    ]
  }
}

// the policy assignment identity deploys the per-machine role assignment here (nested deployment): it needs
// deployments only; every resource in that template is still checked against its own rights (RBAC Administrator
// limited to the writer role by a delegation condition, assigned in tests/lab/lab-policy.sh / README)
param deployerRoleName string = 'PerfMon Blackbox Deployer'
resource deployerRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' = {
  name: guid(resourceGroup().id, deployerRoleName)
  properties: {
    roleName: deployerRoleName
    description: 'perfmon-blackbox: the DINE policy identity deploys the per-machine writer role assignment in this resource group. Deployments only.'
    type: 'CustomRole'
    assignableScopes: [ resourceGroup().id ]
    permissions: [
      {
        actions: [
          'Microsoft.Resources/deployments/*'
          'Microsoft.Resources/subscriptions/resourceGroups/read'
        ]
        notActions: []
        dataActions: []
        notDataActions: []
      }
    ]
  }
}

var blobDataReader = '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1'

resource readers 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for p in readerPrincipalIds: {
  scope: container
  name: guid(container.id, p, blobDataReader)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', blobDataReader)
    principalId: p
    principalType: 'ServicePrincipal'
  }
}]

output storageAccountResourceId string = sa.id
output storageAccountName string = sa.name
output containerName string = container.name
output writerRoleDefinitionId string = writerRole.id
output deployerRoleDefinitionId string = deployerRole.id
output blobEndpoint string = sa.properties.primaryEndpoints.blob
