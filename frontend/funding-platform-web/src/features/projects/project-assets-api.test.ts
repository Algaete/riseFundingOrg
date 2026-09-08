import { setAuthenticatedSession } from '@/features/auth/auth-session'
import {
  ProjectAssetDirectUploadError,
  projectAssetApi,
  type ProjectAssetUploadIntentCreated,
  uploadProjectAssetDirectly,
} from '@/features/projects/project-assets-api'

const organizationId = '51ea2f6f-b1af-4e09-856c-6dcbdcfc812f'
const projectId = 'bd351806-9139-4524-bc01-93c3676729cb'

const grant: ProjectAssetUploadIntentCreated = {
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
  statusUrl: `/api/v1/organizations/${organizationId}/projects/${projectId}/asset-upload-intents/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb`,
  eTag: '"0102030405060708"',
  projectETag: '"1112131415161718"',
  securityNotice: 'server validates again',
}

describe('API de adjuntos de proyecto', () => {
  beforeEach(() => {
    setAuthenticatedSession({
      status: 'authenticated',
      accessToken: 'project-asset-token',
      accessTokenExpiresAtUtc: '2099-09-08T18:00:00Z',
      user: {
        publicId: '89b8d22a-472c-42e4-b034-c772ce3bb08e',
        email: 'admin@example.test',
        displayName: 'Administradora',
        preferredLocale: 'es-CL',
        roles: ['Professional'],
        mfaEnabled: false,
      },
    })
    sessionStorage.clear()
    localStorage.clear()
  })

  afterEach(() => {
    sessionStorage.clear()
    localStorage.clear()
    vi.restoreAllMocks()
    vi.unstubAllGlobals()
  })

  it('transfiere directo con exactamente los headers concedidos y sin credenciales', async () => {
    const fetchMock = vi.fn().mockResolvedValue(new Response(null, { status: 201 }))
    vi.stubGlobal('fetch', fetchMock)
    const file = new File(['png'], 'photo.png', { type: 'image/png' })

    await uploadProjectAssetDirectly(grant, file)

    const [url, options] = fetchMock.mock.calls[0] as [string, RequestInit]
    const headers = options.headers as Headers
    expect(url).toBe(grant.uploadUrl)
    expect(options).toMatchObject({
      method: 'PUT',
      body: file,
      credentials: 'omit',
      cache: 'no-store',
      redirect: 'error',
      referrerPolicy: 'no-referrer',
    })
    expect(headers.get('x-ms-blob-type')).toBe('BlockBlob')
    expect(headers.get('Content-Type')).toBe('image/png')
    expect(headers.get('If-None-Match')).toBe('*')
    expect(headers.has('Authorization')).toBe(false)
    expect([...headers.keys()]).toHaveLength(3)
    expect(sessionStorage).toHaveLength(0)
    expect(localStorage).toHaveLength(0)
  })

  it('no refleja el cuerpo ni la URL SAS cuando Azure rechaza la transferencia', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(new Response(
      `${grant.uploadUrl}&diagnostic=private`,
      { status: 403 },
    )))

    await expect(uploadProjectAssetDirectly(
      grant,
      new File(['png'], 'photo.png', { type: 'image/png' }),
    )).rejects.toEqual(new ProjectAssetDirectUploadError(403))
  })

  it('envía ETags separados para metadatos, orden y borrado sin persistir secretos', async () => {
    const fetchMock = vi.fn().mockImplementation(() => Promise.resolve(new Response(JSON.stringify({
      code: 'updated',
      assetId: 'cccccccc-cccc-cccc-cccc-cccccccccccc',
      assetETag: '"2122232425262728"',
      projectETag: '"3132333435363738"',
      wasReplay: false,
    }), { status: 200, headers: { 'Content-Type': 'application/json' } })))
    vi.stubGlobal('fetch', fetchMock)

    await projectAssetApi.updateMetadata(
      organizationId,
      projectId,
      'cccccccc-cccc-cccc-cccc-cccccccccccc',
      '"asset-version"',
      '"project-version"',
      { displayName: 'Portada', altText: 'Comunidad junto al río', caption: null, isCover: true },
    )
    await projectAssetApi.reorder(
      organizationId,
      projectId,
      '"project-order-version"',
      [{ assetId: 'cccccccc-cccc-cccc-cccc-cccccccccccc', eTag: '"asset-order-version"' }],
    )
    await projectAssetApi.delete(
      organizationId,
      projectId,
      'cccccccc-cccc-cccc-cccc-cccccccccccc',
      '"asset-delete-version"',
      '"project-delete-version"',
    )

    const [url, options] = fetchMock.mock.calls[0] as [string, RequestInit]
    const headers = new Headers(options.headers)
    expect(url).toBe(`/api/v1/organizations/${organizationId}/projects/${projectId}/assets/cccccccc-cccc-cccc-cccc-cccccccccccc`)
    expect(options.method).toBe('PATCH')
    expect(headers.get('If-Match')).toBe('"asset-version"')
    expect(headers.get('X-Project-If-Match')).toBe('"project-version"')
    expect(JSON.parse(String(options.body))).toEqual({
      displayName: 'Portada',
      altText: 'Comunidad junto al río',
      caption: null,
      isCover: true,
    })
    const [orderUrl, orderOptions] = fetchMock.mock.calls[1] as [string, RequestInit]
    expect(orderUrl).toBe(`/api/v1/organizations/${organizationId}/projects/${projectId}/assets/order`)
    expect(orderOptions.method).toBe('PUT')
    expect(new Headers(orderOptions.headers).get('If-Match')).toBe('"project-order-version"')
    expect(JSON.parse(String(orderOptions.body))).toEqual({
      items: [{ assetId: 'cccccccc-cccc-cccc-cccc-cccccccccccc', eTag: '"asset-order-version"' }],
    })
    const [deleteUrl, deleteOptions] = fetchMock.mock.calls[2] as [string, RequestInit]
    const deleteHeaders = new Headers(deleteOptions.headers)
    expect(deleteUrl).toBe(`/api/v1/organizations/${organizationId}/projects/${projectId}/assets/cccccccc-cccc-cccc-cccc-cccccccccccc`)
    expect(deleteOptions.method).toBe('DELETE')
    expect(deleteHeaders.get('If-Match')).toBe('"asset-delete-version"')
    expect(deleteHeaders.get('X-Project-If-Match')).toBe('"project-delete-version"')
    expect(sessionStorage).toHaveLength(0)
    expect(localStorage).toHaveLength(0)
  })

  it('obtiene contenido privado como blob mediante el cliente autenticado', async () => {
    const fetchMock = vi.fn().mockResolvedValue(new Response('pdf', {
      status: 200,
      headers: { 'Content-Type': 'application/pdf' },
    }))
    vi.stubGlobal('fetch', fetchMock)

    const result = await projectAssetApi.getContent(
      organizationId,
      projectId,
      'cccccccc-cccc-cccc-cccc-cccccccccccc',
    )

    expect(result.contentType).toBe('application/pdf')
    const [url, options] = fetchMock.mock.calls[0] as [string, RequestInit]
    const headers = new Headers(options.headers)
    expect(url).toContain(`/organizations/${organizationId}/projects/${projectId}/assets/cccccccc-cccc-cccc-cccc-cccccccccccc/content`)
    expect(headers.get('Authorization')).toBe('Bearer project-asset-token')
    expect(options.cache).toBe('no-store')
  })
})
