#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage: bash infra/scripts/restore-database-dev.sh validate|execute

Required environment variables:
  AZURE_SUBSCRIPTION_ID
  AZURE_TENANT_ID
  AZURE_UNIQUE_SUFFIX
  RF_DEV_RESTORE_SOURCE_DATABASE
  RF_DEV_RESTORE_DESTINATION
  RF_DEV_RESTORE_POINT_UTC

execute also requires RF_DEV_RESTORE_CONFIRMATION to equal the exact phrase
printed by a successful validate run.
USAGE
}

if [[ "$#" != "1" ]]; then
  usage
  exit 2
fi
mode="$1"
if [[ "$mode" != "validate" && "$mode" != "execute" ]]; then
  usage
  exit 2
fi

required=(
  AZURE_SUBSCRIPTION_ID
  AZURE_TENANT_ID
  AZURE_UNIQUE_SUFFIX
  RF_DEV_RESTORE_SOURCE_DATABASE
  RF_DEV_RESTORE_DESTINATION
  RF_DEV_RESTORE_POINT_UTC
)
for name in "${required[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    echo "${name} is required" >&2
    exit 2
  fi
done

uuid_pattern='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
if [[ ! "$AZURE_SUBSCRIPTION_ID" =~ $uuid_pattern ]] ||
   [[ ! "$AZURE_TENANT_ID" =~ $uuid_pattern ]]; then
  echo "AZURE_SUBSCRIPTION_ID and AZURE_TENANT_ID must be explicit lowercase UUIDs" >&2
  exit 2
fi
if [[ ! "$AZURE_UNIQUE_SUFFIX" =~ ^[a-z0-9]{8}$ ]]; then
  echo "AZURE_UNIQUE_SUFFIX must be exactly 8 lowercase letters or digits" >&2
  exit 2
fi

source_database="$RF_DEV_RESTORE_SOURCE_DATABASE"
destination_database="$RF_DEV_RESTORE_DESTINATION"
restore_point_utc="$RF_DEV_RESTORE_POINT_UTC"
if [[ "$source_database" != "risefunding-dev" ]]; then
  echo "RF_DEV_RESTORE_SOURCE_DATABASE must be exactly risefunding-dev" >&2
  exit 2
fi
destination_pattern="^risefunding-dev-restore-${AZURE_UNIQUE_SUFFIX}-[0-9]{8}t[0-9]{6}z-[0-9a-f]{4}$"
if [[ ! "$destination_database" =~ $destination_pattern ]]; then
  echo "RF_DEV_RESTORE_DESTINATION must match risefunding-dev-restore-${AZURE_UNIQUE_SUFFIX}-YYYYMMDDtHHMMSSz-NNNN (NNNN is lowercase hexadecimal)" >&2
  exit 2
fi
if [[ "$destination_database" == "$source_database" ]]; then
  echo "The restore destination must differ from the source database" >&2
  exit 2
fi
restore_point_pattern='^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])T([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]Z$'
if [[ ! "$restore_point_utc" =~ $restore_point_pattern ]]; then
  echo "RF_DEV_RESTORE_POINT_UTC must be UTC to whole seconds: YYYY-MM-DDTHH:MM:SSZ" >&2
  exit 2
fi
for command in az date; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "${command} is required" >&2
    exit 2
  fi
done
normalized_restore_point=''
if normalized_restore_point="$(date -u -d "$restore_point_utc" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" &&
   [[ "$normalized_restore_point" == "$restore_point_utc" ]]; then
  : # GNU date accepted the timestamp without normalizing it.
elif normalized_restore_point="$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' \
    "$restore_point_utc" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" &&
     [[ "$normalized_restore_point" == "$restore_point_utc" ]]; then
  : # BSD date accepted the timestamp without normalizing it.
else
  echo "RF_DEV_RESTORE_POINT_UTC is not a real UTC calendar timestamp" >&2
  exit 2
fi

actual_account="$(az account show --query "join('|', [id, tenantId, state])" --output tsv)"
if [[ "$actual_account" != "${AZURE_SUBSCRIPTION_ID}|${AZURE_TENANT_ID}|Enabled" ]]; then
  echo "Azure CLI is not authenticated to the exact enabled subscription and tenant" >&2
  exit 3
fi

