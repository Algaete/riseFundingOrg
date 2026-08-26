param environmentName string
param location string
param uniqueSuffix string
param sqlEntraAdminLogin string
param sqlEntraAdminObjectId string
param sqlDatabaseName string
param deployCompute bool
param deployApiContainer bool
param apiContainerImageReference string

@minValue(0)
@maxValue(1)
param apiMinReplicas int

param tags object

var prefix = 'rf-${environmentName}-${uniqueSuffix}'
var compact = take(replace(prefix, '-', ''), 14)
var documentStorageName = take('stdoc${compact}${uniqueString(resourceGroup().id)}', 24)
var dataStorageName = take('stdata${compact}${uniqueString(subscription().id, prefix)}', 24)
var apiRegistryName = take('cr${compact}${uniqueString(subscription().id, prefix)}', 50)
var apiAppName = 'ca-${prefix}-api'
var apiEnvironmentName = 'cae-${prefix}'
var staticWebAppName = 'swa-${prefix}'
var generalWorkerName = 'func-${prefix}-general'
var extractionWorkerName = 'func-${prefix}-extract'
var keyVaultName = take('kv-${prefix}', 24)
var sqlServerName = take('sql-${prefix}', 63)
var blobContributorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
var blobReaderRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1')
var queueSenderRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'c6a89b2d-59bc-44d0-9896-0f6e12d7b80a')
var queueProcessorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '8a0f0c08-91a1-4084-bc3d-661d67233fed')
var secretsUserRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
var cryptoUserRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '12338af0-0e69-4776-bea7-57ae8d297424')
var metricsPublisherRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '3913510d-42f4-4e42-8a64-420c390055eb')
var acrPullRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')

resource logs 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'log-${prefix}'
  location: location
  tags: tags
  properties: { retentionInDays: 30, features: { searchVersion: 1 }, sku: { name: 'PerGB2018' } }
}

resource insights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'appi-${prefix}'
  location: location
  kind: 'web'
  tags: tags
  properties: { Application_Type: 'web', WorkspaceResourceId: logs.id, DisableLocalAuth: true }
}

resource apiIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-${prefix}-api'
  location: location
  tags: tags
}
resource extractionSenderIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-${prefix}-extract-send'
  location: location
  tags: tags
}
resource extractionConsumerIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-${prefix}-extract-consume'
  location: location
  tags: tags
}

resource documents 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: documentStorageName
  location: location
  kind: 'StorageV2'
  sku: { name: 'Standard_LRS' }
  tags: union(tags, { boundary: 'private-documents' })
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowCrossTenantReplication: false
    allowSharedKeyAccess: false
    defaultToOAuthAuthentication: true
    minimumTlsVersion: 'TLS1_2'
    publicNetworkAccess: 'Enabled'
    supportsHttpsTrafficOnly: true
    networkAcls: { bypass: 'AzureServices', defaultAction: 'Allow' }
  }
  resource blobService 'blobServices' = {
    name: 'default'
    properties: {
      deleteRetentionPolicy: { enabled: true, days: 14 }
      containerDeleteRetentionPolicy: { enabled: true, days: 14 }
      isVersioningEnabled: true
    }
    resource incoming 'containers' = { name: 'fp-source-incoming', properties: { publicAccess: 'None' } }
    resource quarantine 'containers' = { name: 'fp-source-quarantine', properties: { publicAccess: 'None' } }
    resource trusted 'containers' = { name: 'fp-source-trusted', properties: { publicAccess: 'None' } }
    resource dataProtection 'containers' = { name: 'dataprotection', properties: { publicAccess: 'None' } }
  }
}

resource dataStorage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: dataStorageName
  location: location
  kind: 'StorageV2'
  sku: { name: 'Standard_LRS' }
  tags: union(tags, { boundary: 'application-queues' })
  properties: {
    allowBlobPublicAccess: false
    allowCrossTenantReplication: false
    allowSharedKeyAccess: false
    defaultToOAuthAuthentication: true
    minimumTlsVersion: 'TLS1_2'
    publicNetworkAccess: 'Enabled'
    supportsHttpsTrafficOnly: true
    networkAcls: { bypass: 'AzureServices', defaultAction: 'Allow' }
  }
  resource queues 'queueServices' = {
    name: 'default'
    properties: {}
    resource extractions 'queues' = { name: 'document-extractions', properties: {} }
  }
}

