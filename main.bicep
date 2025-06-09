@description('Environment')
param env string

@description('Array of MPE configuration objects')
var mpeConfigs = [
  {
    synapseWorkspaceName: 'synapsewsdemo123'
    name: 'mpe-kv1'
    resourceId: '/subscriptions/1ad372fa-1532-4709-9b46-17de54fa0b71/resourceGroups/rg-synapse-demo/providers/Microsoft.KeyVault/vaults/synapsekvu31mi8'
    groupId: 'vault'
  }
]

resource mpeScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = [for (mpe, i) in mpeConfigs: {
  name: 'createMPE-${i}'
  location: resourceGroup().location
  kind: 'AzureCLI'

  // Uncomment this block if you're using User Assigned Managed Identity (recommended)
  /*
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentity.id}': {}
    }
  }
  */

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
