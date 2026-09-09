import { QueryClientProvider } from '@tanstack/react-query'
import { act, render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { createMemoryRouter, RouterProvider } from 'react-router-dom'

import { createAppQueryClient } from '@/api/query-client'
import { alertsApi } from '@/features/alerts/alerts-api'
import { applicationApi, type ApplicationStatus } from '@/features/applications/application-api'
import { calendarApi } from '@/features/calendar/calendar-api'
import { DashboardWorkspacePage } from '@/features/dashboard/dashboard-page'
import { organizationApi } from '@/features/organizations/organization-api'
import { projectApi } from '@/features/projects/project-api'
import { setInterfaceLanguage } from '@/i18n'
import { dashboardApplications, dashboardCalendar, dashboardOrganizations } from '@/test/fixtures/dashboard-workspace'
import { workspaceProject } from '@/test/fixtures/project-workspace'

function renderDashboard(path = '/dashboard') {
  const queryClient = createAppQueryClient()
  queryClient.setDefaultOptions({ queries: { retry: false, staleTime: 30_000 } })
  const router = createMemoryRouter([{ path: '/dashboard', element: <DashboardWorkspacePage /> }], { initialEntries: [path] })
  render(<QueryClientProvider client={queryClient}><RouterProvider router={router} /></QueryClientProvider>)
  return router
}

describe('dashboard language changes', () => {
  beforeEach(() => {
    vi.spyOn(organizationApi, 'list').mockResolvedValue(dashboardOrganizations)
    vi.spyOn(projectApi, 'list').mockResolvedValue([workspaceProject])
    vi.spyOn(applicationApi, 'list').mockResolvedValue(dashboardApplications)
    vi.spyOn(calendarApi, 'get').mockResolvedValue(dashboardCalendar)
    vi.spyOn(alertsApi, 'list').mockResolvedValue({ items: [], totalCount: 2, page: 1, pageSize: 1 })
  })
  afterEach(() => vi.restoreAllMocks())

  it('preserves the selected organization, source titles, request scope and links while localizing counts and dates', async () => {
    const id = dashboardOrganizations[1].publicId
    const router = renderDashboard(`/dashboard?organizationId=${id}&keep=original`)
    await screen.findByText('Cierre Fondo Agua Ñandú')
    await act(() => setInterfaceLanguage('en'))
    expect(screen.getByRole('heading', { name: 'Overview' })).toBeVisible()
    expect(screen.getByRole('combobox', { name: 'Overview organization' })).toHaveValue(id)
    expect(screen.getByText('Sep 20, 2026')).toBeVisible()
    expect(screen.getByText('1,234')).toBeVisible()
    expect(screen.getByText('Agua segura Ñandú · Preparing application')).toBeVisible()
    expect(screen.getByText('Fondo Agua Ñandú')).toBeVisible()
    expect(screen.getByRole('link', { name: 'View all applications' })).toHaveAttribute('href', `/applications?organizationId=${id}`)
    expect(router.state.location.search).toBe(`?organizationId=${id}&keep=original`)
    expect(projectApi.list).toHaveBeenCalledExactlyOnceWith(id, expect.any(AbortSignal))
    expect(applicationApi.list).toHaveBeenCalledExactlyOnceWith(id, { page: 1, pageSize: 5 }, expect.any(AbortSignal))
    expect(calendarApi.get).toHaveBeenCalledOnce()
    expect(alertsApi.list).toHaveBeenCalledOnce()
    expect(organizationApi.list).toHaveBeenCalledOnce()
    await act(() => setInterfaceLanguage('es'))
    expect(screen.getByRole('combobox', { name: 'Organización del resumen' })).toHaveValue(id)
    expect(screen.getByText('Agua segura Ñandú · Preparando postulación')).toBeVisible()
    expect(projectApi.list).toHaveBeenCalledOnce()
  })

  it('changes organization and refreshes only after an explicit action, keeping other URL parameters', async () => {
    const router = renderDashboard('/dashboard?keep=original')
    await screen.findByText('Cierre Fondo Agua Ñandú')
    await act(() => setInterfaceLanguage('en'))
    await userEvent.selectOptions(screen.getByRole('combobox', { name: 'Overview organization' }), dashboardOrganizations[1].publicId)
    await waitFor(() => expect(screen.getByRole('button', { name: 'Refresh' })).toBeEnabled())
    expect(new URLSearchParams(router.state.location.search).get('keep')).toBe('original')
    expect(projectApi.list).toHaveBeenCalledTimes(2)
    expect(projectApi.list).toHaveBeenLastCalledWith(dashboardOrganizations[1].publicId, expect.any(AbortSignal))
    await userEvent.click(screen.getByRole('button', { name: 'Refresh' }))
    await waitFor(() => expect(projectApi.list).toHaveBeenCalledTimes(3))
    expect(organizationApi.list).toHaveBeenCalledOnce()
  })

  it.each([
    [0, 'Interested'], [1, 'Preparing application'], [2, 'Submitted'],
    [3, 'Awarded'], [4, 'Not awarded'], [5, 'Discarded'],
  ] as const)('localizes application status %s without changing its value', async (status: ApplicationStatus, label) => {
    vi.mocked(applicationApi.list).mockResolvedValue({ ...dashboardApplications, items: [{ ...dashboardApplications.items[0], status }] })
    renderDashboard()
    await screen.findByText('Fondo Agua Ñandú')
    await act(() => setInterfaceLanguage('en'))
    expect(screen.getByText(`Agua segura Ñandú · ${label}`)).toBeVisible()
    expect(applicationApi.list).toHaveBeenCalledOnce()
  })

  it.each([1, 2])('localizes %s failed metrics and leaves the available data visible', async count => {
    vi.mocked(calendarApi.get).mockRejectedValue(new Error('synthetic failure'))
    if (count === 2) vi.mocked(alertsApi.list).mockRejectedValue(new Error('synthetic failure'))
    renderDashboard()
    await screen.findByText('El calendario no está disponible.')
    await act(() => setInterfaceLanguage('en'))
    expect(screen.getByRole('status')).toHaveTextContent(count === 1
      ? 'One metric could not be refreshed. The remaining data is still available.'
      : '2 metrics could not be refreshed. The remaining data is still available.')
    expect(screen.getByText('Fondo Agua Ñandú')).toBeVisible()
    expect(screen.getByText('1,234')).toBeVisible()
    expect(calendarApi.get).toHaveBeenCalledOnce()
  })

  it('localizes loading without starting an additional organization request', async () => {
    vi.mocked(organizationApi.list).mockReturnValue(new Promise(() => undefined))
    renderDashboard()
    expect(screen.getByRole('status')).toHaveTextContent('Cargando tu resumen…')
    await act(() => setInterfaceLanguage('en'))
    expect(screen.getByRole('status')).toHaveTextContent('Loading your overview…')
    expect(organizationApi.list).toHaveBeenCalledOnce()
    expect(projectApi.list).not.toHaveBeenCalled()
  })

  it('localizes the empty workspace without fetching private modules', async () => {
    vi.mocked(organizationApi.list).mockResolvedValue([])
    renderDashboard()
    await screen.findByRole('heading', { name: 'Comienza creando tu organización' })
    await act(() => setInterfaceLanguage('en'))
    expect(screen.getByRole('link', { name: 'Create organization' })).toHaveAttribute('href', '/onboarding')
    expect(projectApi.list).not.toHaveBeenCalled()
    expect(applicationApi.list).not.toHaveBeenCalled()
    expect(calendarApi.get).not.toHaveBeenCalled()
    expect(alertsApi.list).not.toHaveBeenCalled()
  })

  it('retries failed organization loading only on request and localizes empty module states', async () => {
    vi.mocked(organizationApi.list).mockRejectedValueOnce(new Error('synthetic failure'))
    vi.mocked(calendarApi.get).mockResolvedValue({ ...dashboardCalendar, items: [] })
    vi.mocked(applicationApi.list).mockResolvedValue({ ...dashboardApplications, items: [], totalCount: 0 })
    renderDashboard()
    await screen.findByRole('heading', { name: 'No pudimos cargar tus organizaciones' })
    await act(() => setInterfaceLanguage('en'))
    expect(screen.getByRole('heading', { name: 'We could not load your organizations' })).toBeVisible()
    expect(organizationApi.list).toHaveBeenCalledOnce()
    await userEvent.click(screen.getByRole('button', { name: 'Retry' }))
    expect(await screen.findByText('There are no milestones in this period.')).toBeVisible()
    expect(await screen.findByText('No applications are being tracked yet.')).toBeVisible()
    expect(organizationApi.list).toHaveBeenCalledTimes(2)
  })
})
