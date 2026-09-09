import { QueryClientProvider } from '@tanstack/react-query'
import { act, fireEvent, render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'

import { ApiError } from '@/api/http-client'
import { createAppQueryClient } from '@/api/query-client'
import { organizationApi } from '@/features/organizations/organization-api'
import { projectApi } from '@/features/projects/project-api'
import { setInterfaceLanguage } from '@/i18n'
import { consumerNetworkOrganization } from '@/test/fixtures/catalog-consumers'
import { collaborationOrganizations, networkConnection, networkConnections, networkDirectory, networkOrganization, networkPreference, workspaceOrganizationId, workspaceProject, workspaceProjectId } from '@/test/fixtures/matching-network'
import { networkApi, type OrganizationConnection } from './network-api'
import { NetworkWorkspacePage } from './network-pages'

function mount() {
  const client = createAppQueryClient()
  client.setDefaultOptions({ queries: { retry: false, staleTime: 30_000 } })
  render(<QueryClientProvider client={client}><MemoryRouter><NetworkWorkspacePage /></MemoryRouter></QueryClientProvider>)
}

function deferred<T>() {
  let resolve!: (value: T) => void
  const promise = new Promise<T>(yes => { resolve = yes })
  return { promise, resolve }
}

async function prepareInvitation() {
  await userEvent.click(await screen.findByRole('button', { name: 'Conectar' }))
  await userEvent.selectOptions(screen.getByRole('combobox', { name: 'Propósito' }), 'consortium-exploration')
  await userEvent.selectOptions(screen.getByRole('combobox', { name: 'Proyecto público opcional' }), workspaceProjectId)
  fireEvent.change(screen.getByRole('textbox', { name: 'Mensaje privado' }), { target: { value: '  Invitación original Ñandú para colaborar.  ' } })
}

describe('organization network ES/EN', () => {
  beforeEach(() => {
    vi.spyOn(organizationApi, 'list').mockResolvedValue(collaborationOrganizations)
    vi.spyOn(projectApi, 'list').mockResolvedValue([{ ...workspaceProject, publicationStatus: 2 }, { ...workspaceProject, publicId: 'private-draft', title: 'SECRET-DRAFT', publicationStatus: 0 }])
    vi.spyOn(networkApi, 'settings').mockResolvedValue(networkPreference)
    vi.spyOn(networkApi, 'directory').mockResolvedValue(networkDirectory)
    vi.spyOn(networkApi, 'connections').mockResolvedValue(networkConnections)
    vi.spyOn(networkApi, 'putSettings').mockResolvedValue(networkPreference)
    vi.spyOn(networkApi, 'create').mockResolvedValue(networkConnection)
    vi.spyOn(networkApi, 'action').mockResolvedValue(networkConnection)
  })
  afterEach(() => vi.restoreAllMocks())

  it('keeps unsent search, selected direction, recipient, purpose, project and private draft without writes', async () => {
    mount()
    await prepareInvitation()
    fireEvent.change(screen.getByRole('textbox', { name: 'Buscar organizaciones' }), { target: { value: '  Búsqueda Ñandú  ' } })
    await userEvent.click(screen.getByRole('button', { name: 'Recibidas' }))
    await waitFor(() => expect(networkApi.connections).toHaveBeenCalledTimes(2))
    await act(() => setInterfaceLanguage('en'))
    expect(screen.getByRole('textbox', { name: 'Search organizations' })).toHaveValue('  Búsqueda Ñandú  ')
    expect(screen.getByRole('button', { name: 'Incoming' })).toHaveAttribute('aria-pressed', 'true')
    expect(screen.getByRole('heading', { name: 'Invite ' + networkOrganization.name })).toBeVisible()
    expect(screen.getByRole('combobox', { name: 'Purpose' })).toHaveValue('consortium-exploration')
    expect(screen.getByRole('combobox', { name: 'Optional public project' })).toHaveValue(workspaceProjectId)
    expect(screen.getByRole('textbox', { name: 'Private message' })).toHaveValue('  Invitación original Ñandú para colaborar.  ')
    expect(screen.getByText('1 public project')).toBeVisible()
    expect(screen.getByText(networkConnection.message)).toHaveAttribute('lang', 'es')
    expect(screen.queryByText('SECRET-DRAFT')).not.toBeInTheDocument()
    expect(screen.getByText('Environment')).toHaveAttribute('lang', 'en')
    expect(networkApi.directory).toHaveBeenCalledExactlyOnceWith(workspaceOrganizationId, '', 1, expect.any(AbortSignal))
    expect(networkApi.settings).toHaveBeenCalledOnce()
    expect(networkApi.connections).toHaveBeenCalledTimes(2)
    expect(networkApi.putSettings).not.toHaveBeenCalled()
    expect(networkApi.create).not.toHaveBeenCalled()
    expect(networkApi.action).not.toHaveBeenCalled()
    await userEvent.click(screen.getByRole('button', { name: 'Search' }))
    await waitFor(() => expect(networkApi.directory).toHaveBeenLastCalledWith(workspaceOrganizationId, 'Búsqueda Ñandú', 1, expect.any(AbortSignal)))
    expect(networkApi.directory).toHaveBeenCalledTimes(2)
  })

  it('keeps a pending invitation’s payload/idempotency key and translates the completion notice', async () => {
    vi.mocked(networkApi.settings).mockResolvedValue({ ...networkPreference, isDiscoverable: true, allowRequests: true })
    const pending = deferred<OrganizationConnection>()
    vi.mocked(networkApi.create).mockImplementation(() => pending.promise)
    mount()
    await prepareInvitation()
    await userEvent.click(screen.getByRole('button', { name: 'Enviar solicitud' }))
    await act(() => setInterfaceLanguage('en'))
    expect(screen.getByRole('button', { name: 'Send request' })).toBeDisabled()
    expect(screen.getByRole('textbox', { name: 'Private message' })).toHaveValue('  Invitación original Ñandú para colaborar.  ')
    expect(networkApi.create).toHaveBeenCalledExactlyOnceWith(workspaceOrganizationId, {
      recipientOrganizationId: networkOrganization.id, requesterProjectId: workspaceProjectId,
      purpose: 'consortium-exploration', message: '  Invitación original Ñandú para colaborar.  ',
    }, expect.stringMatching(/^organization-connect-/))
    await act(async () => { pending.resolve(networkConnection); await pending.promise })
    expect(await screen.findByText('Request sent. The other organization must explicitly accept it.')).toBeVisible()
    await act(() => setInterfaceLanguage('es'))
    expect(screen.getByText('Solicitud enviada. La otra organización debe aceptarla explícitamente.')).toBeVisible()
    expect(networkApi.create).toHaveBeenCalledOnce()
    expect(networkApi.putSettings).not.toHaveBeenCalled()
    expect(networkApi.action).not.toHaveBeenCalled()
  })

  it('localizes only reviewed directory labels without fetching catalogs, exposing more fields or sending the draft', async () => {
    vi.mocked(networkApi.directory).mockResolvedValue({ ...networkDirectory, items: [consumerNetworkOrganization] })
    const catalogs = vi.spyOn(organizationApi, 'catalogs')
    mount()
    await prepareInvitation()
    await act(() => setInterfaceLanguage('en'))
    expect(screen.getByText('Foundation', { exact: true })).toHaveAttribute('lang', 'en')
    expect(screen.getByText('Environment and biodiversity')).toHaveAttribute('lang', 'en')
    for (const text of ['Territorio Ñandú', 'Educación comunitaria Ñandú', 'Nueva área Ñandú']) {
      expect(screen.getByText(text)).toHaveAttribute('lang', 'es')
    }
    expect(screen.getByText(consumerNetworkOrganization.description)).toBeVisible()
    expect(screen.getByRole('textbox', { name: 'Private message' })).toHaveValue('  Invitación original Ñandú para colaborar.  ')
    await act(() => setInterfaceLanguage('es'))
    expect(screen.getByText('Fundación', { exact: true })).toHaveAttribute('lang', 'es')
    expect(networkApi.directory).toHaveBeenCalledOnce()
    expect(catalogs).not.toHaveBeenCalled()
    expect(networkApi.create).not.toHaveBeenCalled()
    expect(networkApi.putSettings).not.toHaveBeenCalled()
    expect(networkApi.action).not.toHaveBeenCalled()
  })

  it('retries an uncertain invitation with the same key and original input after language changes', async () => {
    vi.mocked(networkApi.settings).mockResolvedValue({ ...networkPreference, isDiscoverable: true, allowRequests: true })
    vi.mocked(networkApi.create).mockRejectedValueOnce(new Error('SECRET-ERROR'))
    mount()
    await prepareInvitation()
    await userEvent.click(screen.getByRole('button', { name: 'Enviar solicitud' }))
    await screen.findByRole('alert')
    const first = vi.mocked(networkApi.create).mock.calls[0]
    await act(() => setInterfaceLanguage('en'))
    expect(screen.getByRole('alert')).toHaveTextContent('We could not confirm the operation. You can retry without duplicating it.')
    expect(screen.queryByText('SECRET-ERROR')).not.toBeInTheDocument()
    expect(networkApi.create).toHaveBeenCalledOnce()
    await userEvent.click(screen.getByRole('button', { name: 'Send request' }))
    await screen.findByText('Request sent. The other organization must explicitly accept it.')
    expect(vi.mocked(networkApi.create).mock.calls[1]).toEqual(first)
    expect(networkApi.create).toHaveBeenCalledTimes(2)
  })

  it('keeps explicit visibility changes and their ETag stable during a language switch', async () => {
    const pending = deferred<typeof networkPreference>()
    vi.mocked(networkApi.putSettings).mockImplementation(() => pending.promise)
    mount()
    await userEvent.click(await screen.findByRole('button', { name: 'Activar directorio y recibir solicitudes' }))
    await act(() => setInterfaceLanguage('en'))
    expect(screen.getByRole('button', { name: 'Join the directory and receive requests' })).toBeDisabled()
    expect(networkApi.putSettings).toHaveBeenCalledExactlyOnceWith(workspaceOrganizationId, { isDiscoverable: true, allowRequests: true }, networkPreference.eTag)
    await act(async () => { pending.resolve(networkPreference); await pending.promise })
    expect(await screen.findByText('Network settings updated.')).toBeVisible()
    await act(() => setInterfaceLanguage('es'))
    expect(screen.getByText('Configuración de networking actualizada.')).toBeVisible()
    expect(networkApi.putSettings).toHaveBeenCalledOnce()
    expect(networkApi.create).not.toHaveBeenCalled()
  })

  it.each([
    ['accept', 'Aceptar'], ['reject', 'Rechazar'], ['cancel', 'Cancelar'], ['block', 'Bloquear'],
  ] as const)('retains the connection and ETag for a pending %s action', async (action, spanish) => {
    const connection = action === 'cancel' ? { ...networkConnection, direction: 'outgoing' as const, canRespond: false, canCancel: true } : networkConnection
    vi.mocked(networkApi.connections).mockResolvedValue({ ...networkConnections, items: [connection] })
    const pending = deferred<OrganizationConnection>()
    vi.mocked(networkApi.action).mockImplementation(() => pending.promise)
    mount()
    await userEvent.click(await screen.findByRole('button', { name: spanish }))
    await act(() => setInterfaceLanguage('en'))
    expect(networkApi.action).toHaveBeenCalledExactlyOnceWith(workspaceOrganizationId, connection, action)
    await act(async () => { pending.resolve(connection); await pending.promise })
    expect(await screen.findByText('Request updated.')).toBeVisible()
    await act(() => setInterfaceLanguage('es'))
    expect(screen.getByText('Solicitud actualizada.')).toBeVisible()
    expect(networkApi.action).toHaveBeenCalledOnce()
  })

  it('keeps member permissions and server capabilities unchanged', async () => {
    vi.mocked(organizationApi.list).mockResolvedValue([{ ...collaborationOrganizations[0], membershipRole: 'member' }])
    vi.mocked(networkApi.connections).mockResolvedValue({ ...networkConnections, items: [{ ...networkConnection, canRespond: false, canCancel: false, canBlock: false }] })
    mount()
    await screen.findByRole('heading', { name: networkOrganization.name })
    await act(() => setInterfaceLanguage('en'))
    expect(screen.getByRole('button', { name: 'Join the directory and receive requests' })).toBeDisabled()
    for (const name of ['Connect', 'Accept', 'Reject', 'Block', 'Cancel']) expect(screen.queryByRole('button', { name })).not.toBeInTheDocument()
    expect(projectApi.list).not.toHaveBeenCalled()
    expect(networkApi.putSettings).not.toHaveBeenCalled()
    expect(networkApi.create).not.toHaveBeenCalled()
    expect(networkApi.action).not.toHaveBeenCalled()
  })

  it('distinguishes an organization read error from not having an organization and only retries on request', async () => {
    vi.mocked(organizationApi.list).mockRejectedValueOnce(new Error('SECRET-ERROR'))
    mount()
    await screen.findByRole('heading', { name: 'No pudimos cargar tu organización.' })
    await act(() => setInterfaceLanguage('en'))
    expect(screen.getByRole('heading', { name: 'We could not load your organization.' })).toBeVisible()
    expect(screen.queryByRole('heading', { name: 'Create your organization first' })).not.toBeInTheDocument()
    expect(organizationApi.list).toHaveBeenCalledOnce()
    await userEvent.click(screen.getByRole('button', { name: 'Retry' }))
    await screen.findByRole('heading', { name: networkOrganization.name })
    expect(organizationApi.list).toHaveBeenCalledTimes(2)
    expect(networkApi.putSettings).not.toHaveBeenCalled()
  })

  it('reports a privacy-settings read failure without suggesting visibility is off or enabling it', async () => {
    vi.mocked(networkApi.settings).mockRejectedValueOnce(new ApiError({ title: 'SECRET-ERROR', status: 503 }, new Response(null, { status: 503 })))
    mount()
    await screen.findByRole('alert')
    await act(() => setInterfaceLanguage('en'))
    expect(screen.getByRole('alert')).toHaveTextContent('The service is unavailable right now. Try again later.')
    expect(screen.queryByRole('button', { name: 'Join the directory and receive requests' })).not.toBeInTheDocument()
    expect(networkApi.settings).toHaveBeenCalledOnce()
    await userEvent.click(screen.getByRole('button', { name: 'Retry' }))
    await screen.findByRole('button', { name: 'Join the directory and receive requests' })
    expect(networkApi.settings).toHaveBeenCalledTimes(2)
    expect(networkApi.putSettings).not.toHaveBeenCalled()
  })
})
