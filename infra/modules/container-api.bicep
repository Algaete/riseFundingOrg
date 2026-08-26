param appName string
param location string
param managedEnvironmentId string
param registryServer string
param registryIdentityResourceId string
param runtimeIdentityResourceId string
param imageReference string

@minValue(0)
@maxValue(1)
param minReplicas int

param appSettings object
param tags object

var targetPort = 8080

resource app 'Microsoft.App/containerApps@2025-01-01' = {
  name: appName
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${runtimeIdentityResourceId}': {}
    }
  }
  properties: {
    managedEnvironmentId: managedEnvironmentId
    configuration: {
      activeRevisionsMode: 'Single'
      maxInactiveRevisions: 2
      ingress: {
        allowInsecure: false
        external: true
        targetPort: targetPort
        transport: 'auto'
        traffic: [
          {
            latestRevision: true
            weight: 100
          }
        ]
      }
      registries: [
        {
          identity: registryIdentityResourceId
          server: registryServer
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'api'
          image: '${registryServer}/${imageReference}'
          env: [for setting in items(appSettings): {
            name: setting.key
            value: string(setting.value)
          }]
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          probes: [
            {
              type: 'Startup'
              httpGet: {
                path: '/health'
                port: targetPort
                scheme: 'HTTP'
              }
              initialDelaySeconds: 2
              periodSeconds: 5
              timeoutSeconds: 3
              failureThreshold: 30
              successThreshold: 1
            }
            {
              type: 'Liveness'
              httpGet: {
                path: '/health'
                port: targetPort
                scheme: 'HTTP'
              }
              initialDelaySeconds: 5
              periodSeconds: 30
              timeoutSeconds: 3
              failureThreshold: 3
              successThreshold: 1
            }
            {
              type: 'Readiness'
              httpGet: {
                path: '/health'
                port: targetPort
                scheme: 'HTTP'
              }
              initialDelaySeconds: 3
              periodSeconds: 15
              timeoutSeconds: 3
              failureThreshold: 3
              successThreshold: 1
            }
          ]
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: 1
        rules: [
          {
            name: 'http-requests'
            http: {
              metadata: {
                concurrentRequests: '20'
              }
            }
          }
        ]
      }
    }
  }
}

output appName string = app.name
output fqdn string = app.properties.configuration.ingress.fqdn
