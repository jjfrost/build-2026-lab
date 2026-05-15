# =============================================================================
# Set HorizonDB Firewall Rules
# -----------------------------------------------------------------------------
# Runs in the Skillable Lab Lifecycle (After VM Build) stage, AFTER
# deployment_build2026.ps1 has completed its Bicep deployment AND
# replace_tokens.ps1 has produced C:\Lab\.env.
#
# This script:
#   1. Receives Skillable @lab tokens (subscription, RG, SP creds).
#   2. Acquires an ARM access token via the lab's service-principal
#      (client_credentials flow).
#   3. Reads the outputs of the most recent successful 'lab-*' ARM deployment
#      in the resource group (produced by infra5/deploy.bicep) to obtain the
#      HorizonDB cluster name.
#   4. Creates HorizonDB firewall rules via ARM REST:
#         - AllowAzureServices (0.0.0.0 / 0.0.0.0)
#         - AllowAll           (0.0.0.0 / 255.255.255.255)  [lab use only]
# =============================================================================

$ErrorActionPreference = "Stop"

# ---------- Logging ----------------------------------------------------------
$logDir = 'C:\Logs'
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$logFile = Join-Path $logDir ("post_deploy_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))

function Write-Log {
    param([string]$Message)
    $line = "{0} {1}" -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"), $Message
    $line | Out-File -FilePath $logFile -Append -Encoding UTF8
    Write-Output $line
}

Write-Log "==== Set HorizonDB Firewall Rules start ===="

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
$clusterFqdn = Get-Output $outputs 'clusterFqdn'

Write-Log "HorizonDB cluster: $clusterName"
Write-Log "HorizonDB FQDN:    $clusterFqdn"

# ================== Apply HorizonDB firewall rules ===========================
$horizonApiVersion = "2026-01-20-preview"
$fwBaseUri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.HorizonDb/clusters/$clusterName/pools/pool1/firewallRules"

function Set-HorizonFirewallRule {
    param(
        [string]$RuleName,
        [string]$StartIp,
        [string]$EndIp,
        [string]$Description
    )

    Write-Log "Creating firewall rule: $RuleName  ($StartIp - $EndIp)"

    $body = @{
        properties = @{
            startIpAddress = $StartIp
            endIpAddress   = $EndIp
            description    = $Description
        }
    } | ConvertTo-Json -Depth 5

    $uri = "$fwBaseUri/$RuleName`?api-version=$horizonApiVersion"

    try {
        $resp = Invoke-RestMethod -Method PUT -Uri $uri -Headers $headers -Body $body
        $state = $resp.properties.provisioningState
        Write-Log "  -> Submitted. Provisioning state: $state"
        return $resp
    } catch {
        Write-Log "  !! Failed to create rule ${RuleName}: $($_.Exception.Message)"
        if ($null -ne $_.Exception.Response) {
            try {
                $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                Write-Log "  Response body: $($reader.ReadToEnd())"
            } catch { }
        }
        throw
    }
}

# 1. Allow Azure services
Set-HorizonFirewallRule -RuleName 'AllowAzureServices' `
    -StartIp '0.0.0.0' -EndIp '0.0.0.0' `
    -Description 'Allow Azure services' | Out-Null

# 2. Allow all IPs (lab purposes only)
Set-HorizonFirewallRule -RuleName 'AllowAll' `
    -StartIp '0.0.0.0' -EndIp '255.255.255.255' `
    -Description 'Allow all for lab' | Out-Null

Write-Log "==== Set HorizonDB Firewall Rules complete ===="