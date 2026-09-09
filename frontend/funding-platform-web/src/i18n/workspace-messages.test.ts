import { ApiError } from '@/api/http-client'
import { setInterfaceLanguage } from '@/i18n'
import { formatWorkspaceDate, workspaceLocale, workspaceMessage, workspaceRequestError } from '@/i18n/workspace-messages'

describe('workspace localization boundaries', () => {
  it('translates stored keys and exact legacy validation without interpreting unknown text', async () => {
    await setInterfaceLanguage('en')
    expect(workspaceMessage('organization.rangeOrder')).toBe('The maximum amount must be greater than or equal to the minimum.')
    expect(workspaceMessage('La fecha de término no puede ser anterior al inicio.')).toBe('The end date cannot be before the start date.')
    expect(workspaceMessage('projectAssets.conflict')).toBe('The project or attachment changed state. Reload before continuing.')
    expect(workspaceMessage('Private server detail https://example.invalid?token=secret')).toBe('Check the indicated fields and try again.')
    expect(workspaceMessage('projects.__proto__')).toBe('Check the indicated fields and try again.')
    expect(workspaceMessage(null)).toBe('')
    await setInterfaceLanguage('es')
    expect(workspaceMessage('organization.rangeOrder')).toBe('El monto máximo debe ser igual o mayor al mínimo.')
  })

  it.each([
    [401, 'invalid-session', 'projectAssets.sessionExpired'],
    [403, 'project-workflow-forbidden', 'workspaceFeedback.forbidden'],
    [409, 'organization-owned-limit', 'workspaceFeedback.ownedLimit'],
    [409, 'project-invalid-transition', 'workspaceFeedback.transition'],
    [409, 'project-concurrency-conflict', 'workspaceFeedback.conflict'],
    [412, 'anything', 'workspaceFeedback.conflict'],
    [428, 'if-match-required', 'workspaceFeedback.conflict'],
    [422, 'project-not-ready', 'workspaceFeedback.notReady'],
    [429, 'anything', 'workspaceFeedback.rateLimited'],
  ])('maps workspace protocol status %s / %s', (status, code, expected) => {
    const error = new ApiError({ title: 'Server detail', status: Number(status), type: `https://fundingplatform.local/problems/${code}` }, new Response(null, { status: Number(status) }))
    expect(workspaceRequestError(error)).toBe(expected)
  })

  it('formats dates in the selected locale without shifting date-only values', async () => {
    await setInterfaceLanguage('en')
    expect(workspaceLocale()).toBe('en-US')
    expect(formatWorkspaceDate('2027-01-01', 'long')).toBe('January 1, 2027')
    await setInterfaceLanguage('es')
    expect(workspaceLocale()).toBe('es-CL')
    expect(formatWorkspaceDate('2027-01-01', 'long')).toBe('1 de enero de 2027')
  })
})
