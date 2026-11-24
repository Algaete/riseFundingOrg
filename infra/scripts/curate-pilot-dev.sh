#!/usr/bin/env bash
# Preview executes inside a rolled-back transaction. Apply commits the reviewed catalog.
# Both modes temporarily allow only the current client IP and remove that rule on exit.
set -euo pipefail
mode="${1:---preview}"
[[ "$mode" == '--preview' || "$mode" == '--apply' || "$mode" == '--preview-expansion' || "$mode" == '--apply-expansion' || "$mode" == '--inspect-expansion' || "$mode" == '--preview-eligibility' || "$mode" == '--apply-eligibility' || "$mode" == '--preview-resume' || "$mode" == '--apply-resume' || "$mode" == '--preview-scale' || "$mode" == '--apply-scale' || "$mode" == '--preview-next' || "$mode" == '--apply-next' || "$mode" == '--preview-regions' || "$mode" == '--apply-regions' || "$mode" == '--preview-more' || "$mode" == '--apply-more' ]] || exit 64
task_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if [[ "$mode" == '--apply' ]]; then
  [[ "${RF_PILOT_CATALOG_CONFIRMATION:-}" == 'PUBLISH-THREE-REVIEWED-FUNDS-AND-WITHDRAW-TWO-SAMPLES' ]] || exit 64
fi
if [[ "$mode" == '--apply-expansion' ]]; then
  [[ "${RF_CATALOG_EXPANSION_CONFIRMATION:-}" == 'PUBLISH-FOUR-NEW-AND-CORRECT-FOUR-REVIEWED-FUNDS' ]] || exit 64
fi
if [[ "$mode" == '--apply-eligibility' ]]; then
  [[ "${RF_CATALOG_ELIGIBILITY_CONFIRMATION:-}" == 'PUBLISH-THREE-NEW-REVIEW-SEVEN-AND-ACTIVATE-ELIGIBILITY-V3' ]] || exit 64
fi
if [[ "$mode" == '--apply-resume' ]]; then
  [[ "${RF_CATALOG_REVIEWED_CONFIRMATION:-}" == 'PUBLISH-FIVE-REVIEWED-CHILE-OPPORTUNITIES-20261122' ]] || exit 64
fi
if [[ "$mode" == '--apply-scale' ]]; then
  [[ "${RF_CATALOG_SCALE_CONFIRMATION:-}" == 'PUBLISH-FOURTEEN-REVIEWED-CHILE-OPPORTUNITIES-20261122' ]] || exit 64
fi
if [[ "$mode" == '--apply-next' ]]; then
  [[ "${RF_CATALOG_NEXT_CONFIRMATION:-}" == 'PUBLISH-SIXTEEN-REVIEWED-CHILE-OPPORTUNITIES-20261123' ]] || exit 64
fi
if [[ "$mode" == '--apply-regions' ]]; then
  [[ "${RF_CATALOG_REGIONS_CONFIRMATION:-}" == 'CONFIRM-FAE-AND-MAPFRE-ALL-SIXTEEN-CHILE-REGIONS-20261123' ]] || exit 64
fi
if [[ "$mode" == '--apply-more' ]]; then
  [[ "${RF_CATALOG_MORE_CONFIRMATION:-}" == 'PUBLISH-TEN-REVIEWED-CHILE-OPPORTUNITIES-20261124' ]] || exit 64
fi
task_group='rg-rf-dev-ag26rf01'
task_server='sql-rf-dev-ag26rf01-centralus'
task_database='risefunding-dev'
[[ "$(az account show --query id -o tsv)" == '3ff82cd2-ffe5-4196-bc0f-547a0cc099cf' ]] || { echo 'Unexpected subscription.' >&2; exit 3; }
[[ "$(az account show --query tenantId -o tsv)" == 'b3e91f16-1727-41da-a381-0b6b6bf936fa' ]] || { echo 'Unexpected tenant.' >&2; exit 3; }
task_fqdn="$(az sql server show -g "$task_group" -n "$task_server" --query fullyQualifiedDomainName -o tsv)"
[[ "$task_fqdn" == 'sql-rf-dev-ag26rf01-centralus.database.windows.net' ]] || { echo 'Unexpected server.' >&2; exit 3; }
[[ "$(az sql db show -g "$task_group" -s "$task_server" -n "$task_database" --query name -o tsv)" == "$task_database" ]] || exit 3
if [[ "$mode" == '--apply' || "$mode" == '--apply-expansion' || "$mode" == '--apply-eligibility' || "$mode" == '--apply-resume' || "$mode" == '--apply-scale' || "$mode" == '--apply-next' || "$mode" == '--apply-regions' || "$mode" == '--apply-more' ]]; then
  task_retention="$(az sql db str-policy show -g "$task_group" -s "$task_server" -n "$task_database" --query retentionDays -o tsv)"
  [[ "$task_retention" =~ ^[0-9]+$ ]] && (( task_retention >= 7 )) || { echo 'At least seven days PITR retention required.' >&2; exit 3; }
  [[ -n "$(az sql db show -g "$task_group" -s "$task_server" -n "$task_database" --query earliestRestoreDate -o tsv)" ]] || { echo 'No existing restore window confirmed.' >&2; exit 3; }
fi
task_client_ip="$(curl --fail --silent --show-error --max-time 15 https://api.ipify.org)"
[[ "$task_client_ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || { echo 'Invalid client IPv4.' >&2; exit 4; }
IFS=. read -r task_a task_b task_c task_d <<< "$task_client_ip"
for task_octet in "$task_a" "$task_b" "$task_c" "$task_d"; do (( 10#$task_octet <= 255 )) || exit 4; done
[[ "$task_a" != '0' && "$task_a" != '10' && "$task_a" != '127' && "$task_a" != '169' ]] || exit 4
task_rule="TemporaryMigrationClient-check-$(date -u +%Y%m%d%H%M%S)-$$"
[[ -z "$(az sql server firewall-rule list -g "$task_group" -s "$task_server" --query "[?name=='$task_rule'].name" -o tsv)" ]] || exit 4
task_created=false
cleanup() {
  if [[ "$task_created" == true ]]; then
    if ! az sql server firewall-rule delete -g "$task_group" -s "$task_server" -n "$task_rule" --only-show-errors -o none; then
      echo "ATTENTION: temporary rule cleanup failed: $task_group/$task_server/$task_rule" >&2
      return 1
    fi
    echo 'Temporary single-IP database firewall rule removed.'
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
# Mark before creation so an ambiguous network response still triggers exact-target cleanup.
task_created=true
az sql server firewall-rule create -g "$task_group" -s "$task_server" -n "$task_rule" \
  --start-ip-address "$task_client_ip" --end-ip-address "$task_client_ip" --only-show-errors -o none
export DOTNET_ENVIRONMENT=Staging
export AZURE_TOKEN_CREDENTIALS=AzureCliCredential
export MIGRATION_REPORT_PROGRESS=true
export MIGRATION_EXPECTED_DATABASE_NAME="$task_database"
export MIGRATION_EXPECTED_SERVER_FQDN="$task_fqdn"
export AZURE_SQL_CONNECTION_STRING="Server=tcp:$task_fqdn,1433;Initial Catalog=$task_database;Encrypt=True;TrustServerCertificate=False;Authentication=Active Directory Default;Connection Timeout=30;"
cd "$task_root"
"$task_root/.dotnet/dotnet" tools/FundingPlatform.PilotCatalog/bin/Release/net10.0/FundingPlatform.PilotCatalog.dll "$mode"
