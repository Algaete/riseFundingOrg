#!/usr/bin/env bash
set -euo pipefail

# This release path uses existing RG/ACR permissions. Its only mutations are an
# ACR image build and the existing API's image plus the three telemetry settings.
uuid_pattern='^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
if [[ ! "${AZURE_SUBSCRIPTION_ID:-}" =~ $uuid_pattern ]] ||
   [[ ! "${AZURE_TENANT_ID:-}" =~ $uuid_pattern ]] ||
   [[ ! "${AZURE_UNIQUE_SUFFIX:-}" =~ ^[a-z0-9]{8}$ ]] ||
   [[ ! "${AZURE_SQL_LOCATION:-}" =~ ^[a-z0-9]+$ ]]; then
  echo "Explicit Azure subscription/tenant UUIDs, immutable dev suffix and SQL region are required" >&2
  exit 2
fi
if [[ "${GITHUB_REF:-}" != "refs/heads/main" ||
      ! "${EXPECTED_RELEASE_SHA:-}" =~ ^[0-9a-f]{40}$ ||
      "${EXPECTED_RELEASE_SHA:-}" != "${GITHUB_SHA:-}" ]]; then
  echo "The release must be the explicitly approved 40-character main commit" >&2
  exit 2
fi
if [[ "${AZURE_API_DEPLOY_CONFIRMATION:-}" != "DEPLOY-DEV-API" ]]; then
  echo "AZURE_API_DEPLOY_CONFIRMATION=DEPLOY-DEV-API is required" >&2
  exit 4
fi
for dependency in az jq git; do command -v "$dependency" >/dev/null; done
# azure/CLI runs in a container with a different UID from checkout. Trust only
# this exact working directory for these read-only git commands, not globally.
repository_root="$(git -c safe.directory="$PWD" rev-parse --show-toplevel)"
cd "$repository_root"
if [[ "$(git -c safe.directory="$repository_root" rev-parse HEAD)" != "$EXPECTED_RELEASE_SHA" ||
      -n "$(git -c safe.directory="$repository_root" status --porcelain --untracked-files=normal)" ]]; then
  echo "Build context must be a clean checkout of the approved release commit" >&2
  exit 2
fi
test -f src/FundingPlatform.Api/Dockerfile
test -f .dockerignore
test -f infra/scripts/verify-dev.sh
# Use the pinned CLI's built-in commands, without installing extensions at runtime.
export AZURE_EXTENSION_USE_DYNAMIC_INSTALL=no

actual_subscription="$(az account show --query id --output tsv --only-show-errors)"
actual_tenant="$(az account show --query tenantId --output tsv --only-show-errors)"
if [[ "$actual_subscription" != "$AZURE_SUBSCRIPTION_ID" || "$actual_tenant" != "$AZURE_TENANT_ID" ]]; then
  echo "Azure CLI is authenticated to a different subscription or tenant" >&2
  exit 3
fi

resource_group="rg-rf-dev-${AZURE_UNIQUE_SUFFIX}"
resource_group_id="/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${resource_group}"
api_name="ca-rf-dev-${AZURE_UNIQUE_SUFFIX}-api"
api_id="${resource_group_id}/providers/Microsoft.App/containerApps/${api_name}"
api_identity_name="id-rf-dev-${AZURE_UNIQUE_SUFFIX}-api"
api_identity_id="${resource_group_id}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/${api_identity_name}"
api_environment_id="${resource_group_id}/providers/Microsoft.App/managedEnvironments/cae-rf-dev-${AZURE_UNIQUE_SUFFIX}"

# ARM resource IDs are case-insensitive; providers return mixed casing even for
# the same resource. Compare their complete values, normalizing casing only.
owned_tags='def arm_equals($expected): type == "string" and (ascii_downcase == ($expected | ascii_downcase)); def owned: .tags.application == "rise-funding-org" and .tags.environment == "dev" and .tags.managedBy == "bicep" and .tags.dataClassification == "confidential";'
group_json="$(az group show --name "$resource_group" --output json --only-show-errors)"
jq -e --arg id "$resource_group_id" --arg name "$resource_group" \
  "${owned_tags} owned and (.id | arm_equals(\$id)) and .name == \$name and .properties.provisioningState == \"Succeeded\"" \
  <<<"$group_json" >/dev/null || { echo "Resource group identity, ownership tags or readiness do not match dev" >&2; exit 3; }

