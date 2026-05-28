$ErrorActionPreference = 'Stop'

function Get-AzdValue {
    param([Parameter(Mandatory = $true)][string]$Name)

    $value = azd env get-value $Name 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($value)) {
        return $null
    }

    return $value.Trim().Trim('"')
}

function Require-Value {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $false)][string]$Fallback = $null
    )

    $value = Get-AzdValue -Name $Name
    if ([string]::IsNullOrWhiteSpace($value)) {
        $value = $Fallback
    }

    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Missing required value: $Name"
    }

    return $value
}

function Get-EnvFileValue {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if (-not (Test-Path $Path)) {
        return $null
    }

    foreach ($line in Get-Content -Path $Path) {
        if ($line -match "^\s*$Name=(.*)$") {
            return $matches[1].Trim()
        }
    }

    return $null
}

Write-Host 'Resolving azd environment values...'
$resourceGroup = Require-Value -Name 'AZURE_RESOURCE_GROUP' -Fallback $env:AZURE_RESOURCE_GROUP
$envPath = Join-Path (Get-Location) '.env'

$pgHost = Require-Value -Name 'AZURE_PG_HOST'
$pgName = Require-Value -Name 'AZURE_PG_NAME' -Fallback 'postgres'
$pgUser = Require-Value -Name 'AZURE_PG_USER'
$pgPassword = Get-AzdValue -Name 'AZURE_PG_PASSWORD'
if ([string]::IsNullOrWhiteSpace($pgPassword)) {
    $pgPassword = Get-EnvFileValue -Path $envPath -Name 'AZURE_PG_PASSWORD'
}
if ([string]::IsNullOrWhiteSpace($pgPassword)) {
    throw 'Missing required value: AZURE_PG_PASSWORD. Re-run azd provision after updating Infra/main.bicep outputs, or set it manually with: azd env set AZURE_PG_PASSWORD <password>'
}
$pgPort = Require-Value -Name 'AZURE_PG_PORT' -Fallback '5432'
$pgSslMode = Require-Value -Name 'AZURE_PG_SSLMODE' -Fallback 'require'

$openAIServiceName = Require-Value -Name 'AZURE_OPENAI_SERVICE_NAME'
$openAIEndpoint = Require-Value -Name 'AZURE_OPENAI_ENDPOINT'
$openAIDeployment = Require-Value -Name 'AZURE_OPENAI_DEPLOYMENT' -Fallback 'gpt-5'
$embedDeployment = Require-Value -Name 'AZURE_EMBED_DEPLOYMENT' -Fallback 'text-embedding-3-small'
$apiVersion = Require-Value -Name 'AZURE_API_VERSION' -Fallback '2025-03-01-preview'

Write-Host 'Fetching Azure OpenAI key...'
$openAIKey = az cognitiveservices account keys list `
    --name $openAIServiceName `
    --resource-group $resourceGroup `
    --query key1 -o tsv
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($openAIKey)) {
    throw 'Failed to fetch AZURE_OPENAI_KEY from Cognitive Services.'
}

Write-Host 'Writing local .env file...'
$envContent = @(
    "AZURE_OPENAI_ENDPOINT=$openAIEndpoint"
    "AZURE_OPENAI_KEY=$openAIKey"
    "AZURE_OPENAI_DEPLOYMENT=$openAIDeployment"
    "AZURE_EMBED_DEPLOYMENT=$embedDeployment"
    "AZURE_API_VERSION=$apiVersion"
    ''
    "AZURE_PG_HOST=$pgHost"
    "AZURE_PG_NAME=$pgName"
    "AZURE_PG_USER=$pgUser"
    "AZURE_PG_PASSWORD=$pgPassword"
    "AZURE_PG_PORT=$pgPort"
    "AZURE_PG_SSLMODE=$pgSslMode"
) -join [Environment]::NewLine

Set-Content -Path $envPath -Value $envContent -Encoding UTF8
Write-Host "Created/updated $envPath"
Write-Host 'postprovision completed successfully.'
