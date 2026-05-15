# =============================================================================
# replace_tokens.ps1
# -----------------------------------------------------------------------------
# Runs in the Skillable Lab Lifecycle (After VM Build) stage, AFTER
# deployment_build2026.ps1 has completed its Bicep deployment.
#
# This script:
#   1. Receives Skillable @lab tokens (subscription, RG, AAD user, SP creds).
#   2. Acquires an ARM access token via the lab's service-principal
#      (client_credentials flow).
#   3. Reads the outputs of the most recent successful ARM deployment in the
#      resource group (produced by infra5/deploy.bicep), specifically:
#         - clusterFqdn                        -> AZURE_PG_HOST
#         - adminLogin (labUser)               -> AZURE_PG_USER
#         - adminPassword (auto-generated)     -> AZURE_PG_PASSWORD
#         - azureOpenAIEndpoint                -> AZURE_OPENAI_ENDPOINT
#         - azureOpenAIChatDeploymentName      -> AZURE_OPENAI_DEPLOYMENT
#         - azureOpenAIEmbeddingDeploymentName -> AZURE_EMBED_DEPLOYMENT
#         - azureOpenAIServiceName             -> used for listKeys
#   4. Calls listKeys on the Azure OpenAI account to retrieve AZURE_OPENAI_KEY.
#   5. Writes a fully-populated .env file to C:\Lab\.env on the lab VM,
#      matching the canonical format used by the lab notebook.
# =============================================================================

$ErrorActionPreference = "Stop"

# ---------- Logging ----------------------------------------------------------
# Logs live OUTSIDE of C:\Lab so the clone target can be wiped freely without
# losing diagnostic output.
$logDir = 'C:\Logs'
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$logFile = Join-Path $logDir ("replace_tokens_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))

function Write-Log {
    param([string]$Message)
    $line = "{0} {1}" -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"), $Message
    $line | Out-File -FilePath $logFile -Append -Encoding UTF8
    Write-Output $line
}

Write-Log "==== Build .env start ===="

# ================== Inputs (Skillable tokens) ================================
$clientId          = "@lab.CloudSubscription.AppId"
$clientSecret      = "@lab.CloudSubscription.AppSecret"
$tenantId          = "@lab.CloudSubscription.TenantId"
$subscriptionId    = "@lab.CloudSubscription.Id"
$resourceGroupName = "@lab.CloudResourceGroup(ResourceGroup1).Name"

Write-Log "Tenant:        $tenantId"
Write-Log "Subscription:  $subscriptionId"
Write-Log "ResourceGroup: $resourceGroupName"

# ================== Acquire ARM token (client credentials) ===================
Write-Log "Requesting ARM access token..."
$tokenResp = Invoke-RestMethod -Method POST `
    -Uri "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token" `
    -ContentType 'application/x-www-form-urlencoded' `
    -Body @{
        client_id     = $clientId
        client_secret = $clientSecret
        scope         = 'https://management.azure.com/.default'
        grant_type    = 'client_credentials'
    }

$armToken = $tokenResp.access_token
if (-not $armToken) { throw "Failed to obtain ARM access token." }

$headers = @{
    "Authorization" = "Bearer $armToken"
    "Content-Type"  = "application/json"
}

# ================== Locate latest successful deployment ======================
# deployment_build2026.ps1 uses deployment names like "lab-yyyyMMdd-HHmmss".
Write-Log "Locating latest successful ARM deployment in $resourceGroupName..."
$deploymentsUrl  = "https://management.azure.com/subscriptions/$subscriptionId/resourcegroups/$resourceGroupName/providers/Microsoft.Resources/deployments?api-version=2021-04-01"
$deploymentsResp = Invoke-RestMethod -Uri $deploymentsUrl -Headers $headers -Method Get

$latestDeployment = $deploymentsResp.value |
    Where-Object {
        $_.properties.provisioningState -eq 'Succeeded' -and
        ($_.name -like 'lab-*' -or $_.properties.outputs.clusterFqdn)
    } |
    Sort-Object { [datetime]$_.properties.timestamp } -Descending |
    Select-Object -First 1

if (-not $latestDeployment) {
    throw "Could not find a successful 'lab-*' ARM deployment in resource group $resourceGroupName."
}

Write-Log "Using deployment: $($latestDeployment.name)  (timestamp $($latestDeployment.properties.timestamp))"

$outputs = $latestDeployment.properties.outputs
if (-not $outputs) { throw "Deployment $($latestDeployment.name) has no outputs." }

function Get-Output($obj, $name) {
    if ($null -eq $obj.$name) { throw "Deployment output '$name' is missing." }
    return $obj.$name.value
}

$postgresHost        = Get-Output $outputs 'clusterFqdn'
$pgAdminLogin        = Get-Output $outputs 'adminLogin'
$pgAdminPassword     = Get-Output $outputs 'adminPassword'
$openaiEndpoint      = Get-Output $outputs 'azureOpenAIEndpoint'
$openaiResourceName  = Get-Output $outputs 'azureOpenAIServiceName'
$gptDeploymentName   = Get-Output $outputs 'azureOpenAIChatDeploymentName'
$embedDeploymentName = Get-Output $outputs 'azureOpenAIEmbeddingDeploymentName'

Write-Log "HorizonDB host:    $postgresHost"
Write-Log "HorizonDB user:    $pgAdminLogin"
Write-Log "OpenAI account:    $openaiResourceName"
Write-Log "OpenAI endpoint:   $openaiEndpoint"
Write-Log "GPT deployment:    $gptDeploymentName"
Write-Log "Embed deployment:  $embedDeploymentName"

# ================== Fetch Azure OpenAI key ===================================
Write-Log "Fetching Azure OpenAI account key..."
$keysUrl   = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.CognitiveServices/accounts/$openaiResourceName/listKeys?api-version=2023-05-01"
$keysResp  = Invoke-RestMethod -Uri $keysUrl -Headers $headers -Method Post
$openaiKey = $keysResp.key1
if (-not $openaiKey) { throw "Failed to retrieve Azure OpenAI key for $openaiResourceName." }

# ================== Compose .env =============================================
$envContent = @"
# Azure OpenAI Configuration
AZURE_OPENAI_ENDPOINT   = "$openaiEndpoint"
AZURE_OPENAI_DEPLOYMENT = "$gptDeploymentName"
AZURE_OPENAI_KEY        = "$openaiKey"
AZURE_EMBED_DEPLOYMENT  = "$embedDeploymentName"
AZURE_API_VERSION       = "2025-03-01-preview"

# Database Configuration
AZURE_PG_HOST           = "$postgresHost"
AZURE_PG_NAME           = "postgres"
AZURE_PG_USER           = "$pgAdminLogin"
AZURE_PG_PASSWORD       = "$pgAdminPassword"
AZURE_PG_PORT           = 5432
AZURE_PG_SSLMODE        = "require"
"@

# ================== Write .env ===============================================
$envDir = 'C:\Lab'
if (-not (Test-Path $envDir)) { New-Item -ItemType Directory -Path $envDir -Force | Out-Null }
$envFilePath = Join-Path $envDir '.env'

$envContent | Out-File -FilePath $envFilePath -Encoding utf8 -NoNewline
Write-Log ".env written to: $envFilePath"

Write-Log "==== Build .env complete ===="
