#=== Start Block Settings ===============================================================
#Stage: First Displayable
#Name: Deployment Validation
#Execute Script in Cloud Platform
#Language	PowerShell
#Blocking	No
#Delay	7500 Seconds
#Timeout	20 Minutes
#Retries	0
#Error Action	End Lab
#=== End Block Settings ===============================================================

# Retrieve deployment info
$Deployment = Get-AzResourceGroupDeployment -ResourceGroup "@lab.CloudResourceGroup(ResourceGroup1).Name"

# Count successful deployments
$SucceededCount = ($Deployment | Where-Object { $_.ProvisioningState -eq 'Succeeded' }).Count

# Validate deployment success
if ($SucceededCount -ne 1) {
    throw "Error: Deployment Failed"
}