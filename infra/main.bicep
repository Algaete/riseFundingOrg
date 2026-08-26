targetScope = 'subscription'

@description('Short environment code. Only dev is approved by this phase.')
@allowed(['dev'])
param environmentName string = 'dev'

@description('Azure region selected after checking service availability.')
param location string

@description('Globally unique lowercase suffix, 4-8 letters or numbers.')
@minLength(4)
@maxLength(8)
param uniqueSuffix string

@description('Microsoft Entra login shown as the Azure SQL administrator.')
@minLength(1)
param sqlEntraAdminLogin string

@description('Object ID of the Microsoft Entra user or group administering Azure SQL.')
param sqlEntraAdminObjectId string

@description('Azure SQL logical database name.')
param sqlDatabaseName string = 'risefunding-dev'

@description('Monthly Cost Management budget in the subscription billing currency.')
@minValue(1)
param monthlyBudgetAmount int = 75

@description('Email that receives 50%, 80% and 100% budget notifications.')
@minLength(3)
param budgetContactEmail string

@description('First UTC day of the current or next month, for example 2026-09-01T00:00:00Z.')
param budgetStartDate string

@description('Create compute resources. Set false for a storage/identity/data-plane preflight deployment.')
param deployCompute bool = true

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
    tags: commonTags
  }
}

output resourceGroupName string = environmentResourceGroup.name
output apiAppName string = environment.outputs.apiAppName
output staticWebAppName string = environment.outputs.staticWebAppName
output generalWorkerAppName string = environment.outputs.generalWorkerAppName
output extractionWorkerAppName string = environment.outputs.extractionWorkerAppName
output keyVaultName string = environment.outputs.keyVaultName
output sqlServerName string = environment.outputs.sqlServerName
output sqlDatabaseName string = sqlDatabaseName
output apiManagedIdentityClientId string = environment.outputs.apiManagedIdentityClientId
output generalWorkerHostIdentityClientId string = environment.outputs.generalWorkerHostIdentityClientId
output extractionWorkerHostIdentityClientId string = environment.outputs.extractionWorkerHostIdentityClientId
output extractionSenderIdentityClientId string = environment.outputs.extractionSenderIdentityClientId
output extractionConsumerIdentityClientId string = environment.outputs.extractionConsumerIdentityClientId
