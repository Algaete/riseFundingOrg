import { ApiError } from '@/api/http-client'
import { setInterfaceLanguage } from '@/i18n'
import { matchingRule } from '@/test/fixtures/matching-network'
import { matchingEs } from './matching/es'
import { matchingEn } from './matching/en'
import { collaborationErrorMessage, hasMatchingRuleLabel, isStandardMatchingDisclaimer, matchingEvidenceField, matchingEvidenceSource, matchingReasonText, matchingRuleName } from './collaboration-messages'

describe('matching controlled explanations', () => {
  it('localizes every bundled reason code without rewriting rules or evaluating them again', async () => {
    for (const code of Object.keys(matchingEs.reasons) as (keyof typeof matchingEs.reasons)[]) {
      const rule = { ...matchingRule, reasonCode: code.toLowerCase().replaceAll('_', '.') }
      const before = structuredClone(rule)
      await setInterfaceLanguage('es')
      expect(matchingReasonText(rule)).toBe(matchingEs.reasons[code])
      await setInterfaceLanguage('en')
      expect(matchingReasonText(rule)).toBe(matchingEn.reasons[code])
      expect(rule).toEqual(before)
    }
  })

  it.each([0, 1, 2, 3] as const)('keeps the outcome-based fallback for an unknown reason (%s)', async outcome => {
    await setInterfaceLanguage('en')
    const rule = { ...matchingRule, outcome, reasonCode: 'FUTURE-REASON', dataState: 0 as const }
    expect(matchingReasonText(rule)).toBe([
      'The available data matches “Geography”.', 'The available data partially matches “Geography”.',
      'An incompatibility was detected for “Geography”.', 'There is not enough data to assess “Geography”.',
    ][outcome])
    expect(matchingReasonText({ ...rule, dataState: 2 })).toBe('This condition does not apply to this case.')
  })

  it('maps the nine current rule codes while preserving unrecognized names', async () => {
    await setInterfaceLanguage('en')
    for (const code of Object.keys(matchingEn.ruleNames) as (keyof typeof matchingEn.ruleNames)[]) {
      expect(matchingRuleName({ code, name: 'Server label' })).toBe(matchingEn.ruleNames[code])
      expect(hasMatchingRuleLabel(code)).toBe(true)
    }
    expect(matchingRuleName({ code: 'custom', name: 'Nombre original' })).toBe('Nombre original')
    expect(hasMatchingRuleLabel('custom')).toBe(false)
  })

  it('does not treat inherited object properties as translated protocol codes or expose unknown evidence', async () => {
    await setInterfaceLanguage('en')
    for (const code of ['constructor', '__proto__', 'toString', 'SECRET-DATA']) {
      expect(matchingEvidenceField(code)).toBe('Structured field')
      expect(matchingEvidenceSource(code)).toBe('Versioned source')
      expect(hasMatchingRuleLabel(code)).toBe(false)
    }
    expect(matchingEvidenceSource('ORGANIZATION_PROFILE')).toBe('Organization profile')
    expect(matchingEvidenceField('operating_years')).toBe('Operating years')
  })

  it('only replaces the exact known disclaimer, leaving new source notices intact', () => {
    expect(isStandardMatchingDisclaimer(matchingEs.disclaimer)).toBe(true)
    expect(isStandardMatchingDisclaimer('')).toBe(true)
    expect(isStandardMatchingDisclaimer('Aviso nuevo')).toBe(false)
    expect(isStandardMatchingDisclaimer(matchingEs.disclaimer + ' Condición adicional.')).toBe(false)
  })
})

describe('matching and networking protocol errors', () => {
  it.each([
    ['matching', 422, 'project-matching-validation', 'Review the project and organization profile before calculating again.'],
    ['matching', 409, 'project-matching-conflict', 'The data or request changed. You can retry the calculation with a new key.'],
    ['network', 422, 'networking-disabled', 'Network visibility is disabled. An administrator must enable it before connecting.'],
    ['network', 409, 'networking-already-exists', 'An active connection with this organization already exists. Check the requests.'],
    ['network', 409, 'networking-invalid-transition', 'The request’s current state no longer allows that action. Reload to review it.'],
    ['network', 412, 'networking-precondition-failed', 'The data changed. Reload and review its state before retrying.'],
    ['network', 403, 'networking-forbidden', 'You do not have permission to perform this action in the organization.'],
    ['network', 401, 'session', 'Your session expired. Sign in again.'],
    ['matching', 404, 'missing', 'The resource does not exist or is unavailable to your organization.'],
    ['matching', 428, 'idempotency-key-required', 'A request version or safety key is missing. Reload before retrying.'],
    ['network', 429, 'networking-rate-limit', 'The request limit was reached. Try again later.'],
    ['matching', 503, 'project-matching-unavailable', 'The service is unavailable right now. Try again later.'],
  ] as const)('maps %s %s %s without rendering private diagnostics', async (scope, status, code, english) => {
    const error = new ApiError({ status, type: 'https://fundingplatform.local/problems/' + code, title: 'SECRET-TITLE', detail: 'SECRET-DETAIL', errors: { message: ['SECRET-VALIDATION'] } }, new Response(null, { status }))
    expect(collaborationErrorMessage(error, scope)).not.toMatch(/SECRET/)
    await setInterfaceLanguage('en')
    expect(collaborationErrorMessage(error, scope)).toBe(english)
  })

  it('keeps uncertainty guidance specific to writes and never displays raw errors', async () => {
    await setInterfaceLanguage('en')
    expect(collaborationErrorMessage(new Error('SECRET'), 'network', 'write')).toBe('We could not confirm the operation. You can retry without duplicating it.')
    expect(collaborationErrorMessage(new Error('SECRET'), 'network')).toBe('Check your connection and try again.')
    expect(collaborationErrorMessage(null, 'matching')).toBe('Check your connection and try again.')
  })
})
