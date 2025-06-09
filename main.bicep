@description('Array of MPE configuration objects')
param mpeConfigs array

@description('Environment')
param env string 

resource userAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: 'mpe-uai'
  scope: resourceGroup()
}

resource mpeScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = [for (mpe, i) in mpeConfigs: {
  name: 'createMPE-${env}-${i}'
  location: resourceGroup().location
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentity.id}': {}
    }
  }
  properties: {
    azCliVersion: '2.52.0'
    timeout: 'PT10M'
    retentionInterval: 'PT1H'
    cleanupPreference: 'OnSuccess'
    scriptContent: format('''
      mkdir -p /tmp/mpe
      rand_suffix=$RANDOM
      json_file="/tmp/mpe/endpoint-{0}-$rand_suffix.json"
      printf '{{"privateLinkResourceId": "%s", "groupId": "%s"}}' '{1}' '{2}' > $json_file

      az synapse managed-private-endpoints create \
        --workspace-name {3} \
        --pe-name {4} \
        --file @$json_file
    ''',
      i,
      mpe.resourceId,
      mpe.groupId,
      mpe.synapseWorkspaceName,
      mpe.name
    )
  }
}]
