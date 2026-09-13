import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { act, fireEvent, render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'

import { setAuthenticatedSession } from '@/features/auth/auth-session'
import { ProjectAssetsPanel } from '@/features/projects/project-assets-panel'
import type { ProjectAsset, ProjectAssetCollection } from '@/features/projects/project-assets-api'
import { setInterfaceLanguage } from '@/i18n'
import { projectAssetPollingIntervalMs, projectAssetPollingWindowMs } from './use-project-asset-polling'

const organizationId = '51ea2f6f-b1af-4e09-856c-6dcbdcfc812f'
const projectId = 'bd351806-9139-4524-bc01-93c3676729cb'

function json(value: unknown, status = 200) {
  return Promise.resolve(new Response(JSON.stringify(value), {
    status,
    headers: { 'Content-Type': 'application/json' },
  }))
}

function collection(items: ProjectAsset[], projectETag = '"0102030405060708"'): ProjectAssetCollection {
  return { projectId, publicationStatus: 0, projectETag, items }
}

function asset(overrides: Partial<ProjectAsset> = {}): ProjectAsset {
  return {
    assetId: 'cccccccc-cccc-cccc-cccc-cccccccccccc',
    kind: 0,
    fileName: 'river.png',
    displayName: 'Río comunitario',
    mimeType: 'image/png',
    contentLength: 1200,
    pixelWidth: 1200,
    pixelHeight: 800,
    storageStatus: 1,
    scanStatus: 0,
    scanProvider: 1,
    scanResultCode: 'pending',
    sortOrder: 0,
    isCover: false,
    altText: null,
    caption: null,
    isReady: false,
    contentUrl: null,
    createdAtUtc: '2026-09-08T12:00:00Z',
    updatedAtUtc: '2026-09-08T12:00:00Z',
    eTag: '"1112131415161718"',
    ...overrides,
  }
}

function renderPanel(overrides: Partial<React.ComponentProps<typeof ProjectAssetsPanel>> = {}) {
  const onProjectChanged = vi.fn().mockResolvedValue(undefined)
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
  })
  const view = render(
    <QueryClientProvider client={queryClient}>
      <ProjectAssetsPanel
        hasUnsavedChanges={false}
        onProjectChanged={onProjectChanged}
        organizationId={organizationId}
        projectETag="&quot;0001020304050607&quot;"
        projectId={projectId}
        publicationStatus={0}
        {...overrides}
      />
    </QueryClientProvider>,
  )
  return { onProjectChanged, queryClient, ...view }
}

