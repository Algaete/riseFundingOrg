import AxeBuilder from '@axe-core/playwright'
import { expect, test, type Page } from '@playwright/test'
import { registerWorkspaceLanguageTests } from './workspace-checks'
import { registerDashboardAccountLanguageTests } from './dashboard-account-checks'
import { registerDiscoveryLanguageTests } from './discovery-checks'
import { registerOrganizationFundingLanguageTests } from './organization-funding-checks'
import { registerMatchingNetworkLanguageTests } from './matching-network-checks'
import { registerTrackingBillingTests } from './tracking-billing-checks'
import { registerCatalogTests } from './catalog-checks'

const unexpectedApiRequests = new WeakMap<Page, string[]>()

async function useGuestSession(page: Page) {
  const unexpectedRequests: string[] = []
  unexpectedApiRequests.set(page, unexpectedRequests)
  await page.route('**/api/v1/**', async (route) => {
    unexpectedRequests.push(new URL(route.request().url()).pathname)
    await route.abort('blockedbyclient')
  })
  await page.route('**/api/v1/auth/refresh', async (route) => {
    await route.fulfill({
      status: 401,
      contentType: 'application/problem+json',
      body: JSON.stringify({ title: 'Unauthorized', status: 401 }),
    })
  })
  await page.route('**/api/v1/auth/external/providers', async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: '[]',
    })
  })
  await page.route('**/api/v1/funding-opportunities?*', async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        items: [
          {
            publicId: 'f5b75d2c-4c84-4ca3-91f7-e9c182fdff2c',
            slug: 'oportunidad-e2e',
            title: 'Oportunidad pública E2E',
            summary: 'Convocatoria sintética para verificar el frontend.',
            sponsorName: 'Fundación de prueba',
            currency: 'USD',
            minimumAmount: 10_000,
            maximumAmount: 50_000,
            openDate: null,
            closeDate: null,
            sourceName: 'Fuente sintética E2E',
            sourceUrl: null,
            publishedAtUtc: '2026-09-01T00:00:00Z',
            dataQualityScore: 100,
          },
        ],
        totalCount: 1,
        pageNumber: 1,
        pageSize: 12,
      }),
    })
  })
}

async function expectNoSeriousAccessibilityViolations(page: Page) {
  // Theme changes animate colors. Audit the settled UI, not a transient mix
  // of the previous foreground and the new background.
  await page.evaluate(async () => {
    const finiteAnimations = document.getAnimations().filter(animation =>
      animation.effect?.getComputedTiming().iterations !== Infinity,
    )
    await Promise.all(finiteAnimations.map(animation => animation.finished.catch(() => undefined)))
  })
  const result = await new AxeBuilder({ page })
    .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa'])
    .analyze()

  expect(result.violations).toEqual([])
}

test.beforeEach(async ({ page }) => {
  await useGuestSession(page)
})

test.afterEach(async ({ page }) => {
  expect(unexpectedApiRequests.get(page) ?? []).toEqual([])
})

registerWorkspaceLanguageTests(expectNoSeriousAccessibilityViolations)
registerDashboardAccountLanguageTests(expectNoSeriousAccessibilityViolations)
registerDiscoveryLanguageTests(expectNoSeriousAccessibilityViolations)
registerOrganizationFundingLanguageTests(expectNoSeriousAccessibilityViolations)
registerMatchingNetworkLanguageTests(expectNoSeriousAccessibilityViolations)
registerTrackingBillingTests(expectNoSeriousAccessibilityViolations)
registerCatalogTests(expectNoSeriousAccessibilityViolations)

test('publica el inicio y permite navegar al acceso', async ({ page }) => {
  const response = await page.goto('/')

  expect(response?.ok()).toBe(true)
  await expect(
    page.getByRole('heading', {
      level: 1,
      name: 'Conecta tu proyecto con el financiamiento y los aliados que necesita',
    }),
  ).toBeVisible()

  await expect(page.getByRole('link', { name: 'Encontrar financiamiento' })).toHaveAttribute('href', '/funding')
  await expect(page.getByRole('link', { name: 'Publicar mi proyecto' })).toHaveAttribute('href', '/register')

  await page.getByRole('link', { name: 'Ingresar' }).click()

  await expect(page).toHaveURL(/\/login$/)
  await expect(page.getByText('Bienvenido de vuelta')).toBeVisible()
  await expect(page.getByLabel('Correo electrónico')).toBeVisible()
  await expect(page.getByLabel('Contraseña')).toBeVisible()
})

