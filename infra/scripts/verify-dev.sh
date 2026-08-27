#!/usr/bin/env bash
set -euo pipefail

stage="${1:-base}"
case "$stage" in
  base|api) ;;
  *) echo "stage must be base or api" >&2; exit 2 ;;
esac

if [[ ! "${AZURE_UNIQUE_SUFFIX:-}" =~ ^[a-z0-9]{8}$ ]]; then
  echo "AZURE_UNIQUE_SUFFIX must be exactly 8 lowercase letters or digits" >&2
  exit 2
fi
if [[ ! "${AZURE_SUBSCRIPTION_ID:-}" =~ ^[0-9a-fA-F-]{36}$ ]] ||
   [[ ! "${AZURE_TENANT_ID:-}" =~ ^[0-9a-fA-F-]{36}$ ]]; then
  echo "AZURE_SUBSCRIPTION_ID and AZURE_TENANT_ID must be explicit UUIDs" >&2
  exit 2
fi
if [[ ! "${AZURE_SQL_LOCATION:-}" =~ ^[a-z0-9]+$ ]]; then
  echo "AZURE_SQL_LOCATION must be an explicit Azure region code" >&2
  exit 2
fi

expected_min_replicas="${AZURE_API_MIN_REPLICAS:-0}"
if [[ "$expected_min_replicas" != "0" && "$expected_min_replicas" != "1" ]]; then
  echo "AZURE_API_MIN_REPLICAS must be 0 or 1" >&2
  exit 2
fi

resource_group="rg-rf-dev-${AZURE_UNIQUE_SUFFIX}"
api_name="ca-rf-dev-${AZURE_UNIQUE_SUFFIX}-api"
api_identity_name="id-rf-dev-${AZURE_UNIQUE_SUFFIX}-api"

actual_subscription="$(az account show --query id --output tsv)"
actual_tenant="$(az account show --query tenantId --output tsv)"
if [[ "$actual_subscription" != "$AZURE_SUBSCRIPTION_ID" || "$actual_tenant" != "$AZURE_TENANT_ID" ]]; then
  echo "Azure CLI is authenticated to a different subscription or tenant" >&2
  exit 3
fi
provisioning_state="$(az group show --name "$resource_group" --query properties.provisioningState --output tsv)"
if [[ "$provisioning_state" != "Succeeded" ]]; then
  echo "Resource group ${resource_group} is not ready: ${provisioning_state}" >&2
  exit 3
fi

resource_count() {
  local resource_type="$1"
  az resource list --resource-group "$resource_group" \
    --query "[?type=='${resource_type}'] | length(@)" --output tsv
}

require_count() {
  local resource_type="$1"
  local expected="$2"
  local actual
  actual="$(resource_count "$resource_type")"
  if [[ "$actual" != "$expected" ]]; then
    echo "Expected ${expected} ${resource_type} resources; found ${actual}" >&2
    exit 3
  fi
}

require_count Microsoft.ContainerRegistry/registries 1
require_count Microsoft.App/managedEnvironments 1
require_count Microsoft.Sql/servers 1
require_count Microsoft.KeyVault/vaults 1
require_count Microsoft.Storage/storageAccounts 4
require_count Microsoft.ManagedIdentity/userAssignedIdentities 5
require_count Microsoft.Web/staticSites 1
require_count Microsoft.Web/sites 2

registry_name="$(az acr list --resource-group "$resource_group" --query '[0].name' --output tsv)"
registry_id="$(az acr show --name "$registry_name" --resource-group "$resource_group" --query id --output tsv)"
registry_server="$(az acr show --name "$registry_name" --resource-group "$resource_group" --query loginServer --output tsv)"
registry_admin="$(az acr show --name "$registry_name" --resource-group "$resource_group" --query adminUserEnabled --output tsv)"
if [[ "$registry_admin" != "false" ]]; then
  echo "ACR admin user must remain disabled" >&2
  exit 3
fi

api_principal_id="$(az identity show --name "$api_identity_name" --resource-group "$resource_group" --query principalId --output tsv)"
acr_pull_count="$(az role assignment list --assignee-object-id "$api_principal_id" --scope "$registry_id" \
  --query "[?roleDefinitionName=='AcrPull'] | length(@)" --output tsv)"
if [[ "$acr_pull_count" != "1" ]]; then
  echo "API identity must have exactly one AcrPull assignment on the dev registry" >&2
  exit 3
fi

sql_server_name="$(az sql server list --resource-group "$resource_group" --query '[0].name' --output tsv)"
sql_server_location="$(az sql server show --resource-group "$resource_group" --name "$sql_server_name" --query location --output tsv)"
if [[ "$sql_server_location" != "$AZURE_SQL_LOCATION" ]]; then
  echo "Unexpected Azure SQL location: ${sql_server_location}" >&2
  exit 3
fi
database_name="$(az sql db list --resource-group "$resource_group" --server "$sql_server_name" \
  --query "[?name!='master'].name | [0]" --output tsv)"
if [[ "$database_name" != "risefunding-dev" ]]; then
  echo "Expected only the dedicated risefunding-dev database; found ${database_name}" >&2
  exit 3
