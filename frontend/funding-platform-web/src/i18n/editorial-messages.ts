import { ApiError } from '@/api/http-client'
import { fieldValidationEntries, requestValidationMessage, validationMessage } from '@/i18n/validation-issues'
import i18n from '@/i18n'
import { editorialValidationEs } from '@/i18n/editorial-validation/es'
import { formatDateValue } from '@/i18n/formats'

type ValidationKey = `editorialValidation.${keyof typeof editorialValidationEs}`
const validationKeys = new Map<string, ValidationKey>()
for (const [key, message] of Object.entries(editorialValidationEs)) {
  validationKeys.set(message, `editorialValidation.${key}` as ValidationKey)
  validationKeys.set(`editorialValidation.${key}`, `editorialValidation.${key}` as ValidationKey)
}

const readinessMessageTranslations: Record<string, ValidationKey> = {
  'name is required': 'editorialValidation.readyName',
  'a stable public slug is required': 'editorialValidation.readySlug',
  'an official website is required': 'editorialValidation.readyWebsite',
  'a primary alias is required': 'editorialValidation.readyAlias',
  'title is required': 'editorialValidation.readyTitle',
  'a published primary funder is required': 'editorialValidation.readyFunder',
  'an enabled primary source url is required': 'editorialValidation.readySource',
  'unknown geographic scope cannot be published': 'editorialValidation.readyScope',
  'explicit geographic scope requires at least one eligible country': 'editorialValidation.readyCountry',
  'global geographic scope cannot contain country or region restrictions': 'editorialValidation.readyGlobal',
  'at least one category is required': 'editorialValidation.readyCategory',
  'every catalog reference must be active and geography must remain consistent': 'editorialValidation.readyCatalog',
  'every critical field requires selected evidence or an explicit unknown value': 'editorialValidation.readyEvidence',
}

export function problemHasCode(error: unknown, code: string) {
  if (!(error instanceof ApiError)) return false
  const type = error.problem.type?.replace(/\/$/, '')
  return type === code || type?.endsWith(`/${code}`) === true
}

// Only bundled, recognized diagnostics are displayed. Never echo unknown API
// detail, SQL/provider exceptions or author-supplied content as UI translations.
export function editorialFieldMessage(message: string): string {
  const structured = validationMessage(message)
  if (structured) return structured
  const normalized = message.trim().replace(/\s+/g, ' ').replace(/\.$/, '').toLowerCase()
  const readinessKey = Object.hasOwn(readinessMessageTranslations, normalized)
    ? readinessMessageTranslations[normalized]
    : undefined
  const key = validationKeys.get(message) ?? readinessKey
  return key ? i18n.t(key) : i18n.t('editorial.validation')
}

export function adminErrorMessage(error: unknown) {
  const validation = requestValidationMessage(error)
  if (validation) return validation
  if (!(error instanceof ApiError)) return i18n.t('editorial.genericError')
  const { status } = error.response
  if (status === 401) return i18n.t('editorial.unauthorized')
  if (status === 403) return i18n.t('editorial.forbidden')
  if (status === 404) return i18n.t('editorial.notFound')
  if (status === 412 || status === 428) return i18n.t('editorial.conflict')
  if (status === 429) return i18n.t('editorial.rateLimit')
  if (status >= 500) return i18n.t('editorial.unavailable')
  if (problemHasCode(error, 'opportunity-not-ready')) return i18n.t('editorial.opportunityNotReady')
  if (problemHasCode(error, 'funder-not-ready')) return i18n.t('editorial.funderNotReady')
  if (problemHasCode(error, 'source-link-conflict')) return i18n.t('editorialValidation.sourceConflict')
  if (status === 409) return i18n.t('editorial.stateConflict')
  if (status === 400 || status === 422) return i18n.t('editorial.validation')
  return i18n.t('editorial.genericError')
}

export function adminValidationMessages(error: unknown) {
  if (!(error instanceof ApiError)) return []
  const messages = fieldValidationEntries(error.problem).map(entry => entry.message)
  return [...new Set(messages.map(editorialFieldMessage))]
}

export function isConcurrencyConflict(error: unknown) {
  return error instanceof ApiError && error.response.status === 412
}

export function formatAdminDate(value: string | null | undefined) {
  if (!value) return i18n.t('editorial.noDate')
  return formatDateValue(value, { dateStyle: 'medium', timeStyle: 'short' })
}
