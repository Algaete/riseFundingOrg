import i18n from '@/i18n'
import { ApiError } from '@/api/http-client'
import { adminErrorMessage, adminValidationMessages, editorialFieldMessage, formatAdminDate } from '@/i18n/editorial-messages'
import { language, problem } from '@/test/tracking-test-harness'
import { editorialValidationEs } from '@/i18n/editorial-validation/es'

describe('editorial diagnostics and locale', () => {
  it.each([
    [401, 'Your session expired. Sign in again.'],
    [403, 'You do not have permission to perform this action.'],
    [404, 'This content is no longer available.'],
    [409, 'The operation conflicts with the current state. Review the details before continuing.'],
    [412, 'Another administrator updated this content. Load and review the current version before retrying.'],
    [428, 'Another administrator updated this content. Load and review the current version before retrying.'],
    [429, 'Too many attempts. Wait before trying again.'],
    [500, 'The service is unavailable. Try again later.'],
    [422, 'Review the indicated fields before continuing.'],
  ])('maps HTTP %s without echoing private diagnostics', async (status, expected) => {
    await language('en')
    expect(adminErrorMessage(problem(Number(status)))).toBe(expected)
  })

  it.each(['es', 'en'] as const)('safely maps readiness and field messages in %s', async locale => {
    await language(locale)
    const error = new ApiError({
      status: 422, type: 'https://fundingplatform.local/problems/opportunity-not-ready/',
      title: 'PRIVATE SQL', detail: 'PRIVATE SQL',
      errors: { readiness: [' A published primary funder is required. ', 'a published primary funder is required', 'PRIVATE SQL', 'PRIVATE SQL'] },
    }, new Response(null, { status: 422 }))
    expect(adminErrorMessage(error)).toBe(i18n.t('editorial.opportunityNotReady'))
    expect(adminValidationMessages(error)).toEqual([i18n.t('editorialValidation.readyFunder'), i18n.t('editorial.validation')])
    for (const unknown of ['PRIVATE SQL', 'constructor', '__proto__', 'toString']) {
      expect(editorialFieldMessage(unknown)).toBe(i18n.t('editorial.validation'))
    }
    expect(adminErrorMessage(problem(422, 'funder-not-ready'))).toBe(i18n.t('editorial.funderNotReady'))
    expect(adminErrorMessage(problem(409, 'source-link-conflict'))).toBe(i18n.t('editorialValidation.sourceConflict'))
    for (const [key, es] of Object.entries(editorialValidationEs)) {
      const fullKey = `editorialValidation.${key}` as `editorialValidation.${keyof typeof editorialValidationEs}`
      expect(editorialFieldMessage(fullKey)).toBe(i18n.t(fullKey))
      expect(editorialFieldMessage(es)).toBe(i18n.t(fullKey))
      expect(i18n.t(fullKey)).not.toBe(fullKey)
    }
  })

  it('changes date presentation without changing the instant and handles missing/invalid dates', async () => {
    const value = '2026-09-01T12:34:56.123Z'
    expect(formatAdminDate(value)).toBe(new Intl.DateTimeFormat('es-CL', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value)))
    await language('en')
    expect(formatAdminDate(value)).toBe(new Intl.DateTimeFormat('en-US', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value)))
    expect(formatAdminDate(null)).toBe('No date')
    expect(formatAdminDate('bad')).toBe('Invalid date')
    expect(adminValidationMessages(new Error('PRIVATE'))).toEqual([])
    expect(adminErrorMessage(new Error('PRIVATE'))).toBe(i18n.t('editorial.genericError'))
  })
})
