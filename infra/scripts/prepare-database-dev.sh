#!/usr/bin/env bash
set -euo pipefail

required=(
  AZURE_SUBSCRIPTION_ID
  AZURE_TENANT_ID
  AZURE_UNIQUE_SUFFIX
  RF_DEV_RELEASE_SHA
  RF_DEV_SQL_ADMIN_GROUP_OBJECT_ID
  RF_DEV_SQL_ADMIN_GROUP_NAME
  RF_DEV_ADMIN_EMAIL
)
for name in "${required[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    echo "${name} is required" >&2
    exit 2
  fi
done
if [[ ! "$AZURE_SUBSCRIPTION_ID" =~ ^[0-9a-fA-F-]{36}$ ]] ||
   [[ ! "$AZURE_TENANT_ID" =~ ^[0-9a-fA-F-]{36}$ ]] ||
   [[ ! "$RF_DEV_SQL_ADMIN_GROUP_OBJECT_ID" =~ ^[0-9a-fA-F-]{36}$ ]]; then
  echo "Subscription, tenant and SQL admin group IDs must be UUIDs" >&2
  exit 2
fi
if [[ ! "$AZURE_UNIQUE_SUFFIX" =~ ^[a-z0-9]{8}$ ]]; then
  echo "AZURE_UNIQUE_SUFFIX must be exactly 8 lowercase letters or digits" >&2
  exit 2
fi
if [[ ! "$RF_DEV_RELEASE_SHA" =~ ^[0-9a-f]{40}$ ]]; then
  echo "RF_DEV_RELEASE_SHA must be the exact lowercase Git commit SHA approved for deployment" >&2
  exit 2
fi
if [[ ! -t 0 || ! -t 1 ]]; then
  echo "An interactive terminal is required for the SuperAdmin password prompt" >&2
  exit 2
fi
available_kib="$(df -Pk . | awk 'NR == 2 { print $4 }')"
if [[ ! "$available_kib" =~ ^[0-9]+$ ]] || (( available_kib < 2097152 )); then
  echo "At least 2 GiB of free local disk is required before building and running deployment tools" >&2
  exit 3
fi

git fetch --quiet --no-tags origin main
actual_commit="$(git rev-parse HEAD)"
if [[ "$actual_commit" != "$RF_DEV_RELEASE_SHA" ||
      "$(git branch --show-current)" != "main" ||
      "$(git rev-parse origin/main)" != "$actual_commit" ||
      -n "$(git status --porcelain --untracked-files=normal)" ]]; then
  echo "The local checkout must be a clean main at the approved origin/main commit" >&2
  exit 3
fi

actual_subscription="$(az account show --query id --output tsv)"
actual_tenant="$(az account show --query tenantId --output tsv)"
if [[ "$actual_subscription" != "$AZURE_SUBSCRIPTION_ID" || "$actual_tenant" != "$AZURE_TENANT_ID" ]]; then
  echo "Azure CLI is authenticated to a different subscription or tenant" >&2
  exit 3
fi

operator_object_id="$(az ad signed-in-user show --query id --output tsv)"
admin_group_shape="$(az ad group show --group "$RF_DEV_SQL_ADMIN_GROUP_OBJECT_ID" \
  --query "join('|', [id, displayName])" --output tsv)"
if [[ "$admin_group_shape" != "${RF_DEV_SQL_ADMIN_GROUP_OBJECT_ID}|${RF_DEV_SQL_ADMIN_GROUP_NAME}" ]]; then
  echo "The configured SQL administrator group ID/name does not match Microsoft Entra" >&2
  exit 3
fi
operator_is_member="$(az ad group member check --group "$RF_DEV_SQL_ADMIN_GROUP_OBJECT_ID" \
  --member-id "$operator_object_id" --query value --output tsv)"
if [[ "$operator_is_member" != "true" ]]; then
  echo "The signed-in operator is not an active member of the Azure SQL administrator group" >&2
  exit 3
