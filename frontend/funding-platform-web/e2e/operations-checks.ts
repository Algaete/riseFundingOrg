import { expect, test, type Page } from '@playwright/test'
import { english, fits } from './workspace-checks'
import { operationsFixtures, operationsIds, operationsDocument, operationsOrganization } from '../src/test/fixtures/operations-workspace'

async function mockOperations(page: Page, overrides: Record<string, unknown> = {}) {
  await page.route('**/api/v1/auth/refresh', route => route.fulfill({ json: {
    status: 'authenticated', accessToken: 'synthetic-ui-only', accessTokenExpiresAtUtc: '2099-01-01T00:00:00Z',
    user: { publicId: operationsIds.user, email: 'admin@example.invalid', displayName: 'Admin Ñandú', preferredLocale: 'es-CL', roles: ['Admin'], mfaEnabled: false },
  } }))
  let reads = 0
  for (const [path, data] of Object.entries({ ...operationsFixtures, ...overrides })) {
    await page.route(url => url.pathname === '/api/v1' + path, route => {
      expect(route.request().method()).toBe('GET')
      reads++
      return route.fulfill({ json: data })
    })
  }
  return () => reads
}

export function registerOperationalTests(accessibility: (page: Page) => Promise<void>) {
  async function bothThemes(page: Page) {
    await accessibility(page)
    const overflow = await page.locator('main').evaluate(main => [...main.querySelectorAll('*')].filter(element => {
      if (element.getBoundingClientRect().right <= window.innerWidth + 1) return false
      for (let parent = element.parentElement; parent; parent = parent.parentElement) {
        if (['auto', 'scroll', 'hidden', 'clip'].includes(getComputedStyle(parent).overflowX)
          && parent.getBoundingClientRect().right <= window.innerWidth + 1) return false
      }
      return true
    }).slice(0, 15).map(element => ({
      tag: element.tagName, classes: element.className, right: element.getBoundingClientRect().right,
    })))
    expect(overflow, 'Operational content must fit; tables may scroll inside their own region').toEqual([])
    await fits(page)
    await page.getByRole('combobox', { name: 'Change theme', exact: true }).selectOption('dark')
    await accessibility(page)
    await fits(page)
  }

  const views = [
    ['/admin', 'Control panel', 'Grants.gov Ñandú'],
    ['/admin/users?q=original&status=1&role=Admin&page=2', 'Users', 'operator@example.invalid'],
    ['/admin/organizations?q=original&profileStatus=1&isActive=true&page=2', 'Organizations', operationsOrganization.name],
    ['/admin/organizations/' + operationsIds.organization, operationsOrganization.name, 'Descripción original de la organización.'],
    ['/admin/errors?category=extraction&retryable=false&page=2', 'Operational errors', 'Diagnóstico sanitizado original.'],
    ['/admin/subscriptions', 'Subscriptions', 'Plan original'],
    ['/admin/imports?sourceId=9&status=2&page=2', 'Imports', '3 procesados'],
    ['/admin/imports/' + operationsIds.run, 'Import: agua Ñandú', 'GRANT-ÑANDÚ-001'],
    ['/admin/sources', 'Import sources', 'Licencia original'],
    ['/admin/imports/upload-document', 'Secure document upload', 'Nueva carga'],
    ['/admin/source-documents/' + operationsIds.intent, 'bases-Ñandú.pdf', 'Defender real pendiente de configuración'],
  ] as const

  for (const width of [320, 1024]) {
    for (const [path, title, ready] of views) {
      test(`I18N05D ${path} preserves operational reads at ${width}px`, async ({ page }) => {
        const reads = await mockOperations(page)
        await page.setViewportSize({ width, height: 900 })
        await page.goto(path)
        await expect(page.getByText(ready, { exact: path !== '/admin/subscriptions' }).first()).toBeVisible()
        const initialUrl = page.url()
        const before = reads()
        await english(page)
        await expect(page.getByRole('heading', { name: title, level: 1, exact: true })).toBeVisible()
        await expect(page.getByRole('main')).not.toHaveAttribute('lang', 'es')
        await expect(page.getByText('PRIVATE-PROVIDER-REFERENCE')).toHaveCount(0)
        await bothThemes(page)
        expect(page.url()).toBe(initialUrl)
        expect(reads()).toBe(before)
      })
    }

    test(`I18N05D duplicate confirmation keeps unsent reason at ${width}px`, async ({ page }) => {
      const reads = await mockOperations(page)
      await page.setViewportSize({ width, height: 900 })
      await page.goto('/admin/imports/' + operationsIds.run)
      await page.getByRole('button', { name: 'Comparar duplicado' }).click()
      await page.getByRole('button', { name: 'Marcar como duplicado' }).click()
      await page.getByRole('dialog').getByRole('textbox').fill('Motivo original Ñandú')
      const before = reads()
      await english(page)
      const dialog = page.getByRole('dialog', { name: 'Confirm duplication decision' })
      await expect(dialog.getByRole('textbox')).toHaveValue('Motivo original Ñandú')
      await expect(dialog).toContainText('The candidate will remain unpublished.')
      await bothThemes(page)
      await dialog.getByRole('button', { name: 'Cancel' }).click()
      await expect(dialog).toHaveCount(0)
      expect(reads()).toBe(before)
    })

    test(`I18N05D PDF file validation keeps selection without uploading at ${width}px`, async ({ page }) => {
      await mockOperations(page)
      await page.setViewportSize({ width, height: 900 })
      await page.goto('/admin/imports/upload-document')
      await expect(page.getByRole('combobox', { name: 'Fuente de procedencia' })).toHaveValue('10')
      await page.locator('input[type=file]').setInputFiles({ name: 'archivo-invalido.txt', mimeType: 'text/plain', buffer: Buffer.from('synthetic invalid file') })
      await page.getByRole('button', { name: 'Cargar y verificar' }).click()
      await expect(page.getByText('Sólo se admiten archivos PDF.')).toBeVisible()
      await english(page)
      await expect(page.getByText('Only PDF files are accepted.')).toBeVisible()
      await expect(page.getByRole('combobox', { name: 'Origin source' })).toHaveValue('10')
      expect(await page.locator('input[type=file]').evaluate((node: HTMLInputElement) => node.files?.[0].name)).toBe('archivo-invalido.txt')
      await bothThemes(page)
    })

    test(`I18N05D failed Defender stays blocked in both languages at ${width}px`, async ({ page }) => {
      await mockOperations(page, {
        ['/admin/source-documents/' + operationsIds.document]: operationsDocument({ scanStatus: 3, storageStatus: 1, scanProvider: 1, isProductionScan: true }),
      })
      await page.setViewportSize({ width, height: 900 })
      await page.goto('/admin/source-documents/' + operationsIds.intent)
      await expect(page.getByText(/reescaneo bajo demanda/)).toBeVisible()
      await english(page)
      await expect(page.getByText(/On-demand Microsoft Defender rescanning is not enabled/)).toBeVisible()
      await expect(page.getByRole('button', { name: 'Retry scan' })).toHaveCount(0)
      await expect(page.getByRole('button', { name: 'Start extraction' })).toHaveCount(0)
      await bothThemes(page)
    })
  }
}
