# Define log file path 
$logDir = 'C:\Lab\Logs'
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
$logFile = Join-Path $logDir ("lab-log_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))

# Simple helper function for logging
function Write-Log {
  param([string]$Message)
  $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  "$timestamp $Message" | Out-File -FilePath $logFile -Append -Encoding UTF8
}

Write-Log "==== Script start ===="

# ================== Inputs (Skillable tokens) ==================
$clientId             = "@lab.CloudSubscription.AppId"
$clientSecret         = "@lab.CloudSubscription.AppSecret"
$tenantId             = "@lab.CloudSubscription.TenantId"
$subscriptionId       = "@lab.CloudSubscription.Id"
$rgName               = "@lab.CloudResourceGroup(ResourceGroup1).Name"
$aadUserPrincipalName = "@lab.CloudPortalCredential(User1).Username"

# Your Bicep file
$bicepPath      = "C:\Lab\Infra\deploy.bicep"
# Where to write compiled JSON
$templateJson   = [System.IO.Path]::ChangeExtension($bicepPath, ".json")

# Optional parameters to your template
$tplParams      = @{ restore = $false }

# ================== Fast, deterministic environment ==================
$ErrorActionPreference = 'Stop'
$env:AZURE_CONFIG_DIR = "C:\Temp\.azure"
if (-not (Test-Path $env:AZURE_CONFIG_DIR)) { New-Item -ItemType Directory -Force $env:AZURE_CONFIG_DIR | Out-Null }
netsh winhttp reset proxy | Out-Null
Remove-Item Env:HTTPS_PROXY, Env:HTTP_PROXY, Env:ALL_PROXY, Env:NO_PROXY -ErrorAction SilentlyContinue
$env:NO_PROXY="*"
[System.Net.WebRequest]::DefaultWebProxy = New-Object System.Net.WebProxy
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ================== Compile Bicep -> JSON (On-The-Fly) ==================
function Compile-Bicep {
  param([string] $BicepPath, [string] $OutJson)

  Write-Log "Compiling Bicep file: $BicepPath"

  if (Get-Command az -ErrorAction SilentlyContinue) {
    Write-Log "Using az bicep CLI"
    
    $env:AZURE_BICEP_USE_BINARY_FROM_PATH = "false"
    $env:AZURE_CORE_ONLY_SHOW_ERRORS = "true"
    
    if (-not (Test-Path "C:\Temp")) { New-Item -ItemType Directory -Path "C:\Temp" -Force | Out-Null }
    
    # FIX: Use unique file IDs to prevent background processes from locking the text files
    $tempId = [guid]::NewGuid().ToString().Substring(0,8)
    $outLog = "C:\Temp\bicep_stdout_$tempId.txt"
    $errLog = "C:\Temp\bicep_stderr_$tempId.txt"
    
    $azProcess = Start-Process -FilePath "az" `
      -ArgumentList "bicep","build","--file",$BicepPath,"--outfile",$OutJson,"--only-show-errors" `
      -NoNewWindow -PassThru -Wait `
      -RedirectStandardOutput $outLog `
      -RedirectStandardError $errLog
    
    $exitCode = $azProcess.ExitCode
    
    # Read and safely remove output files
    if (Test-Path $outLog) { Write-Log "Bicep stdout: $(Get-Content $outLog -Raw)"; Remove-Item $outLog -ErrorAction SilentlyContinue }
    if (Test-Path $errLog) { Write-Log "Bicep stderr: $(Get-Content $errLog -Raw)"; Remove-Item $errLog -ErrorAction SilentlyContinue }
    
    if (Test-Path $OutJson) {
      Write-Log "Az bicep compilation successful"
      return
    }
    
    throw "Az bicep compilation failed with exit code: $exitCode"
  }

  throw "Azure CLI ('az') is not available to compile the Bicep file."
}

try {
  Compile-Bicep -BicepPath $bicepPath -OutJson $templateJson
  
  $templateObject = Get-Content -Raw -Path $templateJson | ConvertFrom-Json
  if (-not $templateObject) { throw "Failed to parse compiled template JSON" }
  Write-Log "Template loaded successfully"
} catch {
  Write-Log "Error during Bicep compilation or template loading: $_"
  throw
}

# ================== Get ARM token ==================
Write-Log "Requesting ARM Token..."
$ct = 'application/x-www-form-urlencoded'
$tokMgmt = Invoke-RestMethod -Method POST `
  -Uri "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token" `
  -ContentType $ct -Body @{
    client_id     = $clientId
    client_secret = $clientSecret
    scope         = 'https://management.azure.com/.default'
    grant_type    = 'client_credentials'
  }

$armHeaders = @{
  Authorization = "Bearer $($tokMgmt.access_token)"
  "Content-Type" = "application/json"
}

# ================== Purge deleted OpenAI accounts ==================
Write-Log "Checking for deleted OpenAI accounts to purge"
try {
  $listDeletedUri = "https://management.azure.com/subscriptions/$subscriptionId/providers/Microsoft.CognitiveServices/deletedAccounts`?api-version=2023-05-01"
  $deletedAccountsResponse = Invoke-RestMethod -Method GET -Uri $listDeletedUri -Headers $armHeaders
  
  $openAIAccounts = @()
  if ($deletedAccountsResponse.value) {
    $openAIAccounts = @($deletedAccountsResponse.value | Where-Object { $_.kind -eq 'OpenAI' })
  }
  
  if ($openAIAccounts -and $openAIAccounts.Count -gt 0) {
    Write-Log "Found $($openAIAccounts.Count) deleted OpenAI account(s) to purge"
    
    foreach ($account in $openAIAccounts) {
      $accountName = if ($account.name) { $account.name } else { ($account.id -split '/')[-1] }
      $location = if ($account.location) { $account.location } else { $account.properties.location }
      
      Write-Log "Purging deleted OpenAI account: $accountName in location: $location"
      $purgeUri = "https://management.azure.com/subscriptions/$subscriptionId/providers/Microsoft.CognitiveServices/locations/$location/resourceGroups/$rgName/deletedAccounts/$accountName`?api-version=2023-05-01"
      
      try {
        Invoke-RestMethod -Method DELETE -Uri $purgeUri -Headers $armHeaders | Out-Null
        Write-Log "Successfully purged: $accountName"
      } catch {
        $altPurgeUri = "https://management.azure.com/subscriptions/$subscriptionId/providers/Microsoft.CognitiveServices/locations/$location/deletedAccounts/$accountName`?api-version=2023-05-01"
        try {
          Invoke-RestMethod -Method DELETE -Uri $altPurgeUri -Headers $armHeaders | Out-Null
          Write-Log "Successfully purged using alternative URI: $accountName"
        } catch {
          Write-Log "Warning: Could not purge $accountName - $($_.Exception.Message)"
        }
      }
    }
    
    Write-Log "Waiting for purge operations to complete across the control plane..."
    $maxPurgeWaitSeconds = 300 # 5 minutes max wait
    $purgePollInterval = 15
    $purgeWaitElapsed = 0

    do {
      Start-Sleep -Seconds $purgePollInterval
      $purgeWaitElapsed += $purgePollInterval
      
      $checkDeletedResponse = Invoke-RestMethod -Method GET -Uri $listDeletedUri -Headers $armHeaders
      $remainingAccounts = @()
      if ($checkDeletedResponse.value) {
        $remainingAccounts = @($checkDeletedResponse.value | Where-Object { $_.kind -eq 'OpenAI' })
      }
      
      Write-Log "Polling purge status... $($remainingAccounts.Count) account(s) still in transitioning/deleted state. Elapsed: ${purgeWaitElapsed}s"
    } while ($remainingAccounts.Count -gt 0 -and $purgeWaitElapsed -lt $maxPurgeWaitSeconds)

    if ($remainingAccounts.Count -gt 0) {
      Write-Log "Warning: Purge timeout reached after $maxPurgeWaitSeconds seconds. Proceeding anyway, but naming conflicts may occur."
    } else {
      Write-Log "Purge confirmed. All deleted OpenAI namespaces have been cleared."
    }
  } else {
    Write-Log "No deleted OpenAI accounts found to purge"
  }
} catch {
  Write-Log "Warning: Error checking for deleted accounts - $($_.Exception.Message)"
}

# ================== Submit deployment via ARM REST ==================
$armParamObj = @{}
foreach ($k in $tplParams.Keys) { $armParamObj[$k] = @{ value = $tplParams[$k] } }

$deploymentName = "lab-" + (Get-Date -Format "yyyyMMdd-HHmmss")
$deployUri = "https://management.azure.com/subscriptions/$subscriptionId/resourcegroups/$rgName/providers/Microsoft.Resources/deployments/$deploymentName`?api-version=2021-04-01"

$deployBody = @{
  properties = @{
    mode       = "Incremental"
    template   = $templateObject
    parameters = $armParamObj
  }
} | ConvertTo-Json -Depth 100

Write-Log "Starting deployment: $deploymentName"

try {
  $start = Invoke-RestMethod -Method PUT -Uri $deployUri -Headers $armHeaders -Body $deployBody
  Write-Log "Deployment initiated successfully. Provisioning state: $($start.properties.provisioningState)"
  
  # ================== Poll deployment status ==================
  $maxWaitMinutes = 40
  $pollIntervalSeconds = 15
  $maxPolls = ($maxWaitMinutes * 60) / $pollIntervalSeconds
  $pollCount = 0
  
  Write-Log "Polling deployment status (max wait: $maxWaitMinutes minutes)"
  
  do {
    Start-Sleep -Seconds $pollIntervalSeconds
    $pollCount++
    
    $status = Invoke-RestMethod -Method GET -Uri $deployUri -Headers $armHeaders
    $provisioningState = $status.properties.provisioningState
    
    Write-Log "Poll $pollCount : Provisioning state = $provisioningState"
    
    if ($provisioningState -eq "Succeeded") {
      Write-Log "==== Deployment succeeded ===="
      Write-Host "Deployment completed successfully!" -ForegroundColor Green
      
      $serverName = $status.properties.outputs.serverName.value
      Write-Log "PostgreSQL Server Name: $serverName"
      break
    }
    
    if ($provisioningState -eq "Failed" -or $provisioningState -eq "Canceled") {
      Write-Log "==== Deployment failed ===="
      Write-Log "Top-level Error details: $($status.properties.error | ConvertTo-Json -Depth 10)"
      
      $platformErrorMessage = "Deployment failed ($provisioningState)."

      Write-Log "Fetching detailed deployment operations to find the exact resource failure..."
      $opsUri = "https://management.azure.com/subscriptions/$subscriptionId/resourcegroups/$rgName/providers/Microsoft.Resources/deployments/$deploymentName/operations?api-version=2021-04-01"
      
      try {
        $opsResponse = Invoke-RestMethod -Method GET -Uri $opsUri -Headers $armHeaders
        $failedOps = @($opsResponse.value | Where-Object { $_.properties.provisioningState -eq 'Failed' })
        
        if ($failedOps.Count -gt 0) {
            Write-Log "Detailed Failed Resource Operations: $($failedOps | ConvertTo-Json -Depth 10)"
            $firstFail = $failedOps[0]
            $resourceName = $firstFail.properties.targetResource.resourceName
            
            $failMsg = $firstFail.properties.statusMessage.error.message
            if (-not $failMsg) { $failMsg = $firstFail.properties.statusMessage.message }
            if (-not $failMsg) { $failMsg = "Check lab logs for raw statusMessage." }

            $platformErrorMessage += " Resource '$resourceName' failed: $failMsg"
        } else {
            Write-Log "No specific failed operations found in the deployment operations log."
            if ($status.properties.error.message) {
                $platformErrorMessage += " Reason: $($status.properties.error.message)"
            }
        }
      } catch {
        Write-Log "Warning: Could not retrieve detailed deployment operations: $($_.Exception.Message)"
        if ($status.properties.error.message) {
            $platformErrorMessage += " Reason: $($status.properties.error.message)"
        }
      }

      throw $platformErrorMessage
    }
    
    if ($pollCount -ge $maxPolls) {
      throw "Deployment timed out after $maxWaitMinutes minutes"
    }
    
  } while ($provisioningState -in @("Running", "Accepted", "Creating", "Updating"))
    
} catch {
  Write-Log "==== FATAL ERROR ENCOUNTERED ===="
  Write-Log "Error details: $($_.Exception.Message)"
  
  # FIX: Wrapped the stream reader so it doesn't crash the catch block
  if ($null -ne $_.Exception.Response) {
    try {
      $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
      Write-Log "Response body: $($reader.ReadToEnd())"
    } catch {
      Write-Log "Could not extract detailed HTTP response body."
    }
  }
  throw
}

Write-Log "==== Script end ===="