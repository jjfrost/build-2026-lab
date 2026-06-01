#=== Start Block Settings =====================================================
#Stage: First Displayable
#Name: Set HorizonDB Parameter Group
#Execute Script in Virtual Machine
#Machine	Win11-Pro-Base-VM
#Language	PowerShell
#Blocking	Yes
#Delay	10 Seconds
#Timeout	30 Minutes
#Retries	0
#Error Action	Notify User
#Error Notification	Set HorizonDB Parameter Group failed
#=== End Block Settings =======================================================

# =============================================================================
# Set HorizonDB Parameter Group
# -----------------------------------------------------------------------------
# Runs in the Skillable Lab Lifecycle (After VM Build) stage, AFTER
# 5_set_firewall_rules.ps1 has completed.
#
# This script:
#   1. Receives Skillable @lab tokens (subscription, RG, SP creds).
#   2. Acquires an ARM access token via the lab's service-principal
#      (client_credentials flow).
#   3. Reads the outputs of the most recent successful 'lab-*' ARM deployment
#      in the resource group to obtain the HorizonDB cluster name and version.
#   4. Creates a HorizonDB parameter group via ARM REST that:
#        - Allow-lists extensions: azure_ai, vector, age, pg_diskann, pg_fts
#          (parameter: azure.extensions)
#        - Enables AGE in shared_preload_libraries
#   5. Attaches the parameter group to the HorizonDB cluster via PATCH.
#
# Docs:
#   https://learn.microsoft.com/azure/horizondb/server-parameters/how-to-parameter-groups-create
#   API version: 2026-01-20-preview
# =============================================================================

$ErrorActionPreference = "Stop"

# ---------- Logging ----------------------------------------------------------
$logDir = 'C:\Logs'
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$logFile = Join-Path $logDir ("set_horizondb_parameter_group_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))

function Write-Log {
    param([string]$Message)
    $line = "{0} {1}" -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"), $Message
    $line | Out-File -FilePath $logFile -Append -Encoding UTF8
    Write-Output $line
}

Write-Log "==== Set HorizonDB Parameter Group start ===="

# ================== Inputs (Skillable tokens) ================================
$clientId          = "@lab.CloudSubscription.AppId"
$clientSecret      = "@lab.CloudSubscription.AppSecret"
$tenantId          = "@lab.CloudSubscription.TenantId"
$subscriptionId    = "@lab.CloudSubscription.Id"
$resourceGroupName = "@lab.CloudResourceGroup(ResourceGroup1).Name"

Write-Log "Tenant:        $tenantId"
Write-Log "Subscription:  $subscriptionId"
Write-Log "ResourceGroup: $resourceGroupName"

# ================== Configuration ============================================
$horizonApiVersion  = "2026-01-20-preview"
$parameterGroupName = "lab-paramgroup"
$applyImmediately   = $true

# Extensions to allow-list (azure.extensions, comma-separated, no spaces)
$allowedExtensions  = @('azure_ai','vector','age','pg_diskann','pg_fts')

# Libraries to enable in shared_preload_libraries (comma-separated, no spaces)
$preloadLibraries   = @('age')

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
Write-Log "Locating latest successful ARM deployment in $resourceGroupName..."
$deploymentsUrl  = "https://management.azure.com/subscriptions/$subscriptionId/resourcegroups/$resourceGroupName/providers/Microsoft.Resources/deployments?api-version=2021-04-01"
$deploymentsResp = Invoke-RestMethod -Uri $deploymentsUrl -Headers $headers -Method Get

$latestDeployment = $deploymentsResp.value |
    Where-Object {
        $_.properties.provisioningState -eq 'Succeeded' -and
        ($_.name -like 'lab-*' -or $_.properties.outputs.clusterName)
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

$clusterName = Get-Output $outputs 'clusterName'
Write-Log "HorizonDB cluster: $clusterName"

# ================== Get cluster details (location, pgVersion) ================
$clusterUri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.HorizonDb/clusters/$clusterName`?api-version=$horizonApiVersion"
Write-Log "Fetching cluster details..."
$clusterResp = Invoke-RestMethod -Uri $clusterUri -Headers $headers -Method Get

$clusterLocation = $clusterResp.location
$clusterVersion  = $clusterResp.properties.version
Write-Log "Cluster location: $clusterLocation"
Write-Log "Cluster version:  $clusterVersion"

# Parse pgVersion (the parameter group requires an integer PG major version)
$pgVersion = 0
if ($clusterVersion) {
    # version could be "17", "17.0", etc. Take leading integer.
    if ($clusterVersion -match '^\s*(\d+)') {
        $pgVersion = [int]$Matches[1]
    }
}
if ($pgVersion -le 0) {
    $pgVersion = 17  # sensible default for HorizonDB preview
    Write-Log "Could not parse pgVersion from cluster; defaulting to $pgVersion"
}
Write-Log "Parameter group pgVersion: $pgVersion"

# ================== Build parameter group payload ============================
$extensionsValue = ($allowedExtensions -join ',')
$preloadValue    = ($preloadLibraries -join ',')

Write-Log "azure.extensions          = $extensionsValue"
Write-Log "shared_preload_libraries  = $preloadValue"

$pgBody = @{
    location   = $clusterLocation
    properties = @{
        description       = 'Lab parameter group: allow-listed extensions and AGE preload'
        pgVersion         = $pgVersion
        applyImmediately  = $applyImmediately
        parameters        = @(
            @{ name = 'azure.extensions';         value = $extensionsValue }
            @{ name = 'shared_preload_libraries'; value = $preloadValue   }
        )
    }
} | ConvertTo-Json -Depth 8

$pgUri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.HorizonDb/parameterGroups/$parameterGroupName`?api-version=$horizonApiVersion"

Write-Log "Creating/updating parameter group: $parameterGroupName"
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
$parameterGroupId = "/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.HorizonDb/parameterGroups/$parameterGroupName"

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
Write-Log "Attaching parameter group to cluster $clusterName..."

$attachBody = @{
    properties = @{
        parameterGroup = @{
            id               = $parameterGroupId
            applyImmediately = $applyImmediately
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

Write-Log "==== Set HorizonDB Parameter Group complete ===="
