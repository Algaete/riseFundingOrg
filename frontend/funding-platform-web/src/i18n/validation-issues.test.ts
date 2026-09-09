import { fieldValidationEntries, readValidationMessage } from '@/i18n/validation-issues'
import { workspaceMessage } from '@/i18n/workspace-messages'
import { validationEs } from '@/i18n/validation/es'
import { validationEn } from '@/i18n/validation/en'
import { setInterfaceLanguage } from '@/i18n'
import type { ProblemDetails } from '@/types/problem-details'

function problem(validationIssues: unknown, errors: unknown = { title: ['PRIVATE-SERVER-DIAGNOSTIC'] }) {
  // Deliberately malformed wire payloads must be checked even outside http-client.
  return { title: 'PRIVATE-SERVER-DIAGNOSTIC', status: 400, errors, validationIssues } as ProblemDetails
}

it.each(Object.keys(validationEs) as (keyof typeof validationEs)[])('renders stable code %s in both languages without using server text', async code => {
  const [entry] = fieldValidationEntries(problem({ title: [{ code, max: 1000, message: 'PRIVATE-SERVER-DIAGNOSTIC' }] }))
  expect(workspaceMessage(entry.message)).toBe(validationEs[code].replace('{{max}}', '1000'))
  await setInterfaceLanguage('en')
  expect(workspaceMessage(entry.message)).toBe(validationEn[code].replace('{{max}}', '1000'))
  expect(entry.message).not.toContain('PRIVATE')
  expect(Object.keys(validationEs)).toEqual(Object.keys(validationEn))
})

it.each([
  null, 'PRIVATE', [], [null], [42], [{ code: 'constructor' }], [{ code: '__proto__' }],
  [{ code: 'future-rule', message: 'PRIVATE' }], [{ code: 'text-max-length' }],
  ...[0, -1, 1.2, 10001, Infinity, 'PRIVATE', {}].map(max => [{ code: 'text-max-length', max }]),
])('uses a safe fallback for malformed or unknown issues: %j', async issues => {
  const [entry] = fieldValidationEntries(problem({ title: issues }))
  expect(workspaceMessage(entry.message)).toBe('Revisa los campos indicados e intenta nuevamente.')
  await setInterfaceLanguage('en')
  expect(workspaceMessage(entry.message)).toBe('Check the indicated fields and try again.')
})

it('combines structured and legacy fields without duplicating or echoing unknown diagnostics', async () => {
  const entries = fieldValidationEntries(problem(
    { title: [{ code: 'project-title-length' }] },
    { title: ['IGNORED'], homeCountryId: ['Selecciona un país válido.'], unknown: ['PRIVATE'] },
  ))
  expect(entries.map(entry => entry.key)).toEqual(['title', 'homeCountryId', 'unknown'])
  expect(entries.map(entry => workspaceMessage(entry.message))).toEqual([
    validationEs['project-title-length'], validationEs['country-invalid'], 'Revisa los campos indicados e intenta nuevamente.',
  ])
  await setInterfaceLanguage('en')
  expect(entries.map(entry => workspaceMessage(entry.message))).toEqual([
    validationEn['project-title-length'], validationEn['country-invalid'], 'Check the indicated fields and try again.',
  ])
})

it.each([null, [], 'PRIVATE', 1])('tolerates malformed containers: %j', value => {
  expect(fieldValidationEntries(problem(value, value))).toEqual([])
})

it('does not treat raw legacy strings as structured descriptors', () => {
  const [entry] = fieldValidationEntries(problem(undefined, { title: ['@field-validation:{"code":"country-invalid"}'] }))
  expect(workspaceMessage(entry.message)).toBe('Revisa los campos indicados e intenta nuevamente.')
  expect(readValidationMessage('@field-validation:{')).toBeUndefined()
  expect(readValidationMessage('@field-validation:' + 'x'.repeat(201))).toBeUndefined()
})
