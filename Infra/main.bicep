targetScope = 'resourceGroup'

@description('Random suffix used to keep resource names unique per deployment.')
param nameSuffix string = uniqueString(newGuid())

@description('Location for all resources.')
param location string = resourceGroup().location

@description('Unique name for the HorizonDB cluster.')
param clusterName string = 'horizondb-lab-${resourceGroup().location}-${nameSuffix}'

@description('Unique name for the Azure OpenAI service.')
param azureOpenAIServiceName string = 'openai-lab-${resourceGroup().location}-${nameSuffix}'

@description('Restore the service instead of creating a new instance.')
param restore bool = false

@description('The version of PostgreSQL to use.')
param postgresVersion string = '17'

@description('Number of vCores per node.')
param vCores int = 2

@description('Number of replicas.')
param replicaCount int = 2

@secure()
@description('Auto-generated admin password.')
param administratorLoginPassword string = 'Z${uniqueString(newGuid())}!'

module base './deploy.bicep' = {
  name: 'build2026BaseInfra'
  params: {
    nameSuffix: nameSuffix
    location: location
    clusterName: clusterName
    azureOpenAIServiceName: azureOpenAIServiceName
    restore: restore
    postgresVersion: postgresVersion
    vCores: vCores
    replicaCount: replicaCount
    administratorLoginPassword: administratorLoginPassword
  }
}

// Canonical outputs for scripts and diagnostics
output clusterName string = base.outputs.clusterName
output clusterFqdn string = base.outputs.clusterFqdn
output clusterFqdnReadOnly string = base.outputs.clusterFqdnReadOnly
output adminLogin string = base.outputs.adminLogin
output adminPassword string = base.outputs.adminPassword
output azureOpenAIServiceName string = base.outputs.azureOpenAIServiceName
output azureOpenAIEndpoint string = base.outputs.azureOpenAIEndpoint
output azureOpenAIEmbeddingDeploymentName string = base.outputs.azureOpenAIEmbeddingDeploymentName
output azureOpenAIChatDeploymentName string = base.outputs.azureOpenAIChatDeploymentName

// Env-style outputs for azd hooks
output AZURE_PG_HOST string = base.outputs.clusterFqdn
output AZURE_PG_NAME string = 'postgres'
output AZURE_PG_USER string = base.outputs.adminLogin
output AZURE_PG_PASSWORD string = base.outputs.adminPassword
output AZURE_PG_PORT string = '5432'
output AZURE_PG_SSLMODE string = 'require'

output AZURE_OPENAI_SERVICE_NAME string = base.outputs.azureOpenAIServiceName
output AZURE_OPENAI_ENDPOINT string = base.outputs.azureOpenAIEndpoint
output AZURE_OPENAI_DEPLOYMENT string = base.outputs.azureOpenAIChatDeploymentName
output AZURE_EMBED_DEPLOYMENT string = base.outputs.azureOpenAIEmbeddingDeploymentName
output AZURE_API_VERSION string = '2025-03-01-preview'