test('protege una ruta privada y conserva el fallback SPA', async ({ page }) => {
  const response = await page.goto('/dashboard')

  expect(response?.ok()).toBe(true)
  await expect(page).toHaveURL(/\/login$/)
  await expect(page.getByText('Bienvenido de vuelta')).toBeVisible()

  await page.goto('/admin')
  await expect(page).toHaveURL(/\/login$/)
})

test('renderiza directamente el catálogo público y envía su búsqueda', async ({ page }) => {
  const requestedQueries: string[] = []
  await page.route('**/api/v1/funding-opportunities?*', async (route) => {
    const requestUrl = new URL(route.request().url())
    requestedQueries.push(requestUrl.searchParams.get('query') ?? '')
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        items: [],
        totalCount: 0,
        pageNumber: 1,
        pageSize: 12,
      }),
    })
  })

  const response = await page.goto('/funding')
  expect(response?.ok()).toBe(true)
  await expect(page.getByRole('heading', { level: 1, name: 'Oportunidades de financiamiento' })).toBeVisible()
  await expect(page.getByText('No encontramos oportunidades')).toBeVisible()

  await page.getByLabel('Buscar oportunidades').fill('agua segura')
  await page.getByRole('button', { name: 'Buscar' }).click()

  await expect.poll(() => requestedQueries).toContain('agua segura')
})

test('valida el formulario sin enviar credenciales', async ({ page }) => {
  await page.goto('/login')
  await page.getByRole('button', { name: 'Ingresar' }).click()

  await expect(page.getByRole('alert', { name: '' }).filter({ hasText: 'Ingresa tu correo' })).toBeVisible()
  await expect(page.getByText('Ingresa tu contraseña')).toBeVisible()
})

test('ofrece acceso usable en la navegación móvil', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 })
  await page.goto('/')

  await page.getByRole('link', { name: 'Ingresar' }).click()
  await expect(page).toHaveURL(/\/login$/)
  await expect(page.getByLabel('Correo electrónico')).toBeVisible()
})

for (const width of [320, 390, 768, 1024, 1440]) {
  test(`conserva el idioma y permite usar la cabecera a ${width}px`, async ({ page }) => {
    await page.setViewportSize({ width, height: 844 })
    await page.goto('/')
    const selector = page.getByRole('combobox', { name: 'Idioma', exact: true })
    await expect(selector).toBeVisible()
    await selector.selectOption('en')

    await expect(page.getByRole('heading', { level: 1, name: 'Connect your project with the funding and partners it needs' })).toBeVisible()
    await expect(page.locator('html')).toHaveAttribute('lang', 'en')
    await expect(page.getByRole('combobox', { name: 'Change theme' })).toBeVisible()
    await expect(page.getByRole('link', { name: 'Sign in', exact: true })).toBeInViewport()
    const fits = await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)
    expect(fits).toBe(true)
    await expectNoSeriousAccessibilityViolations(page)

    // Full reload exercises the persisted preference, not just React's in-memory state.
    await page.reload()
    await expect(page.getByRole('combobox', { name: 'Language', exact: true })).toHaveValue('en')
    await expect(page.locator('html')).toHaveAttribute('lang', 'en')
    await page.getByRole('link', { name: 'Sign in', exact: true }).click()
    await expect(page).toHaveURL(/\/login$/)
    await expect(page.getByRole('combobox', { name: 'Language', exact: true })).toHaveValue('en')
    await expect(page.getByRole('main')).not.toHaveAttribute('lang', 'es')
    await expect(page.getByRole('heading', { name: 'Welcome back' })).toBeVisible()

    await page.getByRole('combobox', { name: 'Language', exact: true }).selectOption('es')
    await expect(page.getByRole('combobox', { name: 'Cambiar tema' })).toBeVisible()
    await expect(page.locator('html')).toHaveAttribute('lang', 'es')
  })
}

