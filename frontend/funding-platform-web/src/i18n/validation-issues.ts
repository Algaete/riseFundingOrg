import { validationEs } from '@/i18n/validation/es'
import type { ProblemDetails } from '@/types/problem-details'

type ValidationCode = keyof typeof validationEs
type KnownIssue = { code: Exclude<ValidationCode, 'text-max-length'> } | { code: 'text-max-length'; max: number }
const prefix = '@field-validation:'
const fallback = 'workspaceFeedback.invalid'

function record(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}

function knownIssue(value: unknown): KnownIssue | undefined {
  if (!record(value) || typeof value.code !== 'string' || !Object.hasOwn(validationEs, value.code)) return
  const code = value.code as ValidationCode
  if (code === 'text-max-length') {
    if (typeof value.max !== 'number' || !Number.isSafeInteger(value.max) || value.max < 1 || value.max > 10000) return
    return { code, max: value.max }
  }
  // No arbitrary server strings or interpolation parameters reach translation.
  return { code }
}

// RHF stores messages as strings. Keep a language-neutral, validated descriptor
// there and translate at render time so switching language never resets a form.
export function readValidationMessage(message: string): KnownIssue | undefined {
  if (!message.startsWith(prefix) || message.length > 200) return
  try { return knownIssue(JSON.parse(message.slice(prefix.length))) } catch { return }
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
