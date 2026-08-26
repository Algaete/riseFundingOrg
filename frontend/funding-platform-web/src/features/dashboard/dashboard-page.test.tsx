import { render, screen } from '@testing-library/react'
import { createMemoryRouter } from 'react-router-dom'

import { createAppQueryClient } from '@/api/query-client'
import { App } from '@/App'
import { alertsApi } from '@/features/alerts/alerts-api'
import { applicationApi } from '@/features/applications/application-api'
import { setAuthenticatedSession } from '@/features/auth/auth-session'
import { calendarApi } from '@/features/calendar/calendar-api'
import { organizationApi } from '@/features/organizations/organization-api'
import { projectApi } from '@/features/projects/project-api'
import { appRoutes } from '@/router'

const organizationId = '22222222-2222-2222-2222-222222222222'

describe('resumen del usuario', () => {
  beforeEach(() => {
    localStorage.clear()
    sessionStorage.clear()
    setAuthenticatedSession({
      status: 'authenticated', accessToken: 'dashboard-token',
      accessTokenExpiresAtUtc: '2027-08-26T13:00:00Z',
      user: {
        publicId: '11111111-1111-1111-1111-111111111111',
        email: 'user@example.test', displayName: 'Usuario Demo', preferredLocale: 'es-CL',
        roles: [], mfaEnabled: false,
      },
    })
    vi.spyOn(organizationApi, 'list').mockResolvedValue([{
      publicId: organizationId, name: 'Fundación Demo', membershipRole: 'admin',
      profileStatus: 2, profileCompleteness: 100, profileVersion: 2,
      updatedAtUtc: '2026-08-26T12:00:00Z',
    }])
    vi.spyOn(projectApi, 'list').mockResolvedValue([{
      publicId: '33333333-3333-3333-3333-333333333333', slug: 'agua-rural',
      title: 'Agua rural', summary: null, status: 2, publicationStatus: 2,
      startDate: null, endDate: null, budgetTotal: 100, confirmedFunding: 20,
      currency: 'CLP', fundingGap: 80, projectVersion: 2, updatedAtUtc: '2026-08-26T12:00:00Z',
    }])
    vi.spyOn(applicationApi, 'list').mockResolvedValue({
      items: [{
        publicId: '44444444-4444-4444-4444-444444444444',
        project: { publicId: '33333333-3333-3333-3333-333333333333', slug: 'agua-rural', title: 'Agua rural' },
        fundingOpportunity: {
          publicId: '55555555-5555-5555-5555-555555555555', slug: 'fondo-agua',
          title: 'Fondo Agua', sponsorName: 'Agencia Demo', closeDate: '2026-09-20',
          closeAtUtc: null, deadlinePrecision: 1,
        },
        status: 1, notes: null, applicationDate: null, requestedAmount: null,
        currency: null, resultDate: null,
        ownerUserPublicId: '11111111-1111-1111-1111-111111111111', canEdit: true,
        createdAtUtc: '2026-08-25T12:00:00Z', updatedAtUtc: '2026-08-26T12:00:00Z', eTag: '"etag"',
      }],
      totalCount: 1, pageNumber: 1, pageSize: 5,
    })
    vi.spyOn(calendarApi, 'get').mockResolvedValue({
      from: '2026-08-26', to: '2026-10-25', items: [{
        eventKey: 'deadline:1', eventType: 'application-deadline', eventDate: '2026-09-20',
        eventAtUtc: null, datePrecision: 1, title: 'Cierre Fondo Agua', status: 1,
        fundingApplicationPublicId: '44444444-4444-4444-4444-444444444444',
        projectPublicId: '33333333-3333-3333-3333-333333333333',
        fundingOpportunityPublicId: '55555555-5555-5555-5555-555555555555',
      }],
    })
    vi.spyOn(alertsApi, 'list').mockResolvedValue({
      items: [], totalCount: 2, page: 1, pageSize: 1,
    })
  })
  afterEach(() => vi.restoreAllMocks())

  it('reúne métricas, hitos y postulaciones sin placeholder', async () => {
    const router = createMemoryRouter(appRoutes, { initialEntries: ['/dashboard'] })
    render(<App router={router} queryClient={createAppQueryClient()} />)

    expect(await screen.findByRole('heading', { name: 'Resumen' })).toBeInTheDocument()
    expect(await screen.findByText('Cierre Fondo Agua')).toBeInTheDocument()
    expect(screen.getByText('Fondo Agua')).toBeInTheDocument()
    expect(screen.getByText('2')).toBeInTheDocument()
    expect(screen.queryByText('Módulo preparado')).not.toBeInTheDocument()
  })
})
