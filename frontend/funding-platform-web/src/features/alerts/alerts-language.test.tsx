import { act, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { AlertsWorkspacePage, AlertUnsubscribePage } from './alerts-pages'
import { alertsApi, type SavedSearchDetail } from './alerts-api'
import { organizationApi } from '@/features/organizations/organization-api'
import { workspaceOrganizationId, workspaceProfile } from '@/test/fixtures/project-workspace'
import { trackingNotifications, trackingSearch, trackingSearchDetail, trackingSearches } from '@/test/fixtures/tracking-workspace'
import { deferred, language, problem, trackingPage } from '@/test/tracking-test-harness'

beforeEach(() => {
  vi.spyOn(organizationApi, 'list').mockResolvedValue([{ ...workspaceProfile, updatedAtUtc: '2027-02-01T12:00:00Z' }])
  vi.spyOn(alertsApi, 'list').mockResolvedValue(trackingSearches)
  vi.spyOn(alertsApi, 'notifications').mockResolvedValue(trackingNotifications)
})
afterEach(() => vi.restoreAllMocks())

it('saves without email, preserves filters and draft across languages, and reports the actual result', async () => {
  const pending = deferred<SavedSearchDetail>()
  const create = vi.spyOn(alertsApi, 'create').mockReturnValue(pending.promise)
  const alert = vi.spyOn(alertsApi, 'putAlert')
  const user = userEvent.setup()
  const entry = '/alerts?new=true&q=agua&countryIds=152&regionIds=7&minAmount=25000&maxAmount=100000&currency=USD&sort=amount-desc&onlyOpen=false'
  const { router } = trackingPage(<AlertsWorkspacePage />, entry)
  await user.type(await screen.findByRole('textbox', { name: 'Nombre' }), 'Agua Ñandú')
  await user.click(screen.getByRole('checkbox'))
  await language('en')
  expect(screen.getByRole('textbox', { name: 'Name' })).toHaveValue('Agua Ñandú')
  expect(screen.getByRole('checkbox')).not.toBeChecked()
  expect(router.state.location.search).toBe(entry.slice(entry.indexOf('?')))
  expect(create).not.toHaveBeenCalled()
  expect(alertsApi.list).toHaveBeenCalledTimes(1)
  await user.click(screen.getByRole('button', { name: 'Save' }))
  await language('es')
  expect(screen.getByRole('button', { name: 'Guardar' })).toBeDisabled()
  await act(async () => pending.resolve(trackingSearchDetail))
  expect(await screen.findByText('Búsqueda guardada correctamente.')).toBeInTheDocument()
  await language('en')
  expect(screen.getByText('Search saved successfully.')).toBeInTheDocument()
  expect(alert).not.toHaveBeenCalled()
  expect(create).toHaveBeenCalledTimes(1)
  expect(create.mock.calls[0][0]).toBe(workspaceOrganizationId)
  expect(create.mock.calls[0][1]).toMatchObject({ name: 'Agua Ñandú', query: 'agua', countryIds: [152], regionIds: [7], minimumAmount: 25000, maximumAmount: 100000, currency: 'USD', sort: 'amount-desc', onlyOpen: false })
  expect(create.mock.calls[0][2]).toMatch(/^saved-search-/)
})

it.each([
  [problem(503, 'alerts-disabled'), /email delivery is not enabled/],
  [problem(503, 'unrelated'), /could not confirm email activation/],
])('keeps partial success and the original local hour/time zone after a language change', async (error, expected) => {
  vi.spyOn(alertsApi, 'create').mockResolvedValue(trackingSearchDetail)
  const alert = vi.spyOn(alertsApi, 'putAlert').mockRejectedValue(error)
  const user = userEvent.setup()
  trackingPage(<AlertsWorkspacePage />, '/alerts?new=true&q=agua')
  await user.type(await screen.findByRole('textbox', { name: 'Nombre' }), 'Agua Ñandú')
  await user.selectOptions(screen.getByLabelText('Hora local'), '21')
  await language('en')
  await user.click(screen.getByRole('button', { name: 'Save' }))
  expect(await screen.findByText(expected)).toBeInTheDocument()
  expect(alert).toHaveBeenCalledExactlyOnceWith(workspaceOrganizationId, trackingSearch.id, 21, Intl.DateTimeFormat().resolvedOptions().timeZone)
  expect(screen.queryByText(/PRIVATE-DIAGNOSTIC/)).not.toBeInTheDocument()
  await language('es')
  expect(screen.getByText(/La búsqueda quedó guardada/)).toBeInTheDocument()
  expect(alertsApi.create).toHaveBeenCalledTimes(1)
})

it('localizes notification states, opens original saved filters and deletes with the original ETag only on request', async () => {
  vi.spyOn(alertsApi, 'get').mockResolvedValue(trackingSearchDetail)
  const remove = vi.spyOn(alertsApi, 'remove').mockResolvedValue(undefined)
  const user = userEvent.setup()
  const { router } = trackingPage(<AlertsWorkspacePage />, '/alerts')
  await screen.findByText('Reintento programado')
  await language('en')
  expect(screen.getByText('Retry scheduled')).toBeInTheDocument()
  expect(screen.getByText(/1 opportunity · scheduled/)).toBeInTheDocument()
  expect(remove).not.toHaveBeenCalled()
  await user.click(screen.getByRole('button', { name: 'Open' }))
  await waitFor(() => expect(router.state.location.pathname).toBe('/opportunities'))
  expect(new URLSearchParams(router.state.location.search).get('countryIds')).toBe('152')
  expect(new URLSearchParams(router.state.location.search).get('sort')).toBe('amount-desc')
  await user.click(screen.getByRole('button', { name: 'Delete Agua Ñandú' }))
  expect(remove).toHaveBeenCalledExactlyOnceWith(workspaceOrganizationId, trackingSearch.id, trackingSearch.eTag)
  expect(await screen.findByText('Search deleted and alert disabled.')).toBeInTheDocument()
})

it('never unsubscribes automatically or moves the token out of the fragment', async () => {
  const unsubscribe = vi.spyOn(alertsApi, 'unsubscribe').mockResolvedValue(undefined)
  const user = userEvent.setup()
  const { router } = trackingPage(<AlertUnsubscribePage />, '/alerts/unsubscribe#token=synthetic-secret')
  await language('en')
  expect(unsubscribe).not.toHaveBeenCalled()
  expect(router.state.location.hash).toBe('#token=synthetic-secret')
  expect(router.state.location.search).toBe('')
  expect(screen.queryByText(/synthetic-secret/)).not.toBeInTheDocument()
  await user.click(screen.getByRole('button', { name: 'Confirm unsubscribe' }))
  expect(await screen.findByText(/The alert has been disabled/)).toBeInTheDocument()
  await language('es')
  expect(screen.getByText(/La alerta quedó desactivada/)).toBeInTheDocument()
  expect(unsubscribe).toHaveBeenCalledExactlyOnceWith('synthetic-secret')
})

it('shows organization load errors without suggesting an account or organization is missing', async () => {
  vi.mocked(organizationApi.list).mockRejectedValue(problem(503))
  trackingPage(<AlertsWorkspacePage />, '/alerts')
  await screen.findByRole('alert')
  await language('en')
  expect(screen.getByRole('alert')).toHaveTextContent('We could not load your organization.')
  expect(screen.queryByRole('link', { name: 'Get started' })).not.toBeInTheDocument()
  expect(alertsApi.list).not.toHaveBeenCalled()
})
