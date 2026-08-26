#!/usr/bin/env bash
set -euo pipefail

operation="${1:-validate}"
case "$operation" in validate|what-if|apply-base|apply) ;; *) echo "operation must be validate, what-if, apply-base or apply" >&2; exit 2 ;; esac

required=(AZURE_SUBSCRIPTION_ID AZURE_TENANT_ID AZURE_LOCATION AZURE_UNIQUE_SUFFIX AZURE_SQL_ADMIN_LOGIN AZURE_SQL_ADMIN_OBJECT_ID AZURE_BUDGET_EMAIL AZURE_BUDGET_START_DATE AZURE_MONTHLY_BUDGET_AMOUNT)
for name in "${required[@]}"; do
  if [[ -z "${!name:-}" ]]; then echo "$name is required" >&2; exit 2; fi
done
if [[ ! "$AZURE_UNIQUE_SUFFIX" =~ ^[a-z0-9]{8}$ ]]; then
  echo "AZURE_UNIQUE_SUFFIX must be exactly 8 lowercase letters or digits" >&2; exit 2
fi
if [[ ! "$AZURE_SQL_ADMIN_OBJECT_ID" =~ ^[0-9a-fA-F-]{36}$ ]] || [[ "$AZURE_SQL_ADMIN_OBJECT_ID" == 00000000-0000-0000-0000-000000000000 ]]; then
  echo "AZURE_SQL_ADMIN_OBJECT_ID must be a non-placeholder UUID" >&2; exit 2
fi
if [[ ! "$AZURE_SUBSCRIPTION_ID" =~ ^[0-9a-fA-F-]{36}$ ]] ||
   [[ ! "$AZURE_TENANT_ID" =~ ^[0-9a-fA-F-]{36}$ ]]; then
  echo "AZURE_SUBSCRIPTION_ID and AZURE_TENANT_ID must be UUIDs" >&2; exit 2
fi
if [[ ! "$AZURE_BUDGET_START_DATE" =~ ^[0-9]{4}-[0-9]{2}-01T00:00:00Z$ ]]; then
  echo "AZURE_BUDGET_START_DATE must be the first UTC day of a month" >&2; exit 2
fi
if [[ ! "$AZURE_MONTHLY_BUDGET_AMOUNT" =~ ^[1-9][0-9]{0,4}$ ]]; then
  echo "AZURE_MONTHLY_BUDGET_AMOUNT must be an explicit positive integer in the subscription billing currency" >&2; exit 2
fi
api_min_replicas="${AZURE_API_MIN_REPLICAS:-0}"
if [[ "$api_min_replicas" != "0" && "$api_min_replicas" != "1" ]]; then
  echo "AZURE_API_MIN_REPLICAS must be 0 or 1" >&2; exit 2
fi
api_image_tag="${AZURE_API_CONTAINER_IMAGE_TAG:-${GITHUB_SHA:-preview}}"
if [[ "$operation" == "apply" && "$api_image_tag" == "preview" ]]; then
  api_image_tag="manual-$(date -u +%Y%m%d%H%M%S)"
fi
if [[ ! "$api_image_tag" =~ ^[a-z0-9][a-z0-9._-]{6,127}$ ]]; then
  echo "API image tag must be 7-128 lowercase tag-safe characters" >&2; exit 2
fi

actual_subscription="$(az account show --query id --output tsv)"
actual_tenant="$(az account show --query tenantId --output tsv)"
if [[ "$actual_subscription" != "$AZURE_SUBSCRIPTION_ID" || "$actual_tenant" != "$AZURE_TENANT_ID" ]]; then
  echo "Azure CLI is authenticated to a different subscription or tenant" >&2; exit 3
fi
expected_resource_group="rg-rf-dev-${AZURE_UNIQUE_SUFFIX}"
while IFS= read -r existing_dev_group; do
  if [[ -n "$existing_dev_group" && "$existing_dev_group" != "$expected_resource_group" ]]; then
    echo "A different dev environment already exists: ${existing_dev_group}. AZURE_UNIQUE_SUFFIX is immutable." >&2
    exit 3
  fi
