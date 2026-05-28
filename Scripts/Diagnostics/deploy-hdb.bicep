@description('Random suffix used to keep resource names unique per deployment.')
param nameSuffix string = uniqueString(newGuid())

@description('Location for all resources.')
param location string = resourceGroup().location

@description('Unique name for the HorizonDB cluster.')
param clusterName string = 'horizondb-lab-${resourceGroup().location}-${nameSuffix}'

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

output clusterName string = horizonDbCluster.name
output clusterFqdn string = horizonDbCluster.properties.?fullyQualifiedDomainName ?? '${clusterName}.${location}.horizondb.azure.com'
output clusterFqdnReadOnly string = horizonDbCluster.properties.?readonlyEndpoint ?? '${clusterName}.ro.${location}.horizondb.azure.com'
output adminLogin string = administratorLogin
output adminPassword string = administratorLoginPassword
