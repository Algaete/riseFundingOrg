import { ApiError } from '@/api/http-client'
import { requestValidationMessage } from '@/i18n/validation-issues'
import type { MatchingRuleResult } from '@/features/matching/matching-api'
import i18n from '@/i18n'
import { matchingEs } from '@/i18n/matching/es'

function ownKey<T extends object>(object: T, value: string): value is Extract<keyof T, string> {
  return Object.prototype.hasOwnProperty.call(object, value)
}

export function matchingRuleName(rule: Pick<MatchingRuleResult, 'code' | 'name'>) {
  const code = rule.code.trim().toLowerCase()
  return ownKey(matchingEs.ruleNames, code) ? i18n.t(`matching.ruleNames.${code}`) : rule.name
}

export function hasMatchingRuleLabel(code: string) {
  return ownKey(matchingEs.ruleNames, code.trim().toLowerCase())
}

export function matchingReasonText(rule: MatchingRuleResult) {
  const code = rule.reasonCode.trim().toUpperCase().replace(/[.-]+/g, '_')
  if (ownKey(matchingEs.reasons, code)) return i18n.t(`matching.reasons.${code}`)
  if (rule.dataState === 2) return i18n.t('matching.reasons.NOT_APPLICABLE')
  return i18n.t(`matching.fallbackReason.${rule.outcome}`, { name: matchingRuleName(rule) })
}

export function matchingEvidenceSource(source: string) {
  const code = source.toLocaleLowerCase('es-CL')
  return ownKey(matchingEs.sources, code) ? i18n.t(`matching.sources.${code}`) : i18n.t('matching.versionedSource')
}

export function matchingEvidenceField(field: string) {
  const code = field.toLocaleLowerCase('es-CL')
  return ownKey(matchingEs.fields, code) ? i18n.t(`matching.fields.${code}`) : i18n.t('matching.structuredField')
}

export function isStandardMatchingDisclaimer(value: string) {
  // Translate only the exact, bundled endpoint notice; retain any new/custom source notice.
  return !value || value === matchingEs.disclaimer
}

export function collaborationErrorMessage(error: unknown, scope: 'matching' | 'network', operation: 'read' | 'write' = 'read') {
  const structured = requestValidationMessage(error)
  if (structured) return structured
  if (error instanceof ApiError) {
    const { status } = error.response
    const type = error.problem.type
    const base = 'https://fundingplatform.local/problems/'
    if (status === 401) return i18n.t('collaborationFeedback.sessionExpired')
    if (status === 403) return i18n.t('collaborationFeedback.forbidden')
    if ([404, 410].includes(status)) return i18n.t('collaborationFeedback.notFound')
    if (status === 429) return i18n.t('collaborationFeedback.rateLimited')
    if (scope === 'network') {
      if (status === 409 && type === base + 'networking-already-exists') return i18n.t('collaborationFeedback.alreadyExists')
      if (status === 422 && type === base + 'networking-disabled') return i18n.t('collaborationFeedback.networkDisabled')
      if (status === 409 && type === base + 'networking-invalid-transition') return i18n.t('collaborationFeedback.invalidTransition')
    }
    if (status === 428) return i18n.t('collaborationFeedback.precondition')
    if ([409, 412].includes(status)) return i18n.t(scope === 'matching' ? 'collaborationFeedback.matchingConflict' : 'collaborationFeedback.conflict')
    if ([400, 422].includes(status)) return i18n.t(scope === 'matching' ? 'collaborationFeedback.matchingInvalid' : 'collaborationFeedback.networkInvalid')
    if (status >= 500) return i18n.t('collaborationFeedback.unavailable')
  }
  // Do not expose arbitrary diagnostics or private payloads from server errors.
  return i18n.t(scope === 'network' && operation === 'write' ? 'collaborationFeedback.networkUncertain' : 'collaborationFeedback.loadHelp')
}
