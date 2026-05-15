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