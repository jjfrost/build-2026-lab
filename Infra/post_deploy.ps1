# ── Post-deployment: HorizonDB firewall rules, database, and extensions ──
# These replicate what Flexible Server does natively in Bicep, but for HorizonDB
# which requires az rest (firewall) and psql (database/extensions).

$resourceGroupName = ""
$apiVersion = "2026-01-20-preview"

# Get the HorizonDB cluster name from the deployment output
$clusterName = az deployment group show --resource-group $resourceGroupName --name "deploy" --query "properties.outputs.clusterName.value" -o tsv
$clusterFqdn = az deployment group show --resource-group $resourceGroupName --name "deploy" --query "properties.outputs.clusterFqdn.value" -o tsv
$adminLogin = az deployment group show --resource-group $resourceGroupName --name "deploy" --query "properties.outputs.adminLogin.value" -o tsv
$subscriptionId = az account show --query id -o tsv

Write-Host "Cluster: $clusterName | FQDN: $clusterFqdn"

# Helper: write JSON body to temp file for az rest
$tempDir = "C:\Lab\Temp"

# ── 1. Firewall rule: Allow Azure services (0.0.0.0 - 0.0.0.0) ──
Write-Host "=== Adding firewall rule: AllowAzureServices ==="
$fwAzureFile = Join-Path $tempDir "fw_azure.json"
@{properties = @{startIpAddress = "0.0.0.0"; endIpAddress = "0.0.0.0"; description = "Allow Azure services"}} | ConvertTo-Json -Depth 3 | Out-File -FilePath $fwAzureFile -Encoding utf8
az rest --method PUT `
  --url "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.HorizonDb/clusters/$clusterName/pools/pool1/firewallRules/AllowAzureServices?api-version=$apiVersion" `
  --body "@$fwAzureFile"

# ── 2. Firewall rule: Allow all IPs (lab only) ──
Write-Host "=== Adding firewall rule: AllowAll (lab purposes only) ==="
$fwAllFile = Join-Path $tempDir "fw_all.json"
@{properties = @{startIpAddress = "0.0.0.0"; endIpAddress = "255.255.255.255"; description = "Allow all for lab"}} | ConvertTo-Json -Depth 3 | Out-File -FilePath $fwAllFile -Encoding utf8
az rest --method PUT `
  --url "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.HorizonDb/clusters/$clusterName/pools/pool1/firewallRules/AllowAll?api-version=$apiVersion" `
  --body "@$fwAllFile"




