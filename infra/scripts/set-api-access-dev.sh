#!/usr/bin/env bash
set -euo pipefail

operation="${1:-}"
case "$operation" in
  pause|resume) ;;
  *) echo "operation must be pause or resume" >&2; exit 2 ;;
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
if [[ "$operation" == "pause" ]]; then
  expected_confirmation="PAUSE-DEV-API"
  desired_external="false"
  desired_min="0"
else
  expected_confirmation="RESUME-DEV-API"
  desired_external="true"
  desired_min="${AZURE_API_MIN_REPLICAS:-0}"
  if [[ "$desired_min" != "0" && "$desired_min" != "1" ]]; then
    echo "AZURE_API_MIN_REPLICAS must be 0 or 1" >&2
    exit 2
  fi
fi
if [[ "${AZURE_API_ACCESS_CONFIRMATION:-}" != "$expected_confirmation" ]]; then
  echo "AZURE_API_ACCESS_CONFIRMATION=${expected_confirmation} is required" >&2
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
  echo "Refusing to change access for an API that is not ready with maximum replicas exactly 1" >&2
  exit 3
fi

az resource update \
  --name "$api_name" \
  --resource-group "$resource_group" \
  --resource-type Microsoft.App/containerApps \
  --api-version 2025-01-01 \
  --set properties.configuration.ingress.external="$desired_external" \
        properties.template.scale.minReplicas="$desired_min" \
        properties.template.scale.maxReplicas=1 \
  --output none

access_ready=false
for _ in {1..30}; do
  actual_shape="$(az resource show --name "$api_name" --resource-group "$resource_group" \
    --resource-type Microsoft.App/containerApps --api-version 2025-01-01 \
    --query "join('|', [to_string(properties.configuration.ingress.external), to_string(properties.template.scale.minReplicas), to_string(properties.template.scale.maxReplicas), properties.provisioningState])" \
    --output tsv)"
  if [[ "$actual_shape" == "${desired_external}|${desired_min}|1|Succeeded" ]]; then
    access_ready=true
    break
  fi
  sleep 10
done
if [[ "$access_ready" != "true" ]]; then
  echo "Container App did not reach the requested access/scale state: ${actual_shape}" >&2
  exit 5
fi

if [[ "$operation" == "resume" ]]; then
  AZURE_API_MIN_REPLICAS="$desired_min" bash infra/scripts/verify-dev.sh api
  echo "API public ingress resumed; minReplicas=${desired_min}, maxReplicas=1."
else
  echo "API public ingress disabled; minReplicas=0, maxReplicas=1. Public requests cannot wake it."
fi
