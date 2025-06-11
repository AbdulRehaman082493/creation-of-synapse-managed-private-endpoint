param (
    [string]$EnvironmentFolder,
    [string]$SynapseWorkspaceName
)

Write-Host "📁 Current Working Directory: $(Get-Location)"

# Step 1: Parse AZURE_CREDENTIALS from GitHub Secrets
$azureCredentials = ConvertFrom-Json -InputObject $env:AZURE_CREDENTIALS
Write-Host "🔐 Authenticating with Client ID: $($azureCredentials.clientId)"

$tenantId       = $azureCredentials.tenantId
$clientId       = $azureCredentials.clientId
$clientSecret   = $azureCredentials.clientSecret
$subscriptionId = $azureCredentials.subscriptionId

Connect-AzAccount -ServicePrincipal -TenantId $tenantId `
    -Credential (New-Object System.Management.Automation.PSCredential `
        ($clientId, (ConvertTo-SecureString $clientSecret -AsPlainText -Force))) | Out-Null

Select-AzSubscription -SubscriptionId $subscriptionId | Out-Null

# Step 2: Validate folder
$repoPath = "$pwd/configs/managedPrivateEndpoints/$EnvironmentFolder"

if (-not (Test-Path $repoPath)) {
    Write-Error "[❌] Environment folder missing: $repoPath"
    exit 1
}

# Step 3: Load all JSON files
$files = Get-ChildItem -Path $repoPath -Filter *.json

if ($files.Count -eq 0) {
    Write-Warning "[⚠️] No JSON files found in $repoPath"
    exit 0
}

# Step 4: Loop and deploy
foreach ($file in $files) {
    $filePath = $file.FullName.Trim()
    Write-Host "`n📄 Processing file: $filePath"

    if (-not (Test-Path $filePath)) {
        Write-Warning "[⚠️] Skipping missing file: $filePath"
        continue
    }

    try {
        $mpeConfig = Get-Content $filePath | ConvertFrom-Json
    } catch {
        Write-Warning "[❌] Failed to parse JSON in: $filePath"
        continue
    }

    # Validate required properties
    if (-not $mpeConfig.name -or -not $mpeConfig.properties.privateLinkResourceId -or -not $mpeConfig.properties.groupId) {
        Write-Warning "[⚠️] Missing required fields in: $filePath"
        continue
    }

    $mpeName = $mpeConfig.name

    # Check if already exists
    $existing = Get-AzSynapseManagedPrivateEndpoint `
        -WorkspaceName $SynapseWorkspaceName `
        -Name $mpeName `
        -ErrorAction SilentlyContinue

    if (-not $existing) {
        $tempPath = ".\temp\$mpeName.json"
        if (-not (Test-Path ".\temp")) {
            New-Item -ItemType Directory -Path ".\temp" | Out-Null
        }

        $mpeConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $tempPath -Encoding utf8

        try {
            New-AzSynapseManagedPrivateEndpoint `
                -WorkspaceName $SynapseWorkspaceName `
                -Name $mpeName `
                -DefinitionFile $tempPath
            Write-Host "✅ Created: $mpeName"
        } catch {
            Write-Warning "❌ Failed to create $mpeName - $_"
        }

        Remove-Item -Path $tempPath -Force
    } else {
        Write-Host "ℹ️ Already exists: $mpeName"
    }
}

# Final Cleanup
if (Test-Path ".\temp") {
    Remove-Item -Path ".\temp" -Recurse -Force
    Write-Host "`n🧹 Temp folder cleaned up."
}
