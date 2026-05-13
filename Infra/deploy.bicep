@description('Location for all resources.')
param location string = resourceGroup().location

@description('Unique name for the HorizonDB cluster.')
param clusterName string = 'horizondb-learn-${uniqueString(resourceGroup().id)}'

@description('Unique name for the Azure OpenAI service.')
param azureOpenAIServiceName string = 'oai-learn-${resourceGroup().location}-${uniqueString(resourceGroup().id)}'

@description('Restore the service instead of creating a new instance. This is useful if you previously soft-deleted the service and want to restore it. If you are restoring a service, set this to true. Otherwise, leave this as false.')
param restore bool = false

@description('The version of PostgreSQL to use.')
param postgresVersion string = '17'

@description('Number of vCores per node.')
param vCores int = 2

@description('Number of replicas.')
param replicaCount int = 2

@description('Admin username for the cluster.')
var administratorLogin = 'labUser'

@secure()
@description('Auto-generated admin password.')
param administratorLoginPassword string = 'Z${uniqueString(newGuid())}!'





@description('Creates a HorizonDB Cluster.')
resource horizonDbCluster 'Microsoft.HorizonDb/clusters@2026-01-20-preview' = {
  name: clusterName
  location: location
  properties: {
    administratorLogin: administratorLogin
    administratorLoginPassword: administratorLoginPassword
    createMode: 'Create'
    vCores: vCores
    replicaCount: replicaCount
    version: postgresVersion
  }
}



@description('Creates an Azure OpenAI service.')
resource azureOpenAIService 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: azureOpenAIServiceName
  location: location
  kind: 'OpenAI'
  sku: {
    name: 'S0'
    tier: 'Standard'
  }
  properties: {
    customSubDomainName: azureOpenAIServiceName
    publicNetworkAccess: 'Enabled'
    restore: restore
  } 
}

@description('Creates an embedding deployment for the Azure OpenAI service.')
resource azureOpenAIEmbeddingDeployment 'Microsoft.CognitiveServices/accounts/deployments@2023-05-01' = {
  name: 'text-embedding-3-small'
  parent: azureOpenAIService
  sku: {
    name: 'GlobalStandard'
    capacity: 1000
  }
  properties: {
    model: {
      // Make the quota higher for the deployment
      name: 'text-embedding-3-small'
      version: '1'
      format: 'OpenAI'
    }
  }
}

@description('Creates a GPT-4o chat deployment for the Azure OpenAI service.')
resource azureOpenAIChatDeployment 'Microsoft.CognitiveServices/accounts/deployments@2023-05-01' = {
  name: 'gpt-4o'
  parent: azureOpenAIService
  dependsOn: [
    azureOpenAIEmbeddingDeployment
  ]
  sku: {
    name: 'GlobalStandard'
    capacity: 1000
  }
  properties: {
    model: {
      name: 'gpt-4o'
      version: '2024-11-20'
      format: 'OpenAI'
    }    
  }
}




output clusterName string = horizonDbCluster.name
output clusterFqdn string = horizonDbCluster.properties.?fullyQualifiedDomainName ?? '${clusterName}.${location}.horizondb.azure.com'
output adminLogin string = administratorLogin
output adminPassword string = administratorLoginPassword

output azureOpenAIServiceName string = azureOpenAIService.name
output azureOpenAIEndpoint string = azureOpenAIService.properties.endpoint
output azureOpenAIEmbeddingDeploymentName string = azureOpenAIEmbeddingDeployment.name
output azureOpenAIChatDeploymentName string = azureOpenAIChatDeployment.name
