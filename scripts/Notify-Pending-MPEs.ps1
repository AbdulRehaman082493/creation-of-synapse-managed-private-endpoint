param()

# Step 1: Parse credentials
$azureCredentials = ConvertFrom-Json $env:AZURE_CREDENTIALS
Connect-AzAccount -ServicePrincipal `
  -TenantId $azureCredentials.tenantId `
  -Credential (New-Object -TypeName PSCredential -ArgumentList $azureCredentials.clientId, (ConvertTo-SecureString $azureCredentials.clientSecret -AsPlainText -Force)) | Out-Null
Set-AzContext -SubscriptionId $azureCredentials.subscriptionId | Out-Null

$workspaceName = $env:SYNAPSE_WORKSPACE_NAME
$resourceGroupName = "rg-synapse-demo" # Update if dynamic

# Step 2: REST call to list MPEs
$token = (Get-AzAccessToken).Token
$uri = "https://management.azure.com/subscriptions/$($azureCredentials.subscriptionId)/resourceGroups/$resourceGroupName/providers/Microsoft.Synapse/workspaces/$workspaceName/managedVirtualNetworks/default/managedPrivateEndpoints?api-version=2021-06-01"
$response = Invoke-RestMethod -Uri $uri -Headers @{ Authorization = "Bearer $token" } -Method GET

# Step 3: Filter for pending MPEs
$pending = $response.value | Where-Object {
  $_.properties.privateLinkServiceConnectionState.status -eq 'Pending'
}

if ($pending.Count -gt 0) {
  Write-Host "⚠️ Found $($pending.Count) pending MPE(s):"
  $pending | ForEach-Object {
    Write-Host " - $($_.name) -> $($_.properties.privateLinkResourceId)"
  }

  # Step 4: Notification (optional: integrate Teams, Email, or GitHub Issue)
  # You can also write to console or post to Teams via webhook
} else {
  Write-Host "✅ No pending MPEs found."
}
