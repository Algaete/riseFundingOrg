#!/usr/bin/env bash
# Default: read-only status. Preflight is reverted. Release requires exact main + green CI.
set -euo pipefail
mode="${1:---status}"
[[ "$mode" == "--status" || "$mode" == "--preflight" || "$mode" == "--release" ]] || { echo 'Use --status, --preflight or --release.' >&2; exit 2; }
task_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if [[ "$mode" == '--release' ]]; then
  [[ "${RF_DEV_DATABASE_CONFIRMATION:-}" == 'DEPLOY-DEV-DATABASE' && "${RF_DEV_RELEASE_SHA:-}" =~ ^[0-9a-f]{40}$ ]] || { echo 'Explicit database release confirmation and SHA required.' >&2; exit 2; }
  [[ "$(git -C "$task_root" rev-parse HEAD)" == "$RF_DEV_RELEASE_SHA" && -z "$(git -C "$task_root" status --porcelain --untracked-files=normal)" ]] || { echo 'Release checkout must be clean at the exact SHA.' >&2; exit 3; }
  [[ "$(git -C "$task_root" remote get-url origin)" == 'https://github.com/Algaete/riseFundingOrg.git' ]] || exit 3
  [[ "$(git -C "$task_root" ls-remote --heads origin main | awk '{print $1}')" == "$RF_DEV_RELEASE_SHA" ]] || { echo 'Release SHA is not current origin/main.' >&2; exit 3; }
  task_ci="$(curl --fail --silent --show-error --max-time 20 'https://api.github.com/repos/Algaete/riseFundingOrg/actions/workflows/ci.yml/runs?branch=main&event=push&per_page=20')"
  jq -e --arg sha "$RF_DEV_RELEASE_SHA" '[.workflow_runs[] | select(.head_sha == $sha)][0] | .status == "completed" and .conclusion == "success"' <<< "$task_ci" >/dev/null || { echo 'The exact main release requires successful CI.' >&2; exit 3; }
fi
task_group='rg-rf-dev-ag26rf01'
task_server='sql-rf-dev-ag26rf01-centralus'
task_database='risefunding-dev'
[[ "$(az account show --query id -o tsv)" == '3ff82cd2-ffe5-4196-bc0f-547a0cc099cf' ]] || { echo 'Unexpected subscription.' >&2; exit 3; }
[[ "$(az account show --query tenantId -o tsv)" == 'b3e91f16-1727-41da-a381-0b6b6bf936fa' ]] || { echo 'Unexpected tenant.' >&2; exit 3; }
task_fqdn="$(az sql server show -g "$task_group" -n "$task_server" --query fullyQualifiedDomainName -o tsv)"
[[ "$task_fqdn" == 'sql-rf-dev-ag26rf01-centralus.database.windows.net' ]] || { echo 'Unexpected server.' >&2; exit 3; }
[[ "$(az sql db show -g "$task_group" -s "$task_server" -n "$task_database" --query name -o tsv)" == "$task_database" ]] || exit 3
if [[ "$mode" == '--release' ]]; then
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
if [[ "$mode" == '--release' ]]; then
  # No account bootstrap, identity provisioning, data seeding outside migrations or paid services.
  for task_operation in --preflight --apply --apply --test; do
    "$task_root/.dotnet/dotnet" run --no-restore --project tools/FundingPlatform.DatabaseMigrator -- "$task_operation"
  done
  echo "Database release completed for $RF_DEV_RELEASE_SHA; repeated apply must report zero pending migrations."
elif [[ "$mode" == '--status' ]]; then
  # Object inventory can contain thousands of lines; keep only the migration summary.
  "$task_root/.dotnet/dotnet" run --no-restore --project tools/FundingPlatform.DatabaseMigrator -- "$mode" | awk '/^Objetos/{print; hide=1} /^Full-Text/{hide=0} !hide {print}'
else
  "$task_root/.dotnet/dotnet" run --no-restore --project tools/FundingPlatform.DatabaseMigrator -- "$mode"
fi
