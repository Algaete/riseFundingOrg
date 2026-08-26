#!/usr/bin/env bash
set -euo pipefail

operation="${1:-validate}"
case "$operation" in validate|what-if|apply) ;; *) echo "operation must be validate, what-if or apply" >&2; exit 2 ;; esac

required=(AZURE_LOCATION AZURE_UNIQUE_SUFFIX AZURE_SQL_ADMIN_LOGIN AZURE_SQL_ADMIN_OBJECT_ID AZURE_BUDGET_EMAIL AZURE_BUDGET_START_DATE)
for name in "${required[@]}"; do
  if [[ -z "${!name:-}" ]]; then echo "$name is required" >&2; exit 2; fi
done
if [[ ! "$AZURE_UNIQUE_SUFFIX" =~ ^[a-z0-9]{4,8}$ ]]; then
  echo "AZURE_UNIQUE_SUFFIX must be 4-8 lowercase letters or digits" >&2; exit 2
fi
if [[ ! "$AZURE_SQL_ADMIN_OBJECT_ID" =~ ^[0-9a-fA-F-]{36}$ ]] || [[ "$AZURE_SQL_ADMIN_OBJECT_ID" == 00000000-0000-0000-0000-000000000000 ]]; then
  echo "AZURE_SQL_ADMIN_OBJECT_ID must be a non-placeholder UUID" >&2; exit 2
fi
if [[ ! "$AZURE_BUDGET_START_DATE" =~ ^[0-9]{4}-[0-9]{2}-01T00:00:00Z$ ]]; then
  echo "AZURE_BUDGET_START_DATE must be the first UTC day of a month" >&2; exit 2
fi

az account show --output none
for namespace in Microsoft.Resources Microsoft.Authorization Microsoft.Consumption Microsoft.ManagedIdentity Microsoft.Storage Microsoft.KeyVault Microsoft.Sql Microsoft.Web Microsoft.Insights Microsoft.OperationalInsights; do
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
az functionapp list-flexconsumption-runtimes --location "$AZURE_LOCATION" --runtime dotnet-isolated \
  --output tsv | grep -q '10.0' || {
    echo ".NET 10 isolated is unavailable for Flex Consumption in ${AZURE_LOCATION}" >&2; exit 3;
  }
az webapp list-runtimes --os-type linux --output tsv | grep -q 'DOTNETCORE:10.0' || {
  echo ".NET 10 is unavailable for Linux App Service" >&2; exit 3;
}
az provider show --namespace Microsoft.Web \
  --query "resourceTypes[?resourceType=='staticSites'].locations[]" --output tsv \
  | grep -Fxiq "$location_display" || {
    echo "Static Web Apps is unavailable in ${AZURE_LOCATION}" >&2; exit 3;
  }

parameters=(
  environmentName=dev
  location="$AZURE_LOCATION"
  uniqueSuffix="$AZURE_UNIQUE_SUFFIX"
  sqlEntraAdminLogin="$AZURE_SQL_ADMIN_LOGIN"
  sqlEntraAdminObjectId="$AZURE_SQL_ADMIN_OBJECT_ID"
  budgetContactEmail="$AZURE_BUDGET_EMAIL"
  budgetStartDate="$AZURE_BUDGET_START_DATE"
  monthlyBudgetAmount="${AZURE_MONTHLY_BUDGET_AMOUNT:-75}"
  deployCompute="${AZURE_DEPLOY_COMPUTE:-true}"
)
deployment_name="rise-funding-dev-${GITHUB_RUN_ID:-manual}"

az deployment sub validate --name "$deployment_name" --location "$AZURE_LOCATION" \
  --template-file infra/main.bicep --parameters "${parameters[@]}" --validation-level Provider
if [[ "$operation" == validate ]]; then exit 0; fi

az deployment sub what-if --name "$deployment_name" --location "$AZURE_LOCATION" \
  --template-file infra/main.bicep --parameters "${parameters[@]}" \
  --validation-level Provider --result-format ResourceIdOnly --no-prompt true
if [[ "$operation" == what-if ]]; then exit 0; fi

if [[ "${AZURE_APPLY_CONFIRMATION:-}" != "DEPLOY-DEV" ]]; then
  echo "AZURE_APPLY_CONFIRMATION=DEPLOY-DEV is required for apply" >&2; exit 4
fi
az deployment sub create --name "$deployment_name" --location "$AZURE_LOCATION" \
  --template-file infra/main.bicep --parameters "${parameters[@]}"
