import { ApiError } from '@/api/http-client'
import { setInterfaceLanguage } from '@/i18n'
import { adminErrorMessage } from './editorial-messages'
import { trackingErrorMessage } from './tracking-messages'
import { collaborationErrorMessage } from './collaboration-messages'
import { discoveryErrorMessage } from './discovery-feedback'
import { workspaceMessage, workspaceRequestError } from './workspace-messages'
import { documentOperationsErrorKey, importOperationsErrorKey, operationsMessage } from './operations-messages'
import { requestValidationMessage, requestValidationToken } from './validation-issues'
import { validationEs } from './validation/es'
import { validationEn } from './validation/en'

function error(status = 422, code = 'funding-ready-primaryFunder') {
  return new ApiError({
    status, title: 'PRIVATE-DIAGNOSTIC', errors: { field: ['PRIVATE-DIAGNOSTIC'] },
    validationIssues: { field: [{ code }] },
  }, new Response(null, { status }))
}

it.each([
  ['editorial', adminErrorMessage],
  ['tracking', (failure: ApiError) => trackingErrorMessage(failure, 'applications')],
  ['collaboration', (failure: ApiError) => collaborationErrorMessage(failure, 'matching')],
  ['discovery', (failure: ApiError) => discoveryErrorMessage(failure, 'marketplace.loadHelp')],
  ['workspace', (failure: ApiError) => workspaceMessage(workspaceRequestError(failure))],
  ['imports', (failure: ApiError) => operationsMessage(importOperationsErrorKey(failure))],
  ['documents', (failure: ApiError) => operationsMessage(documentOperationsErrorKey(failure))],
] as const)('%s renders the same stable issue again after language change', async (_name, render) => {
  const failure = error()
  expect(render(failure)).toBe(validationEs['funding-ready-primaryFunder'])
  await setInterfaceLanguage('en')
  expect(render(failure)).toBe(validationEn['funding-ready-primaryFunder'])
})

it.each([401, 403, 404, 429, 500])('does not treat metadata on HTTP %s as a field validation response', status => {
  expect(requestValidationMessage(error(status))).toBeUndefined()
  expect(requestValidationToken(error(status))).toBeUndefined()
})

it('keeps a validated descriptor stable and safely handles unknown wire codes', async () => {
  const token = requestValidationToken(error())!
  await setInterfaceLanguage('en')
  expect(requestValidationToken(error())).toBe(token)
  expect(workspaceMessage(token)).toBe(validationEn['funding-ready-primaryFunder'])
  expect(requestValidationMessage(error(422, 'PRIVATE-DIAGNOSTIC'))).toBe(validationEn['validation-unknown'])
})
