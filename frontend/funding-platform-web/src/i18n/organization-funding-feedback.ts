import { ApiError } from '@/api/http-client'
import i18n from '@/i18n'

export function organizationFundingErrorMessage(error: unknown, fallback: 'organizationFunding.loadHelp' | 'organizationFunding.notAvailable') {
  // Do not expose arbitrary server diagnostics. Per-rule API codes remain in I18N-05.
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
