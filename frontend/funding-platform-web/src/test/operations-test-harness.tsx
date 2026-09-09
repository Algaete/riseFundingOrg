import { render } from '@testing-library/react'
import { createMemoryRouter } from 'react-router-dom'
import { createAppQueryClient } from '@/api/query-client'
import { App } from '@/App'
import { setAuthenticatedSession } from '@/features/auth/auth-session'
import { appRoutes } from '@/router'
import { operationsFixtures, operationsIds } from '@/test/fixtures/operations-workspace'

export function operationsJson(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: {
    'Content-Type': status >= 400 ? 'application/problem+json' : 'application/json',
  } })
}
export interface OperationRequest {
  url: URL
  method: string
  init: RequestInit
}
export function renderOperations(path: string, overrides: Record<string, unknown> = {}, handler?: (request: OperationRequest) => Promise<Response> | Response | undefined) {
  setAuthenticatedSession({
    status: 'authenticated', accessToken: 'synthetic-ui-only', accessTokenExpiresAtUtc: '2099-01-01T00:00:00Z',
    user: { publicId: operationsIds.user, email: 'admin@example.invalid', displayName: 'Admin Ñandú', roles: ['Admin'], mfaEnabled: true, preferredLocale: 'es-CL' },
  })
  const fixtures = { ...operationsFixtures, ...overrides }
  const requests: OperationRequest[] = []
  const unexpected: string[] = []
  vi.stubGlobal('fetch', vi.fn((input: RequestInfo | URL, init: RequestInit = {}) => {
    const url = new URL(String(input), window.location.origin)
    const request = { url, init, method: init.method ?? 'GET' }
    requests.push(request)
    const response = handler?.(request)
    if (response) return Promise.resolve(response)
    const key = url.pathname.replace(/^\/api\/v1/, '')
    if (request.method === 'GET' && Object.hasOwn(fixtures, key)) return Promise.resolve(operationsJson(fixtures[key]))
    unexpected.push(request.method + ' ' + url.pathname)
    return Promise.resolve(operationsJson({ title: 'Unexpected synthetic request' }, 500))
  }))
  const client = createAppQueryClient()
  client.setDefaultOptions({ queries: { retry: false, staleTime: Infinity }, mutations: { retry: false } })
  const router = createMemoryRouter(appRoutes, { initialEntries: [path] })
  render(<App router={router} queryClient={client} />)
  return { requests, unexpected, router, client }
}