resource_group="rg-rf-dev-${AZURE_UNIQUE_SUFFIX}"
expected_resource_group_id="/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${resource_group}"
resource_group_shape="$(az group show --subscription "$AZURE_SUBSCRIPTION_ID" \
  --name "$resource_group" \
  --query "join('|', [id, name, tags.application, tags.environment])" --output tsv)"
if [[ "$resource_group_shape" != "${expected_resource_group_id}|${resource_group}|rise-funding-org|dev" ]]; then
  echo "The derived resource group does not match the expected dev environment identity and tags" >&2
  exit 3
fi

sql_server_count="$(az sql server list --subscription "$AZURE_SUBSCRIPTION_ID" \
  --resource-group "$resource_group" --query 'length(@)' --output tsv)"
if [[ "$sql_server_count" != "1" ]]; then
  echo "Expected exactly one Azure SQL logical server in ${resource_group}" >&2
  exit 3
fi
sql_server="$(az sql server list --subscription "$AZURE_SUBSCRIPTION_ID" \
  --resource-group "$resource_group" --query '[0].name' --output tsv)"
if [[ ! "$sql_server" =~ ^sql-rf-dev-${AZURE_UNIQUE_SUFFIX}-[a-z0-9]+$ ]]; then
  echo "The Azure SQL server name does not belong to the derived dev environment" >&2
  exit 3
fi
sql_server_fqdn="$(az sql server show --subscription "$AZURE_SUBSCRIPTION_ID" \
  --resource-group "$resource_group" --name "$sql_server" \
  --query fullyQualifiedDomainName --output tsv)"
if [[ "$sql_server_fqdn" != "${sql_server}.database.windows.net" ]]; then
  echo "Unexpected Azure SQL server FQDN" >&2
  exit 3
fi

expected_source_id="${expected_resource_group_id}/providers/Microsoft.Sql/servers/${sql_server}/databases/${source_database}"
source_shape="$(az sql db show --subscription "$AZURE_SUBSCRIPTION_ID" \
  --resource-group "$resource_group" --server "$sql_server" --name "$source_database" \
  --query "join('|', [id, name, status, currentServiceObjectiveName, to_string(sku.capacity), to_string(autoPauseDelay), to_string(minCapacity), to_string(zoneRedundant), requestedBackupStorageRedundancy, to_string(maxSizeBytes), earliestRestoreDate])" \
  --output tsv)"
IFS='|' read -r source_id actual_source_name source_status source_objective source_capacity \
  source_auto_pause source_min_capacity source_zone_redundant source_backup_redundancy \
  source_max_size_bytes earliest_restore_raw <<<"$source_shape"
if [[ "$source_id" != "$expected_source_id" || "$actual_source_name" != "$source_database" ]]; then
  echo "The source database resource is not the exact expected dev database" >&2
  exit 3
fi
if [[ "$source_status" != "Online" && "$source_status" != "Paused" ]]; then
  echo "Source database must be Online or Paused, not ${source_status:-unknown}" >&2
  exit 3
fi
source_cost_shape="${source_objective}|${source_capacity}|${source_auto_pause}|${source_min_capacity}|${source_zone_redundant}|${source_backup_redundancy}"
if [[ "$source_cost_shape" != "GP_S_Gen5_1|1|60|0.5|false|Local" ]]; then
  echo "Unexpected source database service or cost shape: ${source_cost_shape}" >&2
  exit 3
fi
if [[ ! "$source_max_size_bytes" =~ ^[1-9][0-9]*$ ]]; then
  echo "Azure SQL did not return a positive integer maxSizeBytes for the source database" >&2
  exit 3
fi
earliest_restore_pattern='^([0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])T([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9])(\.[0-9]+)?(Z|\+00:00)$'
if [[ "$earliest_restore_raw" =~ $earliest_restore_pattern ]]; then
  earliest_restore_utc="${BASH_REMATCH[1]}Z"
else
  echo "Azure SQL did not return a supported earliestRestoreDate in UTC (only Z or +00:00 are accepted)" >&2
  exit 3
fi
current_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
if [[ "$restore_point_utc" < "$earliest_restore_utc" || "$restore_point_utc" == "$earliest_restore_utc" ]]; then
  echo "Restore point must be later than earliestRestoreDate (${earliest_restore_raw})" >&2
  exit 3
fi
if [[ "$restore_point_utc" > "$current_utc" || "$restore_point_utc" == "$current_utc" ]]; then
  echo "Restore point must be earlier than the current UTC time (${current_utc})" >&2
  exit 3
fi