resource vault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    tenantId: tenant().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    enablePurgeProtection: false
    softDeleteRetentionInDays: 30
    publicNetworkAccess: 'Enabled'
    sku: { family: 'A', name: 'standard' }
  }
  resource dataProtectionKey 'keys' = {
    name: 'data-protection'
    properties: {
      attributes: { enabled: true, exportable: false }
      kty: 'RSA'
      keySize: 2048
      keyOps: [ 'encrypt', 'decrypt', 'wrapKey', 'unwrapKey' ]
      rotationPolicy: {
        attributes: { expiryTime: 'P12M' }
        lifetimeActions: [ { action: { type: 'rotate' }, trigger: { timeBeforeExpiry: 'P30D' } } ]
      }
    }
  }
}

resource sqlServer 'Microsoft.Sql/servers@2023-08-01-preview' = {
  name: sqlServerName
  location: location
  tags: tags
  properties: {
    administrators: {
      administratorType: 'ActiveDirectory'
      azureADOnlyAuthentication: true
      login: sqlEntraAdminLogin
      principalType: 'Group'
      sid: sqlEntraAdminObjectId
      tenantId: tenant().tenantId
    }
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    restrictOutboundNetworkAccess: 'Enabled'
    version: '12.0'
  }
}

resource allowAzureServices 'Microsoft.Sql/servers/firewallRules@2023-08-01-preview' = {
  parent: sqlServer
  name: 'AllowAzureServicesForDev'
  properties: { startIpAddress: '0.0.0.0', endIpAddress: '0.0.0.0' }
}

resource database 'Microsoft.Sql/servers/databases@2023-08-01-preview' = {
  parent: sqlServer
  name: sqlDatabaseName
  location: location
  tags: tags
  sku: { name: 'GP_S_Gen5_1', tier: 'GeneralPurpose', family: 'Gen5', capacity: 1 }
  properties: {
    autoPauseDelay: 60
    minCapacity: json('0.5')
    readScale: 'Disabled'
    requestedBackupStorageRedundancy: 'Local'
    zoneRedundant: false
  }
}

resource apiRegistry 'Microsoft.ContainerRegistry/registries@2025-11-01' = if (deployCompute) {
  name: apiRegistryName
  location: location
  tags: union(tags, { boundary: 'private-container-images' })
  sku: { name: 'Basic' }
  properties: {
    adminUserEnabled: false
    anonymousPullEnabled: false
    dataEndpointEnabled: false
    networkRuleBypassOptions: 'AzureServices'
    policies: {
      azureADAuthenticationAsArmPolicy: { status: 'enabled' }
      exportPolicy: { status: 'enabled' }
      quarantinePolicy: { status: 'disabled' }
      retentionPolicy: { days: 7, status: 'disabled' }
      trustPolicy: { status: 'disabled', type: 'Notary' }
    }
    publicNetworkAccess: 'Enabled'
    roleAssignmentMode: 'LegacyRegistryPermissions'
    zoneRedundancy: 'Disabled'
  }
}

resource apiContainerEnvironment 'Microsoft.App/managedEnvironments@2025-01-01' = if (deployCompute) {
  name: apiEnvironmentName
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'azure-monitor'
    }
    zoneRedundant: false
  }
}

resource apiContainerEnvironmentDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (deployCompute) {
  name: 'send-to-${logs.name}'
  scope: apiContainerEnvironment
  properties: {
    workspaceId: logs.id
    logs: [
      { categoryGroup: 'allLogs', enabled: true }
    ]
    metrics: [
      { category: 'AllMetrics', enabled: true }
    ]
  }
}

resource staticSite 'Microsoft.Web/staticSites@2025-03-01' = if (deployCompute) {
  name: staticWebAppName
  location: location
  tags: tags
  sku: { name: 'Free', tier: 'Free' }
  properties: {
    allowConfigFileUpdates: true
    publicNetworkAccess: 'Enabled'
    stagingEnvironmentPolicy: 'Disabled'
  }
}

var apiDefaultOrigin = deployCompute ? 'https://${apiAppName}.${apiContainerEnvironment!.properties.defaultDomain}' : ''
var frontendDefaultOrigin = deployCompute ? 'https://${staticSite!.properties.defaultHostname}' : ''

