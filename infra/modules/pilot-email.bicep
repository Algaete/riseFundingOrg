// Optional, isolated pilot email resources. No changes to SQL, capacity or payments.
// Default-off deployment parameter prevents accidental activation.
param enabled bool = false
param apiIdentityName string = 'id-rf-dev-ag26rf01-api'
param emailServiceName string = 'email-rf-dev-ag26rf01'
param communicationServiceName string = 'acs-rf-dev-ag26rf01'
param dataLocation string = 'United States'
resource apiIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = { name: apiIdentityName }
resource email 'Microsoft.Communication/emailServices@2023-03-31' = if (enabled) {
  name: emailServiceName
  location: 'global'
  tags: { project: 'FundingPlatform', purpose: 'pilot-account-verification' }
  properties: { dataLocation: dataLocation }
}
resource domain 'Microsoft.Communication/emailServices/domains@2023-03-31' = if (enabled) {
  parent: email
  name: 'AzureManagedDomain'
  location: 'global'
  properties: { domainManagement: 'AzureManaged' }
}
resource communication 'Microsoft.Communication/communicationServices@2023-03-31' = if (enabled) {
  name: communicationServiceName
  location: 'global'
  tags: { project: 'FundingPlatform', purpose: 'pilot-account-verification' }
  properties: { dataLocation: dataLocation, linkedDomains: [domain.id] }
}
resource emailRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' = if (enabled) {
  name: guid(resourceGroup().id, 'FundingPlatform-pilot-email')
  properties: {
    roleName: 'FundingPlatform pilot email access'
    description: 'ACS SDK email access for the API identity; assigned only on the pilot communication resource.'
    type: 'CustomRole'
    permissions: [{ actions: ['Microsoft.Communication/CommunicationServices/Read', 'Microsoft.Communication/CommunicationServices/Write'], notActions: [], dataActions: [], notDataActions: [] }]
    assignableScopes: [resourceGroup().id]
  }
}
resource emailAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enabled) {
  scope: communication
  name: guid(communication.id, apiIdentity.id, emailRole.id)
  properties: { principalId: apiIdentity.properties.principalId, principalType: 'ServicePrincipal', roleDefinitionId: emailRole.id }
}
output endpoint string = enabled ? 'https://${communication!.properties.hostName}' : ''
output mailFromDomain string = enabled ? domain!.properties.mailFromSenderDomain : ''
