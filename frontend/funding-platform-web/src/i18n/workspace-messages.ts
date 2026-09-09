import { ApiError } from '@/api/http-client'
import { readValidationMessage } from '@/i18n/validation-issues'
import { validationEs } from '@/i18n/validation/es'
import i18n from '@/i18n'
import { organizationEs } from '@/i18n/organization/es'
import { projectsEs } from '@/i18n/projects/es'
import { projectAssetsEs } from '@/i18n/project-assets/es'
import { workspaceFeedbackEs } from '@/i18n/workspace-feedback/es'

export type OrganizationTextKey = `organization.${keyof typeof organizationEs}`
export type ProjectTextKey = `projects.${keyof typeof projectsEs}`
export type AssetTextKey = `projectAssets.${keyof typeof projectAssetsEs}`
type FeedbackTextKey = `workspaceFeedback.${keyof typeof workspaceFeedbackEs}`
type WorkspaceTextKey = OrganizationTextKey | ProjectTextKey | AssetTextKey | FeedbackTextKey | `validation.${keyof typeof validationEs}`

const resources = { organization: organizationEs, projects: projectsEs, projectAssets: projectAssetsEs, workspaceFeedback: workspaceFeedbackEs, validation: validationEs }
const keys = new Set<string>()
const legacyMessages = new Map<string, WorkspaceTextKey>()
for (const [namespace, values] of Object.entries(resources)) {
  for (const [key, value] of Object.entries(values)) {
    const fullKey = `${namespace}.${key}` as WorkspaceTextKey
    keys.add(fullKey)
    // The legacy API returns Spanish field errors, not stable per-rule codes.
    // Only exact, bundled messages can be localized; never infer from substrings.
    if (!value.includes('{{')) legacyMessages.set(value, fullKey)
  }
}

export function workspaceMessage(message: string | null | undefined): string {
  if (!message) return ''
  const issue = readValidationMessage(message)
  if (issue?.code === 'text-max-length') return i18n.t('validation.text-max-length', { max: issue.max })
  if (issue) return i18n.t(`validation.${issue.code}`)
  const key = keys.has(message) ? message as WorkspaceTextKey : legacyMessages.get(message)
  if (key) return i18n.t(key)
  // Unknown server diagnostics must not be shown in either language.
  return i18n.t('workspaceFeedback.invalid')
}

export function workspaceRequestError(error: unknown, scope: 'organization' | 'project' = 'project'): string {
  if (!(error instanceof ApiError)) return scope === 'organization' ? 'organization.saveFailure' : 'projects.operationFailed'
  const { status } = error.response
  const type = error.problem.type
  const base = 'https://fundingplatform.local/problems/'
  if (status === 401) return 'projectAssets.sessionExpired'
  if (status === 403) return 'workspaceFeedback.forbidden'
  if (status === 429) return 'workspaceFeedback.rateLimited'
  if (status === 409 && type === `${base}organization-owned-limit`) return 'workspaceFeedback.ownedLimit'
  if (status === 409 && type === `${base}project-invalid-transition`) return 'workspaceFeedback.transition'
  if ([409, 412, 428].includes(status)) return 'workspaceFeedback.conflict'
  if (status === 422 && type === `${base}project-not-ready`) return 'workspaceFeedback.notReady'
  return error.problem.detail ?? error.problem.title
}

export function workspaceLocale() {
  return i18n.resolvedLanguage === 'en' ? 'en-US' : 'es-CL'
}

export function formatWorkspaceDate(value: string, dateStyle: 'medium' | 'long' = 'medium') {
  // Date-only fields have no timezone; do not shift them into the previous day.
  const dateOnly = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value)
  const date = dateOnly
    ? new Date(Number(dateOnly[1]), Number(dateOnly[2]) - 1, Number(dateOnly[3]))
    : new Date(value)
  return new Intl.DateTimeFormat(workspaceLocale(), { dateStyle }).format(date)
}
