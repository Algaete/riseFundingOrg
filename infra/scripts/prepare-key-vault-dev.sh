#!/usr/bin/env bash
set -euo pipefail

required=(AZURE_SUBSCRIPTION_ID AZURE_TENANT_ID AZURE_UNIQUE_SUFFIX)
for name in "${required[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    echo "${name} is required" >&2
    exit 2
  fi
done
if [[ ! "$AZURE_SUBSCRIPTION_ID" =~ ^[0-9a-fA-F-]{36}$ ]] ||
   [[ ! "$AZURE_TENANT_ID" =~ ^[0-9a-fA-F-]{36}$ ]]; then
  echo "AZURE_SUBSCRIPTION_ID and AZURE_TENANT_ID must be explicit UUIDs" >&2
  exit 2
fi
if [[ ! "$AZURE_UNIQUE_SUFFIX" =~ ^[a-z0-9]{8}$ ]]; then
  echo "AZURE_UNIQUE_SUFFIX must be exactly 8 lowercase letters or digits" >&2
  exit 2
fi
for command in az openssl mktemp; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "${command} is required" >&2
    exit 2
  fi
done

actual_subscription="$(az account show --query id --output tsv)"
actual_tenant="$(az account show --query tenantId --output tsv)"
if [[ "$actual_subscription" != "$AZURE_SUBSCRIPTION_ID" || "$actual_tenant" != "$AZURE_TENANT_ID" ]]; then
  echo "Azure CLI is authenticated to a different subscription or tenant" >&2
  exit 3
fi

resource_group="rg-rf-dev-${AZURE_UNIQUE_SUFFIX}"
vault_count="$(az keyvault list --resource-group "$resource_group" --query 'length(@)' --output tsv)"
if [[ "$vault_count" != "1" ]]; then
  echo "Expected exactly one Key Vault in ${resource_group}" >&2
  exit 3
fi
vault_name="$(az keyvault list --resource-group "$resource_group" --query '[0].name' --output tsv)"
vault_id="$(az keyvault show --resource-group "$resource_group" --name "$vault_name" --query id --output tsv)"
operator_object_id="$(az ad signed-in-user show --query id --output tsv)"

existing_officer_count="$(az role assignment list --assignee-object-id "$operator_object_id" \
  --scope "$vault_id" --query "[?roleDefinitionName=='Key Vault Secrets Officer'] | length(@)" --output tsv)"
if [[ "$existing_officer_count" != "0" ]]; then
  echo "The operator already has Key Vault Secrets Officer at this scope; review it before using a temporary grant" >&2
  exit 3
fi

temporary_assignment_id=''
temporary_directory=''
bootstrap_complete=false
created_secret_names=()
cleanup() {
  if [[ -n "$temporary_assignment_id" ]]; then
    if az role assignment delete --ids "$temporary_assignment_id" --output none; then
      temporary_assignment_id=''
    else
      echo "WARNING: temporary Key Vault role cleanup failed for assignment ${temporary_assignment_id}." >&2
    fi
  fi
  if [[ -n "$temporary_directory" && "$temporary_directory" == */rf-kv-dev.* ]]; then
    rm -rf -- "$temporary_directory"
    temporary_directory=''
  fi
  if [[ "$bootstrap_complete" != "true" && "${#created_secret_names[@]}" -gt 0 ]]; then
    echo "PARTIAL KEY VAULT BOOTSTRAP: created metadata for ${created_secret_names[*]}. Do not rerun or overwrite; reconcile these versions explicitly." >&2
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

temporary_assignment_id="$(az role assignment create \
  --assignee-object-id "$operator_object_id" \
  --assignee-principal-type User \
  --role 'Key Vault Secrets Officer' \
  --scope "$vault_id" \
  --query id --output tsv)"
if [[ -z "$temporary_assignment_id" ]]; then
  echo "Temporary Key Vault role assignment was not created" >&2
  exit 3
fi

existing_secret_names=''
metadata_ready=false
for _ in {1..60}; do
  if existing_secret_names="$(az keyvault secret list --vault-name "$vault_name" \
      --query '[].name' --output tsv 2>/dev/null)"; then
    metadata_ready=true
    break
  fi
  sleep 10
done
if [[ "$metadata_ready" != "true" ]]; then
  echo "Key Vault data-plane permission did not propagate within ten minutes" >&2
  exit 5
fi

secret_names=(
  Authentication--Jwt--SigningKey
  Authentication--SecurityHash--IpHashPepper
  Authentication--SecurityHash--RecoveryCodePepper
)
for secret_name in "${secret_names[@]}"; do
  if printf '%s\n' "$existing_secret_names" | grep -Fxq "$secret_name"; then
    echo "Secret ${secret_name} already exists; refusing to overwrite it" >&2
    exit 5
  fi
done

umask 077
temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/rf-kv-dev.XXXXXX")"
openssl rand 64 | openssl base64 -A -out "${temporary_directory}/jwt"
openssl rand 32 | openssl base64 -A -out "${temporary_directory}/ip"
openssl rand 32 | openssl base64 -A -out "${temporary_directory}/recovery"

secret_files=(jwt ip recovery)
for index in 0 1 2; do
  secret_id="$(az keyvault secret set --vault-name "$vault_name" \
    --name "${secret_names[$index]}" \
    --file "${temporary_directory}/${secret_files[$index]}" \
    --encoding utf-8 --query id --output tsv)"
  secret_version="${secret_id##*/}"
  if [[ ! "$secret_version" =~ ^[0-9a-fA-F]{32}$ ]]; then
    echo "Key Vault did not return a valid version for ${secret_names[$index]}" >&2
    exit 5
  fi
  created_secret_names+=("${secret_names[$index]}")
  echo "Created ${secret_names[$index]} version ${secret_version}."
done

bootstrap_complete=true
cleanup
remaining_officer_count="$(az role assignment list --assignee-object-id "$operator_object_id" \
  --scope "$vault_id" --query "[?roleDefinitionName=='Key Vault Secrets Officer'] | length(@)" --output tsv)"
if [[ -n "$temporary_assignment_id" || "$remaining_officer_count" != "0" ]]; then
  echo "The temporary Key Vault role was not proven revoked" >&2
  exit 5
fi
trap - EXIT INT TERM
echo "Key Vault bootstrap completed without reading or printing secret values."
