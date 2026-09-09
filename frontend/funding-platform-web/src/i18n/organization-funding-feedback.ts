import { ApiError } from '@/api/http-client'
import { requestValidationMessage } from '@/i18n/validation-issues'
import i18n from '@/i18n'

export function organizationFundingErrorMessage(error: unknown, fallback: 'organizationFunding.loadHelp' | 'organizationFunding.notAvailable') {
  const structured = requestValidationMessage(error)
  if (structured) return structured
  // Do not expose arbitrary server diagnostics.
  if (error instanceof ApiError) {
    const status = error.response.status
    if (status === 401) return i18n.t('organizationFunding.sessionExpired')
    if (status === 403) return i18n.t('organizationFunding.forbidden')
    if ([404, 410].includes(status)) return i18n.t('organizationFunding.notAvailable')
    if ([400, 422].includes(status)) return i18n.t('organizationFunding.invalidFilters')
    if (status === 429) return i18n.t('organizationFunding.rateLimited')
    if (status >= 500) return i18n.t('organizationFunding.serviceUnavailable')
  }
  return i18n.t(fallback)
}