identity_json="$(az identity show --resource-group "$resource_group" --name "$api_identity_name" --output json --only-show-errors)"
jq -e --arg id "$api_identity_id" --arg name "$api_identity_name" --arg tenant "$AZURE_TENANT_ID" \
  "${owned_tags} owned and (.id | arm_equals(\$id)) and .name == \$name and (.type | arm_equals(\"Microsoft.ManagedIdentity/userAssignedIdentities\")) and .tenantId == \$tenant and (.clientId | type == \"string\" and length > 0) and (.principalId | type == \"string\" and length > 0)" \
  <<<"$identity_json" >/dev/null || { echo "The existing API managed identity does not match dev" >&2; exit 3; }
api_client_id="$(jq -er '.clientId' <<<"$identity_json")"
api_principal_id="$(jq -er '.principalId' <<<"$identity_json")"
[[ "$api_client_id" =~ $uuid_pattern && "$api_principal_id" =~ $uuid_pattern ]] || exit 3

registries_json="$(az acr list --resource-group "$resource_group" --output json --only-show-errors)"
jq -e 'type == "array" and length == 1' <<<"$registries_json" >/dev/null || {
  echo "Expected exactly one existing dev Container Registry" >&2; exit 3;
}
registry_json="$(jq -c '.[0]' <<<"$registries_json")"
registry_name="$(jq -er '.name' <<<"$registry_json")"
if [[ ! "$registry_name" =~ ^crrfdev${AZURE_UNIQUE_SUFFIX}[a-z0-9]{13}$ ]]; then
  echo "Container Registry name does not match the immutable dev naming scheme" >&2
  exit 3
fi
registry_id="${resource_group_id}/providers/Microsoft.ContainerRegistry/registries/${registry_name}"
registry_server="${registry_name}.azurecr.io"
jq -e --arg id "$registry_id" --arg server "$registry_server" \
  "${owned_tags} owned and (.id | arm_equals(\$id)) and (.type == null or (.type | arm_equals(\"Microsoft.ContainerRegistry/registries\"))) and .loginServer == \$server and .tags.boundary == \"private-container-images\" and .provisioningState == \"Succeeded\" and .sku.name == \"Basic\" and .adminUserEnabled == false and .anonymousPullEnabled == false" \
  <<<"$registry_json" >/dev/null || { echo "Container Registry ownership or security settings do not match dev" >&2; exit 3; }

read_api() {
  az resource show --resource-group "$resource_group" --name "$api_name" \
    --resource-type Microsoft.App/containerApps --api-version 2025-01-01 \
    --output json --only-show-errors
}

