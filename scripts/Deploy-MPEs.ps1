param (
    [Parameter(Mandatory = $true)]
    [string]$EnvironmentFolder,

    [Parameter(Mandatory = $true)]
    [string]$SynapseWorkspaceName
)

# Step 1: Authenticate to Azure
$azureCredentials = ConvertFrom-Json -InputObject $env:AZURE_CREDENTIALS
Write-Host "🔐 Logging in with Client ID: $($azureCredentials.clientId)"

$tenantId       = $azureCredentials.tenantId
$clientId       = $azureCredentials.clientId
$clientSecret   = $azureCredentials.clientSecret
$subscriptionId = $azureCredentials.subscriptionId

Connect-AzAccount -ServicePrincipal -TenantId $tenantId `
    -Credential (New-Object System.Management.Automation.PSCredential `
        ($clientId, (ConvertTo-SecureString $clientSecret -AsPlainText -Force))) | Out-Null

Select-AzSubscription -SubscriptionId $subscriptionId | Out-Null

# Step 2: Locate config folder
$configFolder = "./configs/managedPrivateEndpoints/$EnvironmentFolder"
if (-not (Test-Path $configFolder)) {
    Write-Error "❌ Environment config folder not found: $configFolder"
    exit 1
}

# Step 3: Loop through and apply each JSON file
Get-ChildItem -Path $configFolder -Filter *.json | ForEach-Object {
    $file = $_.FullName
    Write-Host "📄 Processing file: $file"

    $mpeConfig = Get-Content $file | ConvertFrom-Json
    $mpeName = $mpeConfig.name

    # Check if already exists
    $existing = Get-AzSynapseManagedPrivateEndpoint -WorkspaceName $SynapseWorkspaceName `
        -Name $mpeName -ErrorAction SilentlyContinue

    if (-not $existing) {
        try {
            New-AzSynapseManagedPrivateEndpoint `
                -WorkspaceName $SynapseWorkspaceName `
                -Name $mpeName `
                -DefinitionFile $file

            Write-Host "✅ Created MPE: $mpeName"
        } catch {
            Write-Warning "❌ Failed to create MPE: $mpeName - $_"
        }
    } else {
        Write-Host "ℹ️ MPE already exists: $mpeName"
    }
}
