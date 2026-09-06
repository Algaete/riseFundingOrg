import { getDomain } from 'tldts'

export type AuthenticatedE2EEnvironment = Readonly<
  Record<string, string | undefined>
>

export interface DisabledAuthenticatedE2EConfig {
  enabled: false
}

export interface EnabledAuthenticatedE2EConfig {
  enabled: true
  apiOrigin: string
  cookieSite?: string
  email: string
  expectedReleaseSha?: string
  frontendOrigin: string
  password: string
}

export type AuthenticatedE2EConfig =
  | DisabledAuthenticatedE2EConfig
  | EnabledAuthenticatedE2EConfig

export type AuthenticatedE2ERequestKind =
  | 'api-read'
  | 'api-preflight'
  | 'frontend-read'
  | 'login'
  | 'logout'
  | 'refresh'

const loopbackHostnames = new Set(['127.0.0.1', '[::1]', 'localhost'])
const authMutationPaths: Readonly<Record<string, AuthenticatedE2ERequestKind>> = {
  '/api/v1/auth/login': 'login',
  '/api/v1/auth/logout': 'logout',
  '/api/v1/auth/refresh': 'refresh',
}

function requiredValue(
  environment: AuthenticatedE2EEnvironment,
  variableName: string,
) {
  const value = environment[variableName]
  if (value === undefined || value.length === 0) {
    throw new Error(`${variableName} es obligatorio cuando E2E_REQUIRE_AUTHENTICATED=true.`)
  }
  return value
}

function parseExactOrigin(variableName: string, value: string) {
  let target: URL
  try {
    target = new URL(value)
  } catch {
    throw new Error(`${variableName} contiene un origen inválido.`)
  }

  const isLoopback = loopbackHostnames.has(target.hostname)
  const validProtocol = target.protocol === 'https:' ||
    (target.protocol === 'http:' && isLoopback)
  if (
    target.username ||
    target.password ||
    target.origin !== value ||
    !validProtocol
  ) {
    throw new Error(
      `${variableName} sólo acepta orígenes canónicos HTTPS exactos; HTTP se permite únicamente en loopback.`,
    )
  }

  return { isLoopback, origin: target.origin, hostname: target.hostname }
}

export function parseExactOriginAllowlist(
  variableName: string,
  rawValue: string,
) {
  const rawEntries = rawValue.split(',')
  if (rawEntries.some((entry) => entry.trim().length === 0)) {
    throw new Error(`${variableName} contiene una entrada vacía.`)
  }

  const origins = rawEntries.map((entry) =>
    parseExactOrigin(variableName, entry.trim()).origin)
  if (new Set(origins).size !== origins.length) {
    throw new Error(`${variableName} contiene orígenes duplicados.`)
  }
  return origins
}

function parseCookieSite(rawValue: string) {
  if (
    rawValue !== rawValue.trim() ||
    rawValue !== rawValue.toLowerCase() ||
    !rawValue.includes('.') ||
    rawValue.length > 253 ||
    !rawValue.split('.').every((label) =>
      /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/.test(label))
  ) {
    throw new Error(
      'E2E_COOKIE_SITE debe ser un sufijo DNS canónico en minúsculas, sin punto inicial ni final.',
    )
  }
  if (getDomain(rawValue, { allowPrivateDomains: true }) !== rawValue) {
    throw new Error(
      'E2E_COOKIE_SITE debe ser un dominio registrable, no un sufijo público ni un subdominio.',
    )
  }
  return rawValue
}

function isHostnameWithinSite(hostname: string, cookieSite: string) {
  return getDomain(hostname, { allowPrivateDomains: true }) === cookieSite
}

function validateCredential(variableName: string, value: string) {
  if (value.includes('\0') || value.includes('\r') || value.includes('\n')) {
    throw new Error(`${variableName} contiene caracteres de control no permitidos.`)
  }
}