describe('panel de adjuntos del proyecto', () => {
  beforeEach(() => {
    vi.stubEnv('VITE_PROJECT_ASSETS_ENABLED', 'true')
    setAuthenticatedSession({
      status: 'authenticated',
      accessToken: 'project-asset-token',
      accessTokenExpiresAtUtc: '2099-09-08T18:00:00Z',
      user: {
        publicId: '89b8d22a-472c-42e4-b034-c772ce3bb08e',
        email: 'member@example.test',
        displayName: 'Miembro',
        preferredLocale: 'es-CL',
        roles: ['Professional'],
        mfaEnabled: false,
      },
    })
  })

  afterEach(() => {
    vi.useRealTimers()
    vi.unstubAllEnvs()
    vi.unstubAllGlobals()
    vi.restoreAllMocks()
  })

  it('detiene consultas al ocultarse y al vencer el plazo; Actualizar estado solo vuelve a leer', async () => {
    vi.useFakeTimers()
    const visibility = vi.spyOn(document, 'visibilityState', 'get')
    const fetchMock = vi.fn().mockImplementation(() => json(collection([asset()])))
    vi.stubGlobal('fetch', fetchMock)
    const { unmount, queryClient } = renderPanel()
    await act(async () => { await vi.advanceTimersByTimeAsync(1) })
    expect(fetchMock).toHaveBeenCalledOnce()
    await act(async () => { await vi.advanceTimersByTimeAsync(projectAssetPollingIntervalMs) })
    expect(fetchMock).toHaveBeenCalledTimes(2)
    visibility.mockReturnValue('hidden')
    act(() => document.dispatchEvent(new Event('visibilitychange')))
    await act(async () => { await vi.advanceTimersByTimeAsync(projectAssetPollingWindowMs) })
    expect(fetchMock).toHaveBeenCalledTimes(2)
    visibility.mockReturnValue('visible')
    act(() => {
      document.dispatchEvent(new Event('visibilitychange'))
      window.dispatchEvent(new Event('focus'))
      window.dispatchEvent(new Event('online'))
    })
    await act(async () => { await vi.advanceTimersByTimeAsync(projectAssetPollingIntervalMs) })
    expect(fetchMock).toHaveBeenCalledTimes(2)
    expect(screen.getByRole('status')).toHaveTextContent('La actualización automática está pausada')
    fireEvent.click(screen.getByRole('button', { name: 'Actualizar estado' }))
    await act(async () => { await vi.advanceTimersByTimeAsync(1) })
    expect(fetchMock).toHaveBeenCalledTimes(3)
    expect(screen.queryByRole('status')).not.toBeInTheDocument()
    for (const [, options] of fetchMock.mock.calls) expect(options?.method ?? 'GET').toBe('GET')
    unmount()
    queryClient.clear()
  })

  it('un resultado tardío de un intento no reinicia consultas ni expone contenido después de pausar', async () => {
    vi.useFakeTimers()
    let resolveIntent!: (response: Response) => void
    let reads = 0
    const fetchMock = vi.fn((input: string | URL | Request, init?: RequestInit) => {
      const url = String(input)
      if (url.endsWith('/assets')) { reads++; return json(collection([])) }
      if (url.endsWith('/asset-upload-intents') && init?.method === 'POST') return json({
        intentId: 'synthetic-intent', projectETag: '"0000000000000002"',
        uploadUrl: 'https://synthetic.example.invalid/upload', uploadMethod: 'PUT',
        requiredHeaders: {}, completionToken: 'synthetic-only',
      })
      if (url === 'https://synthetic.example.invalid/upload') return Promise.resolve(new Response(null, { status: 201 }))
      if (url.endsWith('/synthetic-intent/complete')) return json({ storageStatus: 1, scanStatus: 0, intentStatus: 2 })
      if (url.endsWith('/synthetic-intent')) return new Promise<Response>(resolve => { resolveIntent = resolve })
      throw new Error('Unexpected fixture request')
    })
    vi.stubGlobal('fetch', fetchMock)
    const { unmount, queryClient } = renderPanel()
    await act(async () => { await vi.advanceTimersByTimeAsync(1) })
    fireEvent.change(screen.getByLabelText('Seleccionar fotos, videos o documentos'), {
      target: { files: [new File(['synthetic'], 'informe.txt', { type: 'text/plain' })] },
    })
    fireEvent.click(screen.getByRole('button', { name: 'Cargar y verificar archivo' }))
    await act(async () => { await vi.advanceTimersByTimeAsync(1) })
    await act(async () => { await vi.advanceTimersByTimeAsync(projectAssetPollingIntervalMs) })
    expect(resolveIntent).toBeTypeOf('function')
    await act(async () => { await vi.advanceTimersByTimeAsync(projectAssetPollingWindowMs) })
    const readsAtPause = reads
    await act(async () => { resolveIntent(await json({ status: 2, storageStatus: 2, scanStatus: 1 })) })
    await act(async () => { await vi.advanceTimersByTimeAsync(projectAssetPollingWindowMs) })
    expect(reads).toBe(readsAtPause)
    expect(screen.getByRole('status')).toHaveTextContent('actualización automática está pausada')
    expect(document.querySelector('img, video, iframe')).not.toBeInTheDocument()
    expect(screen.queryByText('synthetic-only')).not.toBeInTheDocument()
    unmount()
    queryClient.clear()
  })

  it('traduce estados sin perder metadatos, abrir una vista insegura ni confirmar una eliminación', async () => {
    const fetchMock = vi.fn().mockImplementation(() => json(collection([asset()])))
    vi.stubGlobal('fetch', fetchMock)
    renderPanel()
    const name = await screen.findByLabelText('Nombre visible')
    fireEvent.change(name, { target: { value: 'Río Ñandú actualizado' } })
    await act(() => setInterfaceLanguage('en'))
    expect(screen.getByLabelText('Display name')).toHaveValue('Río Ñandú actualizado')
    expect(screen.getByText('Quarantined and being scanned')).toBeVisible()
    expect(screen.getByRole('checkbox', { name: /Use as cover/ })).toBeDisabled()
    expect(document.querySelector('img')).not.toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'Delete' }))
    await act(() => setInterfaceLanguage('es'))
    expect(screen.getByRole('alertdialog')).toHaveAccessibleName('¿Eliminar Río comunitario?')
    expect(screen.getByLabelText('Nombre visible')).toHaveValue('Río Ñandú actualizado')
    expect(fetchMock).toHaveBeenCalledOnce()
  })

  it('traduce un error de tamaño ya visible sin volver a validar ni cargar el archivo', async () => {
    const fetchMock = vi.fn().mockImplementation(() => json(collection([])))
    vi.stubGlobal('fetch', fetchMock)
    renderPanel()
    await waitFor(() => expect(screen.getByLabelText('Seleccionar fotos, videos o documentos')).toBeEnabled())
    const file = new File(['synthetic'], 'imagen-grande.png', { type: 'image/png' })
    Object.defineProperty(file, 'size', { value: 11 * 1024 * 1024 })
    await userEvent.upload(screen.getByLabelText('Seleccionar fotos, videos o documentos'), file)
    expect(await screen.findByRole('alert')).toHaveTextContent('imagen-grande.png debe pesar entre 1 byte y')
    await act(() => setInterfaceLanguage('en'))
    expect(screen.getByRole('alert')).toHaveTextContent('imagen-grande.png must be between 1 byte and 10 MB.')
    expect(screen.getByRole('button', { name: 'Upload and verify file' })).toBeDisabled()
    expect(fetchMock).toHaveBeenCalledOnce()
  })

  it('no reinicia una carga pendiente al cambiar de idioma y traduce el resultado posterior', async () => {
    let resolveIntent!: (response: Response) => void
    const intent = new Promise<Response>(resolve => { resolveIntent = resolve })
    let intentRequests = 0
    let transfers = 0
    const fetchMock = vi.fn((input: string | URL | Request, init?: RequestInit) => {
      const url = String(input)
      if (url.endsWith('/assets')) return json(collection([]))
      if (url.endsWith('/asset-upload-intents')) { intentRequests += 1; return intent }
      if (url === 'https://synthetic.example.invalid/upload') { transfers += 1; expect(init?.credentials).toBe('omit'); return Promise.resolve(new Response(null, { status: 201 })) }
      if (url.endsWith('/asset-upload-intents/synthetic-intent/complete')) return json({ projectETag: '"0000000000000002"', storageStatus: 2, scanStatus: 1, intentStatus: 2 })
      throw new Error(`Unexpected request: ${url}`)
    })
    vi.stubGlobal('fetch', fetchMock)
    renderPanel()
    await waitFor(() => expect(screen.getByLabelText('Seleccionar fotos, videos o documentos')).toBeEnabled())
    await userEvent.upload(screen.getByLabelText('Seleccionar fotos, videos o documentos'), new File(['synthetic'], 'Río.png', { type: 'image/png' }))
    await userEvent.click(screen.getByRole('button', { name: 'Cargar y verificar archivo' }))
    expect(await screen.findByText('Solicitando una autorización de corta duración.')).toBeVisible()
    await act(() => setInterfaceLanguage('en'))
    expect(screen.getByText('Requesting short-lived authorization.')).toBeVisible()
    expect(intentRequests).toBe(1)
    resolveIntent(await json({ intentId: 'synthetic-intent', projectETag: '"0000000000000002"', uploadUrl: 'https://synthetic.example.invalid/upload', uploadMethod: 'PUT', requiredHeaders: {}, completionToken: 'synthetic-only' }))
    expect(await screen.findByText('The file passed the security checks and is available.')).toBeVisible()
    expect(intentRequests).toBe(1)
    expect(transfers).toBe(1)
    expect(screen.queryByText('synthetic-only')).not.toBeInTheDocument()
  })

  it.each([
    ['evidencia.mp4', 'video/mp4', 2],
    ['informe.txt', 'text/plain', 1],
  ] as const)('solicita %s con su tipo y no lo reproduce automáticamente', async (name, mime, kind) => {
    const commands: Record<string, unknown>[] = []
    vi.stubGlobal('fetch', vi.fn((input: string | URL | Request, init?: RequestInit) => {
      const url = String(input)
      if (url.endsWith('/assets')) return json(collection([]))
      if (url.endsWith('/asset-upload-intents')) {
        commands.push(JSON.parse(String(init?.body)) as Record<string, unknown>)
        return json({ intentId: 'synthetic-intent', projectETag: '"0000000000000002"', uploadUrl: 'https://synthetic.example.invalid/upload', uploadMethod: 'PUT', requiredHeaders: {}, completionToken: 'synthetic-only' })
      }
      if (url === 'https://synthetic.example.invalid/upload') return Promise.resolve(new Response(null, { status: 201 }))
      if (url.endsWith('/synthetic-intent/complete')) return json({ projectETag: '"0000000000000003"', storageStatus: 1, scanStatus: 0, intentStatus: 2 })
      throw new Error(`Unexpected request: ${url}`)
    }))
    renderPanel()
    const input = screen.getByLabelText('Seleccionar fotos, videos o documentos')
    await waitFor(() => expect(input).toBeEnabled())
    await userEvent.upload(input, new File(['synthetic'], name, { type: mime }))
    await userEvent.click(screen.getByRole('button', { name: 'Cargar y verificar archivo' }))
    await waitFor(() => expect(commands).toHaveLength(1))
    expect(commands[0]).toMatchObject({ kind, fileName: name, mimeType: mime })
    expect(document.querySelector('video, iframe, object, embed')).not.toBeInTheDocument()
    expect(screen.getByText(/conservan el contenido y los metadatos originales/)).toBeVisible()
  })

  it('limita TXT a 1 MB sin crear una autorización ni cargar bytes', async () => {
    const fetchMock = vi.fn().mockImplementation(() => json(collection([])))
    vi.stubGlobal('fetch', fetchMock)
    renderPanel()
    const input = screen.getByLabelText('Seleccionar fotos, videos o documentos')
    await waitFor(() => expect(input).toBeEnabled())
    const file = new File(['synthetic'], 'informe.txt', { type: 'text/plain' })
    Object.defineProperty(file, 'size', { value: 1_048_577 })
    await userEvent.upload(input, file)
    expect(await screen.findByRole('alert')).toHaveTextContent('1 MB')
    expect(screen.getByRole('button', { name: 'Cargar y verificar archivo' })).toBeDisabled()
    expect(fetchMock).toHaveBeenCalledOnce()
  })

  it('permanece ausente y no consulta la API cuando la bandera está apagada', async () => {
    vi.stubEnv('VITE_PROJECT_ASSETS_ENABLED', 'false')
    const fetchMock = vi.fn()
    vi.stubGlobal('fetch', fetchMock)

    renderPanel()

    expect(screen.queryByRole('heading', { name: 'Fotos, videos y documentos' })).not.toBeInTheDocument()
    expect(fetchMock).not.toHaveBeenCalled()
  })

  it('bloquea mutaciones con cambios sin guardar y nunca previsualiza un archivo pendiente', async () => {
    const fetchMock = vi.fn().mockImplementation(() => json(collection([asset()])))
    vi.stubGlobal('fetch', fetchMock)

    renderPanel({ hasUnsavedChanges: true })

    expect(await screen.findByRole('heading', { name: 'Fotos, videos y documentos' })).toBeInTheDocument()
    expect(await screen.findByText('Sin vista previa hasta completar el análisis')).toBeInTheDocument()
    expect(document.querySelector('img')).not.toBeInTheDocument()
    expect(screen.getByLabelText('Seleccionar fotos, videos o documentos')).toBeDisabled()
    expect(screen.getByRole('button', { name: /Cargar y verificar/ })).toBeDisabled()
    expect(screen.getByText(/MP4 privado, sin reproducción pública/)).toBeInTheDocument()
    expect(fetchMock).toHaveBeenCalledTimes(1)
  })

  it('carga de forma secuencial, mantiene el secreto sólo en memoria y muestra fases reales', async () => {
    let assetListRequests = 0
    const createHeaders: Headers[] = []
    const completionBodies: Record<string, unknown>[] = []
    const fetchMock = vi.fn((input: string | URL | Request, init?: RequestInit) => {
      const url = String(input)
      if (url.endsWith(`/organizations/${organizationId}/projects/${projectId}/assets`) && init?.method === 'GET') {
        assetListRequests += 1
        return json(collection([], assetListRequests === 1 ? '"0102030405060708"' : '"3132333435363738"'))
      }
      if (url.endsWith(`/organizations/${organizationId}/projects/${projectId}/asset-upload-intents`)) {
        createHeaders.push(new Headers(init?.headers))
        return json({
          intentId: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
          kind: 0,
          status: 0,
          expiresAtUtc: '2026-09-08T12:05:00Z',
          maxContentLength: 10 * 1024 * 1024,
          uploadMethod: 'PUT',
          uploadUrl: 'https://testing.blob.core.windows.net/project-incoming/photo.png?sig=secret',
          requiredHeaders: {
            'x-ms-blob-type': 'BlockBlob',
            'Content-Type': 'image/png',
            'If-None-Match': '*',
          },
          completionToken: 'one-time-project-secret',
          statusUrl: 'private-status-url',
          eTag: '"1112131415161718"',
          projectETag: '"2122232425262728"',
          securityNotice: 'server validates again',
        }, 201)
      }
      if (url.startsWith('https://testing.blob.core.windows.net/')) {
        return Promise.resolve(new Response(null, { status: 201 }))
      }
      if (url.endsWith('/asset-upload-intents/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb/complete')) {
        completionBodies.push(JSON.parse(String(init?.body)) as Record<string, unknown>)
        return json({
          code: 'ready',
          intentId: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
          intentStatus: 2,
          assetId: 'cccccccc-cccc-cccc-cccc-cccccccccccc',
          storageStatus: 2,
          scanStatus: 1,
          scanProvider: 0,
          intentETag: '"2223242526272829"',
          assetETag: '"2324252627282930"',
          projectETag: '"3132333435363738"',
          wasReplay: false,
        })
      }
      throw new Error(`Unexpected request: ${url}`)
    })
    vi.stubGlobal('fetch', fetchMock)

    const user = userEvent.setup()
    const { onProjectChanged, queryClient } = renderPanel()
    const input = await screen.findByLabelText('Seleccionar fotos, videos o documentos')
    await vi.waitFor(() => expect(input).toBeEnabled())
    await user.upload(input, new File(['png'], 'photo.png', { type: 'image/png' }))
    await user.click(screen.getByRole('button', { name: 'Cargar y verificar archivo' }))

    await vi.waitFor(() => expect(createHeaders).toHaveLength(1))
    await vi.waitFor(() => expect(completionBodies).toHaveLength(1))
    await vi.waitFor(() => expect(onProjectChanged).toHaveBeenCalled())
    await vi.waitFor(() => expect(queryClient.isMutating()).toBe(0))
    expect(screen.getByText(/photo\.png.*Listo/, { selector: 'span' })).toBeInTheDocument()
    expect(createHeaders[0]?.get('If-Match')).toBe('"0102030405060708"')
    expect(completionBodies[0]).toEqual({ completionToken: 'one-time-project-secret' })
    const directCall = fetchMock.mock.calls.find(([url]) => String(url).startsWith('https://testing.blob.core.windows.net/'))
    expect(directCall?.[1]).toMatchObject({ credentials: 'omit', cache: 'no-store', redirect: 'error', referrerPolicy: 'no-referrer' })
    expect(sessionStorage.length).toBe(0)
    expect(localStorage.length).toBe(0)
    expect(assetListRequests).toBeGreaterThanOrEqual(2)
    expect(onProjectChanged).toHaveBeenCalled()
  })

  it('sólo permite una portada lista con texto alternativo y usa contenido autenticado', async () => {
    const readyImage = asset({
      storageStatus: 2,
      scanStatus: 1,
      scanResultCode: 'clean',
      isReady: true,
      contentUrl: `/api/v1/organizations/${organizationId}/projects/${projectId}/assets/cccccccc-cccc-cccc-cccc-cccccccccccc/content`,
    })
    const metadataRequests: { headers: Headers; body: Record<string, unknown> }[] = []
    const fetchMock = vi.fn((input: string | URL | Request, init?: RequestInit) => {
      const url = String(input)
      if (url.endsWith(`/organizations/${organizationId}/projects/${projectId}/assets`) && init?.method === 'GET') {
        return json(collection([readyImage]))
      }
      if (url.endsWith('/assets/cccccccc-cccc-cccc-cccc-cccccccccccc/content')) {
        return Promise.resolve(new Response('image', { status: 200, headers: { 'Content-Type': 'image/png' } }))
      }
      if (url.endsWith('/assets/cccccccc-cccc-cccc-cccc-cccccccccccc') && init?.method === 'PATCH') {
        metadataRequests.push({
          headers: new Headers(init.headers),
          body: JSON.parse(String(init.body)) as Record<string, unknown>,
        })
        return json({
          code: 'updated',
          assetId: readyImage.assetId,
          assetETag: '"4142434445464748"',
          projectETag: '"5152535455565758"',
          wasReplay: false,
        })
      }
      throw new Error(`Unexpected request: ${url}`)
    })
    vi.stubGlobal('fetch', fetchMock)
    vi.stubGlobal('URL', {
      ...URL,
      createObjectURL: vi.fn(() => 'blob:private-preview'),
      revokeObjectURL: vi.fn(),
    })

    const user = userEvent.setup()
    renderPanel()

    const cover = await screen.findByRole('checkbox', { name: /Usar como portada/ })
    await user.click(cover)
    await user.click(screen.getByRole('button', { name: 'Guardar datos' }))
    expect(await screen.findByText('La portada necesita texto alternativo.')).toBeInTheDocument()
    expect(metadataRequests).toHaveLength(0)

    await user.type(screen.getByLabelText(/Texto alternativo/), 'Personas trabajando junto al río')
    await user.click(screen.getByRole('button', { name: 'Guardar datos' }))

    await vi.waitFor(() => expect(metadataRequests).toHaveLength(1))
    expect(metadataRequests[0]?.headers.get('If-Match')).toBe(readyImage.eTag)
    expect(metadataRequests[0]?.headers.get('X-Project-If-Match')).toBe('"0102030405060708"')
    expect(metadataRequests[0]?.body).toMatchObject({
      altText: 'Personas trabajando junto al río',
      isCover: true,
    })
    const contentCall = fetchMock.mock.calls.find(([url]) => String(url).endsWith('/content'))
    expect(new Headers(contentCall?.[1]?.headers).get('Authorization')).toBe('Bearer project-asset-token')
  })

  it('pide confirmación explícita antes de eliminar', async () => {
    vi.stubGlobal('fetch', vi.fn().mockImplementation(() => json(collection([asset()]))))
    const user = userEvent.setup()
    renderPanel()

    await user.click(await screen.findByRole('button', { name: 'Eliminar' }))
    expect(screen.getByRole('alertdialog', { name: /Eliminar Río comunitario/ })).toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: 'Cancelar' }))
    expect(screen.queryByRole('alertdialog')).not.toBeInTheDocument()
  })
})
