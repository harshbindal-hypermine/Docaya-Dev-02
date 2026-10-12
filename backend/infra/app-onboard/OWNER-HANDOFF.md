# Docaya owner deployment handoff

This handoff lets a subscription Owner finish the Azure resources that are still blocked by provider registration.

Existing resources that this deployment reuses:

- Resource group: `rg-hmai-docayapoc-hp05`
- Storage account: `stdocayadev09e7` in `eastus`
- Static Web App: `swa-docaya-dev-09e7` in `eastus2`
- Static Web App URL: `https://yellow-island-0fec9a10f.6.azurestaticapps.net`

## 1. Register required providers

Provider registration is a subscription-level Azure action. It cannot be expressed as a normal Bicep resource because the providers must be registered before ARM can deploy those resource types.

Run this with an account that can register providers at subscription scope:

```powershell
$sub = "5f45e10c-751a-406e-8ca9-bfb25ed43bf4"

az provider register --subscription $sub --namespace Microsoft.App --wait
az provider register --subscription $sub --namespace Microsoft.ContainerRegistry --wait
az provider register --subscription $sub --namespace Microsoft.Sql --wait
az provider register --subscription $sub --namespace Microsoft.ServiceBus --wait
az provider register --subscription $sub --namespace Microsoft.Search --wait
az provider register --subscription $sub --namespace Microsoft.Insights --wait
az provider register --subscription $sub --namespace Microsoft.OperationalInsights --wait
az provider register --subscription $sub --namespace Microsoft.ManagedIdentity --wait
```

Confirm registration:

```powershell
$providers = @(
  "Microsoft.App",
  "Microsoft.ContainerRegistry",
  "Microsoft.Sql",
  "Microsoft.ServiceBus",
  "Microsoft.Search",
  "Microsoft.Insights",
  "Microsoft.OperationalInsights",
  "Microsoft.ManagedIdentity"
)

$providers | ForEach-Object {
  az provider show --subscription $sub --namespace $_ --query "{namespace:namespace,state:registrationState}" -o table
}
```

## 2. Validate the remaining-resource template

The Bicep file is resource-group scoped and avoids recreating Storage or the Static Web App.

```powershell
az bicep build --file .\infra\app-onboard\owner-remaining-rg.bicep
```

## 3. Run what-if

Do not place the `apiInternalSecret` value in a file. Pass it only as a secure parameter at deployment time.

```powershell
$sub = "5f45e10c-751a-406e-8ca9-bfb25ed43bf4"
$rg = "rg-hmai-docayapoc-hp05"
$apiInternalSecret = Read-Host "API internal secret" -AsSecureString

az deployment group what-if `
  --subscription $sub `
  --resource-group $rg `
  --name owner-remaining-docaya-09e7 `
  --template-file .\infra\app-onboard\owner-remaining-rg.bicep `
  --parameters .\infra\app-onboard\owner-remaining-rg.parameters.example.json `
  --parameters apiInternalSecret=$apiInternalSecret
```

## 4. Deploy remaining resources

```powershell
$sub = "5f45e10c-751a-406e-8ca9-bfb25ed43bf4"
$rg = "rg-hmai-docayapoc-hp05"
$apiInternalSecret = Read-Host "API internal secret" -AsSecureString

az deployment group create `
  --subscription $sub `
  --resource-group $rg `
  --name owner-remaining-docaya-09e7 `
  --template-file .\infra\app-onboard\owner-remaining-rg.bicep `
  --parameters .\infra\app-onboard\owner-remaining-rg.parameters.example.json `
  --parameters apiInternalSecret=$apiInternalSecret
```

Expected remaining resources:

- Log Analytics: `log-docaya-dev-09e7`
- Application Insights: `appi-docaya-dev-09e7`
- Service Bus: `sb-docaya-dev-09e7`
- Azure AI Search: `srch-docaya-dev-09e7`
- SQL server/database: `sql-docaya-dev-09e7` / `sqldb-docaya-dev-09e7`
- Container Registry: `crdocayadev09e7`
- Container Apps environment/API: `cae-docaya-dev-09e7` / `ca-docaya-dev-09e7`
- Function App/plan: `func-docaya-dev-09e7` / `plan-func-docaya-dev-09e7`
- Managed identity data-plane role assignments for API and Functions

Note: `apiContainerImage` currently points to the placeholder Microsoft sample image. Replace it with an immutable Docaya API image digest after the API image is built and pushed to ACR.