export function resolveAuthenticatedE2EConfig(
  environment: AuthenticatedE2EEnvironment,
): AuthenticatedE2EConfig {
  const requirement = environment.E2E_REQUIRE_AUTHENTICATED
  if (requirement === undefined || requirement === '' || requirement === 'false') {
    return { enabled: false }
  }
  if (requirement !== 'true') {
    throw new Error(
      'E2E_REQUIRE_AUTHENTICATED sólo acepta los valores exactos true o false.',
    )
  }

  const configuredBaseUrl = requiredValue(environment, 'PLAYWRIGHT_BASE_URL')
  const target = parseExactOrigin('PLAYWRIGHT_BASE_URL', configuredBaseUrl)
  const frontendOrigins = parseExactOriginAllowlist(
    'E2E_ALLOWED_ORIGINS',
    requiredValue(environment, 'E2E_ALLOWED_ORIGINS'),
  )
  if (frontendOrigins.length !== 1 || frontendOrigins[0] !== target.origin) {
    throw new Error(
      'E2E_ALLOWED_ORIGINS debe contener únicamente el origen exacto de PLAYWRIGHT_BASE_URL.',
    )
  }

  const apiOrigins = parseExactOriginAllowlist(
    'E2E_ALLOWED_API_ORIGINS',
    requiredValue(environment, 'E2E_ALLOWED_API_ORIGINS'),
  )
  if (apiOrigins.length !== 1) {
    throw new Error(
      'E2E_ALLOWED_API_ORIGINS debe contener exactamente un origen de API.',
    )
  }
  const apiTarget = parseExactOrigin('E2E_ALLOWED_API_ORIGINS', apiOrigins[0])

  const email = requiredValue(environment, 'E2E_USER_EMAIL')
  const password = requiredValue(environment, 'E2E_USER_PASSWORD')
  validateCredential('E2E_USER_EMAIL', email)
  validateCredential('E2E_USER_PASSWORD', password)
  if (email !== email.trim() || !/^[^\s@]+@[^\s@]+$/.test(email)) {
    throw new Error('E2E_USER_EMAIL no tiene un formato de correo válido.')
  }
  if (password.length > 128) {
    throw new Error('E2E_USER_PASSWORD supera el máximo admitido por el formulario.')
  }

  const expectedReleaseSha = environment.E2E_EXPECTED_RELEASE_SHA
  if (expectedReleaseSha && !/^[0-9a-f]{40}$/.test(expectedReleaseSha)) {
    throw new Error(
      'E2E_EXPECTED_RELEASE_SHA debe ser un SHA Git completo en minúsculas.',
    )
  }
  if (!target.isLoopback && !expectedReleaseSha) {
    throw new Error(
      'E2E_EXPECTED_RELEASE_SHA es obligatorio para un frontend remoto.',
    )
  }

  let cookieSite: string | undefined
  if (!target.isLoopback) {
    if (apiTarget.isLoopback) {
      throw new Error('Una ejecución remota sólo puede usar una API HTTPS remota.')
    }
    cookieSite = parseCookieSite(requiredValue(environment, 'E2E_COOKIE_SITE'))
    if (
      !isHostnameWithinSite(target.hostname, cookieSite) ||
      !isHostnameWithinSite(apiTarget.hostname, cookieSite)
    ) {
      throw new Error(
        'Los orígenes frontend y API deben pertenecer al E2E_COOKIE_SITE aprobado.',
      )
    }
  }

  return {
    enabled: true,
    apiOrigin: apiTarget.origin,
    cookieSite,
    email,
    expectedReleaseSha,
    frontendOrigin: target.origin,
    password,
  }
}

export function classifyAuthenticatedE2ERequest(
  config: Pick<EnabledAuthenticatedE2EConfig, 'apiOrigin' | 'frontendOrigin'>,
  requestUrl: string,
  requestMethod: string,
): AuthenticatedE2ERequestKind | null {
  let target: URL
  try {
    target = new URL(requestUrl)
  } catch {
    return null
  }

  const method = requestMethod.toUpperCase()
  if (target.username || target.password) return null
  const isApiPath = target.pathname.startsWith('/api/v1/')
  if (target.origin === config.apiOrigin && isApiPath) {
    if (method === 'POST') {
      if (target.search) return null
      return authMutationPaths[target.pathname] ?? null
    }
    if (method === 'GET' || method === 'HEAD') return 'api-read'
    if (method === 'OPTIONS') return 'api-preflight'
    return null
  }

  if (
    target.origin === config.frontendOrigin &&
    (method === 'GET' || method === 'HEAD')
  ) {
    return 'frontend-read'
  }

  return null
}

export function isRedirectResponseStatus(status: number) {
  return status >= 300 && status < 400 && status !== 304
}
