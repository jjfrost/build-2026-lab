#=== Start Block Settings ===============================================================
#Stage: Tearing Down 
#Name: Purge AI Resources
#Execute Script in Cloud Platform
#Language	PowerShell
#Blocking	No
#Timeout	5 Minutes
#Retries	1
#Error Action	Log
#=== End Block Settings ===============================================================

# Query for all OpenAI deployment accounts in the subscription or resource group, depending on the context scope.
$AIObjs = Get-AzResource -ResourceType "Microsoft.CognitiveServices/accounts"

# Get the model deployments for each OpenAI account and store them in an array

$AIObjArray = @()
foreach ($AIobj in $AIObjs) {
    $AIObjArray += Get-AzCognitiveServicesAccountDeployment -ResourceGroupName $AIobj.ResourceGroupName -AccountName $AIobj.Name
}

#Loop through each model deployment and delete it
foreach ($Deployment in $AIObjArray) {
    Remove-AzCognitiveServicesAccountDeployment -ResourceId $deployment.Id -Force    
}


# Loop through each Open AI deployment account and delete it
foreach ($account in $AIObjs) {
    Remove-AzResource -ResourceId $account.ResourceId -Force
    Write-Output "Deleted OpenAI deployment: $($account.Name)"
}