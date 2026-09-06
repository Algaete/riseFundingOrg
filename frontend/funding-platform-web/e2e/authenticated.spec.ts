import {
  expect,
  test,
  type APIRequestContext,
  type BrowserContext,
  type Page,
  type Response,
} from '@playwright/test'

import {
  classifyAuthenticatedE2ERequest,
  isRedirectResponseStatus,
  resolveAuthenticatedE2EConfig,
  type AuthenticatedE2ERequestKind,
  type EnabledAuthenticatedE2EConfig,
} from './authenticated-config'

const resolvedConfig = resolveAuthenticatedE2EConfig(process.env)
const authenticatedConfig = resolvedConfig.enabled ? resolvedConfig : null

test.use({
  screenshot: 'off',
  serviceWorkers: 'block',
  trace: 'off',
  video: 'off',
})
test.describe.configure({ mode: 'serial', retries: 0 })

interface TrafficAudit {
  blockedRequests: number
  loginRequests: number
  logoutRequests: number
  refreshRequests: number
}

type TrafficCounter = 'loginRequests' | 'logoutRequests' | 'refreshRequests'

function authResponseMatches(
  response: Response,
  config: EnabledAuthenticatedE2EConfig,
  expectedKind: 'login' | 'logout' | 'refresh',
) {
  return classifyAuthenticatedE2ERequest(
    config,
    response.url(),
    response.request().method(),
  ) === expectedKind
}

async function expectApprovedPath(
  page: Page,
  config: EnabledAuthenticatedE2EConfig,
  approvedPath: (pathname: string) => boolean,
  timeout = 5_000,
) {
  await expect.poll(() => {
    try {
      const location = new URL(page.url())
      return location.origin === config.frontendOrigin &&
        approvedPath(location.pathname)
    } catch {
      return false
    }
  }, { timeout }).toBe(true)
}

async function verifyApprovedRelease(
  request: APIRequestContext,
  config: EnabledAuthenticatedE2EConfig,
) {
  if (!config.expectedReleaseSha) return

  const metadataUrl = `${config.frontendOrigin}/deploy-meta.json`
  const response = await request.get(metadataUrl, {
    failOnStatusCode: false,
    headers: { Accept: 'application/json' },
    maxRedirects: 0,
  })
  expect(response.url()).toBe(metadataUrl)
  expect(response.status()).toBe(200)
  expect(response.headers()['content-type'] ?? '').toContain('application/json')

  const metadata = (await response.json()) as { commitSha?: unknown }
  expect(metadata.commitSha).toBe(config.expectedReleaseSha)
  await response.dispose()
}

async function enforceNetworkPolicy(
  context: BrowserContext,
  config: EnabledAuthenticatedE2EConfig,
) {
  const audit: TrafficAudit = {
    blockedRequests: 0,
    loginRequests: 0,
    logoutRequests: 0,
    refreshRequests: 0,
  }

  await context.addInitScript(() => {
    const browserFetch = globalThis.fetch.bind(globalThis)
    globalThis.fetch = (input, init) => browserFetch(input, {
      ...init,
      redirect: 'error',
    })
  })

  context.on('response', (response) => {
    const kind = classifyAuthenticatedE2ERequest(
      config,
      response.url(),
      response.request().method(),
    )
    if (kind && isRedirectResponseStatus(response.status())) {
      audit.blockedRequests += 1
    }
  })

  await context.routeWebSocket(/.*/, async (webSocket) => {
    audit.blockedRequests += 1
    try {
      await webSocket.close({ code: 1008, reason: 'Blocked by E2E policy' })
    } catch {
      // The page may have closed the blocked socket first.
    }
  })

  await context.route('**/*', async (route) => {
    const browserRequest = route.request()
    const kind = classifyAuthenticatedE2ERequest(
      config,
      browserRequest.url(),
      browserRequest.method(),
    )
    if (!kind) {
      audit.blockedRequests += 1
      await route.abort('blockedbyclient')
      return
    }

    const counterByKind: Partial<Record<AuthenticatedE2ERequestKind, TrafficCounter>> = {
      login: 'loginRequests',
      logout: 'logoutRequests',
      refresh: 'refreshRequests',
    }
    const counter = counterByKind[kind]
    if (counter) audit[counter] += 1
    await route.continue()
  })

  return audit
}

function expectNoBlockedTraffic(audit: TrafficAudit) {
  expect(audit.blockedRequests).toBe(0)
}

async function verifyRefreshCookie(context: BrowserContext, config: EnabledAuthenticatedE2EConfig) {
  const cookies = (await context.cookies()).filter((cookie) =>
    cookie.name === '__Secure-fp_refresh')
  // Compare only metadata: an assertion failure must never print a cookie value.
  expect(cookies.length).toBe(1)
  const cookie = cookies[0]
  expect({
    domain: cookie.domain,
    httpOnly: cookie.httpOnly,
    path: cookie.path,
    sameSite: cookie.sameSite,
    secure: cookie.secure,
  }).toEqual({
    domain: new URL(config.apiOrigin).hostname,
    httpOnly: true,
    path: '/api/v1/auth',
    sameSite: 'Lax',
    secure: true,
  })
}

