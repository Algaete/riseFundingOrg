import { QueryClientProvider } from '@tanstack/react-query'
import { act, fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import { useForm } from 'react-hook-form'
import { createAppQueryClient } from '@/api/query-client'
import { ApiError } from '@/api/http-client'
import { organizationApi } from '@/features/organizations/organization-api'
import { projectApi, type ProjectWriteInput } from './project-api'
import { ProjectsPage } from './project-pages'
import { ProjectEnrichmentFields } from './project-enrichment-fields'
import { ProjectEnrichmentSummary } from './project-enrichment-summary'
import { enrichmentInput } from './project-enrichment'
import { workspaceCatalogs, workspaceProfile, workspaceProject } from '@/test/fixtures/project-workspace'
import { setInterfaceLanguage } from '@/i18n'

const enrichment = enrichmentInput({ ...enrichmentInput(), problem: 'Problema Ñandú', solution: 'Solución territorial',
  beneficiaryCount: 1200, locality: 'Localidad privada', latitude: -33.456789, longitude: -70.654321,
  impactIndicators: [{ name: 'Acceso al agua', unit: 'hogares', baseline: 0, target: 1200 }],
  soughtPartners: 'Municipios', soughtProfessionals: 'Ingenieros', seekingConsortium: true })

function Harness({ onSubmit = vi.fn(), locked = false, value = enrichmentInput() }: { onSubmit?: (input: ProjectWriteInput) => void; locked?: boolean; value?: typeof enrichment }) {
  const form = useForm<ProjectWriteInput>({ defaultValues: { ...workspaceProject, enrichment: value } })
  return <form noValidate onSubmit={form.handleSubmit(onSubmit)}><fieldset disabled={locked}><ProjectEnrichmentFields form={form} /><button type="submit">Save</button></fieldset></form>
}

describe('project enrichment', () => {
  afterEach(() => vi.restoreAllMocks())

  it('saves an empty optional extension without requiring any new field', async () => {
    const save = vi.fn()
    render(<Harness onSubmit={save} />)
    await userEvent.click(screen.getByRole('button', { name: 'Save' }))
    expect(save).toHaveBeenCalledOnce()
    expect(save.mock.calls[0][0].enrichment).toEqual(enrichmentInput())
    expect(screen.getByLabelText('Cantidad de beneficiarios')).not.toBeRequired()
  })

  it('preserves loaded coordinates, indicators, false and zero when saving', async () => {
    const save = vi.fn()
    render(<Harness onSubmit={save} value={{ ...enrichment, seekingConsortium: false, beneficiaryCount: 0 }} />)
    expect(screen.getByLabelText('¿Busca formar o integrar un consorcio?')).toHaveValue('false')
    await userEvent.click(screen.getByRole('button', { name: 'Save' }))
    expect(save.mock.calls[0][0].enrichment).toEqual({ ...enrichment, seekingConsortium: false, beneficiaryCount: 0 })
  })

  it('adds and removes structured indicators without clearing the draft on language change', async () => {
    const save = vi.fn()
    render(<Harness onSubmit={save} />)
    fireEvent.change(screen.getByLabelText('Problema que aborda'), { target: { value: 'Contenido original Ñandú' } })
    await userEvent.click(screen.getByRole('button', { name: 'Agregar indicador' }))
    await userEvent.click(screen.getByRole('button', { name: 'Save' }))
    expect(screen.getAllByText('Completa este campo o quita el indicador.')).toHaveLength(2)
    expect(save).not.toHaveBeenCalled()
    await act(() => setInterfaceLanguage('en'))
    expect(screen.getByLabelText('Problem addressed')).toHaveValue('Contenido original Ñandú')
    expect(screen.getAllByText('Complete this field or remove the indicator.')).toHaveLength(2)
    fireEvent.change(screen.getByLabelText(/Indicator name/), { target: { value: 'Emisiones' } })
    fireEvent.change(screen.getByLabelText(/Measurement unit/), { target: { value: 'tCO2' } })
    fireEvent.change(screen.getByLabelText('Baseline'), { target: { value: '100' } })
    fireEvent.change(screen.getByLabelText('Target'), { target: { value: '-5' } })
    await userEvent.click(screen.getByRole('button', { name: 'Save' }))
    expect(save.mock.calls[0][0].enrichment.impactIndicators).toEqual([{ name: 'Emisiones', unit: 'tCO2', baseline: 100, target: -5 }])
    await userEvent.click(screen.getByRole('button', { name: 'Remove indicator 1' }))
    await userEvent.click(screen.getByRole('button', { name: 'Save' }))
    expect(save.mock.lastCall![0].enrichment.impactIndicators).toEqual([])
  })

  it('requires coordinates only for an opted-in point or a partially entered pair', async () => {
    const save = vi.fn()
    render(<Harness onSubmit={save} />)
    await userEvent.selectOptions(screen.getByLabelText(/Ubicación visible al público/), '2')
    await userEvent.click(screen.getByRole('button', { name: 'Save' }))
    expect(save).not.toHaveBeenCalled()
    expect(screen.getByLabelText(/Latitud/)).toBeRequired()
    fireEvent.change(screen.getByLabelText(/Latitud/), { target: { value: '0' } })
    fireEvent.change(screen.getByLabelText(/Longitud/), { target: { value: '0' } })
    await userEvent.click(screen.getByRole('button', { name: 'Save' }))
    expect(save.mock.lastCall![0].enrichment).toMatchObject({ latitude: 0, longitude: 0, locationVisibility: 2 })
    await userEvent.selectOptions(screen.getByLabelText(/Ubicación visible al público/), '0')
    fireEvent.change(screen.getByLabelText(/Latitud/), { target: { value: '' } })
    fireEvent.change(screen.getByLabelText(/Longitud/), { target: { value: '' } })
    await userEvent.click(screen.getByRole('button', { name: 'Save' }))
    expect(save.mock.lastCall![0].enrichment).toMatchObject({ latitude: null, longitude: null, locationVisibility: 0 })
  })

  it.each(['-1', '1.5', '2147483648'])('rejects invalid beneficiary counts (%s) before calling the API', async value => {
    const save = vi.fn()
    render(<Harness onSubmit={save} />)
    fireEvent.change(screen.getByLabelText('Cantidad de beneficiarios'), { target: { value } })
    await userEvent.click(screen.getByRole('button', { name: 'Save' }))
    expect(save).not.toHaveBeenCalled()
    expect(screen.getByRole('alert')).toHaveTextContent('Ingresa una cantidad entera')
  })

  it('limits indicators to 20 and allows removing one', async () => {
    render(<Harness value={{ ...enrichment, impactIndicators: Array.from({ length: 20 }, () => ({ name: 'Test', unit: 'people', baseline: null, target: null })) }} />)
    expect(screen.getByRole('button', { name: 'Agregar indicador' })).toBeDisabled()
    await userEvent.click(screen.getByRole('button', { name: 'Quitar indicador 1' }))
    expect(screen.getByRole('button', { name: 'Agregar indicador' })).toBeEnabled()
  })

  it('freezes every enrichment input and indicator action with the reviewed content', () => {
    render(<Harness value={enrichment} locked />)
    for (const input of screen.getAllByRole('textbox')) expect(input).toBeDisabled()
    for (const input of screen.getAllByRole('spinbutton')) expect(input).toBeDisabled()
    for (const input of screen.getAllByRole('combobox')) expect(input).toBeDisabled()
    expect(screen.getByRole('button', { name: 'Quitar indicador 1' })).toBeDisabled()
  })

  it.each([0, 1, 2])('renders public location visibility %s without exact coordinates', async visibility => {
    render(<ProjectEnrichmentSummary value={{ ...enrichment, locationVisibility: visibility }} />)
    expect(screen.getByText('Problema Ñandú')).toBeVisible()
    if (visibility === 0) expect(screen.queryByText(/Localidad privada/)).not.toBeInTheDocument()
    else expect(screen.getByText(/Localidad privada/)).toBeVisible()
    expect(screen.queryByText(/33,456789|70,654321/)).not.toBeInTheDocument()
    if (visibility === 2) expect(screen.getByText(/-33,46, -70,65/)).toBeVisible()
    await act(() => setInterfaceLanguage('en'))
    expect(screen.getByText('Number of beneficiaries:').parentElement).toHaveTextContent('1,200')
    expect(screen.getByText('Problema Ñandú')).toBeVisible()
  })

  it('shows private coordinates only in the administrative/owner view', () => {
    render(<ProjectEnrichmentSummary value={enrichment} privateView />)
    expect(screen.getByText(/-33,456789, -70,654321/)).toBeVisible()
    expect(screen.getByText(/Localidad privada/)).toBeVisible()
  })

  it('connects the complete form to the API and localizes nested server errors', async () => {
    vi.spyOn(organizationApi, 'list').mockResolvedValue([{ ...workspaceProfile, updatedAtUtc: '2026-09-01T12:00:00Z' }])
    vi.spyOn(organizationApi, 'catalogs').mockResolvedValue(workspaceCatalogs)
    vi.spyOn(projectApi, 'list').mockResolvedValue([])
    const create = vi.spyOn(projectApi, 'create').mockRejectedValue(new ApiError({ title: 'PRIVATE', status: 400,
      errors: { 'enrichment.problem': ['PRIVATE'] }, validationIssues: { 'enrichment.problem': [{ code: 'text-max-length', max: 3000 }] },
    }, new Response(null, { status: 400 })))
    render(<QueryClientProvider client={createAppQueryClient()}><MemoryRouter><ProjectsPage /></MemoryRouter></QueryClientProvider>)
    await userEvent.click(await screen.findByRole('button', { name: 'Nuevo proyecto' }))
    fireEvent.change(screen.getByLabelText(/Título/), { target: { value: 'Proyecto enriquecido' } })
    fireEvent.change(screen.getByLabelText('Problema que aborda'), { target: { value: 'Problema original' } })
    await userEvent.click(screen.getByRole('button', { name: 'Crear proyecto' }))
    await waitFor(() => expect(create).toHaveBeenCalledOnce())
    expect(create.mock.calls[0][1].enrichment).toMatchObject({ problem: 'Problema original', locationVisibility: 0, impactIndicators: [] })
    expect(await screen.findAllByText('Admite hasta 3000 caracteres.')).toHaveLength(2)
    await act(() => setInterfaceLanguage('en'))
    const label = screen.getByLabelText(/Problem addressed/).closest('label')!
    expect(within(label).getByRole('alert')).toHaveTextContent('Must not exceed 3000 characters.')
    expect(screen.getByLabelText(/Problem addressed/)).toHaveValue('Problema original')
    expect(screen.queryByText('PRIVATE')).not.toBeInTheDocument()
    expect(create).toHaveBeenCalledOnce()
  })
})
