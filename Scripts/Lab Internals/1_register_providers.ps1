#=== Start Block Settings =====================================================
#Stage: Pre-Build
#Name: Register Resource Providers
#Execute Script in Cloud Platform
#Language	PowerShell
#Blocking	No
#Delay	10 Seconds
#Timeout	10 Minutes
#Retries	2
#Error Action	Log
#=== End Block Settings =======================================================

$ResourceProviders = @(
    'Microsoft.CognitiveServices',
    'Microsoft.DBforPostgreSQL',
    'Microsoft.HorizonDB'
)

foreach ($Provider in $ResourceProviders) {
    Register-AzResourceProvider -ProviderNamespace $Provider
    do {
        $ProviderInfo = Get-AzResourceProvider -ProviderNamespace $Provider
        Start-Sleep -Seconds 5
    } until ($ProviderInfo.RegistrationState -eq 'Registered')
}