done < <(az group list --query "[?starts_with(name, 'rg-rf-dev-')].name" --output tsv)

for namespace in Microsoft.Resources Microsoft.Authorization Microsoft.Consumption Microsoft.ManagedIdentity Microsoft.Storage Microsoft.KeyVault Microsoft.Sql Microsoft.Web Microsoft.App Microsoft.ContainerRegistry Microsoft.Insights Microsoft.OperationalInsights; do
  state="$(az provider show --namespace "$namespace" --query registrationState --output tsv)"
  if [[ "$state" != "Registered" ]]; then
    echo "$namespace is not registered; registration is an explicit subscription-owner step" >&2; exit 3
  fi
done
location_display="$(az account list-locations --query "[?name=='${AZURE_LOCATION}'].displayName | [0]" --output tsv)"
if [[ -z "$location_display" ]]; then echo "Unknown Azure location ${AZURE_LOCATION}" >&2; exit 3; fi
flex_count="$(az functionapp list-flexconsumption-locations --query "[?name=='${AZURE_LOCATION}'] | length(@)" --output tsv)"
if [[ "$flex_count" != "1" ]]; then
  echo "Flex Consumption is unavailable in ${AZURE_LOCATION}" >&2; exit 3
fi
dotnet10_runtime_count="$(az functionapp list-flexconsumption-runtimes \
  --location "$AZURE_LOCATION" \
  --runtime dotnet-isolated \
  --query "[?sku.functionAppConfigProperties.runtime.name=='dotnet-isolated' && sku.functionAppConfigProperties.runtime.version=='10.0'] | length(@)" \
  --output tsv)"
if [[ "$dotnet10_runtime_count" != "1" ]]; then
  echo ".NET 10 isolated is unavailable for Flex Consumption in ${AZURE_LOCATION}" >&2; exit 3
fi
az provider show --namespace Microsoft.App \
  --query "resourceTypes[?resourceType=='managedEnvironments'].locations[]" --output tsv \
  | grep -Fxiq "$location_display" || {
    echo "Azure Container Apps is unavailable in ${AZURE_LOCATION}" >&2; exit 3;
  }
az provider show --namespace Microsoft.ContainerRegistry \
  --query "resourceTypes[?resourceType=='registries'].locations[]" --output tsv \
  | grep -Fxiq "$location_display" || {
    echo "Azure Container Registry is unavailable in ${AZURE_LOCATION}" >&2; exit 3;
  }
az provider show --namespace Microsoft.Web \
  --query "resourceTypes[?resourceType=='staticSites'].locations[]" --output tsv \
  | grep -Fxiq "$location_display" || {
    echo "Static Web Apps is unavailable in ${AZURE_LOCATION}" >&2; exit 3;
  }

common_parameters=(
  environmentName=dev
  location="$AZURE_LOCATION"
  uniqueSuffix="$AZURE_UNIQUE_SUFFIX"
  sqlEntraAdminLogin="$AZURE_SQL_ADMIN_LOGIN"
  sqlEntraAdminObjectId="$AZURE_SQL_ADMIN_OBJECT_ID"
  budgetContactEmail="$AZURE_BUDGET_EMAIL"
  budgetStartDate="$AZURE_BUDGET_START_DATE"
  monthlyBudgetAmount="$AZURE_MONTHLY_BUDGET_AMOUNT"
  deployCompute="${AZURE_DEPLOY_COMPUTE:-true}"
  apiMinReplicas="$api_min_replicas"
)
deployment_name="rise-funding-dev-${GITHUB_RUN_ID:-manual}"
preview_parameters=("${common_parameters[@]}" deployApiContainer=true apiContainerImageReference="rise-funding-api:${api_image_tag}")
base_parameters=("${common_parameters[@]}" deployApiContainer=false)
validation_parameters=("${preview_parameters[@]}")
if [[ "$operation" == "apply-base" ]]; then
  validation_parameters=("${base_parameters[@]}")
fi