module apiContainer './container-api.bicep' = if (deployCompute && deployApiContainer) {
  name: 'api-container'
  params: {
    appName: apiAppName
    location: location
    managedEnvironmentId: apiContainerEnvironment.id
    registryServer: apiRegistry!.properties.loginServer
    registryIdentityResourceId: apiIdentity.id
    runtimeIdentityResourceId: apiIdentity.id
    imageReference: apiContainerImageReference
    minReplicas: apiMinReplicas
    tags: tags
    appSettings: {
      ASPNETCORE_ENVIRONMENT: 'Production'
      ASPNETCORE_FORWARDEDHEADERS_ENABLED: 'true'
      ASPNETCORE_HTTP_PORTS: '8080'
      AZURE_CLIENT_ID: apiIdentity.properties.clientId
      AZURE_KEY_VAULT_URI: vault.properties.vaultUri
      AZURE_STORAGE_DATA_PROTECTION_BLOB_URI: '${documents.properties.primaryEndpoints.blob}dataprotection/keys.xml'
      AZURE_KEY_VAULT_DATA_PROTECTION_KEY_URI: '${vault.properties.vaultUri}keys/data-protection'
      AZURE_SQL_CONNECTION_STRING: 'Server=tcp:${sqlServer.properties.fullyQualifiedDomainName},1433;Initial Catalog=${database.name};Encrypt=True;TrustServerCertificate=False;Authentication=Active Directory Managed Identity;User Id=${apiIdentity.properties.clientId};'
      AZURE_STORAGE_BLOB_SERVICE_URI: documents.properties.primaryEndpoints.blob
      SOURCE_DOCUMENT_INCOMING_CONTAINER: 'fp-source-incoming'
      SOURCE_DOCUMENT_QUARANTINE_CONTAINER: 'fp-source-quarantine'
      SOURCE_DOCUMENT_TRUSTED_CONTAINER: 'fp-source-trusted'
      APPLICATIONINSIGHTS_CONNECTION_STRING: insights.properties.ConnectionString
      APPLICATIONINSIGHTS_AUTHENTICATION_STRING: 'ClientId=${apiIdentity.properties.clientId};Authorization=AAD'
      FRONTEND_BASE_URL: frontendDefaultOrigin
      ALLOWED_CORS_ORIGINS: frontendDefaultOrigin
      JWT_ISSUER: apiDefaultOrigin
      JWT_AUDIENCE: 'FundingPlatform.Web'
      AUTH_ACCESS_TOKEN_MINUTES: '15'
      AUTH_REFRESH_TOKEN_DAYS: '30'
      AUTH_ADMIN_SESSION_MINUTES: '60'
      DEFENDER_EVENT_GRID_ENABLED: 'false'
      OFFICIAL_RSS_ENABLED: 'false'
      SEMANTIC_ENABLED: 'false'
      OPENAI_ENABLED: 'false'
      ALERTS_ENABLED: 'false'
      BILLING_ENABLED: 'false'
      BILLING_SANDBOX_ONLY: 'true'
      PAYMENT_PROVIDER: 'Disabled'
    }
  }
  dependsOn: [
    apiAcrPull
  ]
}

var documentsBlobUri = documents.properties.primaryEndpoints.blob
var dataQueueUri = dataStorage.properties.primaryEndpoints.queue

module generalWorker './flex-function.bicep' = if (deployCompute) {
  name: 'general-worker'
  params: {
    appName: generalWorkerName
    location: location
    applicationInsightsConnectionString: insights.properties.ConnectionString
    applicationInsightsName: insights.name
    extraIdentityResourceId: extractionSenderIdentity.id
    sqlServerFqdn: sqlServer.properties.fullyQualifiedDomainName
    sqlDatabaseName: database.name
    tags: tags
    appSettings: {
      AZURE_STORAGE_BLOB_SERVICE_URI: documentsBlobUri
      DocumentExtractionQueueStorage__queueServiceUri: dataQueueUri
      DocumentExtractionQueueStorage__credential: 'managedidentity'
      DocumentExtractionQueueStorage__senderClientId: extractionSenderIdentity.properties.clientId
      DocumentExtractionQueueStorage__clientId: extractionConsumerIdentity.properties.clientId
      DEFENDER_EVENT_GRID_ENABLED: 'false'
      OFFICIAL_RSS_ENABLED: 'false'
      SEMANTIC_ENABLED: 'false'
      OPENAI_ENABLED: 'false'
      ALERTS_ENABLED: 'false'
      BILLING_ENABLED: 'false'
      BILLING_SANDBOX_ONLY: 'true'
      PAYMENT_PROVIDER: 'Disabled'
    }
  }
}

