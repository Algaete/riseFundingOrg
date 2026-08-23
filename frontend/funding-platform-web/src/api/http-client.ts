import type { ProblemDetails } from '@/types/problem-details'
import { getApiBaseUrl } from '@/api/api-config'
import {
  getAccessToken,
  getAuthState,
  refreshAuthSession,
} from '@/features/auth/auth-session'

type JsonObject = Record<string, unknown>

export interface ApiRequestOptions
  extends Omit<RequestInit, 'body' | 'headers'> {
  body?: unknown
  headers?: HeadersInit
}

export class ApiError extends Error {
  readonly problem: ProblemDetails
  readonly response: Response

  constructor(problem: ProblemDetails, response: Response) {
    super(problem.detail ?? problem.title)
    this.name = 'ApiError'
    this.problem = problem
    this.response = response
  }
}

function isRecord(value: unknown): value is JsonObject {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}

function isNativeBody(value: unknown): value is BodyInit {
  return (
    typeof value === 'string' ||
    value instanceof Blob ||
    value instanceof FormData ||
    value instanceof URLSearchParams ||
    value instanceof ArrayBuffer
  )
}

function serializeBody(body: unknown, headers: Headers): BodyInit | null | undefined {
  if (body === undefined || body === null) return body
  if (isNativeBody(body)) return body

  if (!headers.has('Content-Type')) {
    headers.set('Content-Type', 'application/json')
  }
  return JSON.stringify(body)
}

async function toProblemDetails(response: Response): Promise<ProblemDetails> {
  const fallback: ProblemDetails = {
    title: response.statusText || 'No fue posible completar la solicitud',
    status: response.status,
  }

  try {
    const value: unknown = await response.json()
    if (!isRecord(value)) return fallback

    return {
      ...fallback,
      ...value,
      title: typeof value.title === 'string' ? value.title : fallback.title,
      status: typeof value.status === 'number' ? value.status : response.status,
    }
  } catch {
    return fallback
  }
}

export class HttpClient {
  private readonly baseUrl: string

  constructor(baseUrl = getApiBaseUrl()) {
    this.baseUrl = baseUrl
  }

  async request<T>(path: string, options: ApiRequestOptions = {}): Promise<T> {
    const headers = new Headers(options.headers)
    if (!headers.has('Accept')) headers.set('Accept', 'application/json')
    const sessionAtStart = getAuthState().session
    const accessToken = getAccessToken()
    if (accessToken && !headers.has('Authorization')) {
      headers.set('Authorization', `Bearer ${accessToken}`)
    }

    const body = serializeBody(options.body, headers)
    const requestUrl =
      this.baseUrl.replace(/\/$/, '') + '/' + path.replace(/^\//, '')
    const send = () =>
      fetch(requestUrl, {
        ...options,
        headers,
        credentials: options.credentials ?? 'include',
        body,
      })

    let response = await send()
    const canRefresh = response.status === 401 &&
      sessionAtStart !== null &&
      getAuthState().session === sessionAtStart &&
      !path.replace(/^\//, '').startsWith('auth/')
    const refreshedSession = canRefresh
      ? await refreshAuthSession()
      : null
    if (
      refreshedSession &&
      getAuthState().session === refreshedSession
    ) {
      headers.set('Authorization', `Bearer ${refreshedSession.accessToken}`)
      response = await send()
    }

    if (!response.ok) {
      throw new ApiError(await toProblemDetails(response), response)
    }

    if (response.status === 204) return undefined as T

    const contentType = response.headers.get('content-type') ?? ''
    if (contentType.includes('json')) return (await response.json()) as T
    return (await response.text()) as T
  }

  get<T>(path: string, options?: ApiRequestOptions) {
    return this.request<T>(path, { ...options, method: 'GET' })
  }

  post<T>(path: string, body?: unknown, options?: ApiRequestOptions) {
    return this.request<T>(path, { ...options, method: 'POST', body })
  }

  put<T>(path: string, body?: unknown, options?: ApiRequestOptions) {
    return this.request<T>(path, { ...options, method: 'PUT', body })
  }

  delete<T>(path: string, options?: ApiRequestOptions) {
    return this.request<T>(path, { ...options, method: 'DELETE' })
  }
}

export const apiClient = new HttpClient()
