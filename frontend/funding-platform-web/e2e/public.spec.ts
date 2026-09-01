import AxeBuilder from '@axe-core/playwright'
import { expect, test, type Page } from '@playwright/test'

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

test('publica el inicio y permite navegar al acceso', async ({ page }) => {
  const response = await page.goto('/')

  expect(response?.ok()).toBe(true)
  await expect(
    page.getByRole('heading', {
      level: 1,
      name: 'Encuentra el fondo correcto para tu próxima iniciativa',
    }),
  ).toBeVisible()

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

test('cumple accesibilidad automatizada básica en inicio y acceso', async ({ page }) => {
  await page.goto('/')
  await expect(page.getByRole('heading', { level: 1 })).toBeVisible()
  await expectNoSeriousAccessibilityViolations(page)

  await page.goto('/login')
  await expect(page.getByText('Bienvenido de vuelta')).toBeVisible()
  await expectNoSeriousAccessibilityViolations(page)

  await page.goto('/funding')
  await expect(page.getByRole('heading', { level: 1, name: 'Oportunidades de financiamiento' })).toBeVisible()
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
