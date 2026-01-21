@description('Location for all resources.')
param location string = resourceGroup().location

@description('The name of the Azure Container Registry.')
param acrName string

@description('The name of the container group to update.')
param containerGroupName string

@description('The name of the container within the group.')
param containerName string

@description('The name of the user-assigned managed identity to create.')
param userAssignedIdentityName string

@description('The full name of the private image to deploy (e.g., myacr.azurecr.io/myimage:latest).')
param privateImage string

@description('Port to open on the container and the public IP address.')
param port int = 5106

@description('The number of CPU cores to allocate to the container.')
param cpuCores int = 1

@description('The amount of memory to allocate to the container in gigabytes.')
param memoryInGb int = 2

@description('The behavior of Azure runtime if container has stopped.')
@allowed([
  'Always'
  'Never'
  'OnFailure'
])
param restartPolicy string = 'Always'

// Reference the existing Azure Container Registry
resource acr 'Microsoft.ContainerRegistry/registries@2021-09-01' existing = {
  name: acrName
}

// Create the user-assigned managed identity
resource userAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: userAssignedIdentityName
  location: location
}

// Assign the 'AcrPull' role to the user-assigned identity for the ACR's scope
resource acrPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  // Use a deterministic GUID for the role assignment name
  name: guid(userAssignedIdentity.id, acr.id, 'AcrPull')
  scope: acr
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d') // Built-in AcrPull role definition ID
    principalId: userAssignedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource containerGroup 'Microsoft.ContainerInstance/containerGroups@2021-09-01' = {
  name: containerGroupName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentity.id}': {}
    }
  }
  properties: {
    containers: [
      {
        name: containerName
        properties: {
          image: privateImage
          ports: [
            {
              port: port
              protocol: 'TCP'
            }
            {
              port: 80
              protocol: 'TCP'
            }
          ]
          resources: {
            requests: {
              cpu: cpuCores
              memoryInGB: memoryInGb
            }
          }
          environmentVariables: [
            {
              name: 'ASPNETCORE_ENVIRONMENT'
              value: 'Docker'
            }
            {
              name: 'UseOnlyInMemoryDatabase'
              value: 'true'
            }
            {
              name: 'ASPNETCORE_HTTP_PORTS'
              value: '80'
            }
          ]
        }
      }
    ]
    osType: 'Linux'
    restartPolicy: restartPolicy
    ipAddress: {
      type: 'Public'
      ports: [
        {
          port: port
          protocol: 'TCP'
        }
        {
          port: 80
          protocol: 'TCP'
        }
      ]
    }
    imageRegistryCredentials: [
      {
        server: acr.properties.loginServer
        identity: userAssignedIdentity.id // Specify the full resource ID of the user-assigned identity
      }
    ]
  }
  dependsOn: [
    acrPullRoleAssignment
  ]
}

output containerIPv4Address string = containerGroup.properties.ipAddress.ip