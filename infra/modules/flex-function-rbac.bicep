@description('Object ID of the Function host user-assigned managed identity.')
param hostIdentityPrincipalId string

param hostStorageName string
param applicationInsightsName string

var blobOwnerRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b')
var queueContributorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '974c5e8b-45b9-4653-ba55-5f855dd0fb88')
var tableContributorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3')
var metricsPublisherRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '3913510d-42f4-4e42-8a64-420c390055eb')

resource hostStorage 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: hostStorageName
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: applicationInsightsName
}

resource hostBlobOwner 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(hostStorage.id, hostIdentityPrincipalId, blobOwnerRoleId)
  scope: hostStorage
  properties: {
    roleDefinitionId: blobOwnerRoleId
    principalId: hostIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource hostQueueContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(hostStorage.id, hostIdentityPrincipalId, queueContributorRoleId)
  scope: hostStorage
  properties: {
    roleDefinitionId: queueContributorRoleId
    principalId: hostIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource hostTableContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(hostStorage.id, hostIdentityPrincipalId, tableContributorRoleId)
  scope: hostStorage
  properties: {
    roleDefinitionId: tableContributorRoleId
    principalId: hostIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource hostMetricsPublisher 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(applicationInsights.id, hostIdentityPrincipalId, metricsPublisherRoleId)
  scope: applicationInsights
  properties: {
    roleDefinitionId: metricsPublisherRoleId
    principalId: hostIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}
