import { ApiError } from '@/api/http-client'
import { requestValidationMessage } from '@/i18n/validation-issues'
import i18n from '@/i18n'

export function discoveryErrorMessage(error: unknown, fallback: 'fundingCatalog.loadHelp' | 'marketplace.loadHelp') {
  const structured = requestValidationMessage(error)
  if (structured) return structured
  // Public pages never render arbitrary server diagnostics.
  if (error instanceof ApiError) {
    const status = error.response.status
    if ([401, 403, 404, 410].includes(status)) return i18n.t('discoveryFeedback.notFound')
    if (status === 429) return i18n.t('discoveryFeedback.rateLimited')
    if ([400, 422].includes(status)) return i18n.t('discoveryFeedback.invalidFilters')
    if (status >= 500) return i18n.t('discoveryFeedback.unavailable')
  }
  return i18n.t(fallback)
}
