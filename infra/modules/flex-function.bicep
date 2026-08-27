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
var effectiveSqlIdentityClientId = empty(sqlIdentityClientId) ? hostIdentity.properties.clientId : sqlIdentityClientId
var additionalAppSettings = [for setting in items(appSettings): {
  name: setting.key
  value: string(setting.value)
}]

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

module hostRbac './flex-function-rbac.bicep' = {
  name: '${appName}-host-rbac'
  params: {
    hostIdentityPrincipalId: hostIdentity.properties.principalId
    hostStorageName: hostStorage.name
    applicationInsightsName: applicationInsights.name
  }
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
      appSettings: concat(additionalAppSettings, [
        { name: 'AZURE_FUNCTIONS_ENVIRONMENT', value: 'Production' }
        // Flex Consumption derives the worker runtime from functionAppConfig.runtime and rejects
        // the legacy worker-runtime application setting during resource creation.
        { name: 'AzureWebJobsStorage__accountName', value: hostStorage.name }
        { name: 'AzureWebJobsStorage__credential', value: 'managedidentity' }
        { name: 'AzureWebJobsStorage__clientId', value: hostIdentity.properties.clientId }
        { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: applicationInsightsConnectionString }
        { name: 'APPLICATIONINSIGHTS_AUTHENTICATION_STRING', value: 'ClientId=${hostIdentity.properties.clientId};Authorization=AAD' }
        { name: 'AZURE_SQL_CONNECTION_STRING', value: 'Server=tcp:${sqlServerFqdn},1433;Initial Catalog=${sqlDatabaseName};Encrypt=True;TrustServerCertificate=False;Authentication=Active Directory Managed Identity;User Id=${effectiveSqlIdentityClientId};' }
      ])
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
  dependsOn: [
    hostStorage::blobs::packages
    hostRbac
  ]
}

output appName string = app.name
output hostStorageName string = hostStorage.name
output hostIdentityResourceId string = hostIdentity.id
output hostIdentityClientId string = hostIdentity.properties.clientId
output hostIdentityPrincipalId string = hostIdentity.properties.principalId
