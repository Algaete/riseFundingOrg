import { expect, test, type Page } from '@playwright/test'
import { fits } from './workspace-checks'

const catalogs = {
  countries: [{ id: 152, code: 'CL', name: 'Chile' }], fundingCategories: [{ id: 4, code: 'water', name: 'Agua y saneamiento' }],
  projectTypes: [], sustainableDevelopmentGoals: [], currencies: [],
}

export function registerHomeReferenceTests(accessibility: (page: Page) => Promise<void>) {
  for (const width of [320, 768, 1024, 1536]) {
    for (const theme of ['light', 'dark']) {
      test(`inicio de referencia vacío accesible a ${width}px en ${theme}`, async ({ page }, testInfo) => {
        await page.setViewportSize({ width, height: 1024 })
        if (width === 1024 && theme === 'light') {
          // Reproduce a slow CDN response: visible layout does not mean the image decoded.
          await page.route('**/images/home-impact-hero.jpg', async route => {
            const response = await route.fetch()
            await new Promise(resolve => setTimeout(resolve, 750))
            await route.fulfill({ response })
          })
        }
        await page.goto('/')
        await expect(page.getByRole('heading', { name: 'Conectamos tu causa con oportunidades.' })).toBeVisible()
        await page.getByRole('combobox', { name: 'Cambiar tema', exact: true }).selectOption(theme)
        const hero = page.locator('.home-hero-photo')
        await expect(hero).toBeVisible()
        await expect.poll(() => hero.evaluate((image: HTMLImageElement) => image.complete && image.naturalWidth > 0), {
          message: 'The home photograph must finish loading successfully',
          timeout: 15_000,
        }).toBe(true)
        await expect(page.locator('.home-map-marker, .home-project-card')).toHaveCount(0)
        await fits(page)
        await accessibility(page)
        await page.screenshot({ path: testInfo.outputPath(`home-${width}-${theme}-es.png`), fullPage: true, animations: 'disabled' })
        await page.getByRole('combobox', { name: 'Idioma', exact: true }).selectOption('en')
        await expect(page.getByRole('heading', { name: 'Project map in Chile' })).toBeVisible()
        await fits(page)
        await accessibility(page)
      })
    }
  }

  test('inicio de referencia conserva criterios y abre la búsqueda unificada', async ({ page }) => {
    await page.route('**/api/v1/marketplace/catalogs', route => route.fulfill({ json: catalogs }))
    await page.route('**/api/v1/funding-discovery?*', route => route.fulfill({ json: { items: [], totalCount: 0, page: 1, pageSize: 6 } }))
    await page.goto('/')
    await page.getByRole('searchbox', { name: 'Término de búsqueda', exact: true }).fill('agua & salud')
    await page.getByRole('combobox', { name: 'País', exact: true }).selectOption('152')
    await page.getByRole('combobox', { name: 'Área de impacto', exact: true }).selectOption('4')
    await page.getByRole('combobox', { name: 'Idioma', exact: true }).selectOption('en')
    await expect(page.getByRole('searchbox', { name: 'Search term' })).toHaveValue('agua & salud')
    await expect(page.getByRole('combobox', { name: 'Country', exact: true })).toHaveValue('152')
    await page.getByRole('button', { name: 'Search', exact: true }).click()
    await expect(page).toHaveURL('/search?scope=funding&q=agua+%26+salud&countryId=152&categoryId=4')
    await page.goto('/')
    await page.route('**/api/v1/funding-discovery/catalogs', route => route.fulfill({ json: { ...catalogs, regions: [], fundingTypes: [], organizationTypes: [], languages: [] } }))
    await page.route('**/api/v1/funding-discovery?*', route => route.fulfill({ json: { items: [], totalCount: 0, page: 1, pageSize: 20 } }))
    await page.getByRole('radio', { name: 'Opportunities', exact: true }).check()
    await page.getByRole('searchbox', { name: 'Search term' }).fill('bosque')
    await page.getByRole('button', { name: 'Search', exact: true }).click()
    await expect(page).toHaveURL('/search?scope=funding&q=bosque&countryId=152')
  })

  test('inicio de referencia abre navegación móvil y entra al buscador', async ({ page }) => {
    await page.setViewportSize({ width: 320, height: 900 })
    await page.goto('/')
    const trigger = page.getByRole('button', { name: 'Explorar la plataforma', exact: true })
    await trigger.click()
    const nav = page.getByRole('navigation', { name: 'Explorar la plataforma', exact: true })
    await expect(nav.getByRole('link', { name: 'Organizaciones', exact: true })).toHaveAttribute('href', '/network')
    await expect(nav.getByRole('link', { name: 'Alianzas', exact: true })).toHaveAttribute('href', '/collaboration/consortia')
    await expect(nav.getByRole('link', { name: 'Profesionales', exact: true })).toHaveAttribute('href', '/professionals')
    await fits(page)
    await accessibility(page)
    await page.keyboard.press('Escape')
    await expect(trigger).toBeFocused()
    await expect(nav).toHaveCount(0)
    await trigger.click()
    await nav.getByRole('link', { name: 'Buscar en la plataforma', exact: true }).click()
    await expect(page).toHaveURL('/search')
    await expect(page.getByRole('searchbox', { name: 'Término de búsqueda' })).toBeVisible()
    await expect(nav).toHaveCount(0)
  })

  test('el piloto mantiene mapa y destacados pendientes aunque existan proyectos publicados', async ({ page }, testInfo) => {
    let projectReads = 0
    await page.route('**/api/v1/marketplace/projects?*', route => { projectReads++; return route.fulfill({ json: { items: [], totalCount: 0 } }) })
    await page.route('**/api/v1/marketplace/project-map?*', route => { projectReads++; return route.fulfill({ json: { items: [], totalCount: 0 } }) })
    await page.goto('/')
    await expect(page.getByText('Próximamente', { exact: true })).toHaveCount(2)
    await expect(page.locator('.home-project-card, .home-map-marker')).toHaveCount(0)
    expect(projectReads).toBe(0)
    await page.setViewportSize({ width: 320, height: 1024 })
    await fits(page)
    await accessibility(page)
    await page.screenshot({ path: testInfo.outputPath('pilot-coming-soon-320.png'), fullPage: true })
  })

  test('inicio de referencia diferencia errores de una comunidad vacía y permite reintentar', async ({ page }) => {
    let attempts = 0
    await page.route('**/api/v1/marketplace/projects?*', route => {
      attempts++
      return attempts === 1 ? route.fulfill({ status: 503, json: { title: 'Internal diagnostic not for display' } }) : route.fulfill({ json: { items: [], totalCount: 0, pageNumber: 1, pageSize: 3 } })
    })
    await page.route('**/api/v1/marketplace/catalogs', route => route.fulfill({ status: 503, json: {} }))
    await page.goto('/')
    await expect(page.getByText('No pudimos cargar los filtros. Puedes buscar por palabra clave.')).toBeVisible()
    await expect(page.getByText('Internal diagnostic not for display')).toHaveCount(0)
    await expect(page.getByRole('combobox', { name: 'País', exact: true })).toBeDisabled()
    await expect(page.getByRole('button', { name: 'Buscar', exact: true })).toBeEnabled()
    await page.getByRole('button', { name: 'Reintentar filtros' }).click()
    expect(attempts).toBe(0)
    await expect(page.getByText('Próximamente', { exact: true })).toHaveCount(2)
    await accessibility(page)
  })
}