validate_api() {
  jq -e --arg id "$api_id" --arg name "$api_name" --arg identity "$api_identity_id" \
    --arg client "$api_client_id" --arg principal "$api_principal_id" \
    --arg environment "$api_environment_id" --arg server "$registry_server" "${owned_tags}"'
      def setting($name): [.properties.template.containers[0].env[] | select(.name == $name) | .value][0];
      owned and (.id | arm_equals($id)) and .name == $name and (.type | arm_equals("Microsoft.App/containerApps")) and
      .identity.type == "UserAssigned" and (.identity.userAssignedIdentities | keys | map(ascii_downcase)) == [($identity | ascii_downcase)] and
      (.identity.userAssignedIdentities | to_entries[0].value.clientId) == $client and
      (.identity.userAssignedIdentities | to_entries[0].value.principalId) == $principal and
      (.properties.managedEnvironmentId | arm_equals($environment)) and
      .properties.provisioningState == "Succeeded" and
      (.properties.latestRevisionName | type == "string" and length > 0) and
      .properties.latestRevisionName == .properties.latestReadyRevisionName and
      .properties.configuration.activeRevisionsMode == "Single" and
      .properties.configuration.ingress.external == true and
      .properties.configuration.ingress.allowInsecure == false and
      .properties.configuration.ingress.targetPort == 8080 and
      (.properties.configuration.ingress.fqdn | test("^[a-z0-9-]+(\\.[a-z0-9-]+)*\\.azurecontainerapps\\.io$")) and
      (.properties.configuration.ingress.traffic | length == 1) and
      .properties.configuration.ingress.traffic[0].latestRevision == true and
      .properties.configuration.ingress.traffic[0].weight == 100 and
      (.properties.configuration.registries | length == 1) and
      .properties.configuration.registries[0].server == $server and
      (.properties.configuration.registries[0].identity | arm_equals($identity)) and
      (.properties.template.containers | length == 1) and
      .properties.template.containers[0].name == "api" and
      ([.properties.template.containers[0].env[].name] | length == (unique | length)) and
      .properties.template.scale.maxReplicas == 1 and
      (.properties.template.scale.minReplicas == 0 or .properties.template.scale.minReplicas == 1) and
      setting("ASPNETCORE_ENVIRONMENT") == "Production" and
      setting("AZURE_CLIENT_ID") == $client and
      (setting("APPLICATIONINSIGHTS_CONNECTION_STRING") | type == "string" and length > 0) and
      setting("APPLICATIONINSIGHTS_AUTHENTICATION_STRING") == ("ClientId=" + $client + ";Authorization=AAD")
    ' >/dev/null
}

# Keep configuration in process memory only. Logs and the job summary receive
# release identifiers, never the resource JSON, environment values or secrets.
api_before="$(read_api)"
validate_api <<<"$api_before" || { echo "API ownership, identity, ingress, scale or ready revision do not match dev" >&2; exit 3; }
previous_image="$(jq -er '.properties.template.containers[0].image' <<<"$api_before")"
previous_digest="${previous_image#${registry_server}/rise-funding-api@}"
if [[ "$previous_image" != "${registry_server}/rise-funding-api@"* || ! "$previous_digest" =~ ^sha256:[0-9a-f]{64}$ ]]; then
  echo "The current API image must already be pinned to a digest in the exact dev repository" >&2
  exit 3
fi
previous_revision="$(jq -er '.properties.latestReadyRevisionName' <<<"$api_before")"
if [[ ! "$previous_revision" =~ ^${api_name}--[a-z0-9-]+$ ]]; then
  echo "The ready revision name does not belong to the exact dev API" >&2
  exit 3
fi
previous_min="$(jq -er '.properties.template.scale.minReplicas' <<<"$api_before")"

release_summary() {
  printf '%s\n' "$1"
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then printf '%s\n' "$1" >> "$GITHUB_STEP_SUMMARY"; fi
}
release_summary "API release commit: ${EXPECTED_RELEASE_SHA}"
release_summary "Rollback image digest: ${previous_digest}"
release_summary "Previous ready revision: ${previous_revision}"
release_summary "Preserved API replicas: min=${previous_min}, max=1"

az acr build --registry "$registry_name" --resource-group "$resource_group" \
  --image "rise-funding-api:${EXPECTED_RELEASE_SHA}" \
  --file src/FundingPlatform.Api/Dockerfile --platform linux/amd64 \
  --no-logs --output none --only-show-errors .
image_digest="$(az acr manifest show-metadata --registry "$registry_name" \
  --name "rise-funding-api:${EXPECTED_RELEASE_SHA}" --query digest --output tsv --only-show-errors)"
if [[ ! "$image_digest" =~ ^sha256:[0-9a-f]{64}$ ]]; then
  echo "ACR did not return a valid OCI image digest" >&2
  exit 5
fi
target_image="${registry_server}/rise-funding-api@${image_digest}"
release_summary "New API image digest: ${image_digest}"