for (const roles of [['Professional'], ['Admin']]) {
  for (const width of [320, 640, 768, 1024, 1440]) {
    test(`mantiene la cabecera usable con sesión simulada ${roles[0]} a ${width}px`, async ({ page }) => {
      await page.route('**/api/v1/auth/refresh', route => route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          status: 'authenticated',
          accessToken: 'synthetic-ui-test-not-a-credential',
          accessTokenExpiresAtUtc: new Date(Date.now() + 600_000).toISOString(),
          user: {
            publicId: '11111111-1111-1111-1111-111111111111',
            email: 'interface@example.invalid', displayName: 'Organización de prueba',
            preferredLocale: 'es-CL', roles, mfaEnabled: true,
          },
        }),
      }))
      await page.setViewportSize({ width, height: 844 })
      await page.goto('/account')
      await page.getByRole('combobox', { name: 'Idioma', exact: true }).selectOption('en')
      await expect(page.getByRole('combobox', { name: 'Language', exact: true })).toBeInViewport()
      await expect(page.getByRole('button', { name: 'Sign out', exact: true })).toBeInViewport()
      const fits = await page.locator('header').evaluate(header => header.scrollWidth <= header.clientWidth)
      expect(fits).toBe(true)
      // Mi cuenta is bilingual since I18N-04A and now inherits the selected language.
      await expect(page.locator('html')).toHaveAttribute('lang', 'en')
      await expect(page.getByRole('main')).not.toHaveAttribute('lang', 'es')
      await expect(page.getByRole('heading', { name: 'My account', exact: true })).toBeVisible()
      // An admin entry point must remain available on mobile without exposing it to members.
      const mobileAdminLink = page.getByRole('navigation', { name: 'Mobile navigation' }).getByRole('link', { name: 'Administration', exact: true })
      if (roles.includes('Admin') && width < 640) await expect(mobileAdminLink).toBeVisible()
      else await expect(mobileAdminLink).toHaveCount(0)
      if (roles.includes('Admin') && width >= 640) {
        await expect(page.getByRole('link', { name: 'Go to the admin panel', exact: true })).toBeInViewport()
      }
    })
  }
}

test('cumple accesibilidad automatizada básica en inicio, acceso y registro', async ({ page }) => {
  await page.goto('/')
  await expect(page.getByRole('heading', { level: 1 })).toBeVisible()
  await expectNoSeriousAccessibilityViolations(page)

  await page.goto('/login')
  await expect(page.getByText('Bienvenido de vuelta')).toBeVisible()
  await expectNoSeriousAccessibilityViolations(page)

  await page.goto('/register')
  await expect(page.getByRole('heading', { level: 2, name: 'Crea tu cuenta' })).toBeVisible()
  await expectNoSeriousAccessibilityViolations(page)

  await page.goto('/funding')
  await expect(page.getByRole('heading', { level: 1, name: 'Oportunidades de financiamiento' })).toBeVisible()
  await expectNoSeriousAccessibilityViolations(page)
})

for (const [path, spanishTitle, englishTitle] of [
  ['/login', 'Bienvenido de vuelta', 'Welcome back'],
  ['/register', 'Crea tu cuenta', 'Create your account'],
  ['/forgot-password', 'Recupera tu contraseña', 'Recover your password'],
  ['/reset-password?token=synthetic-token', 'Define una nueva contraseña', 'Set a new password'],
  ['/verify-email?token=synthetic-token', 'Verifica tu correo', 'Verify your email'],
  ['/mfa', 'Verificación en dos pasos', 'Two-step verification'],
  ['/mfa/setup', 'Protege tu cuenta administrativa', 'Protect your admin account'],
  ['/auth/external/callback', 'Acceso con Microsoft', 'Sign in with Microsoft'],
] as const) {
  test(`traduce ${path} y conserva accesibilidad a 320px`, async ({ page }) => {
    await page.setViewportSize({ width: 320, height: 844 })
    await page.goto(path)
    await expect(page.getByRole('heading', { name: spanishTitle, exact: true })).toBeVisible()
    await page.getByRole('combobox', { name: 'Idioma', exact: true }).selectOption('en')
    await expect(page.getByRole('heading', { name: englishTitle, exact: true })).toBeVisible()
    await expect(page.getByRole('main')).not.toHaveAttribute('lang', 'es')
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true)
    await expectNoSeriousAccessibilityViolations(page)
    await page.getByRole('combobox', { name: 'Change theme', exact: true }).selectOption('dark')
    await expectNoSeriousAccessibilityViolations(page)
  })
}

test('traduce errores visibles sin perder lo escrito ni enviar credenciales', async ({ page }) => {
  await page.goto('/login')
  await page.getByLabel('Correo electrónico').fill('incomplete@')
  await page.getByRole('button', { name: 'Ingresar', exact: true }).click()
  await expect(page.getByText('Ingresa un correo válido')).toBeVisible()
  await page.getByRole('combobox', { name: 'Idioma', exact: true }).selectOption('en')
  await expect(page.getByLabel('Email address')).toHaveValue('incomplete@')
  await expect(page.getByLabel('Email address')).toHaveAccessibleDescription('Enter a valid email')
  await expect(page.getByLabel('Password', { exact: true })).toHaveAccessibleDescription('Enter your password')
  await expectNoSeriousAccessibilityViolations(page)
})

