param parLocation string
param parInitials string
param parTenantId string
param parEntraGroupId string
param parAppgwName string
param parAcrName string

var varAcrPullRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')

resource resVnet 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: 'aks-${parInitials}-vnet'
  location: parLocation
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/12'
      ]
    }
    subnets: [
      {
        name: 'aksCluster'
        properties: {
          addressPrefix: '10.1.0.0/16'
          natGateway: {
            id: resNatGw.id
          }
        }
      }
      {
        name: 'appGw'
        properties: {
          addressPrefix: '10.2.0.0/16'
        }
      }
      {
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: '10.3.0.0/26'
        }
      }
    ]
  }
}

resource resAcr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: parAcrName
  location: parLocation
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: true
  }
}
resource resAksCluster 'Microsoft.ContainerService/managedClusters@2023-09-01' = {
  name: 'aks-${parInitials}-akscluster'
  location: parLocation
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    kubernetesVersion: '1.26.6'
    dnsPrefix: 'aks-${parInitials}-akscluster-dns'
    enableRBAC: true
    agentPoolProfiles: [
      {
        name: 'system'
        count: 1
        vmSize: 'Standard_DS2_v2'
        maxPods: 30
        maxCount: 20
        minCount: 1
        enableAutoScaling: true
        osType: 'Linux'
        osSKU: 'CBLMariner'
        mode: 'System'
        vnetSubnetID: resVnet.properties.subnets[0].id
      }
      {
        name: 'application'
        count: 1
        vmSize: 'Standard_DS2_v2'
        maxPods: 30
        maxCount: 20
        minCount: 1
        enableAutoScaling: true
        osType: 'Linux'
        osSKU: 'CBLMariner'
        mode: 'System'
        vnetSubnetID: resVnet.properties.subnets[0].id
      }
    ]
    aadProfile: {
      managed: true
      adminGroupObjectIDs: [
        parEntraGroupId
      ]
      tenantID: parTenantId
    }
    disableLocalAccounts: true
    addonProfiles: {
      ingressApplicationGateway: {
        enabled: true
        config: {
          applicationGatewayId: resAppgw.id
        }
      }
      omsagent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: resLaw.id
        }
      }
    }
  }
}

resource resAcrPullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, resAcr.id, varAcrPullRoleDefinitionId)
  scope: resAcr
  properties: {
    principalId: resAksCluster.properties.identityProfile.kubeletidentity.objectId
    roleDefinitionId: varAcrPullRoleDefinitionId
    principalType: 'ServicePrincipal'
  }
}


resource resNatGwPublicIP 'Microsoft.Network/publicIPAddresses@2023-05-01' = {
  name: 'aks-${parInitials}-natgw-pip'
  location: parLocation
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}
resource resNatGw 'Microsoft.Network/natGateways@2023-05-01' = {
  name: 'aks-${parInitials}-natgw'
  location: parLocation
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIpAddresses: [
      {
        id: resNatGwPublicIP.id
      }
    ]
  }
}

// resource resBasPublicIP 'Microsoft.Network/publicIPAddresses@2023-05-01' = {
//   name: 'aks-${parInitials}-baspip'
//   location: parLocation
//   sku: {
//     name: 'Standard'
//   }
//   properties: {
//     publicIPAllocationMethod: 'Static'
//   }
// }
// resource resBas 'Microsoft.Network/bastionHosts@2023-05-01' = {
//   name: 'aks-${parInitials}-bas'
//   location: parLocation
//   sku: {
//     name: 'Standard'
//   }
//   properties: {
//     ipConfigurations: [
//       {
//         name: 'ipConfig'
//         properties: {
//           privateIPAllocationMethod:'Dynamic'
//           publicIPAddress: {
//             id: resBasPublicIP.id
//           }
//           subnet: {
//             id: resVnet.properties.subnets[2].id
//           }
//         }
//       }
//     ]
//   }
// }

resource resLaw 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: 'aks-${parInitials}-law'
  location: parLocation
}

resource resAppgwPublicIP 'Microsoft.Network/publicIPAddresses@2023-05-01' = {
  name: 'aks-${parInitials}-appgwpip'
  location: parLocation
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource resAppgw 'Microsoft.Network/applicationGateways@2023-05-01' = {
  name: 'aks-${parInitials}-appgw'
  location: parLocation
  properties: {
    sku: {
      name: 'WAF_v2'
      tier: 'WAF_v2'
    }
    gatewayIPConfigurations: [
      {
        name: 'ipConfig'
        properties: {
          subnet: {
            id: resVnet.properties.subnets[1].id
          }
        }
      }
    ]
    frontendIPConfigurations: [
      {
        name: 'frontendPIP'
        properties: {
          publicIPAddress: {
            id: resAppgwPublicIP.id
          }
        }
      }
    ]
    frontendPorts: [
      {
        name: 'port_80'
        properties: {
          port: 80
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'bepool-akscluster'
      }
    ]
    backendHttpSettingsCollection: [
      {
        name: 'bepool-settings'
        properties: {
          port: 80
          protocol: 'Http'
          cookieBasedAffinity: 'Disabled'
          pickHostNameFromBackendAddress: false
        }
      }
    ]
    httpListeners: [
      {
        name: 'http-listener'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', parAppgwName, 'frontendPIP')
          }
          frontendPort: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', parAppgwName, 'port_80')
          }
          protocol: 'Http'
        }
      }
    ]
    requestRoutingRules: [
      {
        name: 'http-only'
        properties: {
          ruleType: 'Basic'
          priority: 1000
          httpListener: {
            id: resourceId('Microsoft.Network/applicationGateways/httpListeners', parAppgwName, 'http-listener')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', parAppgwName, 'bepool-akscluster')
          }
          backendHttpSettings: {
            id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', parAppgwName, 'bepool-settings')
          }
        }
      }
    ]
    firewallPolicy: {
      id: resAppgwWaf.id
    }
    autoscaleConfiguration: {
      minCapacity: 0
      maxCapacity: 10
    }
  }
}

resource resAppgwWaf 'Microsoft.Network/ApplicationGatewayWebApplicationFirewallPolicies@2023-05-01' = {
  name: 'appgwWaf'
  location: parLocation
  properties: {
    policySettings: {
      requestBodyCheck: true
      maxRequestBodySizeInKb: 128
      fileUploadLimitInMb: 100
      state: 'Enabled'
      mode: 'Detection'
    }
    managedRules: {
      managedRuleSets: [
        {
          ruleSetType: 'OWASP'
          ruleSetVersion: '3.2'
        }
      ]
    }
  }
}
