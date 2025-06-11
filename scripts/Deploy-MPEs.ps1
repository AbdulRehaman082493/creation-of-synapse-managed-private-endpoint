param (
    [string]$EnvironmentConfig
)

# Step 1: Parse AZURE_CREDENTIALS from GitHub Secrets
$azureCredentials = ConvertFrom-Json -InputObject $env:AZURE_CREDENTIALS
Write-Host "🔐 Logging in with Client ID: $($azureCredentials.clientId)"

$tenantId       = $azureCredentials.tenantId
$clientId       = $azureCredentials.clientId
$clientSecret   = $azureCredentials.clientSecret
$subscriptionId = $azureCredentials.subscriptionId

Connect-AzAccount -ServicePrincipal -TenantId $tenantId `
    -Credential (New-Object System.Management.Automation.PSCredential `
        ($clientId, (ConvertTo-SecureString $clientSecret -AsPlainText -Force)))

Select-AzSubscription -SubscriptionId $subscriptionId

# Step 2: Load environment config JSON
if (-not (Test-Path $EnvironmentConfig)) {
    Write-Error "❌ File not found: $EnvironmentConfig"
    exit 1
}

$envConfig = Get-Content $EnvironmentConfig | ConvertFrom-Json
$synapseWorkspaceName = $envConfig.synapseWorkspaceName
$resourceGroupName = $envConfig.resourceGroupName
$mpeList = $envConfig.mpes

# Step 3: Create temp folder
$tempFolder = ".\temp"
if (-not (Test-Path $tempFolder)) {
    New-Item -ItemType Directory -Path $tempFolder | Out-Null
}

# Step 4: Loop through MPEs
foreach ($mpe in $mpeList) {
    $mpeName = $mpe.name
    $tempJsonPath = "$tempFolder\$mpeName.json"

    $mpe | ConvertTo-Json -Depth 10 | Set-Content -Path $tempJsonPath -Encoding utf8

    $existing = Get-AzSynapseManagedPrivateEndpoint -WorkspaceName $synapseWorkspaceName `
        -Name $mpeName -ResourceGroupName $resourceGroupName -ErrorAction SilentlyContinue

    if (-not $existing) {
        try {
            New-AzSynapseManagedPrivateEndpoint -WorkspaceName $synapseWorkspaceName `
                -Name $mpeName -DefinitionFile $tempJsonPath
            Write-Host "✅ Created MPE: $mpeName"
        } catch {
            Write-Warning "❌ Failed to create MPE: $mpeName - $_"
        }
    } else {
        Write-Host "ℹ️ MPE already exists: $mpeName"
    }
}

# Step 5: Cleanup
Remove-Item -Path $tempFolder -Recurse -Force
Write-Host "🧹 Temp folder cleaned up."
