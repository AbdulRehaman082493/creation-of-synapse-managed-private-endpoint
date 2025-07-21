param (
    [Parameter(Mandatory = $true)]
    [string]$EnvironmentFolder  # Pass only the name without `.json`
)

Write-Host "`n===== Starting Synapse MPE Deployment Script =====`n"

# Step 1: Get Synapse workspace name
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

# Step 3: Authenticate
Connect-AzAccount -ServicePrincipal `
    -TenantId $azureCredentials.tenantId `
    -Credential (New-Object System.Management.Automation.PSCredential `
        ($azureCredentials.clientId, (ConvertTo-SecureString $azureCredentials.clientSecret -AsPlainText -Force))) | Out-Null

Set-AzContext -SubscriptionId $azureCredentials.subscriptionId | Out-Null

# Step 4: Load config folder
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$configFolder = Join-Path -Path $repoRoot -ChildPath "configs/managedPrivateEndpoints/$EnvironmentFolder"
Write-Host "[INFO] Looking for config file: $configFolder"

if (-not (Test-Path $configFolder)) {
    Write-Error "[ERROR] Config folder not found: $configFolder"
    exit 1
}

# Step 5: Load JSON files
$files = Get-ChildItem -Path $configFolder -Filter *.json | Select-Object -ExpandProperty FullName
Write-Host "[INFO] Found config file(s):"
$files | ForEach-Object { Write-Host "  - $_" }

# Step 6: Process files
foreach ($filePath in $files) {
    Write-Host "`n[INFO] Processing file: $filePath"

    try {
        $rawConfig = Get-Content $filePath -Raw | ConvertFrom-Json
    } catch {
        Write-Warning "[WARNING] Failed to parse JSON file: $filePath"
        continue
    }

    $fileName = [System.IO.Path]::GetFileNameWithoutExtension($filePath)
    $mpeName = $rawConfig.name

    if ($fileName -ne $mpeName) {
        Write-Warning "[WARNING] File name '$fileName' does not match 'name' value '$mpeName'. Skipping."
        continue
    }

    $props = $rawConfig.properties
    $privateLinkResourceId = $props.privateLinkResourceId
    $groupId               = $props.groupId
    $privateLinkServiceId  = $props.privateLinkServiceId
    $requestMessage        = $props.requestMessage
    $fqdns                 = $props.fqdns

    # Validation
    if (-not $mpeName -or (-not $privateLinkResourceId -and -not $privateLinkServiceId)) {
        Write-Warning "[WARNING] Missing required fields. Either 'privateLinkResourceId' and 'groupId', OR 'privateLinkServiceId' must be provided. Skipping: $filePath"
        continue
    }

    Write-Host "[DEBUG] MPE Details:"
    Write-Host "  Name                  : $mpeName"
    if ($privateLinkResourceId) { Write-Host "  Resource ID           : $privateLinkResourceId" }
    if ($privateLinkServiceId) { Write-Host "  Private Link Service  : $privateLinkServiceId" }
    if ($groupId)              { Write-Host "  Group ID              : $groupId" }
    if ($requestMessage)       { Write-Host "  Request Message       : $requestMessage" }
    if ($fqdns)                { Write-Host "  FQDNs                 : $($fqdns -join ', ')" }

    # Build MPE definition
    $definitionJson = @{
        name       = $mpeName
        properties = @{}
    }

    if ($privateLinkServiceId) {
        $definitionJson.properties.privateLinkServiceId = $privateLinkServiceId
    } else {
        $definitionJson.properties.privateLinkResourceId = $privateLinkResourceId
        $definitionJson.properties.groupId = $groupId
    }

    if ($requestMessage) {
        $definitionJson.properties.requestMessage = $requestMessage
    }
    if ($fqdns) {
        $definitionJson.properties.fqdns = $fqdns
    }

    $tempFile = Join-Path -Path $PSScriptRoot -ChildPath "$mpeName.json"
    $definitionJson | ConvertTo-Json -Depth 10 | Set-Content -Path $tempFile -Encoding UTF8

    # Check if MPE already exists
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

    Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
}

Write-Host "`n===== Synapse MPE Deployment Script Completed =====`n"
