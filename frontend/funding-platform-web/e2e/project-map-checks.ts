import { expect, test, type Page } from '@playwright/test'
import { workspaceCatalogs } from '../src/test/fixtures/project-workspace'
import { english, fits, readOnlyJson } from './workspace-checks'

export function registerProjectMapTests(checkAccessibility: (page: Page) => Promise<void>) {
  for (const width of [320, 1024]) {
    test(`mapa avanzado conserva selección, moneda y necesidades a ${width}px`, async ({ page }, testInfo) => {
      const selected = '11111111-1111-1111-1111-111111111111'
      await page.setViewportSize({ width, height: 900 })
      await page.route('**/api/v1/marketplace/catalogs', readOnlyJson(workspaceCatalogs))
      const reads: URLSearchParams[] = []
      await page.route('**/api/v1/marketplace/project-map?*', route => {
        expect(route.request().method()).toBe('GET')
        expect(route.request().headers().authorization).toBeUndefined()
        const query = new URL(route.request().url()).searchParams
        reads.push(query)
        return route.fulfill({ json: { items: [], totalCount: 101, withoutPublicLocationCount: 2, page: Number(query.get('page')), pageSize: 100 } })
      })
      await page.goto(`/marketplace/map?projectIds=${selected}&minimumFundingGap=0`)
      await expect(page.getByRole('alert')).toContainText('Revisa los filtros')
      expect(reads).toHaveLength(0)
      await english(page)
      await page.getByRole('combobox', { name: 'Currency', exact: true }).selectOption('USD')
      await page.getByRole('spinbutton', { name: 'Maximum remaining amount' }).fill('50000.1234')
      await page.getByRole('combobox', { name: 'Organization type', exact: true }).selectOption(String(workspaceCatalogs.organizationTypes[0].id))
      for (const label of ['Seeks funding (gap greater than zero)', 'Declares a need for partners', 'Declares a need for professionals', 'Wants to form a consortium']) await page.getByRole('checkbox', { name: label, exact: true }).check()
      expect(reads).toHaveLength(0)
      await page.getByRole('button', { name: 'Apply filters', exact: true }).click()
      await expect.poll(() => reads.length).toBe(1)
      expect(Object.fromEntries(reads[0])).toMatchObject({ minimumFundingGap: '0', maximumFundingGap: '50000.1234', currency: 'USD', seekingFunding: 'true', seekingPartners: 'true', seekingProfessionals: 'true', seekingConsortium: 'true' })
      expect(reads[0].getAll('projectIds')).toEqual([selected])
      expect(reads[0].get('organizationTypeId')).toBe(String(workspaceCatalogs.organizationTypes[0].id))
      await page.getByRole('button', { name: 'Next', exact: true }).click()
      await expect.poll(() => reads.at(-1)?.get('page')).toBe('2')
      expect(reads.at(-1)?.getAll('projectIds')).toEqual([selected])
      expect(reads.at(-1)?.get('currency')).toBe('USD')
      await fits(page)
      await checkAccessibility(page)
      await page.screenshot({ path: testInfo.outputPath(`advanced-map-${width}.png`), fullPage: true })
      await page.getByRole('button', { name: 'Explore the full map with these filters' }).click()
      await expect.poll(() => reads.at(-1)?.has('projectIds')).toBe(false)
      expect(reads.at(-1)?.get('currency')).toBe('USD')
      expect(reads.at(-1)?.get('page')).toBe('1')
      await page.getByRole('button', { name: 'Clear filters', exact: true }).click()
      await expect.poll(() => reads.at(-1)?.toString()).toBe('page=1&pageSize=100')
    })

    test(`mapa agrupa, filtra y pagina en ES/EN a ${width}px`, async ({ page }) => {
      await page.setViewportSize({ width, height: 900 })
      await page.route('**/api/v1/marketplace/catalogs', readOnlyJson(workspaceCatalogs))
      const reads: URLSearchParams[] = []
      await page.route('**/api/v1/marketplace/project-map?*', route => {
        expect(route.request().method()).toBe('GET')
        expect(route.request().headers().authorization).toBeUndefined()
        const query = new URL(route.request().url()).searchParams
        reads.push(query)
        return route.fulfill({ json: { items: [1, 2].map(n => ({ publicId: `map-${n}`, slug: `map-${n}`, title: `Impacto ${n}`, summary: 'Contenido de organización', organizationName: 'Organización', latitude: -33.46, longitude: -70.65, projectStatus: 2, projectStage: 0, fundingGap: 1000, currency: 'USD' })), totalCount: 101, withoutPublicLocationCount: 4, page: Number(query.get('page')), pageSize: 100 } })
      })
      await page.goto('/marketplace/map')
      await expect(page.getByRole('heading', { name: 'Mapa de proyectos' })).toBeVisible()
      await expect(page.getByRole('button', { name: 'Ver grupo de 2 proyectos' })).toBeVisible()
      await page.getByRole('button', { name: 'Ver grupo de 2 proyectos' }).click()
      await expect(page.getByRole('button', { name: 'Mostrar toda la página' })).toBeVisible()
      await page.getByRole('textbox', { name: 'Buscar proyecto u organización' }).fill('Agua Ñandú')
      await fits(page)
      await english(page)
      await expect(page.getByRole('textbox', { name: 'Search project or organization' })).toHaveValue('Agua Ñandú')
      await expect(page.getByRole('main')).not.toHaveAttribute('lang', 'es')
      expect(reads).toHaveLength(1)
      await page.getByRole('button', { name: 'World view', exact: true }).click()
      await page.getByRole('combobox', { name: 'Project stage', exact: true }).selectOption('0')
      await page.getByRole('button', { name: 'Apply filters', exact: true }).click()
      await expect.poll(() => reads.at(-1)?.get('q')).toBe('Agua Ñandú')
      expect(reads.at(-1)?.get('projectStage')).toBe('0')
      await page.getByRole('button', { name: 'Next', exact: true }).click()
      await expect(page.getByText('Page 2 of 2', { exact: true })).toBeVisible()
      await expect(page.getByRole('link', { name: 'View project details' }).first()).toHaveAttribute('href', '/marketplace/projects/map-1')
      await fits(page)
      await checkAccessibility(page)
      await page.getByRole('combobox', { name: 'Change theme', exact: true }).selectOption('dark')
      await checkAccessibility(page)
    })
  }

  test('mapa vacío y errores conservan catálogo y reintento', async ({ page }) => {
    await page.route('**/api/v1/marketplace/catalogs', readOnlyJson(workspaceCatalogs))
    let failed = true
    await page.route('**/api/v1/marketplace/project-map?*', route => failed
      ? route.fulfill({ status: 503, json: { title: 'Internal untrusted detail' } })
      : route.fulfill({ json: { items: [], totalCount: 0, withoutPublicLocationCount: 7, page: 1, pageSize: 100 } }))
    await page.goto('/marketplace/map')
    await expect(page.getByRole('alert')).toContainText('No se pudo cargar el mapa.')
    await expect(page.getByText('Internal untrusted detail')).toHaveCount(0)
    failed = false
    await page.getByRole('button', { name: 'Reintentar', exact: true }).click()
    await expect(page.getByText('No hay puntos públicos en esta página.', { exact: false })).toBeVisible()
    await expect(page.getByRole('link', { name: 'Ver catálogo completo' })).toHaveAttribute('href', '/marketplace')
    await checkAccessibility(page)
  })
}
