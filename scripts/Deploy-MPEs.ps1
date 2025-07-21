param (
    [Parameter(Mandatory = $true)]
    [string]$EnvironmentFolder
)

# Fetch Synapse Workspace name from GitHub Environment variable
$SynapseWorkspaceName = $env:SYNAPSE_WORKSPACE_NAME
if (-not $SynapseWorkspaceName) {
    Write-Error "❌ Environment variable 'SYNAPSE_WORKSPACE_NAME' not found. Ensure it's set in GitHub Environments."
    exit 1
}

# Parse Azure credentials from GitHub Actions secret
$azureCredentials = $env:AZURE_CREDENTIALS | ConvertFrom-Json
Write-Host "🔐 Logging in with Client ID: $($azureCredentials.clientId)"

$tenantId       = $azureCredentials.tenantId
$clientId       = $azureCredentials.clientId
$clientSecret   = $azureCredentials.clientSecret
$subscriptionId = $azureCredentials.subscriptionId

# Login and set subscription
Connect-AzAccount -ServicePrincipal -TenantId $tenantId `
    -Credential (New-Object PSCredential ($clientId, (ConvertTo-SecureString $clientSecret -AsPlainText -Force))) | Out-Null
Select-AzSubscription -SubscriptionId $subscriptionId | Out-Null

# Locate config folder relative to script path
$configFolder = Join-Path -Path $PSScriptRoot -ChildPath "../configs/managedPrivateEndpoints/$EnvironmentFolder"
if (-not (Test-Path $configFolder)) {
    Write-Error "❌ Config folder not found: $configFolder"
    exit 1
}

# Loop through all JSON files in the environment folder
Get-ChildItem -Path $configFolder -Filter *.json | ForEach-Object {
    $filePath = $_.FullName
    Write-Host "📄 Processing file: $filePath"

    $mpeConfig = Get-Content $filePath | ConvertFrom-Json
    $mpeName = $mpeConfig.name

    # Write definition to temp file within script directory to avoid permission issues
    $definitionTempFile = Join-Path -Path $PSScriptRoot -ChildPath "$mpeName.json"
    $mpeConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $definitionTempFile -Encoding utf8

    # Check for existing MPE
    $existing = Get-AzSynapseManagedPrivateEndpoint -WorkspaceName $SynapseWorkspaceName -Name $mpeName -ErrorAction SilentlyContinue

    if (-not $existing) {
        try {
            New-AzSynapseManagedPrivateEndpoint -WorkspaceName $SynapseWorkspaceName `
                -Name $mpeName `
                -DefinitionFile $definitionTempFile | Out-Null
            Write-Host "✅ Created MPE: $mpeName"
        } catch {
            Write-Warning "❌ Failed to create MPE: $mpeName - $_"
        }
    } else {
        Write-Host "ℹ️ MPE already exists: $mpeName"
    }

    # Clean up the temporary file
    Remove-Item -Path $definitionTempFile -Force -ErrorAction SilentlyContinue
}
