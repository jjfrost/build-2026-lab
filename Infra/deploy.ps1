param(
    [Parameter(Mandatory)]
    [string]$ResourceGroup,

    [string]$TemplateFile = "deploy-hdb.bicep"
)

az deployment group create --resource-group $ResourceGroup --template-file $TemplateFile --debug