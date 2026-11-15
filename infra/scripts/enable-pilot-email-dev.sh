#!/usr/bin/env bash
# Isolated ACS email setup. Requires owner approval for this new metered service.
# Pricing reference: https://learn.microsoft.com/azure/communication-services/concepts/email-pricing
set -euo pipefail
[[ "${RF_PILOT_EMAIL_CONFIRMATION:-}" == 'ENABLE-PILOT-ACCOUNT-EMAIL' ]] || exit 64
task_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
task_group='rg-rf-dev-ag26rf01'
[[ "$(az account show --query id -o tsv)" == '3ff82cd2-ffe5-4196-bc0f-547a0cc099cf' ]] || exit 64
[[ "$(az account show --query tenantId -o tsv)" == 'b3e91f16-1727-41da-a381-0b6b6bf936fa' ]] || exit 64
# The template creates a free Azure-managed sender domain and a narrowly scoped
# custom read/write ACS role for the existing API identity. No secrets are read.
task_result="$(az deployment group create -g "$task_group" -n 'pilot-account-email' --template-file "$task_root/infra/modules/pilot-email.bicep" --parameters enabled=true --query properties.outputs -o json --only-show-errors)"
task_endpoint="$(jq -er '.endpoint.value' <<< "$task_result")"
task_domain="$(jq -er '.mailFromDomain.value' <<< "$task_result")"
[[ "$task_endpoint" == https://*.communication.azure.com && "$task_domain" == *.azurecomm.net ]] || exit 65
# Does not alter image, scaling, other flags, payment settings, or worker triggers.
az containerapp update -g "$task_group" -n ca-rf-dev-ag26rf01-api --set-env-vars \
 "Email__Enabled=true" "Email__Endpoint=$task_endpoint" "Email__FromAddress=donotreply@$task_domain" \
 --only-show-errors --query '{revision:properties.latestRevisionName,ready:properties.latestReadyRevisionName}' -o json
