param()

# Step 1: Parse credentials
$azureCredentials = ConvertFrom-Json $env:AZURE_CREDENTIALS
Connect-AzAccount -ServicePrincipal `
  -TenantId $azureCredentials.tenantId `
  -Credential (New-Object -TypeName PSCredential -ArgumentList $azureCredentials.clientId, (ConvertTo-SecureString $azureCredentials.clientSecret -AsPlainText -Force)) | Out-Null
Set-AzContext -SubscriptionId $azureCredentials.subscriptionId | Out-Null

$workspaceName = $env:SYNAPSE_WORKSPACE_NAME
$resourceGroupName = "rg-synapse-demo" # Update if needed

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

  # Step 4: Email settings
  $smtpServer = "smtp.office365.com"
  $smtpPort = 587
  $from = $env:OUTLOOK_USERNAME

  # ✅ Multiple recipients
  $to = @(
    "approver1@yourdomain.com",
    "approver2@yourdomain.com",
    "teamlead@yourdomain.com"
  )

  $subject = "🚨 Synapse MPE(s) Pending Approval"
  $body = "The following Managed Private Endpoints are pending approval:`n`n"

  foreach ($mpe in $pending) {
    $body += "• Name: $($mpe.name)`n"
    $body += "  Target: $($mpe.properties.privateLinkResourceId)`n`n"
  }

  $body += "Review in Azure Portal: https://portal.azure.com/#blade/Microsoft_Azure_Synapse/SynapseWorkspaceMenu/synapseworkspace/$workspaceName/privateLinkHub"

  # Send email
  $securePassword = ConvertTo-SecureString -String $env:OUTLOOK_PASSWORD -AsPlainText -Force
  $cred = New-Object System.Management.Automation.PSCredential($from, $securePassword)

  Send-MailMessage -SmtpServer $smtpServer -Port $smtpPort -UseSsl `
    -Credential $cred -From $from -To $to -Subject $subject -Body $body
} else {
  Write-Host "✅ No pending MPEs found."
}
