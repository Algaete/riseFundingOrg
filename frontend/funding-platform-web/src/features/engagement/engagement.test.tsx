import { act, fireEvent, render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { createMemoryRouter, MemoryRouter, RouterProvider } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { setInterfaceLanguage } from '@/i18n'
import { workspaceCatalogs, workspaceProfile } from '@/test/fixtures/project-workspace'
import { ContactPage, ServicesPage, AdminInquiriesPage } from './contact-pages'
import { StoriesWorkspacePage } from './story-pages'
import { StoryFeed } from './story-feed'
import { DonationComingSoon } from './engagement-ui'
import { engagementApi } from './engagement-api'
import type { ReactElement } from 'react'

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } })
const client = () => new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } })
function open(element: ReactElement, path = '/') { return render(<QueryClientProvider client={client()}><MemoryRouter initialEntries={[path]}>{element}</MemoryRouter></QueryClientProvider>) }
afterEach(() => { vi.unstubAllGlobals(); vi.restoreAllMocks() })

it('shows seven quote-only services and passes the chosen service to contact', async () => {
  const fetch = vi.fn(); vi.stubGlobal('fetch', fetch); open(<ServicesPage />)
  expect(screen.getAllByRole('link', { name: 'Solicitar cotización' })).toHaveLength(7)
  expect(screen.getAllByRole('link', { name: 'Solicitar cotización' })[5]).toHaveAttribute('href', '/contact?service=translation')
  expect(screen.getByText(/no está incluido automáticamente/)).toBeInTheDocument()
  expect(fetch).not.toHaveBeenCalled()
  await act(() => setInterfaceLanguage('en'))
  expect(screen.getByRole('heading', { name: 'Professional services' })).toBeInTheDocument()
  expect(screen.getAllByRole('link', { name: 'Request a quote' })).toHaveLength(7)
})
it('has separate disabled donation buttons without a payment request', async () => {
  const fetch = vi.fn(); vi.stubGlobal('fetch', fetch); open(<><DonationComingSoon /><DonationComingSoon project /></>)
  expect(screen.getByRole('button', { name: 'Dona aquí — Próximamente' })).toBeDisabled()
  expect(screen.getByRole('button', { name: 'Dona a este proyecto — Próximamente' })).toBeDisabled()
  await userEvent.click(screen.getAllByRole('button')[0]); expect(fetch).not.toHaveBeenCalled()
})
it('captures optional-field contact with consent and keeps its id on retry', async () => {
  const writes: Record<string, unknown>[] = []; let fail = true
  vi.stubGlobal('fetch', vi.fn(async (_input: RequestInfo | URL, options: RequestInit) => {
    if (options.method === 'GET') return json(workspaceCatalogs)
    const data = JSON.parse(String(options.body)); writes.push(data)
    return fail ? json({ status: 503, title: 'private failure' }, 503) : json({ requestId: data.requestId, wasReplay: true })
  }))
  const user = userEvent.setup(); open(<ContactPage />, '/contact?service=translation')
  expect(await screen.findByRole('option', { name: 'Chile' })).toBeInTheDocument()
  expect(screen.getByLabelText('Servicio *')).toHaveValue('translation')
  fireEvent.change(screen.getByLabelText('Nombre *'), { target: { value: 'Ana' } })
  fireEvent.change(screen.getByLabelText('Correo electrónico *'), { target: { value: 'ana@example.invalid' } })
  fireEvent.change(screen.getByLabelText(/Describe tu necesidad/), { target: { value: 'Necesitamos traducción de nuestra propuesta.' } })
  await user.selectOptions(screen.getByLabelText('País *'), '152')
  expect(screen.getByRole('button', { name: 'Enviar solicitud' })).toBeDisabled()
  await user.click(screen.getByRole('checkbox'))
  await user.click(screen.getByRole('button', { name: 'Enviar solicitud' }))
  expect(await screen.findByRole('alert')).not.toHaveTextContent('private failure')
  expect(screen.getByLabelText('Nombre *')).toHaveValue('Ana')
  fail = false; await user.click(screen.getByRole('button', { name: 'Enviar solicitud' }))
  expect(await screen.findByRole('heading', { name: 'Solicitud registrada' })).toBeInTheDocument()
  expect(writes).toHaveLength(2); expect(writes[0].requestId).toBe(writes[1].requestId)
  expect(writes[0]).toMatchObject({ topic: 'service', serviceCode: 'translation', consentToContact: true, projectReference: null, organization: null, deadline: null })
  expect(screen.queryByText(/correo enviado/i)).not.toBeInTheDocument()
})
it('country search narrows options without clearing a selection or changing request data', async () => {
  vi.stubGlobal('fetch', vi.fn(async () => json({ ...workspaceCatalogs, countries: [...workspaceCatalogs.countries, { id: 32, code: 'AR', name: 'Argentina' }] })))
  open(<ContactPage />); const user = userEvent.setup()
  await screen.findByRole('option', { name: 'Chile' })
  await user.selectOptions(screen.getByLabelText('País *'), '152')
  fireEvent.change(screen.getByLabelText('Buscar país'), { target: { value: 'no existe' } })
  expect(screen.getByLabelText('País *')).toHaveValue('152'); expect(screen.queryByRole('option', { name: 'Argentina' })).not.toBeInTheDocument()
})
it.each([null, undefined, []])('handles empty story collections %j without map crashes', async items => {
  vi.stubGlobal('fetch', vi.fn(async () => json({ items, totalCount: 0, page: 1 })))
  open(<StoryFeed organizationId={workspaceProfile.publicId} />)
  expect(await screen.findByText('Aún no hay historias para mostrar.')).toBeInTheDocument()
})
it('does not present malformed story data as an empty success', async () => {
  vi.stubGlobal('fetch', vi.fn(async () => json({ items: null, totalCount: 2, page: 1 })))
  open(<StoryFeed />); expect(await screen.findByText('Las historias no están disponibles en este momento.')).toBeInTheDocument()
  expect(screen.queryByText('Aún no hay historias para mostrar.')).not.toBeInTheDocument()
})
it('requires both rights and personal consent to publish beneficiary stories', async () => {
  const writes: Record<string, unknown>[] = []
  const story = { id: '22222222-2222-2222-2222-222222222222', organizationId: workspaceProfile.publicId, organizationName: 'Organización TEST', status: 0, revision: 1,
    content: { title: 'Historia TEST', body: 'Trabajo con la comunidad local.', kind: 'beneficiaries', containsPersonalExperiences: true, categoryIds: [], goalIds: [], countryIds: [] } }
  vi.stubGlobal('fetch', vi.fn(async (input: RequestInfo | URL, options: RequestInit) => {
    const path = String(input)
    if (options.method === 'POST') { writes.push(JSON.parse(String(options.body))); return new Response(null, { status: 204 }) }
    return json(path.includes('/stories') ? { items: [story], totalCount: 1, page: 1 } : [workspaceProfile])
  }))
  const router = createMemoryRouter([{ path: '/', element: <StoriesWorkspacePage /> }]);
  render(<QueryClientProvider client={client()}><RouterProvider router={router} /></QueryClientProvider>)
  const user = userEvent.setup(); await screen.findByRole('option', { name: workspaceProfile.name })
  await user.selectOptions(screen.getByRole('combobox'), workspaceProfile.publicId)
  const publish = await screen.findByRole('button', { name: 'Publicar historia' }); expect(publish).toBeDisabled()
  await user.click(screen.getByLabelText(/tiene autorización/)); expect(publish).toBeDisabled()
  await user.click(screen.getByLabelText(/contamos con consentimiento/)); expect(publish).toBeEnabled()
  await user.click(publish); await waitFor(() => expect(writes).toHaveLength(1))
  expect(writes[0]).toMatchObject({ expectedRevision: 1, publish: true, rightsConfirmed: true, personalConsentConfirmed: true })
})
it('keeps inquiry lists private and sends optimistic review version', async () => {
  const review = vi.spyOn(engagementApi, 'reviewInquiry').mockResolvedValue()
  vi.spyOn(engagementApi, 'inquiries').mockResolvedValue({ items: [{ requestId: 'test-request', countryName: 'Chile', status: 0, revision: 3, notificationStatus: 0, createdAtUtc: '2026-09-22T00:00:00Z', data: { requestId: 'test-request', name: 'Ana', email: 'ana@example.invalid', organization: null, countryId: 152, topic: 'funding', serviceCode: null, projectReference: null, fundingReference: null, deadline: null, description: 'Necesitamos orientación para el proyecto.', consentToContact: true, website: '' } }], totalCount: 1, page: 1 })
  open(<AdminInquiriesPage />); const user = userEvent.setup(); await screen.findByText('ana@example.invalid')
  await user.selectOptions(screen.getByLabelText('Estado de atención'), '1'); await user.click(screen.getByRole('button', { name: 'Guardar estado' }))
  await waitFor(() => expect(review).toHaveBeenCalledWith(expect.objectContaining({ revision: 3 }), 1))
  expect(screen.getByText('Aviso por correo pendiente o deshabilitado.')).toBeInTheDocument()
})
