@description('Object ID of the API user-assigned managed identity.')
param apiIdentityPrincipalId string

@description('Object ID of the extraction queue sender user-assigned managed identity.')
param extractionSenderIdentityPrincipalId string

@description('Object ID of the extraction queue consumer user-assigned managed identity.')
param extractionConsumerIdentityPrincipalId string

@description('Object ID of the general worker host identity. Required when compute is deployed.')
param generalWorkerHostIdentityPrincipalId string = ''

param keyVaultName string
param dataProtectionKeyName string
param documentStorageName string
param dataStorageName string
param applicationInsightsName string
param containerRegistryName string
param deployCompute bool

var blobContributorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
var blobReaderRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1')
var queueSenderRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'c6a89b2d-59bc-44d0-9896-0f6e12d7b80a')
var queueProcessorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '8a0f0c08-91a1-4084-bc3d-661d67233fed')
var secretsUserRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
var cryptoUserRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '12338af0-0e69-4776-bea7-57ae8d297424')
var metricsPublisherRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '3913510d-42f4-4e42-8a64-420c390055eb')
var acrPullRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')

resource vault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource dataProtectionKey 'Microsoft.KeyVault/vaults/keys@2023-07-01' existing = {
  parent: vault
  name: dataProtectionKeyName
}

resource documents 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: documentStorageName
}

resource documentsBlobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' existing = {
  parent: documents
  name: 'default'
}

resource trustedDocuments 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' existing = {
  parent: documentsBlobService
  name: 'fp-source-trusted'
}

resource dataStorage 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: dataStorageName
}

resource dataQueueService 'Microsoft.Storage/storageAccounts/queueServices@2023-05-01' existing = {
  parent: dataStorage
  name: 'default'
}

resource extractionsQueue 'Microsoft.Storage/storageAccounts/queueServices/queues@2023-05-01' existing = {
  parent: dataQueueService
  name: 'document-extractions'
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: applicationInsightsName
}

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2025-11-01' existing = {
  name: containerRegistryName
}

resource apiSecrets 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(vault.id, apiIdentityPrincipalId, secretsUserRoleId)
  scope: vault
  properties: {
    roleDefinitionId: secretsUserRoleId
    principalId: apiIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource apiCrypto 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(dataProtectionKey.id, apiIdentityPrincipalId, cryptoUserRoleId)
  scope: dataProtectionKey
  properties: {
    roleDefinitionId: cryptoUserRoleId
    principalId: apiIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource apiDocuments 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(documents.id, apiIdentityPrincipalId, blobContributorRoleId)
  scope: documents
  properties: {
    roleDefinitionId: blobContributorRoleId
    principalId: apiIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource apiMetrics 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(applicationInsights.id, apiIdentityPrincipalId, metricsPublisherRoleId)
  scope: applicationInsights
  properties: {
    roleDefinitionId: metricsPublisherRoleId
    principalId: apiIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource apiAcrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (deployCompute) {
  name: guid(containerRegistry.id, apiIdentityPrincipalId, acrPullRoleId)
  scope: containerRegistry
  properties: {
    roleDefinitionId: acrPullRoleId
    principalId: apiIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource senderQueue 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(extractionsQueue.id, extractionSenderIdentityPrincipalId, queueSenderRoleId)
  scope: extractionsQueue
  properties: {
    roleDefinitionId: queueSenderRoleId
    principalId: extractionSenderIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource consumerQueue 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(extractionsQueue.id, extractionConsumerIdentityPrincipalId, queueProcessorRoleId)
  scope: extractionsQueue
  properties: {
    roleDefinitionId: queueProcessorRoleId
    principalId: extractionConsumerIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource consumerTrusted 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(trustedDocuments.id, extractionConsumerIdentityPrincipalId, blobReaderRoleId)
  scope: trustedDocuments
  properties: {
    roleDefinitionId: blobReaderRoleId
    principalId: extractionConsumerIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource generalDocuments 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (deployCompute) {
  name: guid(documents.id, generalWorkerHostIdentityPrincipalId, blobContributorRoleId)
  scope: documents
  properties: {
    roleDefinitionId: blobContributorRoleId
    principalId: generalWorkerHostIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}