module extractionWorker './flex-function.bicep' = if (deployCompute) {
  name: 'extraction-worker'
  params: {
    appName: extractionWorkerName
    location: location
    applicationInsightsConnectionString: insights.properties.ConnectionString
    applicationInsightsName: insights.name
    extraIdentityResourceId: extractionConsumerIdentity.id
    sqlServerFqdn: sqlServer.properties.fullyQualifiedDomainName
    sqlDatabaseName: database.name
    sqlIdentityClientId: extractionConsumerIdentity.properties.clientId
    tags: tags
    appSettings: {
      AZURE_STORAGE_BLOB_SERVICE_URI: documentsBlobUri
      SOURCE_DOCUMENT_TRUSTED_CONTAINER: 'fp-source-trusted'
      DocumentExtractionQueueStorage__queueServiceUri: dataQueueUri
      DocumentExtractionQueueStorage__credential: 'managedidentity'
      DocumentExtractionQueueStorage__clientId: extractionConsumerIdentity.properties.clientId
      DocumentExtractionQueueStorage__senderClientId: extractionSenderIdentity.properties.clientId
    }
  }
}

resource apiSecrets 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(vault.id, apiIdentity.id, secretsUserRoleId)
  scope: vault
  properties: { roleDefinitionId: secretsUserRoleId, principalId: apiIdentity.properties.principalId, principalType: 'ServicePrincipal' }
}
resource apiCrypto 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(vault::dataProtectionKey.id, apiIdentity.id, cryptoUserRoleId)
  scope: vault::dataProtectionKey
  properties: { roleDefinitionId: cryptoUserRoleId, principalId: apiIdentity.properties.principalId, principalType: 'ServicePrincipal' }
}
resource apiDocuments 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(documents.id, apiIdentity.id, blobContributorRoleId)
  scope: documents
  properties: { roleDefinitionId: blobContributorRoleId, principalId: apiIdentity.properties.principalId, principalType: 'ServicePrincipal' }
}
resource apiMetrics 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(insights.id, apiIdentity.id, metricsPublisherRoleId)
  scope: insights
  properties: { roleDefinitionId: metricsPublisherRoleId, principalId: apiIdentity.properties.principalId, principalType: 'ServicePrincipal' }
}
resource apiAcrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (deployCompute) {
  name: guid(apiRegistry!.id, apiIdentity.id, acrPullRoleId)
  scope: apiRegistry
  properties: { roleDefinitionId: acrPullRoleId, principalId: apiIdentity.properties.principalId, principalType: 'ServicePrincipal' }
}
resource senderQueue 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(dataStorage::queues::extractions.id, extractionSenderIdentity.id, queueSenderRoleId)
  scope: dataStorage::queues::extractions
  properties: { roleDefinitionId: queueSenderRoleId, principalId: extractionSenderIdentity.properties.principalId, principalType: 'ServicePrincipal' }
}
resource consumerQueue 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(dataStorage::queues::extractions.id, extractionConsumerIdentity.id, queueProcessorRoleId)
  scope: dataStorage::queues::extractions
  properties: { roleDefinitionId: queueProcessorRoleId, principalId: extractionConsumerIdentity.properties.principalId, principalType: 'ServicePrincipal' }
}
resource consumerTrusted 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(documents::blobService::trusted.id, extractionConsumerIdentity.id, blobReaderRoleId)
  scope: documents::blobService::trusted
  properties: { roleDefinitionId: blobReaderRoleId, principalId: extractionConsumerIdentity.properties.principalId, principalType: 'ServicePrincipal' }
}
resource generalDocuments 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (deployCompute) {
  name: guid(documents.id, generalWorkerName, blobContributorRoleId)
  scope: documents
  properties: { roleDefinitionId: blobContributorRoleId, principalId: generalWorker!.outputs.hostIdentityPrincipalId, principalType: 'ServicePrincipal' }
}

output apiAppName string = deployCompute && deployApiContainer ? apiContainer!.outputs.appName : apiAppName
output apiContainerFqdn string = deployCompute && deployApiContainer ? apiContainer!.outputs.fqdn : ''
output apiContainerRegistryName string = deployCompute ? apiRegistry!.name : ''
output apiContainerRegistryLoginServer string = deployCompute ? apiRegistry!.properties.loginServer : ''
output staticWebAppName string = deployCompute ? staticSite.name : staticWebAppName
output generalWorkerAppName string = deployCompute ? generalWorker!.outputs.appName : generalWorkerName
output extractionWorkerAppName string = deployCompute ? extractionWorker!.outputs.appName : extractionWorkerName
output keyVaultName string = vault.name
output sqlServerName string = sqlServer.name
output apiManagedIdentityClientId string = apiIdentity.properties.clientId
output generalWorkerHostIdentityClientId string = deployCompute ? generalWorker!.outputs.hostIdentityClientId : ''
output extractionWorkerHostIdentityClientId string = deployCompute ? extractionWorker!.outputs.hostIdentityClientId : ''
output extractionSenderIdentityClientId string = extractionSenderIdentity.properties.clientId
output extractionConsumerIdentityClientId string = extractionConsumerIdentity.properties.clientId