fi

resource_group="rg-rf-dev-${AZURE_UNIQUE_SUFFIX}"
sql_server_count="$(az sql server list --resource-group "$resource_group" --query 'length(@)' --output tsv)"
if [[ "$sql_server_count" != "1" ]]; then
  echo "Expected exactly one SQL server in ${resource_group}" >&2
  exit 3
fi
sql_server="$(az sql server list --resource-group "$resource_group" --query '[0].name' --output tsv)"
sql_server_fqdn="$(az sql server show --resource-group "$resource_group" --name "$sql_server" \
  --query fullyQualifiedDomainName --output tsv)"
if [[ "$sql_server_fqdn" != "${sql_server}.database.windows.net" ]]; then
  echo "Unexpected Azure SQL server FQDN" >&2
  exit 3
fi
sql_admin_count="$(az sql server ad-admin list --resource-group "$resource_group" \
  --server-name "$sql_server" --query 'length(@)' --output tsv)"
if [[ "$sql_admin_count" != "1" ]]; then
  echo "Expected exactly one Microsoft Entra administrator on the Azure SQL server" >&2
  exit 3
fi
sql_admin_row="$(az sql server ad-admin list --resource-group "$resource_group" \
  --server-name "$sql_server" --query '[0].[sid, login, tenantId]' --output tsv)"
IFS=$'\t' read -r sql_admin_sid sql_admin_login sql_admin_tenant <<<"$sql_admin_row"
if [[ "$sql_admin_sid" != "$RF_DEV_SQL_ADMIN_GROUP_OBJECT_ID" ||
      "$sql_admin_login" != "$RF_DEV_SQL_ADMIN_GROUP_NAME" ||
      "$sql_admin_tenant" != "$AZURE_TENANT_ID" ]]; then
  echo "The Azure SQL server administrator does not match the approved Entra group and tenant" >&2
  exit 3
fi
earliest_restore_date_before="$(az sql db show --resource-group "$resource_group" --server "$sql_server" \
  --name risefunding-dev --query earliestRestoreDate --output tsv)"
deployment_started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Database preparation starts at ${deployment_started_at}; earliestRestoreDate=${earliest_restore_date_before:-not-yet-available}."

stale_firewall_rules="$(az sql server firewall-rule list --resource-group "$resource_group" \
  --server "$sql_server" --query "[?starts_with(name, 'TemporaryMigrationClient-')].name" --output tsv)"
if [[ -n "$stale_firewall_rules" ]]; then
  echo "Stale temporary migration firewall rules must be reviewed and removed first: ${stale_firewall_rules//$'\n'/, }" >&2
  exit 3
fi