fi
sql_shape="$(az sql db show --resource-group "$resource_group" --server "$sql_server_name" \
  --name "$database_name" --query "join('|', [currentServiceObjectiveName, to_string(sku.capacity), to_string(autoPauseDelay), to_string(minCapacity)])" --output tsv)"
if [[ "$sql_shape" != "GP_S_Gen5_1|1|60|0.5" ]]; then
  echo "Unexpected SQL serverless configuration: ${sql_shape}" >&2
  exit 3
fi
retention_shape="$(az sql db str-policy show --resource-group "$resource_group" \
  --server "$sql_server_name" --name "$database_name" \
  --query "join('|', [to_string(retentionDays), to_string(diffBackupIntervalInHours)])" --output tsv)"
if [[ "$retention_shape" != "7|12" ]]; then
  echo "Unexpected SQL short-term retention policy: ${retention_shape}" >&2
  exit 3
fi

for function_name in "func-rf-dev-${AZURE_UNIQUE_SUFFIX}-general" "func-rf-dev-${AZURE_UNIQUE_SUFFIX}-extract"; do
  maximum_instances="$(az resource show --resource-group "$resource_group" --resource-type Microsoft.Web/sites \
    --name "$function_name" --api-version 2024-04-01 \
    --query properties.functionAppConfig.scaleAndConcurrency.maximumInstanceCount --output tsv)"
  if [[ "$maximum_instances" != "1" ]]; then
    echo "${function_name} must remain capped at one on-demand instance in dev" >&2
    exit 3
  fi
done

if [[ "$stage" == "api" ]]; then
  require_count Microsoft.App/containerApps 1
  api_shape="$(az resource show --name "$api_name" --resource-group "$resource_group" \
    --resource-type Microsoft.App/containerApps --api-version 2025-01-01 \
    --query "join('|', [to_string(properties.template.scale.minReplicas), to_string(properties.template.scale.maxReplicas), properties.provisioningState])" \
    --output tsv)"
  if [[ "$api_shape" != "${expected_min_replicas}|1|Succeeded" ]]; then
    echo "Unexpected Container App scale/state: ${api_shape}" >&2
    exit 3
  fi

  api_image="$(az resource show --name "$api_name" --resource-group "$resource_group" \
    --resource-type Microsoft.App/containerApps --api-version 2025-01-01 \
    --query 'properties.template.containers[0].image' --output tsv)"
  api_digest="${api_image#${registry_server}/rise-funding-api@}"
  if [[ "$api_image" != "${registry_server}/rise-funding-api@"* ||
        ! "$api_digest" =~ ^sha256:[0-9a-f]{64}$ ]]; then
    echo "Container App image is not the expected dev ACR repository pinned to an OCI digest" >&2
    exit 3
  fi

  identity_count="$(az resource show --name "$api_name" --resource-group "$resource_group" \
    --resource-type Microsoft.App/containerApps --api-version 2025-01-01 \
    --query 'keys(identity.userAssignedIdentities) | length(@)' --output tsv)"
  if [[ "$identity_count" != "1" ]]; then
    echo "Container App must have exactly one user-assigned identity" >&2
    exit 3
  fi
  expected_api_identity_id="$(az identity show --name "$api_identity_name" --resource-group "$resource_group" --query id --output tsv)"
  attached_api_identity_id="$(az resource show --name "$api_name" --resource-group "$resource_group" \
    --resource-type Microsoft.App/containerApps --api-version 2025-01-01 \
    --query 'keys(identity.userAssignedIdentities)[0]' --output tsv)"
  if [[ "$attached_api_identity_id" != "$expected_api_identity_id" ]]; then
    echo "Container App is not attached to the exact expected API identity" >&2
    exit 3
  fi

  revision_shape="$(az resource show --name "$api_name" --resource-group "$resource_group" \
    --resource-type Microsoft.App/containerApps --api-version 2025-01-01 \
    --query "join('|', [to_string(properties.configuration.ingress.external), properties.latestRevisionName, properties.latestReadyRevisionName])" \
    --output tsv)"
  IFS='|' read -r ingress_external latest_revision ready_revision <<<"$revision_shape"
  if [[ "$ingress_external" != "true" || -z "$latest_revision" || "$latest_revision" != "$ready_revision" ]]; then
    echo "Container App ingress or latest ready revision is not healthy: ${revision_shape}" >&2
    exit 3
  fi

  fqdn="$(az resource show --name "$api_name" --resource-group "$resource_group" \
    --resource-type Microsoft.App/containerApps --api-version 2025-01-01 \
    --query properties.configuration.ingress.fqdn --output tsv)"
  curl_options=(--fail --silent --show-error --connect-timeout 10 --max-time 30 --retry 5 --retry-delay 5 --retry-all-errors --retry-max-time 120)
  curl "${curl_options[@]}" "https://${fqdn}/health" >/dev/null
  curl "${curl_options[@]}" "https://${fqdn}/api/v1/funding-opportunities/?pageNumber=1&pageSize=1" >/dev/null
  echo "API liveness, SQL connectivity and public catalog permission OK: https://${fqdn}"
fi

echo "Azure dev verification passed for stage=${stage}, resourceGroup=${resource_group}."
