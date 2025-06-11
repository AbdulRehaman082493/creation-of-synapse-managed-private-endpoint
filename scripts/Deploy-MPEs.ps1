param (
    [Parameter(Mandatory = $true)]
    [string]$EnvironmentFolder,

    [Parameter(Mandatory = $true)]
    [string]$SynapseWorkspaceName
)

# Parse Azure credentials from GitHub Actions secret
$azureCredentials = $env:AZURE_CREDENTIALS | ConvertFrom-Json
Connect-AzAccount -ServicePrincipal -TenantId $azureCredentials.tenantId `
    -Credential (New-Object System.Management.Automation.PSCredential (
        $azureCredentials.clientId,
        (ConvertTo-SecureString $azureCredentials.clientSecret -AsPlainText -Force)
    )) | Out-Null
Select-AzSubscription -SubscriptionId $azureCredentials.subscriptionId | Out-Null

# Path to the config folder for the selected environment
$configFolder = "./configs/managedPrivateEndpoints/$EnvironmentFolder"

if (-not (Test-Path $configFolder)) {
    Write-Error "❌ Config folder not found: $configFolder"
    exit 1
}

# Loop through each JSON config and create MPE
Get-ChildItem -Path $configFolder -Filter *.json | ForEach-Object {
    $file = $_.FullName
    $mpeName = (Get-Content $file | ConvertFrom-Json).name

    $existing = Get-AzSynapseManagedPrivateEndpoint -WorkspaceName $SynapseWorkspaceName -Name $mpeName -ErrorAction SilentlyContinue

    if (-not $existing) {
        try {
            Write-Host "🚀 Creating: $mpeName"
            New-AzSynapseManagedPrivateEndpoint -WorkspaceName $SynapseWorkspaceName -Name $mpeName -DefinitionFile $file
            Write-Host "✅ Created MPE: $mpeName"
        } catch {
            Write-Warning "❌ Failed to create MPE: $mpeName - $_"
        }
    } else {
        Write-Host "ℹ️ MPE already exists: $mpeName"
    }
}
