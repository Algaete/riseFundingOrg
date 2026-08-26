#!/usr/bin/env bash
set -euo pipefail

if [[ ! "${AZURE_UNIQUE_SUFFIX:-}" =~ ^[a-z0-9]{8}$ ]]; then
  echo "AZURE_UNIQUE_SUFFIX must be exactly 8 lowercase letters or digits" >&2
  exit 2
fi
if [[ ! "${AZURE_SUBSCRIPTION_ID:-}" =~ ^[0-9a-fA-F-]{36}$ ]] ||
   [[ ! "${AZURE_TENANT_ID:-}" =~ ^[0-9a-fA-F-]{36}$ ]]; then
  echo "AZURE_SUBSCRIPTION_ID and AZURE_TENANT_ID must be explicit UUIDs" >&2
  exit 2
fi
if [[ ! "${AZURE_API_ROLLBACK_DIGEST:-}" =~ ^sha256:[0-9a-f]{64}$ ]]; then
  echo "AZURE_API_ROLLBACK_DIGEST must be an explicit sha256 OCI digest" >&2
  exit 2
fi
if [[ "${AZURE_API_ROLLBACK_CONFIRMATION:-}" != "ROLLBACK-DEV-API" ]]; then
  echo "AZURE_API_ROLLBACK_CONFIRMATION=ROLLBACK-DEV-API is required" >&2
  exit 4
fi

resource_group="rg-rf-dev-${AZURE_UNIQUE_SUFFIX}"
api_name="ca-rf-dev-${AZURE_UNIQUE_SUFFIX}-api"
actual_subscription="$(az account show --query id --output tsv)"
actual_tenant="$(az account show --query tenantId --output tsv)"
if [[ "$actual_subscription" != "$AZURE_SUBSCRIPTION_ID" || "$actual_tenant" != "$AZURE_TENANT_ID" ]]; then
  echo "Azure CLI is authenticated to a different subscription or tenant" >&2
  exit 3
fi

registry_count="$(az acr list --resource-group "$resource_group" --query 'length(@)' --output tsv)"
if [[ "$registry_count" != "1" ]]; then
  echo "Expected exactly one Container Registry in ${resource_group}" >&2
  exit 3
fi
registry_name="$(az acr list --resource-group "$resource_group" --query '[0].name' --output tsv)"
registry_server="$(az acr show --name "$registry_name" --resource-group "$resource_group" --query loginServer --output tsv)"
verified_digest="$(az acr manifest show-metadata \
  --registry "$registry_name" \
  --name "rise-funding-api@${AZURE_API_ROLLBACK_DIGEST}" \
  --query digest --output tsv)"
if [[ "$verified_digest" != "$AZURE_API_ROLLBACK_DIGEST" ]]; then
  echo "The requested digest does not exist in the dev API repository" >&2
  exit 3
fi

current_image="$(az resource show --name "$api_name" --resource-group "$resource_group" \
  --resource-type Microsoft.App/containerApps --api-version 2025-01-01 \
  --query 'properties.template.containers[0].image' --output tsv)"
current_ingress="$(az resource show --name "$api_name" --resource-group "$resource_group" \
  --resource-type Microsoft.App/containerApps --api-version 2025-01-01 \
  --query properties.configuration.ingress.external --output tsv)"
if [[ "$current_ingress" != "true" ]]; then
  echo "Resume the API ingress before rollback so the target revision can be verified" >&2
  exit 3
fi
target_image="${registry_server}/rise-funding-api@${AZURE_API_ROLLBACK_DIGEST}"
if [[ "$current_image" == "$target_image" ]]; then
  echo "The API already uses the requested digest; no mutation was needed."
else
  echo "Current API image is recorded; switching to the verified prior digest."
  az resource update \
    --name "$api_name" \
    --resource-group "$resource_group" \
    --resource-type Microsoft.App/containerApps \
    --api-version 2025-01-01 \
    --set properties.template.containers[0].image="$target_image" \
    --output none
fi

rollback_ready=false
for _ in {1..30}; do
  revision_state="$(az resource show --name "$api_name" --resource-group "$resource_group" \
    --resource-type Microsoft.App/containerApps --api-version 2025-01-01 \
    --query "join('|', [properties.provisioningState, properties.latestRevisionName, properties.latestReadyRevisionName, properties.template.containers[0].image])" \
    --output tsv)"
  IFS='|' read -r provisioning_state latest_revision ready_revision ready_image <<<"$revision_state"
  if [[ "$provisioning_state" == "Succeeded" && -n "$latest_revision" &&
        "$latest_revision" == "$ready_revision" && "$ready_image" == "$target_image" ]]; then
    rollback_ready=true
    break
  fi
  sleep 10
done
if [[ "$rollback_ready" != "true" ]]; then
  echo "The rollback revision did not become ready within five minutes" >&2
  exit 5
fi

current_min="$(az resource show --name "$api_name" --resource-group "$resource_group" \
  --resource-type Microsoft.App/containerApps --api-version 2025-01-01 \
  --query properties.template.scale.minReplicas --output tsv)"
AZURE_API_MIN_REPLICAS="$current_min" bash infra/scripts/verify-dev.sh api
echo "API rollback completed to ${AZURE_API_ROLLBACK_DIGEST}. Previous image was ${current_image}."
