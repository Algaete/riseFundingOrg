import { describe, expect, it } from 'vitest'

import {
  classifyAuthenticatedE2ERequest,
  isRedirectResponseStatus,
  parseExactOriginAllowlist,
  resolveAuthenticatedE2EConfig,
  type AuthenticatedE2EEnvironment,
} from '../../e2e/authenticated-config'

const releaseSha = '0123456789abcdef0123456789abcdef01234567'
const remoteEnvironment: AuthenticatedE2EEnvironment = {
  E2E_ALLOWED_API_ORIGINS: 'https://api.dev.example.org',
  E2E_ALLOWED_ORIGINS: 'https://app.dev.example.org',
  E2E_COOKIE_SITE: 'example.org',
  E2E_EXPECTED_RELEASE_SHA: releaseSha,
  E2E_REQUIRE_AUTHENTICATED: 'true',
  E2E_USER_EMAIL: 'browser-test@example.org',
  E2E_USER_PASSWORD: 'ephemeral-password',
  PLAYWRIGHT_BASE_URL: 'https://app.dev.example.org',
}

describe('resolveAuthenticatedE2EConfig', () => {
  it('permanece deshabilitada salvo opt-in exacto', () => {
    expect(resolveAuthenticatedE2EConfig({})).toEqual({ enabled: false })
    expect(resolveAuthenticatedE2EConfig({
      ...remoteEnvironment,
      E2E_REQUIRE_AUTHENTICATED: 'false',
    })).toEqual({ enabled: false })
    expect(() => resolveAuthenticatedE2EConfig({
      ...remoteEnvironment,
      E2E_REQUIRE_AUTHENTICATED: 'TRUE',
    })).toThrow(/sólo acepta los valores exactos true o false/)
  })

  it.each([
    'PLAYWRIGHT_BASE_URL',
    'E2E_ALLOWED_ORIGINS',
    'E2E_ALLOWED_API_ORIGINS',
    'E2E_USER_EMAIL',
    'E2E_USER_PASSWORD',
    'E2E_EXPECTED_RELEASE_SHA',
    'E2E_COOKIE_SITE',
  ])('falla cerrado si falta %s', (missingVariable) => {
    expect(() => resolveAuthenticatedE2EConfig({
      ...remoteEnvironment,
      [missingVariable]: undefined,
    })).toThrow(missingVariable)
  })

  it('resuelve una ejecución remota canónica y same-site', () => {
    expect(resolveAuthenticatedE2EConfig(remoteEnvironment)).toEqual({
      enabled: true,
      apiOrigin: 'https://api.dev.example.org',
      cookieSite: 'example.org',
      email: 'browser-test@example.org',
      expectedReleaseSha: releaseSha,
      frontendOrigin: 'https://app.dev.example.org',
      password: 'ephemeral-password',
    })
  })

  it('permite HTTP sólo para una ejecución local explícita', () => {
    expect(resolveAuthenticatedE2EConfig({
      E2E_ALLOWED_API_ORIGINS: 'http://127.0.0.1:5070',
      E2E_ALLOWED_ORIGINS: 'http://127.0.0.1:5173',
      E2E_REQUIRE_AUTHENTICATED: 'true',
      E2E_USER_EMAIL: 'browser-test@example.org',
      E2E_USER_PASSWORD: 'ephemeral-password',
      PLAYWRIGHT_BASE_URL: 'http://127.0.0.1:5173',
    })).toMatchObject({
      enabled: true,
      apiOrigin: 'http://127.0.0.1:5070',
      frontendOrigin: 'http://127.0.0.1:5173',
    })
  })

  it.each([
    ['una ruta', { PLAYWRIGHT_BASE_URL: 'https://app.dev.example.org/login' }],
    ['una barra final', { E2E_ALLOWED_API_ORIGINS: 'https://api.dev.example.org/' }],
    ['credenciales URL', { PLAYWRIGHT_BASE_URL: 'https://user@app.dev.example.org' }],
    ['HTTP remoto', { E2E_ALLOWED_API_ORIGINS: 'http://api.dev.example.org' }],
    ['un SHA abreviado', { E2E_EXPECTED_RELEASE_SHA: '0123456' }],
  ])('rechaza %s en la configuración de destinos', (_caseName, override) => {
    expect(() => resolveAuthenticatedE2EConfig({
      ...remoteEnvironment,
      ...override,
    })).toThrow()
  })

  it('rechaza allowlists ampliadas, vacías o duplicadas', () => {
    expect(() => resolveAuthenticatedE2EConfig({
      ...remoteEnvironment,
      E2E_ALLOWED_ORIGINS:
        'https://app.dev.example.org,https://other.dev.example.org',
    })).toThrow(/únicamente el origen exacto/)
    expect(() => parseExactOriginAllowlist(
      'ALLOWLIST',
      'https://api.dev.example.org,',
    )).toThrow(/entrada vacía/)
    expect(() => parseExactOriginAllowlist(
      'ALLOWLIST',
      'https://api.dev.example.org, https://api.dev.example.org',
    )).toThrow(/duplicados/)
  })

  it('rechaza orígenes que no comparten el sitio de cookie aprobado', () => {
    expect(() => resolveAuthenticatedE2EConfig({
      ...remoteEnvironment,
      E2E_ALLOWED_API_ORIGINS: 'https://api.other.example',
    })).toThrow(/deben pertenecer al E2E_COOKIE_SITE/)
  })

  it.each(['co.uk', 'github.io', 'azurestaticapps.net', 'dev.example.org'])(
    'rechaza %s como sitio registrable compartido',
    (cookieSite) => {
      expect(() => resolveAuthenticatedE2EConfig({
        ...remoteEnvironment,
        E2E_COOKIE_SITE: cookieSite,
      })).toThrow(/dominio registrable/)
    },
  )

  it('rechaza distintos sitios privados aunque compartan un sufijo DNS', () => {
    expect(() => resolveAuthenticatedE2EConfig({
      ...remoteEnvironment,
      E2E_COOKIE_SITE: 'amazonaws.com',
      PLAYWRIGHT_BASE_URL: 'https://first.s3.amazonaws.com',
      E2E_ALLOWED_ORIGINS: 'https://first.s3.amazonaws.com',
      E2E_ALLOWED_API_ORIGINS: 'https://second.s3.amazonaws.com',
    })).toThrow(/deben pertenecer al E2E_COOKIE_SITE/)
  })

  it('acepta un dominio registrable con sufijo público de varias etiquetas', () => {
    expect(resolveAuthenticatedE2EConfig({
      ...remoteEnvironment,
      E2E_COOKIE_SITE: 'example.co.uk',
      PLAYWRIGHT_BASE_URL: 'https://app.example.co.uk',
      E2E_ALLOWED_ORIGINS: 'https://app.example.co.uk',
      E2E_ALLOWED_API_ORIGINS: 'https://api.example.co.uk',
    })).toMatchObject({ enabled: true, cookieSite: 'example.co.uk' })
  })

  it('no incorpora el contenido de secretos a sus errores', () => {
    const secret = 'do-not-print-this-secret\n'
    let error: unknown
    try {
      resolveAuthenticatedE2EConfig({
        ...remoteEnvironment,
        E2E_USER_PASSWORD: secret,
      })
    } catch (caught) {
      error = caught
    }

    expect(error).toBeInstanceOf(Error)
    expect((error as Error).message).not.toContain(secret.trim())
  })
})

