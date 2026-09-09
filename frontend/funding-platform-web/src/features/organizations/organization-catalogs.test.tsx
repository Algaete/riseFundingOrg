import { act, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { organizationApi, type OrganizationProfile } from './organization-api'
import { OrganizationWorkspacePage } from './organization-pages'
import { bilingualCatalogs, bilingualProfile } from '@/test/fixtures/catalog-workspace'
import { workspaceOrganizationId, workspaceProfile } from '@/test/fixtures/project-workspace'
import { deferred, language, trackingPage } from '@/test/tracking-test-harness'

beforeEach(() => {
  vi.spyOn(organizationApi, 'list').mockResolvedValue([{ ...workspaceProfile, updatedAtUtc: '2027-02-01T12:00:00Z' }])
  vi.spyOn(organizationApi, 'catalogs').mockResolvedValue(bilingualCatalogs)
  vi.spyOn(organizationApi, 'profile').mockResolvedValue(bilingualProfile)
})
afterEach(() => vi.restoreAllMocks())

it('preserves a legacy size, organization types, raw query data and a clean form across languages', async () => {
  const update = vi.spyOn(organizationApi, 'update')
  const { client } = trackingPage(<OrganizationWorkspacePage />, '/organization/profile')
  await screen.findByLabelText(/Tamaño del equipo/)
  await language('en')
  expect(screen.getByLabelText(/Team size/)).toHaveValue('2')
  expect(screen.getByRole('option', { name: 'Small (previous range; confirm a new one)' })).toHaveAttribute('lang', 'en')
  expect(screen.getByRole('option', { name: '11–50 people' })).toHaveValue('6')
  expect(screen.getByLabelText(/Organization type/)).toHaveValue('2')
  expect(screen.getAllByRole('option', { name: 'Foundation' })).toHaveLength(2)
  expect(screen.getByRole('button', { name: 'Save' })).toBeDisabled()
  expect(client.getQueryData(['organization-catalogs'])).toBe(bilingualCatalogs)
  expect(bilingualCatalogs.organizationSizes[1].name).toBe('Pequeña')
  expect(organizationApi.catalogs).toHaveBeenCalledTimes(1)
  expect(organizationApi.profile).toHaveBeenCalledTimes(1)
  expect(update).not.toHaveBeenCalled()
  await language('es')
  expect(screen.getByRole('option', { name: 'Pequeña (rango anterior; confirma uno nuevo)' })).toBeInTheDocument()
})

it('keeps selected legacy project types, private values and drafts while rejecting official labels in either language', async () => {
  const update = vi.spyOn(organizationApi, 'update')
  const user = userEvent.setup()
  trackingPage(<OrganizationWorkspacePage />, '/organization/profile')
  await user.click(await screen.findByRole('button', { name: /Impacto$/ }))
  const original = within(screen.getByRole('group', { name: /Áreas de impacto/ }))
  await user.type(original.getByRole('textbox'), 'Opción privada Ñandú pendiente')
  await language('en')
  expect(screen.getByRole('checkbox', { name: 'Program (previous value; confirm a new type)' })).toBeChecked()
  expect(screen.getByRole('checkbox', { name: 'Environment and biodiversity' })).toBeChecked()
  const impact = within(screen.getByRole('group', { name: /Impact areas/ }))
  expect(impact.getByRole('textbox')).toHaveValue('Opción privada Ñandú pendiente')
  expect(impact.getByText('Cultura Ñandú')).toBeInTheDocument()
  for (const official of ['environment and biodiversity', 'Medio ambiente y biodiversidad']) {
    await user.clear(impact.getByRole('textbox'))
    await user.type(impact.getByRole('textbox'), official + '{Enter}')
    expect(await impact.findByRole('alert')).toHaveTextContent('That option already exists in the list.')
  }
  expect(update).not.toHaveBeenCalled()
  await language('es')
  expect(screen.getByRole('checkbox', { name: 'Programa (valor anterior; confirma un tipo nuevo)' })).toBeChecked()
})

it('submits only original IDs and private values once, including when the language changes during save', async () => {
  const pending = deferred<OrganizationProfile>()
  const update = vi.spyOn(organizationApi, 'update').mockReturnValue(pending.promise)
  const user = userEvent.setup()
  trackingPage(<OrganizationWorkspacePage />, '/organization/profile')
  await user.selectOptions(await screen.findByLabelText(/Tamaño del equipo/), '6')
  await language('en')
  await user.click(screen.getByRole('button', { name: /Impact$/ }))
  await user.click(screen.getByRole('checkbox', { name: 'Education' }))
  await user.click(screen.getByRole('button', { name: /Funding$/ }))
  expect(screen.getByRole('checkbox', { name: 'Governments / public funds' })).toBeChecked()
  expect(screen.getByRole('checkbox', { name: 'Spanish' })).toBeChecked()
  await user.click(screen.getByRole('button', { name: 'Save' }))
  await language('es')
  expect(screen.getByRole('button', { name: 'Guardar' })).toBeDisabled()
  expect(update).toHaveBeenCalledTimes(1)
  expect(update.mock.calls[0]).toEqual([workspaceOrganizationId, bilingualProfile.eTag, expect.objectContaining({
    organizationSizeId: 6, categoryIds: [1, 2], projectTypeIds: [1, 4],
    customImpactAreas: ['Cultura Ñandú'], fundingExperienceTypeIds: [1, 4],
    languages: bilingualProfile.languages,
  })])
  expect(update.mock.calls[0][2]).not.toHaveProperty('locale')
  await act(async () => pending.resolve({ ...bilingualProfile, ...update.mock.calls[0][2] }))
  await waitFor(() => expect(screen.getByRole('button', { name: 'Guardar' })).toBeDisabled())
  expect(update).toHaveBeenCalledTimes(1)
})

it('retains a renamed server label in Spanish instead of silently substituting the bundled translation', async () => {
  vi.mocked(organizationApi.catalogs).mockResolvedValue({ ...bilingualCatalogs, organizationTypes: [{ id: 2, code: 'FOUNDATION', name: 'Fundación comunitaria Ñandú' }] })
  trackingPage(<OrganizationWorkspacePage />, '/organization/profile')
  await screen.findByLabelText(/Tipo de organización/)
  await language('en')
  expect(screen.getByRole('option', { name: 'Fundación comunitaria Ñandú' })).toHaveAttribute('lang', 'es')
})
