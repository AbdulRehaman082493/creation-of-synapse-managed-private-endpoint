param (
    [Parameter(Mandatory = $true)]
    [string]$EnvironmentFolder  # Pass only the name without `.json`
)

Write-Host "`n===== Starting Synapse MPE Deployment Script =====`n"

# Step 1: Get Synapse workspace name from env var
$SynapseWorkspaceName = $env:SYNAPSE_WORKSPACE_NAME
if (-not $SynapseWorkspaceName) {
    Write-Error "[ERROR] Environment variable 'SYNAPSE_WORKSPACE_NAME' not found. Ensure it's set in GitHub Environments."
    exit 1
}
Write-Host "[INFO] Synapse Workspace: $SynapseWorkspaceName"

# Step 2: Parse Azure credentials
try {
    $azureCredentials = ConvertFrom-Json -InputObject $env:AZURE_CREDENTIALS
} catch {
    Write-Error "[ERROR] Failed to parse AZURE_CREDENTIALS. Ensure it's valid JSON."
    exit 1
}

if (-not $azureCredentials) {
    Write-Error "[ERROR] AZURE_CREDENTIALS is missing or empty."
    exit 1
}

Write-Host "[INFO] Parsed Azure Credentials:"
Write-Host "  Tenant ID       : $($azureCredentials.tenantId)"
Write-Host "  Client ID       : $($azureCredentials.clientId)"
Write-Host "  Subscription ID : $($azureCredentials.subscriptionId)"

# Step 3: Authenticate with Azure
Connect-AzAccount -ServicePrincipal `
    -TenantId $azureCredentials.tenantId `
    -Credential (New-Object -TypeName System.Management.Automation.PSCredential `
        -ArgumentList $azureCredentials.clientId, (ConvertTo-SecureString $azureCredentials.clientSecret -AsPlainText -Force)) `
    | Out-Null

# Set the Azure subscription context
Set-AzContext -SubscriptionId $azureCredentials.subscriptionId | Out-Null

# Step 4: Locate and load the config file
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$configFolder = Join-Path -Path $repoRoot -ChildPath "configs/managedPrivateEndpoints/$EnvironmentFolder"
Write-Host "[INFO] Looking for config file: $configFolder"

if (-not (Test-Path $configFolder)) {
    Write-Error "[ERROR] Config folder not found: $configFolder"
    exit 1
}

# Step 5: Get list of JSON files from the config folder
$files = Get-ChildItem -Path $configFolder -Filter *.json | Select-Object -ExpandProperty FullName
Write-Host "[INFO] Found config file(s):"
$files | ForEach-Object { Write-Host "  - $_" }

# Step 6: Process each config file
foreach ($filePath in $files) {
    Write-Host "`n[INFO] Processing file: $filePath"

    try {
        $rawConfig = Get-Content $filePath -Raw | ConvertFrom-Json
    } catch {
        Write-Warning "[WARNING] Failed to parse JSON file: $filePath"
        continue
    }

    # Validation: Filename matches 'name' field
    $fileName = [System.IO.Path]::GetFileNameWithoutExtension($filePath)
    $mpeName = $rawConfig.name

    if ($fileName -ne $mpeName) {
        Write-Warning "[ERROR] File name '$fileName' does not match 'name' value '$mpeName'. Skipping."
        continue
    }

    $privateLinkResourceId = $rawConfig.properties.privateLinkResourceId
    $groupId = $rawConfig.properties.groupId

    if (-not $mpeName -or -not $privateLinkResourceId -or -not $groupId) {
        Write-Warning "[WARNING] Missing required fields (name, privateLinkResourceId, groupId) in file: $filePath"
        continue
    }

    Write-Host "[DEBUG] MPE Details:"
    Write-Host "  Name        : $mpeName"
    Write-Host "  Resource ID : $privateLinkResourceId"
    Write-Host "  Group ID    : $groupId"

    # Create a temporary JSON definition file
    $tempFile = Join-Path -Path $PSScriptRoot -ChildPath "$mpeName.json"
    $definitionJson = @{
        name       = $mpeName
        properties = @{
            privateLinkResourceId = $privateLinkResourceId
            groupId               = $groupId
        }
    } | ConvertTo-Json -Depth 10

    Set-Content -Path $tempFile -Value $definitionJson -Encoding UTF8

    # Check if the MPE already exists
    Write-Host "[DEBUG] Checking if MPE exists: $mpeName"
    $existing = Get-AzSynapseManagedPrivateEndpoint -WorkspaceName $SynapseWorkspaceName -Name $mpeName -ErrorAction SilentlyContinue

    if (-not $existing) {
        try {
            Write-Host "[INFO] Creating new MPE: $mpeName"
            New-AzSynapseManagedPrivateEndpoint -WorkspaceName $SynapseWorkspaceName `
                -Name $mpeName `
                -DefinitionFile $tempFile | Out-Null
            Write-Host "[SUCCESS] Created MPE: $mpeName"
        } catch {
            Write-Warning "[ERROR] Failed to create MPE: $mpeName - $_"
        }
    } else {
        Write-Host "[INFO] MPE already exists: $mpeName"
    }

    # Clean up
    Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
}

Write-Host "`n===== Synapse MPE Deployment Script Completed =====`n"
