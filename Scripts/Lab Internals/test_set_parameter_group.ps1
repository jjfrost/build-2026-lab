# =============================================================================
# Set HorizonDB Parameter Group (LOCAL TEST VERSION)
# -----------------------------------------------------------------------------
# Local testing equivalent of 5b_set_parameter_group.ps1.
# Assumes you have already authenticated with:
#     az login
#     az account set --subscription <subscription-id>
#
# Differences vs the Skillable lifecycle version:
#   - No @lab.* token substitution; reads subscription / RG from params or
#     from `az account show`.
#   - Uses `az account get-access-token` instead of client_credentials flow.
#   - Resource group + cluster name can be passed in directly; auto-discovery
#     from the latest 'lab-*' deployment is still available as fallback.
#
# What it does:
#   1. Creates a HorizonDB parameter group via ARM REST that:
#        - Allow-lists extensions: azure_ai, vector, age, pg_diskann, pg_fts
#          (parameter: azure.extensions)
#        - Enables AGE in shared_preload_libraries
#   2. Attaches the parameter group to the HorizonDB cluster via PATCH.
#
# Usage examples:
#   .\test_set_parameter_group.ps1 -ResourceGroupName my-rg -ClusterName my-cluster
#   .\test_set_parameter_group.ps1 -ResourceGroupName my-rg   # auto-discover cluster
#   .\test_set_parameter_group.ps1                            # auto-discover both
# =============================================================================

[CmdletBinding()]
param(
    [string]$SubscriptionId,
    [string]$ResourceGroupName,
    [string]$ClusterName,
    [string]$ParameterGroupName = 'lab-paramgroup',
    [string[]]$AllowedExtensions = @('azure_ai','vector','age','pg_diskann','pg_fts'),
    [string[]]$PreloadLibraries  = @('age'),
    [string]$HorizonApiVersion   = '2026-01-20-preview',
    [bool]$ApplyImmediately      = $true
)

$ErrorActionPreference = "Stop"

