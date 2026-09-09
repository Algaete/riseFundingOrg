#!/usr/bin/env bash
# Release code only to the existing dev general worker; preserve exactly three import triggers.
set -euo pipefail
task_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
[[ "${RF_DEV_WORKER_CONFIRMATION:-}" == 'DEPLOY-DEV-GENERAL-WORKER' && "${RF_DEV_RELEASE_SHA:-}" =~ ^[0-9a-f]{40}$ ]] || { echo 'Explicit worker release confirmation and SHA required.' >&2; exit 2; }
[[ $# == 1 && -d "$1" ]] || { echo 'Pass the verified worker artifact directory.' >&2; exit 2; }
task_artifacts="$(cd "$1" && pwd)"
[[ "$(git -C "$task_root" rev-parse HEAD)" == "$RF_DEV_RELEASE_SHA" && -z "$(git -C "$task_root" status --porcelain --untracked-files=normal)" ]] || exit 3
[[ "$(git -C "$task_root" remote get-url origin)" == 'https://github.com/Algaete/riseFundingOrg.git' ]] || exit 3
[[ "$(git -C "$task_root" ls-remote --heads origin main | awk '{print $1}')" == "$RF_DEV_RELEASE_SHA" ]] || { echo 'Release SHA must be current origin/main.' >&2; exit 3; }
task_ci="$(curl --fail --silent --show-error --max-time 20 'https://api.github.com/repos/Algaete/riseFundingOrg/actions/workflows/ci.yml/runs?branch=main&event=push&per_page=20')"
jq -e --arg sha "$RF_DEV_RELEASE_SHA" '[.workflow_runs[] | select(.head_sha == $sha)][0] | .status == "completed" and .conclusion == "success"' <<< "$task_ci" >/dev/null || { echo 'Exact release CI must be successful.' >&2; exit 3; }
python3 "$task_root/infra/scripts/package-workers.py" verify --artifact-directory "$task_artifacts" --source-revision "$RF_DEV_RELEASE_SHA"
[[ "$(az account show --query id -o tsv)" == '3ff82cd2-ffe5-4196-bc0f-547a0cc099cf' && "$(az account show --query tenantId -o tsv)" == 'b3e91f16-1727-41da-a381-0b6b6bf936fa' ]] || exit 3
task_group='rg-rf-dev-ag26rf01'
task_app='func-rf-dev-ag26rf01-general'
task_resource="$(az resource show -g "$task_group" -n "$task_app" --resource-type Microsoft.Web/sites --api-version 2025-03-01 --query '{name:name,kind:kind,tags:tags,state:properties.state,runtime:properties.functionAppConfig.runtime}' -o json)"
jq -e --arg name "$task_app" '.name == $name and .kind == "functionapp,linux" and .state == "Running" and .runtime.name == "dotnet-isolated" and .runtime.version == "10.0" and .tags.application == "rise-funding-org" and .tags.environment == "dev"' <<< "$task_resource" >/dev/null || { echo 'Worker identity/runtime drifted.' >&2; exit 3; }
task_manifest="$task_artifacts/general-workers.manifest.json"
read_flags() {
  az functionapp config appsettings list -g "$task_group" -n "$task_app" \
    --query "[?starts_with(name, 'AzureWebJobs.') || name=='PROJECT_ASSETS_ENABLED' || name=='ProjectAssets__Enabled'].{name:name,value:value}" -o json
}
validate_flags() {
  local task_allow_missing="$1"
  jq -e --argjson allowMissing "$task_allow_missing" --slurpfile manifest "$task_manifest" '
    def imports: ["ImportSchedulerFunction", "ImportOutboxDispatcherFunction", "ImportQueueFunction"];
    def assets: ["ProjectAssetContentRetentionFunction", "ProjectAssetDefenderEventGridFunction", "ProjectAssetDefenderScanWatchdogFunction"];
    . as $settings | all($manifest[0].functions[]; . as $function |
      [$settings[] | select(.name == ("AzureWebJobs." + $function + ".Disabled")) | .value] as $values |
      if (imports | index($function)) != null then $values == ["false"]
      else $values == ["true"] or ($allowMissing and ($values | length) == 0 and (assets | index($function)) != null) end)
    and all(.[] | select(.name == "PROJECT_ASSETS_ENABLED" or .name == "ProjectAssets__Enabled"); .value == "false")
  ' <<< "$task_flags" >/dev/null
}
task_flags="$(read_flags)"
validate_flags true || { echo 'Trigger or asset flags differ from the reviewed import-only boundary.' >&2; exit 3; }
# New functions must be disabled before their code is indexed. Do not enable other jobs.
az functionapp config appsettings set -g "$task_group" -n "$task_app" --settings \
  AzureWebJobs.ProjectAssetContentRetentionFunction.Disabled=true \
  AzureWebJobs.ProjectAssetDefenderEventGridFunction.Disabled=true \
  AzureWebJobs.ProjectAssetDefenderScanWatchdogFunction.Disabled=true \
  PROJECT_ASSETS_ENABLED=false --only-show-errors -o none
task_flags="$(read_flags)"
validate_flags false || { echo 'New trigger disable flags were not confirmed; code was not published.' >&2; exit 3; }
az functionapp deployment source config-zip -g "$task_group" -n "$task_app" \
  --src "$task_artifacts/general-workers.zip" --build-remote false --timeout 300 --only-show-errors -o none
task_flags="$(read_flags)"
validate_flags false || { echo 'Post-release trigger flags drifted; inspect worker before proceeding.' >&2; exit 3; }
echo "General worker code published for $RF_DEV_RELEASE_SHA; only the three existing import triggers are enabled."
