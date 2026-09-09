import { validationEs } from '@/i18n/validation/es'
import i18n from '@/i18n'
import { ApiError } from '@/api/http-client'
import type { ProblemDetails } from '@/types/problem-details'

type ValidationCode = keyof typeof validationEs
export type ValidationMessageToken = `@field-validation:${string}`
type KnownIssue = { code: ValidationCode; min?: number; max?: number }
const prefix = '@field-validation:'
const fallback = 'workspaceFeedback.invalid'

function record(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}

function knownIssue(value: unknown): KnownIssue | undefined {
  if (!record(value) || typeof value.code !== 'string' || !Object.hasOwn(validationEs, value.code)) return
  const code = value.code as ValidationCode
  const issue: KnownIssue = { code }
  for (const bound of ['min', 'max'] as const) {
    if (!validationEs[code].includes('{{' + bound + '}}')) continue
    const number = value[bound]
    if (typeof number !== 'number' || !Number.isSafeInteger(number) || number < 1) return
    issue[bound] = number
  }
  if (issue.min !== undefined && issue.max !== undefined && issue.min > issue.max) return
  // No arbitrary server strings or interpolation parameters reach translation.
  return issue
}

// RHF stores messages as strings. Keep a language-neutral, validated descriptor
// there and translate at render time so switching language never resets a form.
export function readValidationMessage(message: string): KnownIssue | undefined {
  if (!message.startsWith(prefix) || message.length > 200) return
  try { return knownIssue(JSON.parse(message.slice(prefix.length))) } catch { return }
}

export function validationMessage(message: string): string | undefined {
  const issue = readValidationMessage(message)
  return issue ? i18n.t(`validation.${issue.code}`, { min: issue.min ?? 0, max: issue.max ?? 0 }) : undefined
}

// Keep raw failures in state, and render again on languageChanged.
export function requestValidationMessage(error: unknown): string | undefined {
  if (!(error instanceof ApiError) || ![400, 409, 415, 422].includes(error.response.status) ||
      !record(error.problem.validationIssues)) return
  const messages = fieldValidationEntries(error.problem).map(entry =>
    validationMessage(entry.message) ?? i18n.t('validation.validation-unknown'))
  return messages.length ? [...new Set(messages)].join(' ') : undefined
}

export function requestValidationToken(error: unknown): ValidationMessageToken | undefined {
  if (!(error instanceof ApiError) || ![400, 409, 415, 422].includes(error.response.status) ||
      !record(error.problem.validationIssues)) return
  const message = fieldValidationEntries(error.problem)[0]?.message
  if (!message) return
  return readValidationMessage(message) ? message as ValidationMessageToken
    : '@field-validation:{"code":"validation-unknown"}'
}

export function fieldValidationEntries(problem: ProblemDetails): { key: string; message: string }[] {
  const legacy = record(problem.errors) ? problem.errors : {}
  const structured = record(problem.validationIssues) ? problem.validationIssues : {}
  const fields = new Set([...Object.keys(legacy), ...Object.keys(structured)])
  return [...fields].flatMap(key => {
    if (Object.hasOwn(structured, key)) {
      const issues: unknown = structured[key]
      if (!Array.isArray(issues) || issues.length === 0) return [{ key, message: fallback }]
      return issues.map(value => {
        const issue = knownIssue(value)
        return { key, message: issue ? prefix + JSON.stringify(issue) : fallback }
      })
    }
    const messages: unknown = legacy[key]
    if (!Array.isArray(messages) || messages.length === 0) return [{ key, message: fallback }]
    return messages.map(message => ({
      key, message: typeof message === 'string' && !message.startsWith(prefix) ? message : fallback,
    }))
  })
}