test.describe('sesión autenticada efímera', () => {
  test.skip(
    authenticatedConfig === null,
    'Requiere E2E_REQUIRE_AUTHENTICATED=true y configuración explícita.',
  )

  test('valida login, refresh tras recarga, logout y guard', async ({
    context,
    page,
    request,
  }) => {
    test.setTimeout(120_000)
    if (!authenticatedConfig) {
      throw new Error('La suite autenticada no fue habilitada explícitamente.')
    }

    const config = authenticatedConfig
    let loginSucceeded = false
    let logoutSucceeded = false

    try {
      await test.step('verificar el release antes de abrir el formulario', async () => {
        await verifyApprovedRelease(request, config)
      })

      const audit = await enforceNetworkPolicy(context, config)

      await test.step('iniciar sesión sólo contra el origen aprobado', async () => {
        const initialRefresh = page.waitForResponse((response) =>
          authResponseMatches(response, config, 'refresh'))
        const navigation = await page.goto('/login', { waitUntil: 'domcontentloaded' })
        expect(navigation?.ok()).toBe(true)
        expect((await initialRefresh).status()).toBe(401)

        await expectApprovedPath(page, config, (pathname) => pathname === '/login')
        await expect(page.getByLabel('Correo electrónico')).toBeVisible()
        await expect(page.getByLabel('Contraseña')).toBeVisible()
        expectNoBlockedTraffic(audit)

        const loginResponse = page.waitForResponse((response) =>
          authResponseMatches(response, config, 'login'))
        await page.getByLabel('Correo electrónico').fill(config.email)
        await page.getByLabel('Contraseña').fill(config.password)
        await page.getByRole('button', { name: 'Ingresar' }).click()

        const response = await loginResponse
        expect(response.status()).toBe(200)
        loginSucceeded = true
        await verifyRefreshCookie(context, config)
        await expectApprovedPath(
          page,
          config,
          (pathname) => pathname === '/dashboard' || pathname === '/onboarding',
          20_000,
        )
        await expect(page.getByRole('button', { name: 'Cerrar sesión' })).toBeVisible()
        expect(audit.loginRequests).toBe(1)
        expectNoBlockedTraffic(audit)
      })

      await test.step('recargar y recuperar la sesión mediante refresh cookie', async () => {
        const refreshesBeforeReload = audit.refreshRequests
        const refreshResponse = page.waitForResponse((response) =>
          authResponseMatches(response, config, 'refresh'))

        await page.reload({ waitUntil: 'domcontentloaded' })

        expect((await refreshResponse).status()).toBe(200)
        await verifyRefreshCookie(context, config)
        await expectApprovedPath(
          page,
          config,
          (pathname) => pathname === '/dashboard' || pathname === '/onboarding',
        )
        await expect(page.getByRole('button', { name: 'Cerrar sesión' })).toBeVisible()
        expect(audit.refreshRequests).toBeGreaterThan(refreshesBeforeReload)
        expectNoBlockedTraffic(audit)
      })

      await test.step('cerrar la sesión y confirmar el guard en una recarga directa', async () => {
        const logoutResponse = page.waitForResponse((response) =>
          authResponseMatches(response, config, 'logout'))
        await page.getByRole('button', { name: 'Cerrar sesión' }).click()

        expect((await logoutResponse).status()).toBe(204)
        logoutSucceeded = true
        expect((await context.cookies()).filter((cookie) =>
          cookie.name === '__Secure-fp_refresh').length).toBe(0)
        await expectApprovedPath(page, config, (pathname) => pathname === '/login')
        expect(audit.logoutRequests).toBe(1)

        const refreshResponse = page.waitForResponse((response) =>
          authResponseMatches(response, config, 'refresh'))
        await page.goto('/account', { waitUntil: 'domcontentloaded' })

        expect((await refreshResponse).status()).toBe(401)
        await expectApprovedPath(page, config, (pathname) => pathname === '/login')
        await expect(page.getByText('Bienvenido de vuelta')).toBeVisible()
        expectNoBlockedTraffic(audit)
      })
    } finally {
      let cleanupFailed = false
      if (loginSucceeded && !logoutSucceeded) {
        try {
          const cleanupResponse = await context.request.post(
            `${config.apiOrigin}/api/v1/auth/logout`,
            {
              failOnStatusCode: false,
              headers: { Origin: config.frontendOrigin },
              maxRedirects: 0,
              timeout: 10_000,
            },
          )
          cleanupFailed = cleanupResponse.status() !== 204
          await cleanupResponse.dispose()
        } catch {
          cleanupFailed = true
        }
      }
      await context.clearCookies()
      expect.soft(
        cleanupFailed,
        'No fue posible confirmar el cleanup de la sesión E2E.',
      ).toBe(false)
    }
  })
})