expected_destination_id="${expected_resource_group_id}/providers/Microsoft.Sql/servers/${sql_server}/databases/${destination_database}"
destination_count="$(az sql db list --subscription "$AZURE_SUBSCRIPTION_ID" \
  --resource-group "$resource_group" --server "$sql_server" \
  --query "[?name=='${destination_database}'] | length(@)" --output tsv)"
if [[ "$destination_count" != "0" ]]; then
  echo "Restore destination ${destination_database} already exists; it will not be reused or overwritten" >&2
  exit 3
fi

expected_confirmation="RESTORE-DEV-DATABASE SUBSCRIPTION ${AZURE_SUBSCRIPTION_ID} TENANT ${AZURE_TENANT_ID} SOURCE ${expected_source_id} TO ${expected_destination_id} AT ${restore_point_utc} MAX-STORAGE-BYTES ${source_max_size_bytes}"
echo "Validated Azure SQL PITR plan (read-only so far):"
echo "  subscription: ${AZURE_SUBSCRIPTION_ID}"
echo "  tenant:       ${AZURE_TENANT_ID}"
echo "  resource:     ${resource_group}/${sql_server}"
echo "  source:       ${source_database} (${source_status})"
echo "  destination:  ${destination_database} (new temporary database)"
echo "  restore UTC:  ${restore_point_utc}"
echo "  earliest UTC: ${earliest_restore_raw}"
echo "  source max storage: ${source_max_size_bytes} bytes"
echo "  storage exposure: the temporary PITR can duplicate up to that source cap; compute is bounded, but this repository does not declare total storage cost bounded"
echo "Exact execute confirmation: ${expected_confirmation}"

if [[ "$mode" == "validate" ]]; then
  echo "Validation complete. No restore command was sent and no Azure resource was changed."
  exit 0
fi
if [[ "${RF_DEV_RESTORE_CONFIRMATION:-}" != "$expected_confirmation" ]]; then
  echo "RF_DEV_RESTORE_CONFIRMATION must equal the exact confirmation printed by validate" >&2
  exit 4
fi

# Azure CLI documents --time without a timezone suffix and interprets it as UTC for PITR.
restore_point_cli="${restore_point_utc%Z}"
echo "Starting PITR. Interruption can leave the destination provisioning in Azure; this script never deletes it."
az sql db restore --subscription "$AZURE_SUBSCRIPTION_ID" \
  --resource-group "$resource_group" \
  --server "$sql_server" \
  --name "$source_database" \
  --dest-name "$destination_database" \
  --time "$restore_point_cli" \
  --edition GeneralPurpose \
  --family Gen5 \
  --capacity 1 \
  --compute-model Serverless \
  --min-capacity 0.5 \
  --auto-pause-delay 60 \
  --backup-storage-redundancy Local \
  --zone-redundant false \
  --tags application=rise-funding-org environment=dev purpose=pitr-restore-drill temporary=true \
  --output none

destination_shape="$(az sql db show --subscription "$AZURE_SUBSCRIPTION_ID" \
  --resource-group "$resource_group" --server "$sql_server" --name "$destination_database" \
  --query "join('|', [id, name, status, currentServiceObjectiveName, to_string(sku.capacity), to_string(autoPauseDelay), to_string(minCapacity), to_string(zoneRedundant), requestedBackupStorageRedundancy, to_string(maxSizeBytes), tags.purpose, tags.temporary])" \
  --output tsv)"
expected_destination_shape="${expected_destination_id}|${destination_database}|Online|GP_S_Gen5_1|1|60|0.5|false|Local|${source_max_size_bytes}|pitr-restore-drill|true"
if [[ "$destination_shape" != "$expected_destination_shape" ]]; then
  echo "The restored database did not reach the exact expected identity, state, tags and cost shape" >&2
  exit 5
fi
source_id_after="$(az sql db show --subscription "$AZURE_SUBSCRIPTION_ID" \
  --resource-group "$resource_group" --server "$sql_server" --name "$source_database" \
  --query id --output tsv)"
if [[ "$source_id_after" != "$expected_source_id" ]]; then
  echo "The source database identity could not be reverified after PITR" >&2
  exit 5
fi

echo "PITR completed: ${destination_database} is Online with the bounded dev compute shape and source-derived maxSizeBytes ${source_max_size_bytes}."
echo "Source ${source_database} still exists at its original resource ID."
echo "No database was deleted. Preserve the destination until evidence is approved; cleanup is a separate authorized operation."