dev_public_ip="$(curl --fail --silent --show-error https://api.ipify.org)"
IFS='.' read -r ip1 ip2 ip3 ip4 extra <<<"$dev_public_ip"
if [[ -n "${extra:-}" || -z "${ip4:-}" ]] ||
   ! [[ "$ip1" =~ ^[0-9]{1,3}$ && "$ip2" =~ ^[0-9]{1,3}$ &&
        "$ip3" =~ ^[0-9]{1,3}$ && "$ip4" =~ ^[0-9]{1,3}$ ]] ||
   (( 10#$ip1 > 255 || 10#$ip2 > 255 || 10#$ip3 > 255 || 10#$ip4 > 255 )); then
  echo "The detected migration client address is not a valid IPv4 address" >&2
  exit 3
fi

firewall_rule="TemporaryMigrationClient-$(date -u +%Y%m%d%H%M%S)-$$"
firewall_created=false
cleanup_sql_firewall() {
  if [[ "$firewall_created" == "true" ]]; then
    if az sql server firewall-rule delete --resource-group "$resource_group" \
      --server "$sql_server" --name "$firewall_rule" --output none; then
      firewall_created=false
    else
      echo "WARNING: automatic SQL firewall cleanup failed for ${firewall_rule}." >&2
    fi
  fi
}
trap cleanup_sql_firewall EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
az sql server firewall-rule create --resource-group "$resource_group" \
  --server "$sql_server" --name "$firewall_rule" \
  --start-ip-address "$dev_public_ip" --end-ip-address "$dev_public_ip" --output none
firewall_created=true
echo "Temporary SQL firewall rule created for this session; automatic cleanup is armed."

export DOTNET_ENVIRONMENT=Staging
export MIGRATION_EXPECTED_DATABASE_NAME=risefunding-dev
export MIGRATION_EXPECTED_SERVER_FQDN="$sql_server_fqdn"
export AZURE_SQL_CONNECTION_STRING="Server=tcp:${sql_server_fqdn},1433;Initial Catalog=risefunding-dev;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;Authentication=Active Directory Default;"

if [[ -x ./.dotnet/dotnet ]]; then
  dotnet_command=(./.dotnet/dotnet)
else
  dotnet_path="$(command -v dotnet || true)"
  if [[ -z "$dotnet_path" ]]; then
    echo "The .NET SDK required by global.json is not available" >&2
    exit 3
  fi
  dotnet_command=("$dotnet_path")
fi
migrator=("${dotnet_command[@]}" run --project tools/FundingPlatform.DatabaseMigrator --)

connection_ready=false
for _ in {1..20}; do
  if "${migrator[@]}" --check-connection; then
    connection_ready=true
    break
  fi
  sleep 15
done
if [[ "$connection_ready" != "true" ]]; then
  echo "Azure SQL connectivity or firewall propagation did not become ready within five minutes" >&2
  exit 5
fi
initial_status="$("${migrator[@]}" --status)"
printf '%s\n' "$initial_status"
initial_recorded="$(printf '%s\n' "$initial_status" | awk -F': ' '/^Migraciones registradas: / { print $2 }')"
if [[ ! "$initial_recorded" =~ ^[0-9]+$ ]]; then
  echo "Could not verify the initial migration count" >&2
  exit 5
fi
if (( initial_recorded > 0 )) && [[ -z "$earliest_restore_date_before" ]]; then
  echo "A non-empty database must have an observable PITR window before migration" >&2
  exit 5
fi
"${migrator[@]}" --validate
"${migrator[@]}" --apply
"${migrator[@]}" --test
"${migrator[@]}" --provision-full-text

full_text_ready=false
for _ in {1..40}; do
  status_output="$("${migrator[@]}" --status)"
  full_text_state="$(printf '%s\n' "$status_output" | awk -F': ' '/^Full-Text 8A: / { print $2 }')"
  if [[ "$full_text_state" == "listo" ]]; then
    full_text_ready=true
    break
  fi
  if [[ "$full_text_state" != "poblando" ]]; then
    echo "Full-Text entered an unexpected state: ${full_text_state:-missing}" >&2
    exit 5
  fi
  sleep 15
done
if [[ "$full_text_ready" != "true" ]]; then
  echo "Full-Text did not become ready within ten minutes" >&2
  exit 5
fi
"${migrator[@]}" --provision-full-text
stable_status="$("${migrator[@]}" --status)"
if ! grep -Fq 'Full-Text 8A: listo' <<<"$stable_status"; then
  echo "Full-Text did not remain ready after the idempotent second provisioning" >&2
  exit 5
fi
reapply_output="$("${migrator[@]}" --apply)"
printf '%s\n' "$reapply_output"
if ! grep -Fq 'Aplicación correcta: 0 migración(es), 0 lote(s).' <<<"$reapply_output"; then
  echo "The second migration apply was not idempotent" >&2
  exit 5
fi
"${migrator[@]}" --test

identity_client_id() {
  local identity_name="$1"
  local client_id
  client_id="$(az identity show --resource-group "$resource_group" --name "$identity_name" \
    --query clientId --output tsv)"
  if [[ ! "$client_id" =~ ^[0-9a-fA-F-]{36}$ || "$client_id" == "00000000-0000-0000-0000-000000000000" ]]; then
    echo "Managed identity ${identity_name} did not return a valid client ID" >&2
    exit 3
  fi
  printf '%s' "$client_id"
}

api_user="id-rf-dev-${AZURE_UNIQUE_SUFFIX}-api"
general_user="id-func-rf-dev-${AZURE_UNIQUE_SUFFIX}-general-host"
consumer_user="id-rf-dev-${AZURE_UNIQUE_SUFFIX}-extract-consume"
extraction_host_user="id-func-rf-dev-${AZURE_UNIQUE_SUFFIX}-extract-host"
sender_user="id-rf-dev-${AZURE_UNIQUE_SUFFIX}-extract-send"
runtime_identity_args=(
  --api-user "$api_user" --api-client-id "$(identity_client_id "$api_user")"
  --general-worker-user "$general_user" --general-worker-client-id "$(identity_client_id "$general_user")"
  --extraction-consumer-user "$consumer_user" --extraction-consumer-client-id "$(identity_client_id "$consumer_user")"
  --extraction-host-user "$extraction_host_user" --extraction-host-client-id "$(identity_client_id "$extraction_host_user")"
  --extraction-sender-user "$sender_user" --extraction-sender-client-id "$(identity_client_id "$sender_user")"
)
"${migrator[@]}" --provision-runtime-identities "${runtime_identity_args[@]}"
identity_replay="$("${migrator[@]}" --provision-runtime-identities "${runtime_identity_args[@]}")"
printf '%s\n' "$identity_replay"
if ! grep -Fq 'creados=0, membresías agregadas=0.' <<<"$identity_replay"; then
  echo "Runtime identity provisioning was not idempotent" >&2
  exit 5
fi
"${migrator[@]}" --verify-runtime-identities "${runtime_identity_args[@]}"

admin_display_name="${RF_DEV_ADMIN_DISPLAY_NAME:-Administrador dev}"
set +e
"${dotnet_command[@]}" run --project tools/FundingPlatform.AdminCli -- \
  bootstrap-superadmin --email "$RF_DEV_ADMIN_EMAIL" --display-name "$admin_display_name"
bootstrap_exit=$?
set -e
if [[ "$bootstrap_exit" != "0" && "$bootstrap_exit" != "6" ]]; then
  echo "SuperAdmin bootstrap did not complete safely" >&2
  exit "$bootstrap_exit"
fi
"${dotnet_command[@]}" run --project tools/FundingPlatform.AdminCli -- list-admins

final_status="$("${migrator[@]}" --status)"
printf '%s\n' "$final_status"
if ! grep -Fq 'Migraciones registradas: 28' <<<"$final_status" ||
   ! grep -Fq 'Migraciones locales: 28' <<<"$final_status" ||
   ! grep -Fq 'Full-Text 8A: listo' <<<"$final_status"; then
  echo "Final database status is incomplete" >&2
  exit 5
fi
earliest_restore_date="$(az sql db show --resource-group "$resource_group" --server "$sql_server" \
  --name risefunding-dev --query earliestRestoreDate --output tsv)"
cleanup_sql_firewall
remaining_firewall_rules="$(az sql server firewall-rule list --resource-group "$resource_group" \
  --server "$sql_server" --query "[?name=='${firewall_rule}'] | length(@)" --output tsv)"
if [[ "$firewall_created" != "false" || "$remaining_firewall_rules" != "0" ]]; then
  echo "The temporary SQL firewall rule was not proven removed; deployment preparation is incomplete" >&2
  exit 5
fi
trap - EXIT INT TERM
echo "Database preparation passed for commit ${actual_commit}; earliestRestoreDate=${earliest_restore_date:-not-yet-available}."
