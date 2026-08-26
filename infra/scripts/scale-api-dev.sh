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
if [[ "${AZURE_API_MIN_REPLICAS:-}" != "0" && "${AZURE_API_MIN_REPLICAS:-}" != "1" ]]; then
  echo "AZURE_API_MIN_REPLICAS must be 0 or 1" >&2
  exit 2
fi
if [[ "${AZURE_API_SCALE_CONFIRMATION:-}" != "SCALE-DEV-API" ]]; then
  echo "AZURE_API_SCALE_CONFIRMATION=SCALE-DEV-API is required" >&2
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
current_shape="$(az resource show --name "$api_name" --resource-group "$resource_group" \
  --resource-type Microsoft.App/containerApps --api-version 2025-01-01 \
  --query "join('|', [to_string(properties.template.scale.maxReplicas), properties.provisioningState])" --output tsv)"
if [[ "$current_shape" != "1|Succeeded" ]]; then
  echo "Refusing to scale an API that is not ready with maximum replicas exactly 1" >&2
  exit 3
fi

az resource update \
  --name "$api_name" \
  --resource-group "$resource_group" \
  --resource-type Microsoft.App/containerApps \
  --api-version 2025-01-01 \
  --set properties.template.scale.minReplicas="$AZURE_API_MIN_REPLICAS" \
        properties.template.scale.maxReplicas=1 \
  --output none

scale_ready=false
for _ in {1..30}; do
  actual_shape="$(az resource show --name "$api_name" --resource-group "$resource_group" \
    --resource-type Microsoft.App/containerApps --api-version 2025-01-01 \
    --query "join('|', [to_string(properties.template.scale.minReplicas), to_string(properties.template.scale.maxReplicas), properties.provisioningState])" \
    --output tsv)"
  if [[ "$actual_shape" == "${AZURE_API_MIN_REPLICAS}|1|Succeeded" ]]; then
    scale_ready=true
    break
  fi
  sleep 10
done
if [[ "$scale_ready" != "true" ]]; then
  echo "Container App did not reach the requested minimum replica setting" >&2
  exit 5
fi
echo "API minimum replicas set to ${AZURE_API_MIN_REPLICAS}; maximum remains 1. No image was rebuilt."