stable_configuration() {
  jq -cS '{id, name, type, location, tags, identity, extendedLocation,
    properties: (.properties | {managedEnvironmentId, environmentId, workloadProfileName, configuration, template})}
    | del(.properties.template.revisionSuffix)
    | .properties.template.containers[0].env |= sort_by(.name)'
}
unchanged_configuration() {
  stable_configuration | jq -cS '
    del(.properties.template.containers[0].image)
    | .properties.template.containers[0].env |= map(select(
      .name != "OTEL_SERVICE_NAME" and
      .name != "OTEL_DOTNET_EXPERIMENTAL_ASPNETCORE_DISABLE_URL_QUERY_REDACTION" and
      .name != "OTEL_DOTNET_EXPERIMENTAL_HTTPCLIENT_DISABLE_URL_QUERY_REDACTION"))'
}

# The shared workflow concurrency group also serializes infrastructure changes.
# Recheck after the remote build so an external configuration change stops us.
api_pre_update="$(read_api)"
if ! validate_api <<<"$api_pre_update" ||
   [[ "$(stable_configuration <<<"$api_before")" != "$(stable_configuration <<<"$api_pre_update")" ]] ||
   [[ "$(jq -r '.properties.latestReadyRevisionName' <<<"$api_pre_update")" != "$previous_revision" ]]; then
  echo "API changed during the image build; deployment stopped before updating it" >&2
  exit 5
fi

# --set-env-vars merges only these keys; --replace-env-vars would erase settings.
az containerapp update --resource-group "$resource_group" --name "$api_name" \
  --container-name api --image "$target_image" \
  --set-env-vars \
    OTEL_SERVICE_NAME=FundingPlatform.Api \
    OTEL_DOTNET_EXPERIMENTAL_ASPNETCORE_DISABLE_URL_QUERY_REDACTION=false \
    OTEL_DOTNET_EXPERIMENTAL_HTTPCLIENT_DISABLE_URL_QUERY_REDACTION=false \
  --output none --only-show-errors

release_ready=false
for _ in {1..30}; do
  api_after="$(read_api)"
  if jq -e --arg image "$target_image" '
    .properties.provisioningState == "Succeeded" and
    (.properties.latestRevisionName | type == "string" and length > 0) and
    .properties.latestRevisionName == .properties.latestReadyRevisionName and
    .properties.template.containers[0].image == $image
  ' <<<"$api_after" >/dev/null; then
    release_ready=true
    break
  fi
  sleep 10
done
if [[ "$release_ready" != "true" ]]; then
  echo "The new API revision did not become ready within five minutes; use the recorded rollback digest" >&2
  exit 5
fi
if ! validate_api <<<"$api_after" ||
   [[ "$(unchanged_configuration <<<"$api_before")" != "$(unchanged_configuration <<<"$api_after")" ]] ||
   ! jq -e '
     [.properties.template.containers[0].env[] | select(.name == "OTEL_SERVICE_NAME")] == [{name:"OTEL_SERVICE_NAME", value:"FundingPlatform.Api"}] and
     [.properties.template.containers[0].env[] | select(.name == "OTEL_DOTNET_EXPERIMENTAL_ASPNETCORE_DISABLE_URL_QUERY_REDACTION")] == [{name:"OTEL_DOTNET_EXPERIMENTAL_ASPNETCORE_DISABLE_URL_QUERY_REDACTION", value:"false"}] and
     [.properties.template.containers[0].env[] | select(.name == "OTEL_DOTNET_EXPERIMENTAL_HTTPCLIENT_DISABLE_URL_QUERY_REDACTION")] == [{name:"OTEL_DOTNET_EXPERIMENTAL_HTTPCLIENT_DISABLE_URL_QUERY_REDACTION", value:"false"}]
   ' <<<"$api_after" >/dev/null; then
  echo "Post-deployment configuration differs outside the approved image/telemetry changes; inspect before further deployment" >&2
  exit 5
fi

AZURE_API_MIN_REPLICAS="$previous_min" bash infra/scripts/verify-dev.sh api
release_summary "Verified ready API revision: $(jq -er '.properties.latestReadyRevisionName' <<<"$api_after")"
release_summary "API-only deployment and existing-environment verification completed."