# ---------- Logging ----------------------------------------------------------
$logDir = Join-Path $PSScriptRoot 'logs'
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$logFile = Join-Path $logDir ("test_set_parameter_group_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))

function Write-Log {
    param([string]$Message)
    $line = "{0} {1}" -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"), $Message
    $line | Out-File -FilePath $logFile -Append -Encoding UTF8
    Write-Output $line
}

Write-Log "==== Set HorizonDB Parameter Group (local test) start ===="

# ================== Verify az CLI is available ===============================
$azCmd = Get-Command az -ErrorAction SilentlyContinue
if (-not $azCmd) { throw "Azure CLI (az) not found on PATH. Install it or run 'az login' in an az-enabled shell." }

# ================== Resolve subscription =====================================
if (-not $SubscriptionId) {
    Write-Log "No -SubscriptionId provided; reading from 'az account show'..."
    $acct = az account show --output json 2>$null | ConvertFrom-Json
    if (-not $acct) { throw "Not logged in. Run 'az login' first." }
    $SubscriptionId = $acct.id
}
Write-Log "Subscription: $SubscriptionId"

# Ensure the CLI is pointed at this subscription
az account set --subscription $SubscriptionId | Out-Null

# ================== Acquire ARM token via az CLI =============================
Write-Log "Acquiring ARM access token via 'az account get-access-token'..."
$tokenJson = az account get-access-token --resource https://management.azure.com --output json
if (-not $tokenJson) { throw "Failed to get access token from az CLI." }
$armToken = ($tokenJson | ConvertFrom-Json).accessToken
if (-not $armToken) { throw "Access token missing from CLI response." }

$headers = @{
    "Authorization" = "Bearer $armToken"
    "Content-Type"  = "application/json"
}

# ================== Resolve resource group ===================================
if (-not $ResourceGroupName) {
    Write-Log "No -ResourceGroupName provided; searching for a RG containing a HorizonDB cluster..."
    $clustersUrl  = "https://management.azure.com/subscriptions/$SubscriptionId/providers/Microsoft.HorizonDb/clusters?api-version=$HorizonApiVersion"
    $clustersResp = Invoke-RestMethod -Uri $clustersUrl -Headers $headers -Method Get
    $first = $clustersResp.value | Select-Object -First 1
    if (-not $first) { throw "No HorizonDB clusters found in subscription $SubscriptionId. Pass -ResourceGroupName explicitly." }
    # Parse RG out of the resource id: /subscriptions/{sub}/resourceGroups/{rg}/...
    if ($first.id -match '/resourceGroups/([^/]+)/') {
        $ResourceGroupName = $Matches[1]
    } else {
        throw "Could not parse resource group from cluster id: $($first.id)"
    }
    if (-not $ClusterName) { $ClusterName = $first.name }
}
Write-Log "ResourceGroup: $ResourceGroupName"

# ================== Resolve cluster name =====================================
if (-not $ClusterName) {
    Write-Log "No -ClusterName provided; auto-discovering from RG..."
    $rgClustersUrl  = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.HorizonDb/clusters?api-version=$HorizonApiVersion"
    $rgClustersResp = Invoke-RestMethod -Uri $rgClustersUrl -Headers $headers -Method Get
    $first = $rgClustersResp.value | Select-Object -First 1
    if (-not $first) {
        # Fall back to deployment outputs (matches the lifecycle script behavior)
        Write-Log "No cluster found by list; falling back to latest 'lab-*' deployment outputs..."
        $deploymentsUrl  = "https://management.azure.com/subscriptions/$SubscriptionId/resourcegroups/$ResourceGroupName/providers/Microsoft.Resources/deployments?api-version=2021-04-01"
        $deploymentsResp = Invoke-RestMethod -Uri $deploymentsUrl -Headers $headers -Method Get
        $latestDeployment = $deploymentsResp.value |
            Where-Object {
                $_.properties.provisioningState -eq 'Succeeded' -and
                ($_.name -like 'lab-*' -or $_.properties.outputs.clusterName)
            } |
            Sort-Object { [datetime]$_.properties.timestamp } -Descending |
            Select-Object -First 1
        if (-not $latestDeployment) { throw "No HorizonDB cluster and no 'lab-*' deployment in $ResourceGroupName." }
        $outputs = $latestDeployment.properties.outputs
        if (-not $outputs -or -not $outputs.clusterName) { throw "Deployment $($latestDeployment.name) has no clusterName output." }
        $ClusterName = $outputs.clusterName.value
    } else {
        $ClusterName = $first.name
    }
}
Write-Log "HorizonDB cluster: $ClusterName"

# ================== Get cluster details (location, pgVersion) ================
$clusterUri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.HorizonDb/clusters/$ClusterName`?api-version=$HorizonApiVersion"
Write-Log "Fetching cluster details..."
$clusterResp = Invoke-RestMethod -Uri $clusterUri -Headers $headers -Method Get

$clusterLocation = $clusterResp.location
$clusterVersion  = $clusterResp.properties.version
Write-Log "Cluster location: $clusterLocation"
Write-Log "Cluster version:  $clusterVersion"

$pgVersion = 0
if ($clusterVersion -and ($clusterVersion -match '^\s*(\d+)')) {
    $pgVersion = [int]$Matches[1]
}
if ($pgVersion -le 0) {
    $pgVersion = 17
    Write-Log "Could not parse pgVersion from cluster; defaulting to $pgVersion"
}
Write-Log "Parameter group pgVersion: $pgVersion"

# ================== Build parameter group payload ============================
$extensionsValue = ($AllowedExtensions -join ',')
$preloadValue    = ($PreloadLibraries  -join ',')

Write-Log "azure.extensions          = $extensionsValue"
Write-Log "shared_preload_libraries  = $preloadValue"

$pgBody = @{
    location   = $clusterLocation
    properties = @{
        description       = 'Lab parameter group: allow-listed extensions and AGE preload'
        pgVersion         = $pgVersion
        applyImmediately  = $ApplyImmediately
        parameters        = @(
            @{ name = 'azure.extensions';         value = $extensionsValue }
            @{ name = 'shared_preload_libraries'; value = $preloadValue   }
        )
    }
} | ConvertTo-Json -Depth 8

$pgUri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.HorizonDb/parameterGroups/$ParameterGroupName`?api-version=$HorizonApiVersion"

Write-Log "Creating/updating parameter group: $ParameterGroupName"
try {
    $pgResp = Invoke-RestMethod -Method PUT -Uri $pgUri -Headers $headers -Body $pgBody
    Write-Log "  -> Submitted. Provisioning state: $($pgResp.properties.provisioningState)"
} catch {
    Write-Log "  !! Failed to create parameter group: $($_.Exception.Message)"
    if ($null -ne $_.Exception.Response) {
        try {
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            Write-Log "  Response body: $($reader.ReadToEnd())"
        } catch { }
    }
    throw
}

# ================== Poll parameter group until ready =========================
$parameterGroupId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.HorizonDb/parameterGroups/$ParameterGroupName"

Write-Log "Waiting for parameter group provisioning to finish..."
$maxWaitSec  = 600
$intervalSec = 15
$elapsed     = 0
$pgState     = ''
while ($elapsed -lt $maxWaitSec) {
    Start-Sleep -Seconds $intervalSec
    $elapsed += $intervalSec
    try {
        $pgGet = Invoke-RestMethod -Uri $pgUri -Headers $headers -Method Get
        $pgState = $pgGet.properties.provisioningState
        Write-Log "  Parameter group state: $pgState (elapsed ${elapsed}s)"
        if ($pgState -in @('Succeeded','Failed','Canceled')) { break }
    } catch {
        Write-Log "  GET parameter group failed: $($_.Exception.Message)"
    }
}

if ($pgState -ne 'Succeeded') {
    throw "Parameter group did not reach Succeeded state (last state: $pgState)."
}

# ================== Attach parameter group to cluster (PATCH) ================
Write-Log "Attaching parameter group to cluster $ClusterName..."

$attachBody = @{
    properties = @{
        parameterGroup = @{
            id               = $parameterGroupId
            applyImmediately = $ApplyImmediately
        }
    }
} | ConvertTo-Json -Depth 8

try {
    $patchResp = Invoke-WebRequest -Method PATCH -Uri $clusterUri -Headers $headers -Body $attachBody -UseBasicParsing
    Write-Log "  -> Cluster PATCH submitted. HTTP $($patchResp.StatusCode)"
} catch {
    Write-Log "  !! Failed to attach parameter group to cluster: $($_.Exception.Message)"
    if ($null -ne $_.Exception.Response) {
        try {
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            Write-Log "  Response body: $($reader.ReadToEnd())"
        } catch { }
    }
    throw
}

# ================== Poll cluster until parameter group is applied ============
Write-Log "Waiting for cluster to apply parameter group..."
$elapsed = 0
$clusterState = ''
$syncStatus   = ''
while ($elapsed -lt $maxWaitSec) {
    Start-Sleep -Seconds $intervalSec
    $elapsed += $intervalSec
    try {
        $clusterGet   = Invoke-RestMethod -Uri $clusterUri -Headers $headers -Method Get
        $clusterState = $clusterGet.properties.provisioningState
        $syncStatus   = $clusterGet.properties.parameterGroup.syncStatus
        Write-Log "  Cluster provisioning: $clusterState | parameterGroup.syncStatus: $syncStatus (elapsed ${elapsed}s)"
        if ($clusterState -in @('Succeeded','Failed','Canceled')) { break }
    } catch {
        Write-Log "  GET cluster failed: $($_.Exception.Message)"
    }
}

if ($clusterState -ne 'Succeeded') {
    throw "Cluster did not reach Succeeded state after attaching parameter group (last state: $clusterState)."
}

Write-Log "==== Set HorizonDB Parameter Group (local test) complete ===="
