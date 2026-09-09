import { act, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { applicationApi, type FundingApplication } from './application-api'
import { ApplicationsWorkspacePage } from './application-pages'
import { organizationApi } from '@/features/organizations/organization-api'
import { organizationFundingApi } from '@/features/funding/organization-funding-api'
import { projectApi } from '@/features/projects/project-api'
import { trackingApplication, trackingApplications } from '@/test/fixtures/tracking-workspace'
import { workspaceCatalogs, workspaceOrganizationId, workspaceProfile, workspaceProject } from '@/test/fixtures/project-workspace'
import { organizationOpportunity } from '@/test/fixtures/organization-funding'
import { deferred, language, problem, trackingPage } from '@/test/tracking-test-harness'
import { consumerCatalogs } from '@/test/fixtures/catalog-consumers'

beforeEach(() => {
  vi.spyOn(organizationApi, 'list').mockResolvedValue([{ ...workspaceProfile, updatedAtUtc: '2027-02-01T12:00:00Z' }])
  vi.spyOn(organizationApi, 'catalogs').mockResolvedValue(workspaceCatalogs)
  vi.spyOn(projectApi, 'list').mockResolvedValue([workspaceProject])
  vi.spyOn(applicationApi, 'list').mockResolvedValue(trackingApplications)
  vi.spyOn(applicationApi, 'get').mockResolvedValue(trackingApplication)
  vi.spyOn(organizationFundingApi, 'search').mockResolvedValue({ items: [organizationOpportunity], totalCount: 1, pageNumber: 1, pageSize: 50, searchMode: 'filtered' })
})
afterEach(() => vi.restoreAllMocks())

it('preserves editor, status zero, URL, dates, amount and ETag across language changes and a pending save', async () => {
  const pending = deferred<FundingApplication>()
  const update = vi.spyOn(applicationApi, 'update').mockReturnValue(pending.promise)
  const user = userEvent.setup()
  const entry = '/applications?page=2&status=0&projectId=' + workspaceProject.publicId + '&applicationId=' + trackingApplication.publicId
  const { router } = trackingPage(<ApplicationsWorkspacePage />, entry)
  const notes = await screen.findByLabelText('Notas de la postulación')
  await waitFor(() => expect(notes).toHaveValue('Notas Ñandú'))
  await user.clear(notes)
  await user.type(notes, 'Borrador Ñandú')
  await language('en')
  expect(screen.getByLabelText('Application notes')).toHaveValue('Borrador Ñandú')
  expect(screen.getByLabelText('Application status')).toHaveValue('0')
  expect(screen.getByLabelText('Application date')).toHaveValue('2027-02-15')
  expect(screen.getByLabelText('Requested amount')).toHaveValue(12500.5)
  expect(screen.getByLabelText('Currency')).toHaveValue('USD')
  expect(screen.getByRole('option', { name: 'USD · US dollar' })).toHaveAttribute('lang', 'en')
  expect(screen.getByText('$12,500.50')).toBeInTheDocument()
  expect(router.state.location.search).toBe(entry.slice(entry.indexOf('?')))
  expect(applicationApi.list).toHaveBeenCalledTimes(1)
  expect(applicationApi.get).toHaveBeenCalledTimes(1)
  expect(update).not.toHaveBeenCalled()
  await user.click(screen.getByRole('button', { name: 'Save changes' }))
  await language('es')
  expect(screen.getByRole('button', { name: 'Guardar cambios' })).toBeDisabled()
  expect(update).toHaveBeenCalledExactlyOnceWith(workspaceOrganizationId, trackingApplication.publicId, trackingApplication.eTag, {
    status: 0, notes: 'Borrador Ñandú', applicationDate: '2027-02-15', requestedAmount: 12500.5, currency: 'USD', resultDate: '2027-03-01',
  })
  await act(async () => pending.resolve({ ...trackingApplication, notes: 'Borrador Ñandú' }))
  expect(await screen.findByText(/Cambios guardados con éxito/)).toBeInTheDocument()
  await language('en')
  expect(screen.getByText(/Changes saved successfully/)).toBeInTheDocument()
  expect(update).toHaveBeenCalledTimes(1)
})

it('refreshes a 412 explicitly, translates its notice and keeps the replacement ETag', async () => {
  vi.mocked(applicationApi.get).mockResolvedValueOnce(trackingApplication).mockResolvedValue({ ...trackingApplication, notes: 'Versión vigente', eTag: '"next"' })
  const update = vi.spyOn(applicationApi, 'update').mockRejectedValueOnce(problem(412)).mockResolvedValue(trackingApplication)
  const user = userEvent.setup()
  trackingPage(<ApplicationsWorkspacePage />, '/applications?applicationId=' + trackingApplication.publicId)
  await screen.findByLabelText('Notas de la postulación')
  await user.click(screen.getByRole('button', { name: 'Guardar cambios' }))
  await waitFor(() => expect(screen.getByLabelText('Notas de la postulación')).toHaveValue('Versión vigente'))
  await language('en')
  expect(screen.getByRole('alert')).toHaveTextContent('Someone else updated')
  expect(applicationApi.get).toHaveBeenCalledTimes(2)
  await user.click(screen.getByRole('button', { name: 'Save changes' }))
  expect(update.mock.calls[1][2]).toBe('"next"')
})

it('retains a new application draft and retries the same command without locale in its payload', async () => {
  const create = vi.spyOn(applicationApi, 'create').mockRejectedValueOnce(problem(503)).mockResolvedValue(trackingApplication)
  const user = userEvent.setup()
  trackingPage(<ApplicationsWorkspacePage />, '/applications?new=1')
  await waitFor(() => expect(screen.getByLabelText('Proyecto para postular')).toHaveTextContent(workspaceProject.title))
  await user.selectOptions(screen.getByLabelText('Proyecto para postular'), workspaceProject.publicId)
  await user.selectOptions(screen.getByLabelText('Fondo para postular'), organizationOpportunity.publicId)
  await user.type(screen.getByLabelText('Notas'), 'Texto original')
  await user.selectOptions(screen.getByLabelText('Moneda'), 'USD')
  await user.type(screen.getByLabelText('Monto solicitado'), '25000.5')
  await language('en')
  expect(screen.getByLabelText('Currency')).toHaveValue('USD')
  expect(screen.getByRole('option', { name: 'USD · US dollar' })).toHaveAttribute('lang', 'en')
  expect(create).not.toHaveBeenCalled()
  await user.click(screen.getByRole('button', { name: 'Start application' }))
  await screen.findByRole('alert')
  await language('es')
  await user.click(screen.getByRole('button', { name: 'Iniciar postulación' }))
  await screen.findByText(/Postulación iniciada con éxito/)
  expect(create).toHaveBeenCalledTimes(2)
  expect(create.mock.calls[1]).toEqual(create.mock.calls[0])
  expect(create.mock.calls[0][1]).toMatchObject({ notes: 'Texto original', projectId: workspaceProject.publicId, fundingOpportunityId: organizationOpportunity.publicId, currency: 'USD', requestedAmount: 25000.5 })
  expect(organizationApi.catalogs).toHaveBeenCalledOnce()
})

it.each([false, true])('preserves an unreviewed currency label and selection without writes (editing=%s)', async editing => {
  vi.mocked(organizationApi.catalogs).mockResolvedValue(consumerCatalogs)
  vi.mocked(applicationApi.get).mockResolvedValue({ ...trackingApplication, currency: 'EUR' })
  const create = vi.spyOn(applicationApi, 'create')
  const update = vi.spyOn(applicationApi, 'update')
  const user = userEvent.setup()
  const { client } = trackingPage(<ApplicationsWorkspacePage />, editing ? '/applications?applicationId=' + trackingApplication.publicId : '/applications?new=1')
  await screen.findByRole('option', { name: 'EUR · Euro de prueba Ñandú' })
  if (editing) await waitFor(() => expect(screen.getByLabelText('Moneda')).toHaveValue('EUR'))
  else await user.selectOptions(screen.getByLabelText('Moneda'), 'EUR')
  await language('en')
  expect(screen.getByLabelText('Currency')).toHaveValue('EUR')
  expect(screen.getByRole('option', { name: 'EUR · Euro de prueba Ñandú' })).toHaveAttribute('lang', 'es')
  expect(screen.getByRole('option', { name: 'USD · US dollar' })).toHaveAttribute('lang', 'en')
  expect(client.getQueryData(['organization-catalogs'])).toBe(consumerCatalogs)
  await language('es')
  expect(screen.getByLabelText('Moneda')).toHaveValue('EUR')
  expect(organizationApi.catalogs).toHaveBeenCalledOnce()
  expect(create).not.toHaveBeenCalled()
  expect(update).not.toHaveBeenCalled()
})

it('keeps read-only applications disabled in either language', async () => {
  vi.mocked(applicationApi.get).mockResolvedValue({ ...trackingApplication, canEdit: false })
  const update = vi.spyOn(applicationApi, 'update')
  trackingPage(<ApplicationsWorkspacePage />, '/applications?applicationId=' + trackingApplication.publicId)
  await screen.findByLabelText('Notas de la postulación')
  await language('en')
  expect(screen.getByLabelText('Application notes')).toBeDisabled()
  expect(screen.getByRole('button', { name: 'Save changes' })).toBeDisabled()
  expect(update).not.toHaveBeenCalled()
})
