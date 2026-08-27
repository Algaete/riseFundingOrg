import { render, screen, waitFor } from '@testing-library/react'
import { createMemoryRouter } from 'react-router-dom'

import { createAppQueryClient } from '@/api/query-client'
import { App } from '@/App'
import { adminUsersApi } from '@/features/admin-users/admin-users-api'
import { adminErrorsApi } from '@/features/admin-errors/admin-errors-api'
import { adminOrganizationsApi } from '@/features/admin-organizations/admin-organizations-api'
import {
  adminFundersApi,
  adminFundingOpportunitiesApi,
} from '@/features/funding/admin-funding-api'
import { setAuthenticatedSession } from '@/features/auth/auth-session'
import { adminImportApi } from '@/features/imports/admin-import-api'
import { projectReviewApi } from '@/features/projects/project-api'
import { appRoutes } from '@/router'

function authenticate() {
  setAuthenticatedSession({
    status: 'authenticated',
    accessToken: 'admin-dashboard-token',
    accessTokenExpiresAtUtc: '2027-08-26T13:00:00Z',
    user: {
      publicId: '11111111-1111-1111-1111-111111111111',
      email: 'admin@example.test',
      displayName: 'Administradora',
      preferredLocale: 'es-CL',
      roles: ['Admin'],
      mfaEnabled: true,
    },
  })
}

function page(totalCount: number) {
  return { items: [], totalCount, page: 1, pageSize: 1 }
}

describe('panel de control administrativo', () => {
  beforeEach(() => {
    localStorage.clear()
    sessionStorage.clear()
    authenticate()
    vi.spyOn(adminUsersApi, 'list').mockResolvedValue(page(12))
    vi.spyOn(adminOrganizationsApi, 'list').mockResolvedValue(page(6))
    vi.spyOn(adminErrorsApi, 'list').mockResolvedValue(page(4))
    vi.spyOn(projectReviewApi, 'list').mockResolvedValue({
      items: [{
        projectId: '22222222-2222-2222-2222-222222222222',
        slug: 'agua-rural',
        title: 'Agua rural',
        summary: 'Resumen',
        projectStatus: 1,
        publicationStatus: 1,
        organizationPublicId: '33333333-3333-3333-3333-333333333333',
        organizationName: 'ONG Demo',
        completeness: 90,
        submittedAtUtc: '2026-08-26T12:00:00Z',
        updatedAtUtc: '2026-08-26T12:00:00Z',
        eTag: '"etag"',
      }],
      totalCount: 2,
      page: 1,
      pageSize: 5,
    })
    vi.spyOn(adminFundingOpportunitiesApi, 'list').mockImplementation(
      async filters => page(filters.status === 1 ? 3 : 21),
    )
    vi.spyOn(adminFundersApi, 'list').mockResolvedValue(page(8))
    vi.spyOn(adminImportApi, 'list').mockResolvedValue({
      items: [{
        runId: '44444444-4444-4444-4444-444444444444',
        fundingSourceId: 1,
        sourceName: 'Grants.gov',
        providerCode: 'grants-gov',
        triggerType: 1,
        statusCode: 1,
        status: 'running',
        keyword: 'agua',
        maximumResults: 10,
        retrievedCount: 4,
        createdCount: 1,
        updatedCount: 0,
        unchangedCount: 0,
        stagedForReviewCount: 0,
        failedCount: 0,
        createdAtUtc: '2026-08-26T12:00:00Z',
        startedAtUtc: '2026-08-26T12:00:01Z',
        completedAtUtc: null,
        lastErrorCode: null,
      }],
      totalCount: 1,
      page: 1,
      pageSize: 5,
    })
    vi.spyOn(adminImportApi, 'listSources').mockResolvedValue([{
      id: 1,
      name: 'Grants.gov',
      providerType: 1,
      providerCode: 'grants-gov',
      baseUrl: 'https://example.test',
      isEnabled: true,
      operationalStatus: 'active',
      complianceStatus: 'approved',
      lastSuccessfulRunAtUtc: null,
      nextScheduledRunAtUtc: null,
      scheduleCron: null,
      isGrantsGov: true,
      licenseName: 'Public domain',
      licenseUrl: null,
      licenseStatus: 'Aprobada',
      isAllowlisted: true,
      allowlistRequired: false,
      allowedHostCount: 1,
      allowlistStatus: 'Autorizada',
      rateLimitPerMinute: 10,
      minimumRequestIntervalSeconds: 1,
      robotsPolicyStatus: 'Aprobada',
      robotsReviewedAtUtc: null,
      acquisitionReady: true,
      isRssProvider: false,
      rssFeedHost: null,
    }])
  })

  afterEach(() => vi.restoreAllMocks())

  it('presenta indicadores, prioridades, actividad y acciones reales', async () => {
    const router = createMemoryRouter(appRoutes, { initialEntries: ['/admin'] })
    render(<App router={router} queryClient={createAppQueryClient()} />)

    expect(await screen.findByRole('heading', { name: 'Panel de control' })).toBeInTheDocument()
    await waitFor(() => {
      expect(screen.getByTestId('metric-Proyectos pendientes')).toHaveTextContent('2')
      expect(screen.getByTestId('metric-Usuarios')).toHaveTextContent('12')
      expect(screen.getByTestId('metric-Organizaciones')).toHaveTextContent('6')
      expect(screen.getByTestId('metric-Errores')).toHaveTextContent('4')
      expect(screen.getByTestId('metric-Fondos')).toHaveTextContent('21')
      expect(screen.getByTestId('metric-Fondos pendientes')).toHaveTextContent('3')
      expect(screen.getByTestId('metric-Financiadores')).toHaveTextContent('8')
      expect(screen.getByTestId('metric-Importaciones')).toHaveTextContent('1')
    })
    expect(screen.getByText('Agua rural')).toBeInTheDocument()
    expect(screen.getByText('Grants.gov')).toBeInTheDocument()
    expect(screen.getByRole('link', { name: /Crear fondo/ })).toHaveAttribute('href', '/admin/funding/new')
    expect(screen.queryByText('Módulo preparado')).not.toBeInTheDocument()
  })
})