az deployment sub validate --name "$deployment_name" --location "$AZURE_LOCATION" \
  --template-file infra/main.bicep --parameters "${validation_parameters[@]}" \
  --validation-level Provider --output none
if [[ "$operation" == validate ]]; then exit 0; fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required to redact the detailed what-if output" >&2; exit 3
fi
az deployment sub what-if --name "$deployment_name" --location "$AZURE_LOCATION" \
  --template-file infra/main.bicep --parameters "${validation_parameters[@]}" \
  --validation-level Provider --result-format FullResourcePayloads --no-prompt true \
  --only-show-errors --output json |
  jq --arg budgetEmail "$AZURE_BUDGET_EMAIL" \
     --arg adminLogin "$AZURE_SQL_ADMIN_LOGIN" \
     --arg adminObjectId "$AZURE_SQL_ADMIN_OBJECT_ID" \
     --arg subscriptionId "$AZURE_SUBSCRIPTION_ID" \
     --arg tenantId "$AZURE_TENANT_ID" '
    def replace_literal($needle; $replacement):
      if ($needle | length) == 0 then . else split($needle) | join($replacement) end;
    walk(if type == "string" then
      replace_literal($budgetEmail; "<redacted-budget-contact>") |
      replace_literal($adminLogin; "<redacted-sql-admin>") |
      replace_literal($adminObjectId; "<redacted-object-id>") |
      replace_literal($subscriptionId; "<redacted-subscription-id>") |
      replace_literal($tenantId; "<redacted-tenant-id>")
    else . end)'
if [[ "$operation" == what-if ]]; then exit 0; fi

if [[ "$operation" == "apply-base" ]]; then
  if [[ "${AZURE_APPLY_CONFIRMATION:-}" != "DEPLOY-DEV-BASE" ]]; then
    echo "AZURE_APPLY_CONFIRMATION=DEPLOY-DEV-BASE is required for apply-base" >&2; exit 4
  fi
  az deployment sub create --name "$deployment_name" --location "$AZURE_LOCATION" \
    --template-file infra/main.bicep --parameters "${base_parameters[@]}" --output none
  exit 0
fi

if [[ "${AZURE_APPLY_CONFIRMATION:-}" != "DEPLOY-DEV" ]]; then
  echo "AZURE_APPLY_CONFIRMATION=DEPLOY-DEV is required for apply" >&2; exit 4
fi

if [[ "${AZURE_DEPLOY_COMPUTE:-true}" != "true" ]]; then
  echo "AZURE_DEPLOY_COMPUTE=false does not pause or delete existing compute in incremental mode."
  az deployment sub create --name "$deployment_name" --location "$AZURE_LOCATION" \
    --template-file infra/main.bicep --parameters "${base_parameters[@]}" --output none
  exit 0
fi

base_deployment_name="${deployment_name}-base"
registry_name="$(az deployment sub create --name "$base_deployment_name" --location "$AZURE_LOCATION" \
  --template-file infra/main.bicep \
  --parameters "${base_parameters[@]}" \
  --query properties.outputs.apiContainerRegistryName.value --output tsv)"
if [[ -z "$registry_name" ]]; then
  echo "Base deployment did not return an Azure Container Registry name" >&2; exit 5
fi

az acr build \
  --registry "$registry_name" \
  --image "rise-funding-api:${api_image_tag}" \
  --file src/FundingPlatform.Api/Dockerfile \
  --platform linux/amd64 \
  .

image_digest="$(az acr manifest show-metadata \
  --registry "$registry_name" \
  --name "rise-funding-api:${api_image_tag}" \
  --query digest --output tsv)"
if [[ ! "$image_digest" =~ ^sha256:[0-9a-f]{64}$ ]]; then
  echo "ACR did not return a valid OCI image digest" >&2; exit 5
fi
final_parameters=("${common_parameters[@]}" deployApiContainer=true apiContainerImageReference="rise-funding-api@${image_digest}")

az deployment sub create --name "$deployment_name" --location "$AZURE_LOCATION" \
  --template-file infra/main.bicep --parameters "${final_parameters[@]}" --output none
