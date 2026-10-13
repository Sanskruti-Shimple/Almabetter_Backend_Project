targetScope = 'resourceGroup'

@description('Azure region for the resources.')
param location string = 'centralus'

@description('Short environment label used to derive globally unique resource names.')
param environmentName string = 'dev'

@description('App Service plan SKU. F1 is intended for a low-traffic demo.')
@allowed([
  'F1'
])
param appServiceSku string = 'F1'

@description('Object ID of the identity running this deployment; used to write the initial Key Vault secret.')
param deploymentPrincipalId string = ''

@description('Principal type of the deployment identity.')
@allowed([
  'User'
  'ServicePrincipal'
])
param deploymentPrincipalType string = 'User'

var resourceToken = uniqueString(subscription().id, resourceGroup().id, location, environmentName)
var keyVaultSecretsOfficerRoleId = 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'
var mongoDatabaseName = 'azdb${resourceToken}'

resource appIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'azid${resourceToken}'
  location: location
}

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'azla${resourceToken}'
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'azai${resourceToken}'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Flow_Type: 'Bluefield'
    Request_Source: 'rest'
    WorkspaceResourceId: logAnalytics.id
    IngestionMode: 'LogAnalytics'
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: 'azkv${resourceToken}'
  location: location
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
  }
}

resource cosmos 'Microsoft.DocumentDB/databaseAccounts@2024-05-15' = {
  name: 'azcos${resourceToken}'
  location: location
  kind: 'MongoDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    apiProperties: {
      serverVersion: '4.2'
    }
    capabilities: [
      {
        name: 'EnableMongo'
      }
      {
        name: 'EnableServerless'
      }
    ]
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    ipRules: [
      {
        ipAddressOrRange: '0.0.0.0'
      }
    ]
    isVirtualNetworkFilterEnabled: false
    publicNetworkAccess: 'Enabled'
  }
}

resource mongoDatabase 'Microsoft.DocumentDB/databaseAccounts/mongodbDatabases@2021-04-15' = {
  parent: cosmos
  name: mongoDatabaseName
  properties: {
    resource: {
      id: mongoDatabaseName
    }
  }
}

resource appServicePlan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: 'azasp${resourceToken}'
  location: location
  kind: 'linux'
  sku: {
    name: appServiceSku
    tier: 'Free'
    size: appServiceSku
    family: 'F'
    capacity: 1
  }
  properties: {
    reserved: true
  }
}

resource webApp 'Microsoft.Web/sites@2024-04-01' = {
  name: 'azapp${resourceToken}'
  location: location
  kind: 'app,linux'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${appIdentity.id}': {}
    }
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    keyVaultReferenceIdentity: appIdentity.id
    siteConfig: {
      linuxFxVersion: 'NODE|22-lts'
      appCommandLine: 'npm start'
      alwaysOn: false
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      http20Enabled: true
      cors: {
        allowedOrigins: [
          '*'
        ]
        supportCredentials: false
      }
      appSettings: [
        {
          name: 'PORT'
          value: '8080'
        }
        {
          name: 'NODE_ENV'
          value: 'production'
        }
        {
          name: 'SCM_DO_BUILD_DURING_DEPLOYMENT'
          value: 'true'
        }
        {
          name: 'MONGODB_URI'
          value: '@Microsoft.KeyVault(SecretUri=${keyVault.properties.vaultUri}secrets/mongodb-uri)'
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsights.properties.ConnectionString
        }
      ]
    }
  }
  dependsOn: [
    keyVaultSecretsOfficerForApp
  ]
}

resource keyVaultSecretsOfficerForApp 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, appIdentity.id, keyVaultSecretsOfficerRoleId)
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsOfficerRoleId)
    principalId: appIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource keyVaultSecretsOfficerForDeployer 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(deploymentPrincipalId)) {
  name: guid(keyVault.id, deploymentPrincipalId, keyVaultSecretsOfficerRoleId)
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsOfficerRoleId)
    principalId: deploymentPrincipalId
    principalType: deploymentPrincipalType
  }
}

resource appDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'azds${resourceToken}'
  scope: webApp
  properties: {
    workspaceId: logAnalytics.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

output appName string = webApp.name
output appHostName string = webApp.properties.defaultHostName
output cosmosAccountName string = cosmos.name
output keyVaultName string = keyVault.name
output mongoDatabaseName string = mongoDatabase.name
output appInsightsName string = appInsights.name
