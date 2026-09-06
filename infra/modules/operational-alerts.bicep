@description('Deployment region for regional Azure Monitor resources.')
param location string

@description('Short environment code used in deterministic resource names.')
param environmentName string

@description('Environment resource prefix, for example rf-dev-abcdefgh.')
param resourcePrefix string

@description('Public HTTPS origin of the API, without a trailing slash.')
@minLength(8)
param apiBaseUrl string

@description('Resource ID of the workspace-based Application Insights component.')
param applicationInsightsResourceId string

@description('Resource ID of the Log Analytics workspace backing Application Insights.')
param logAnalyticsWorkspaceResourceId string

@description('Existing budget contact reused only as the operational action-group receiver.')
@secure()
@minLength(3)
param contactEmail string

param tags object

var actionGroupName = 'ag-${resourcePrefix}-operations'
var actionGroupShortName = take('rf-${environmentName}-ops', 12)
var healthWebTestName = 'webtest-${resourcePrefix}-api-health'
var availabilityAlertName = 'alert-${resourcePrefix}-api-health'
var serverErrorAlertName = 'alert-${resourcePrefix}-api-5xx'
var exceptionAlertName = 'alert-${resourcePrefix}-api-exceptions'

// This entire module is gated by deployOperationalAlerts in environment.bicep. Keeping the
// receiver inside the module means neither the action group nor active probes exist until a
// reviewed deployment explicitly opts in.
resource operationsActionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: actionGroupName
  location: 'global'
  tags: tags
  properties: {
    enabled: true
    groupShortName: actionGroupShortName
    emailReceivers: [
      {
        name: 'budget-contact'
        emailAddress: contactEmail
        useCommonAlertSchema: true
      }
    ]
  }
}

// One location and a fifteen-minute cadence intentionally bound dev cost. Retry suppresses most
// transient network failures while keeping the maximum probe volume finite during an outage.
resource apiHealthWebTest 'Microsoft.Insights/webTests@2022-06-15' = {
  name: healthWebTestName
  location: location
  kind: 'standard'
  tags: union(tags, {
    'hidden-link:${applicationInsightsResourceId}': 'Resource'
  })
  properties: {
    Description: 'HTTPS GET /health for the Rise Funding dev API.'
    Enabled: true
    Frequency: 900
    Kind: 'standard'
    Locations: [
      {
        Id: 'us-va-ash-azr'
      }
    ]
    Name: healthWebTestName
    Request: {
      FollowRedirects: false
      HttpVerb: 'GET'
      ParseDependentRequests: false
      RequestUrl: '${apiBaseUrl}/health'
    }
    RetryEnabled: true
    SyntheticMonitorId: healthWebTestName
    Timeout: 30
    ValidationRules: {
      ExpectedHttpStatusCode: 200
      IgnoreHttpStatusCode: false
      SSLCheck: true
      SSLCertRemainingLifetimeCheck: 7
    }
  }
}

resource apiAvailabilityAlert 'Microsoft.Insights/metricAlerts@2026-01-01' = {
  name: availabilityAlertName
  location: 'global'
  tags: union(tags, {
    'hidden-link:${applicationInsightsResourceId}': 'Resource'
    'hidden-link:${apiHealthWebTest.id}': 'Resource'
  })
  properties: {
    actions: [
      {
        actionGroupId: operationsActionGroup.id
      }
    ]
    autoMitigate: true
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.WebtestLocationAvailabilityCriteria'
      componentId: applicationInsightsResourceId
      failedLocationCount: 1
      webTestId: apiHealthWebTest.id
    }
    description: 'Rise Funding dev API /health failed from its single cost-bounded probe location.'
    enabled: true
    evaluationFrequency: 'PT5M'
    scopes: [
      apiHealthWebTest.id
      applicationInsightsResourceId
    ]
    severity: 1
    windowSize: 'PT15M'
  }
}

resource apiServerErrorAlert 'Microsoft.Insights/scheduledQueryRules@2023-12-01' = {
  name: serverErrorAlertName
  location: location
  kind: 'LogAlert'
  tags: tags
  properties: {
    actions: {
      actionGroups: [
        operationsActionGroup.id
      ]
    }
    autoMitigate: true
    checkWorkspaceAlertsStorageConfigured: false
    criteria: {
      allOf: [
        {
          failingPeriods: {
            minFailingPeriodsToAlert: 1
            numberOfEvaluationPeriods: 1
          }
          metricMeasureColumn: 'EventCount'
          operator: 'GreaterThan'
          query: '''
            AppRequests
            | where AppRoleName == 'FundingPlatform.Api'
            | where ResultCode matches regex '^5[0-9][0-9]$'
            | summarize EventCount = sum(ItemCount)
          '''
          threshold: 0
          timeAggregation: 'Total'
        }
      ]
    }
    description: 'At least one sampled API 5xx was observed in the five-minute window.'
    displayName: 'Rise Funding dev API 5xx'
    enabled: true
    evaluationFrequency: 'PT5M'
    muteActionsDuration: 'PT30M'
    scopes: [
      logAnalyticsWorkspaceResourceId
    ]
    severity: 2
    skipQueryValidation: false
    windowSize: 'PT5M'
  }
}

resource apiExceptionAlert 'Microsoft.Insights/scheduledQueryRules@2023-12-01' = {
  name: exceptionAlertName
  location: location
  kind: 'LogAlert'
  tags: tags
  properties: {
    actions: {
      actionGroups: [
        operationsActionGroup.id
      ]
    }
    autoMitigate: true
    checkWorkspaceAlertsStorageConfigured: false
    criteria: {
      allOf: [
        {
          failingPeriods: {
            minFailingPeriodsToAlert: 1
            numberOfEvaluationPeriods: 1
          }
          metricMeasureColumn: 'EventCount'
          operator: 'GreaterThan'
          query: '''
            AppExceptions
            | where AppRoleName == 'FundingPlatform.Api'
            | summarize EventCount = sum(ItemCount)
          '''
          threshold: 0
          timeAggregation: 'Total'
        }
      ]
    }
    description: 'At least one sampled API exception was observed in the five-minute window.'
    displayName: 'Rise Funding dev API exceptions'
    enabled: true
    evaluationFrequency: 'PT5M'
    muteActionsDuration: 'PT30M'
    scopes: [
      logAnalyticsWorkspaceResourceId
    ]
    severity: 2
    skipQueryValidation: false
    windowSize: 'PT5M'
  }
}