test('muestra el error de acceso traducido con una respuesta sintética', async ({ page }) => {
  await page.route('**/api/v1/auth/login', route => route.fulfill({
    status: 401, contentType: 'application/problem+json',
    body: JSON.stringify({ status: 401, type: 'https://fundingplatform.local/problems/invalid-credentials', title: 'El correo o la contraseña no son válidos.' }),
  }))
  await page.goto('/login')
  await page.getByRole('combobox', { name: 'Idioma', exact: true }).selectOption('en')
  await page.getByLabel('Email address').fill('synthetic@example.invalid')
  await page.getByLabel('Password', { exact: true }).fill('Synthetic-test-only')
  await page.getByRole('button', { name: 'Sign in', exact: true }).click()
  await expect(page.getByRole('alert')).toHaveText('The email or password is invalid.')
  await page.getByRole('combobox', { name: 'Language', exact: true }).selectOption('es')
  await expect(page.getByRole('alert')).toHaveText('El correo o la contraseña no son válidos.')
  await expectNoSeriousAccessibilityViolations(page)
  await page.getByRole('combobox', { name: 'Cambiar tema', exact: true }).selectOption('dark')
  await expectNoSeriousAccessibilityViolations(page)
})

test('conserva un QR MFA sintético y su configuración al cambiar de idioma', async ({ page }) => {
  let setupRequests = 0
  await page.route('**/api/v1/auth/login', route => route.fulfill({
    status: 202, contentType: 'application/json',
    body: JSON.stringify({ status: 'mfa_setup_required', mfaSetupToken: 'synthetic-limited-token' }),
  }))
  await page.route('**/api/v1/me/mfa/setup', route => {
    setupRequests += 1
    return route.fulfill({
      status: 200, contentType: 'application/json',
      body: JSON.stringify({ sharedKey: 'JBSWY3DPEHPK3PXP', authenticatorUri: 'otpauth://totp/Synthetic:test@example.invalid?secret=JBSWY3DPEHPK3PXP&issuer=Synthetic' }),
    })
  })
  await page.setViewportSize({ width: 320, height: 844 })
  await page.goto('/login')
  await page.getByLabel('Correo electrónico').fill('synthetic@example.invalid')
  await page.getByLabel('Contraseña', { exact: true }).fill('Synthetic-test-only')
  await page.getByRole('button', { name: 'Ingresar', exact: true }).click()
  await expect(page).toHaveURL(/\/mfa\/setup$/)
  const qr = page.getByRole('img', { name: 'Código QR para configurar MFA' })
  await expect(qr).toBeVisible()
  const paths = await qr.locator('path').evaluateAll(nodes => nodes.map(node => node.getAttribute('d')))
  await page.getByLabel('Código de 6 dígitos').fill('123456')
  await page.getByRole('combobox', { name: 'Idioma', exact: true }).selectOption('en')
  const translatedQr = page.getByRole('img', { name: 'QR code to set up MFA' })
  await expect(translatedQr).toBeVisible()
  expect(await translatedQr.locator('path').evaluateAll(nodes => nodes.map(node => node.getAttribute('d')))).toEqual(paths)
  await expect(page.getByLabel('6-digit code')).toHaveValue('123456')
  expect(setupRequests).toBe(1)
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true)
  await expectNoSeriousAccessibilityViolations(page)
  await page.getByRole('combobox', { name: 'Change theme', exact: true }).selectOption('dark')
  await expectNoSeriousAccessibilityViolations(page)
})

test('expone la revisión aprobada cuando Azure entrega metadatos', async ({ request }) => {
  const expectedReleaseSha = process.env.E2E_EXPECTED_RELEASE_SHA
  test.skip(!expectedReleaseSha, 'Solo aplica a la publicación inmutable de Azure.')

  expect(expectedReleaseSha).toMatch(/^[0-9a-f]{40}$/)
  const response = await request.get('/deploy-meta.json')
  expect(response.ok()).toBe(true)
  const metadata = (await response.json()) as { commitSha?: string }
  expect(metadata.commitSha).toBe(expectedReleaseSha)
})
