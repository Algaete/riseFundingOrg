targetScope = 'subscription'

@description('Short environment code. Only dev is approved by this phase.')
@allowed(['dev'])
param environmentName string = 'dev'

@description('Azure region selected after checking service availability.')
param location string

@description('Globally unique suffix of exactly eight lowercase ASCII letters or digits: [a-z0-9]{8}.')
@minLength(8)
@maxLength(8)
param uniqueSuffix string

@description('Microsoft Entra login shown as the Azure SQL administrator.')
@secure()
@minLength(1)
param sqlEntraAdminLogin string

@description('Object ID of the Microsoft Entra group administering Azure SQL.')
@secure()
param sqlEntraAdminObjectId string

@description('Azure SQL logical database name.')
param sqlDatabaseName string = 'risefunding-dev'

@description('Monthly Cost Management budget in the subscription billing currency.')
@minValue(1)
param monthlyBudgetAmount int = 75

@description('Email that receives 50%, 80% and 100% budget notifications.')
@secure()
@minLength(3)
param budgetContactEmail string

@description('First UTC day of the current or next month, for example 2026-09-01T00:00:00Z.')
param budgetStartDate string

@description('Create compute resources. False omits them from a new incremental deployment; it does not pause or delete existing resources.')
param deployCompute bool = true

@description('Create the API Container App. The first apply keeps this false until its private image exists.')
param deployApiContainer bool = false

@description('API repository plus tag/digest already present in the environment Azure Container Registry.')
@minLength(7)
@maxLength(200)
param apiContainerImageReference string = 'rise-funding-api:preview'

@description('Minimum API replicas in dev. Defaults to scale-to-zero; select one only for a warm smoke window.')
@minValue(0)
@maxValue(1)
param apiMinReplicas int = 0

var prefix = 'rf-${environmentName}'
var resourceGroupName = 'rg-${prefix}-${uniqueSuffix}'
var commonTags = {
  application: 'rise-funding-org'
  environment: environmentName
  managedBy: 'bicep'
  dataClassification: 'confidential'
  monthlyBudgetAmount: string(monthlyBudgetAmount)
}

resource environmentResourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: commonTags
}

resource devBudget 'Microsoft.Consumption/budgets@2023-11-01' = {
  name: '${resourceGroupName}-monthly'
  properties: {
    amount: monthlyBudgetAmount
    category: 'Cost'
    timeGrain: 'Monthly'
    timePeriod: { startDate: budgetStartDate }
    filter: {
      dimensions: { name: 'ResourceGroupName', operator: 'In', values: [ resourceGroupName ] }
    }
    notifications: {
      Actual50: { enabled: true, operator: 'GreaterThanOrEqualTo', threshold: 50, thresholdType: 'Actual', contactEmails: [ budgetContactEmail ] }
      Actual80: { enabled: true, operator: 'GreaterThanOrEqualTo', threshold: 80, thresholdType: 'Actual', contactEmails: [ budgetContactEmail ] }
      Forecast100: { enabled: true, operator: 'GreaterThanOrEqualTo', threshold: 100, thresholdType: 'Forecasted', contactEmails: [ budgetContactEmail ] }
    }
  }
}

module environment './modules/environment.bicep' = {
  name: 'rise-funding-${environmentName}'
  scope: environmentResourceGroup
  params: {
    environmentName: environmentName
    location: location
    uniqueSuffix: uniqueSuffix
    sqlEntraAdminLogin: sqlEntraAdminLogin
    sqlEntraAdminObjectId: sqlEntraAdminObjectId
    sqlDatabaseName: sqlDatabaseName
    deployCompute: deployCompute
    deployApiContainer: deployApiContainer
    apiContainerImageReference: apiContainerImageReference
    apiMinReplicas: apiMinReplicas
    tags: commonTags
  }
}

output resourceGroupName string = environmentResourceGroup.name
output apiAppName string = environment.outputs.apiAppName
output apiContainerFqdn string = environment.outputs.apiContainerFqdn
output apiContainerRegistryName string = environment.outputs.apiContainerRegistryName
output apiContainerRegistryLoginServer string = environment.outputs.apiContainerRegistryLoginServer
output staticWebAppName string = environment.outputs.staticWebAppName
output generalWorkerAppName string = environment.outputs.generalWorkerAppName
output extractionWorkerAppName string = environment.outputs.extractionWorkerAppName
output keyVaultName string = environment.outputs.keyVaultName
output sqlServerName string = environment.outputs.sqlServerName
output sqlDatabaseName string = sqlDatabaseName
output apiManagedIdentityClientId string = environment.outputs.apiManagedIdentityClientId
output apiManagedIdentityPrincipalId string = environment.outputs.apiManagedIdentityPrincipalId
output generalWorkerHostIdentityClientId string = environment.outputs.generalWorkerHostIdentityClientId
output generalWorkerHostIdentityPrincipalId string = environment.outputs.generalWorkerHostIdentityPrincipalId
output extractionWorkerHostIdentityClientId string = environment.outputs.extractionWorkerHostIdentityClientId
output extractionWorkerHostIdentityPrincipalId string = environment.outputs.extractionWorkerHostIdentityPrincipalId
output extractionSenderIdentityClientId string = environment.outputs.extractionSenderIdentityClientId
output extractionSenderIdentityPrincipalId string = environment.outputs.extractionSenderIdentityPrincipalId
output extractionConsumerIdentityClientId string = environment.outputs.extractionConsumerIdentityClientId
output extractionConsumerIdentityPrincipalId string = environment.outputs.extractionConsumerIdentityPrincipalId
