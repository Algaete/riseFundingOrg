import { expect, test, type Page } from '@playwright/test'
import { english, fits } from './workspace-checks'
import { editorialCatalogs } from '../src/test/fixtures/editorial-workspace'

export function registerFundingDiscoveryTests(accessibility: (page: Page) => Promise<void>) {
  for (const width of [320, 1024]) {
    test(`fondos avanzados filtra sin equiparar desconocido con no ES/EN a ${width}px`, async ({ page }) => {
      await page.setViewportSize({ width, height: 900 })
      const requests: URLSearchParams[] = []
      await page.route('**/api/v1/funding-discovery/catalogs', route => route.fulfill({ json: editorialCatalogs }))
      await page.route('**/api/v1/funding-discovery?*', route => {
        expect(route.request().method()).toBe('GET')
        requests.push(new URL(route.request().url()).searchParams)
        return route.fulfill({ json: { items: [{ id: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', slug: 'fondo-sintetico', title: 'Fondo Ñandú', summary: 'Descripción', sourceName: 'Fuente oficial', sourceUrl: 'https://official.example/fund', lastVerifiedAtUtc: null, minimumAmount: null, maximumAmount: null, currency: null, closeDate: null, classification: null }], totalCount: 1, page: 1, pageSize: 20 } })
      })
      await page.goto('/funding/explore')
      await expect(page.getByRole('heading', { name: 'Fondo Ñandú' })).toBeVisible()
      await expect(page.getByText('Requiere consorcio: No informado', { exact: true })).toBeVisible()
      await page.getByRole('combobox', { name: 'Tipo de financiador principal', exact: true }).selectOption('3')
      await page.getByRole('combobox', { name: 'Requiere consorcio', exact: true }).selectOption('false')
      await page.getByLabel('Monto mínimo', { exact: true }).fill('100')
      await page.getByRole('button', { name: 'Buscar fondos', exact: true }).click()
      await expect(page.getByRole('alert')).toBeVisible()
      expect(requests).toHaveLength(1)
      await english(page)
      await expect(page.getByLabel('Minimum amount', { exact: true })).toHaveValue('100')
      await page.getByRole('combobox', { name: 'Currency', exact: true }).selectOption('USD')
      await page.getByRole('button', { name: 'Search funding', exact: true }).click()
      await expect.poll(() => requests.length).toBe(2)
      expect(requests[1].get('requiresConsortium')).toBe('false')
      expect(requests[1].get('funderKind')).toBe('3')
      expect(requests[1].get('currency')).toBe('USD')
      await expect(page.getByRole('link', { name: 'Original source: Fuente oficial' })).toHaveAttribute('href', 'https://official.example/fund')
      await accessibility(page); await fits(page)
    })
    test(`clasificación revisada no publica ni inventa requisitos a ${width}px`, async ({ page }) => {
      await page.setViewportSize({ width, height: 900 })
      const id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
      await page.route('**/api/v1/auth/refresh', route => route.fulfill({ json: { status: 'authenticated', accessToken: 'synthetic-ui-only', accessTokenExpiresAtUtc: new Date(Date.now() + 600_000).toISOString(), user: { publicId: id, email: 'admin@example.invalid', displayName: 'Admin', preferredLocale: 'es-CL', roles: ['Admin'], mfaEnabled: true } } }))
      const writes: Record<string, unknown>[] = []
      await page.route(`**/api/v1/admin/funding-discovery/${id}`, route => {
        if (route.request().method() === 'GET') return route.fulfill({ json: { opportunityId: id, title: 'Fondo Ñandú', contentVersion: 2, reviewedContentVersion: 1, data: null, eTag: null, sourceUrls: ['https://official.example/fund'] } })
        expect(route.request().method()).toBe('PUT')
        expect(route.request().headers()['if-none-match']).toBe('*')
        expect(route.request().headers()['idempotency-key']).toBeTruthy()
        writes.push(route.request().postDataJSON())
        return route.fulfill({ json: { eTag: '"0102030405060708"' } })
      })
      await page.goto(`/admin/funding/${id}/discovery`)
      await expect(page.getByText('El fondo cambió desde la revisión anterior.', { exact: false })).toBeVisible()
      await page.getByRole('combobox', { name: 'Tipo de financiador principal', exact: true }).selectOption('3')
      await page.getByRole('combobox', { name: 'Fuente que respalda la clasificación *', exact: true }).selectOption('https://official.example/fund')
      await english(page)
      await page.getByRole('button', { name: 'Confirm classification', exact: true }).click()
      await expect(page.getByText('Classification reviewed and saved.', { exact: true })).toBeVisible()
      expect(writes).toHaveLength(1)
      expect(writes[0]).toMatchObject({ contentVersion: 2, data: { funderKind: 3, requiresConsortium: null, requiresInternationalPartner: null } })
      await accessibility(page); await fits(page)
    })
  }
}
