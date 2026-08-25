import { render, screen } from '@testing-library/react'
import { createMemoryRouter } from 'react-router-dom'

import { createAppQueryClient } from '@/api/query-client'
import { App } from '@/App'
import { clearAuthSession, setAuthenticatedSession } from '@/features/auth/auth-session'
import { appRoutes } from '@/router'

const organizationId = '51ea2f6f-b1af-4e09-856c-6dcbdcfc812f'
const projectId = 'bd351806-9139-4524-bc01-93c3676729cb'
const opportunityId = 'f5b75d2c-4c84-4ca3-91f7-e9c182fdff2c'
const applicationId = 'f4299117-a4b5-4dfc-b89f-1a3942268f12'

function json(value: unknown) {
  return Promise.resolve(new Response(JSON.stringify(value), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  }))
}

describe('calendario básico', () => {
  afterEach(() => { vi.unstubAllGlobals(); clearAuthSession() })

  it('consulta el mes al servidor, agrupa hitos y enlaza sus entidades', async () => {
    setAuthenticatedSession({
      status: 'authenticated', accessToken: 'calendar-test-token', accessTokenExpiresAtUtc: '2027-08-24T12:00:00Z',
      user: { publicId: '89b8d22a-472c-42e4-b034-c772ce3bb08e', email: 'member@example.test', displayName: 'Miembro demo', preferredLocale: 'es-CL', roles: ['Professional'], mfaEnabled: false },
    })
    const fetchMock = vi.fn((input: RequestInfo | URL, _init?: RequestInit) => {
      const url = new URL(String(input), 'http://localhost')
      if (url.pathname.endsWith('/organizations')) return json([{ publicId: organizationId, name: 'Fundación Demo', membershipRole: 'admin', profileStatus: 2, profileCompleteness: 100, profileVersion: 2, updatedAtUtc: '2026-08-24T10:00:00Z' }])
      if (url.pathname.endsWith(`/organizations/${organizationId}/calendar`)) return json({
        from: '2027-02-01',
        to: '2027-02-28',
        items: [
          { eventKey: `application:${applicationId}:deadline`, eventType: 'application-deadline', eventDate: '2027-02-15', eventAtUtc: '2027-02-15T20:30:00Z', datePrecision: 2, title: 'Cierre Fondo para agua rural', status: 1, fundingApplicationPublicId: applicationId, projectPublicId: projectId, fundingOpportunityPublicId: opportunityId },
          { eventKey: `project:${projectId}:end`, eventType: 'project-end', eventDate: '2027-02-15', eventAtUtc: null, datePrecision: 1, title: 'Término Agua segura', status: null, fundingApplicationPublicId: null, projectPublicId: projectId, fundingOpportunityPublicId: null },
        ],
      })
      throw new Error(`Unexpected request: ${url}`)
    })
    vi.stubGlobal('fetch', fetchMock)
    const router = createMemoryRouter(appRoutes, { initialEntries: ['/calendar?month=2027-02'] })
    render(<App queryClient={createAppQueryClient()} router={router} />)

    expect(await screen.findByRole('heading', { name: /febrero de 2027/i })).toBeInTheDocument()
    expect(await screen.findByText('Cierre Fondo para agua rural')).toBeInTheDocument()
    expect(screen.getByRole('heading', { name: /lunes, 15 de febrero de 2027/i })).toBeInTheDocument()
    expect(screen.getByText('Término Agua segura')).toBeInTheDocument()
    const links = screen.getAllByRole('link', { name: /Abrir/ })
    expect(links.map((link) => link.getAttribute('href'))).toEqual(expect.arrayContaining([
      `/applications?applicationId=${applicationId}`,
      `/projects/${projectId}`,
    ]))
    const calendarCall = fetchMock.mock.calls.find(([input]) => String(input).includes('/calendar?'))
    const requestUrl = new URL(String(calendarCall![0]), 'http://localhost')
    expect(requestUrl.searchParams.get('from')).toBe('2027-02-01')
    expect(requestUrl.searchParams.get('to')).toBe('2027-02-28')
    expect(new Headers(calendarCall?.[1]?.headers).get('Authorization')).toBe('Bearer calendar-test-token')
  })
})
