import { HttpClient } from '@/api/http-client'
import { setAuthenticatedSession } from '@/features/auth/auth-session'

const createSession = (accessToken: string, publicId: string) => ({
  status: 'authenticated' as const,
  accessToken,
  accessTokenExpiresAtUtc: '2026-08-21T17:00:00Z',
  user: {
    publicId,
    email: `${publicId}@example.com`,
    displayName: publicId,
    preferredLocale: 'es-CL',
    roles: ['User'],
    mfaEnabled: false,
  },
})

describe('HttpClient', () => {
  afterEach(() => {
    vi.unstubAllGlobals()
  })

  it('normaliza application/problem+json como ApiError', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(
        new Response(
          JSON.stringify({
            title: 'Datos inválidos',
            status: 422,
            detail: 'Revisa los campos enviados',
            traceId: 'trace-123',
          }),
          {
            status: 422,
            headers: { 'content-type': 'application/problem+json' },
          },
        ),
      ),
    )

    const client = new HttpClient('/api/v1')
    const request = client.post('/organizations', { name: '' })

    await expect(request).rejects.toMatchObject({
      name: 'ApiError',
      problem: {
        title: 'Datos inválidos',
        status: 422,
        traceId: 'trace-123',
      },
    })
  })

  it('never retries a request from one session under a newer session', async () => {
    setAuthenticatedSession(createSession('user-a-token', 'user-a'))
    let finishRefresh: ((response: Response) => void) | undefined
    const pendingRefresh = new Promise<Response>((resolve) => {
      finishRefresh = resolve
    })
    const fetchMock = vi.fn()
      .mockResolvedValueOnce(new Response(null, { status: 401 }))
      .mockReturnValueOnce(pendingRefresh)
    vi.stubGlobal('fetch', fetchMock)

    const client = new HttpClient('/api/v1')
    const request = client.get('/organizations')
    await vi.waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(2))

    setAuthenticatedSession(createSession('user-b-token', 'user-b'))
    finishRefresh?.(new Response(null, { status: 401 }))

    await expect(request).rejects.toMatchObject({
      name: 'ApiError',
      response: { status: 401 },
    })
    expect(fetchMock).toHaveBeenCalledTimes(2)
    expect(fetchMock.mock.calls[0]?.[1]?.headers).toEqual(
      expect.objectContaining({}),
    )
    expect(new Headers(fetchMock.mock.calls[0]?.[1]?.headers).get('Authorization'))
      .toBe('Bearer user-a-token')
  })

  it('downloads a private blob with JWT refresh and no-store semantics', async () => {
    setAuthenticatedSession(createSession('expired-token', 'user-a'))
    const refreshed = createSession('fresh-token', 'user-a')
    const fetchMock = vi.fn()
      .mockResolvedValueOnce(new Response(null, { status: 401 }))
      .mockResolvedValueOnce(new Response(JSON.stringify(refreshed), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      }))
      .mockResolvedValueOnce(new Response('private-image', {
        status: 200,
        headers: { 'Content-Type': 'image/png' },
      }))
    vi.stubGlobal('fetch', fetchMock)

    const result = await new HttpClient('/api/v1').getBlob('/private/content')

    expect(result.contentType).toBe('image/png')
    expect(fetchMock).toHaveBeenCalledTimes(3)
    const firstHeaders = new Headers(fetchMock.mock.calls[0]?.[1]?.headers)
    const retriedHeaders = new Headers(fetchMock.mock.calls[2]?.[1]?.headers)
    expect(firstHeaders.get('Authorization')).toBe('Bearer expired-token')
    expect(firstHeaders.get('Accept')).toBe('*/*')
    expect(retriedHeaders.get('Authorization')).toBe('Bearer fresh-token')
    expect(fetchMock.mock.calls[2]?.[1]?.cache).toBe('no-store')
    expect(fetchMock.mock.calls[2]?.[1]?.credentials).toBe('include')
  })
})
