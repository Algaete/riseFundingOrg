@description('Function app name.')
param appName string
param location string
param runtimeVersion string = '10.0'
param maximumInstanceCount int = 10
param applicationInsightsConnectionString string
param applicationInsightsName string
param extraIdentityResourceId string
param sqlServerFqdn string
param sqlDatabaseName string
param sqlIdentityClientId string = ''
param appSettings object
param tags object

var compact = take(replace(appName, '-', ''), 20)
var hostStorageName = take('st${compact}${uniqueString(resourceGroup().id, appName)}', 24)
var packageContainerName = 'app-package-${take(uniqueString(appName), 12)}'
var blobOwnerRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b')
var queueContributorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '974c5e8b-45b9-4653-ba55-5f855dd0fb88')
var tableContributorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3')
var metricsPublisherRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '3913510d-42f4-4e42-8a64-420c390055eb')
var effectiveSqlIdentityClientId = empty(sqlIdentityClientId) ? hostIdentity.properties.clientId : sqlIdentityClientId

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: applicationInsightsName
}

resource hostIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-${appName}-host'
  location: location
  tags: tags
}

resource hostStorage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: hostStorageName
  location: location
  kind: 'StorageV2'
  sku: { name: 'Standard_LRS' }
  tags: tags
  properties: {
    allowBlobPublicAccess: false
    allowCrossTenantReplication: false
    allowSharedKeyAccess: false
    defaultToOAuthAuthentication: true
    minimumTlsVersion: 'TLS1_2'
    publicNetworkAccess: 'Enabled'
    networkAcls: { bypass: 'AzureServices', defaultAction: 'Allow' }
  }
  resource blobs 'blobServices' = {
    name: 'default'
    properties: {
      deleteRetentionPolicy: { enabled: true, days: 7 }
      containerDeleteRetentionPolicy: { enabled: true, days: 7 }
    }
    resource packages 'containers' = {
      name: packageContainerName
      properties: { publicAccess: 'None' }
    }
  }
  resource queues 'queueServices' = {
    name: 'default'
    properties: {}
    resource imports 'queues' = {
      name: 'imports'
      properties: {}
    }
  }
}

resource hostBlobOwner 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(hostStorage.id, hostIdentity.id, blobOwnerRoleId)
  scope: hostStorage
  properties: { roleDefinitionId: blobOwnerRoleId, principalId: hostIdentity.properties.principalId, principalType: 'ServicePrincipal' }
}
resource hostQueueContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(hostStorage.id, hostIdentity.id, queueContributorRoleId)
  scope: hostStorage
  properties: { roleDefinitionId: queueContributorRoleId, principalId: hostIdentity.properties.principalId, principalType: 'ServicePrincipal' }
}
resource hostTableContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(hostStorage.id, hostIdentity.id, tableContributorRoleId)
  scope: hostStorage
  properties: { roleDefinitionId: tableContributorRoleId, principalId: hostIdentity.properties.principalId, principalType: 'ServicePrincipal' }
}
resource hostMetricsPublisher 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(applicationInsights.id, hostIdentity.id, metricsPublisherRoleId)
  scope: applicationInsights
  properties: { roleDefinitionId: metricsPublisherRoleId, principalId: hostIdentity.properties.principalId, principalType: 'ServicePrincipal' }
}

resource plan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: 'plan-${appName}'
  location: location
  kind: 'functionapp'
  tags: tags
  sku: { name: 'FC1', tier: 'FlexConsumption' }
  properties: { reserved: true }
}

resource app 'Microsoft.Web/sites@2024-04-01' = {
  name: appName
  location: location
  kind: 'functionapp,linux'
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: union({ '${hostIdentity.id}': {} }, { '${extraIdentityResourceId}': {} })
  }
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    clientAffinityEnabled: false
    siteConfig: {
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      http20Enabled: true
    }
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: '${hostStorage.properties.primaryEndpoints.blob}${packageContainerName}'
          authentication: { type: 'UserAssignedIdentity', userAssignedIdentityResourceId: hostIdentity.id }
        }
      }
      scaleAndConcurrency: {
        maximumInstanceCount: maximumInstanceCount
        instanceMemoryMB: 2048
      }
      runtime: { name: 'dotnet-isolated', version: runtimeVersion }
    }
  }
  resource settings 'config' = {
    name: 'appsettings'
    properties: union(appSettings, {
      AZURE_FUNCTIONS_ENVIRONMENT: 'Production'
      FUNCTIONS_WORKER_RUNTIME: 'dotnet-isolated'
      AzureWebJobsStorage__accountName: hostStorage.name
      AzureWebJobsStorage__credential: 'managedidentity'
      AzureWebJobsStorage__clientId: hostIdentity.properties.clientId
      APPLICATIONINSIGHTS_CONNECTION_STRING: applicationInsightsConnectionString
      APPLICATIONINSIGHTS_AUTHENTICATION_STRING: 'ClientId=${hostIdentity.properties.clientId};Authorization=AAD'
      AZURE_SQL_CONNECTION_STRING: 'Server=tcp:${sqlServerFqdn},1433;Initial Catalog=${sqlDatabaseName};Encrypt=True;TrustServerCertificate=False;Authentication=Active Directory Managed Identity;User Id=${effectiveSqlIdentityClientId};'
    })
  }
}

output appName string = app.name
output hostStorageName string = hostStorage.name
output hostIdentityResourceId string = hostIdentity.id
output hostIdentityClientId string = hostIdentity.properties.clientId
output hostIdentityPrincipalId string = hostIdentity.properties.principalId