describe('classifyAuthenticatedE2ERequest', () => {
  const policy = {
    apiOrigin: 'https://api.dev.example.org',
    frontendOrigin: 'https://app.dev.example.org',
  }

  it.each([
    ['GET', 'https://app.dev.example.org/account', 'frontend-read'],
    ['HEAD', 'https://app.dev.example.org/deploy-meta.json', 'frontend-read'],
    ['GET', 'https://api.dev.example.org/api/v1/organizations', 'api-read'],
    ['OPTIONS', 'https://api.dev.example.org/api/v1/auth/login', 'api-preflight'],
    ['POST', 'https://api.dev.example.org/api/v1/auth/login', 'login'],
    ['POST', 'https://api.dev.example.org/api/v1/auth/refresh', 'refresh'],
    ['POST', 'https://api.dev.example.org/api/v1/auth/logout', 'logout'],
  ])('permite %s sólo para %s como %s', (method, url, expectedKind) => {
    expect(classifyAuthenticatedE2ERequest(policy, url, method)).toBe(expectedKind)
  })

  it.each([
    ['POST', 'https://evil.example/api/v1/auth/login'],
    ['GET', 'https://cdn.example/app.js'],
    ['POST', 'https://api.dev.example.org/api/v1/organizations'],
    ['PUT', 'https://api.dev.example.org/api/v1/auth/login'],
    ['POST', 'https://api.dev.example.org/api/v1/auth/logout-all'],
    ['POST', 'https://api.dev.example.org/api/v1/auth/login?redirect=elsewhere'],
    ['GET', 'https://api.dev.example.org/health'],
  ])('bloquea %s hacia %s', (method, url) => {
    expect(classifyAuthenticatedE2ERequest(policy, url, method)).toBeNull()
  })
})

describe('isRedirectResponseStatus', () => {
  it.each([300, 301, 302, 303, 305, 306, 307, 308, 399])(
    'bloquea el status de redirección %i',
    (status) => {
      expect(isRedirectResponseStatus(status)).toBe(true)
    },
  )

  it.each([200, 204, 299, 304, 400, 500])(
    'no confunde el status %i con una redirección',
    (status) => {
      expect(isRedirectResponseStatus(status)).toBe(false)
    },
  )
})
