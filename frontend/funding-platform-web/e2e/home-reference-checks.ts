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
        await page.goto('/')
        await expect(page.getByRole('heading', { name: 'El próximo gran proyecto puede ser el tuyo' })).toBeVisible()
        await page.getByRole('combobox', { name: 'Cambiar tema', exact: true }).selectOption(theme)
        const hero = page.locator('.home-hero-photo')
        await expect(hero).toBeVisible()
        expect(await hero.evaluate((image: HTMLImageElement) => image.complete && image.naturalWidth > 0)).toBe(true)
        await expect(page.locator('.home-map-marker, .home-project-card')).toHaveCount(0)
        await fits(page)
        await accessibility(page)
        await page.screenshot({ path: testInfo.outputPath(`home-${width}-${theme}-es.png`), fullPage: true, animations: 'disabled' })
        await page.getByRole('combobox', { name: 'Idioma', exact: true }).selectOption('en')
        await expect(page.getByRole('heading', { name: 'Projects around the world' })).toBeVisible()
        await fits(page)
        await accessibility(page)
      })
    }
  }

  test('inicio de referencia conserva criterios y busca en proyectos u oportunidades', async ({ page }) => {
    await page.route('**/api/v1/marketplace/catalogs', route => route.fulfill({ json: catalogs }))
    await page.goto('/')
    await page.getByRole('searchbox', { name: 'Término de búsqueda', exact: true }).fill('agua & salud')
    await page.getByRole('combobox', { name: 'País', exact: true }).selectOption('152')
    await page.getByRole('combobox', { name: 'Área de impacto', exact: true }).selectOption('4')
    await page.getByRole('combobox', { name: 'Idioma', exact: true }).selectOption('en')
    await expect(page.getByRole('searchbox', { name: 'Search term' })).toHaveValue('agua & salud')
    await expect(page.getByRole('combobox', { name: 'Country', exact: true })).toHaveValue('152')
    await page.getByRole('button', { name: 'Search', exact: true }).click()
    await expect(page).toHaveURL('/marketplace?q=agua+%26+salud&countryId=152&categoryId=4')
    await page.goto('/')
    await page.route('**/api/v1/funding-discovery/catalogs', route => route.fulfill({ json: { ...catalogs, regions: [], fundingTypes: [], organizationTypes: [], languages: [] } }))
    await page.route('**/api/v1/funding-discovery?*', route => route.fulfill({ json: { items: [], totalCount: 0, page: 1, pageSize: 20 } }))
    await page.getByRole('radio', { name: 'Opportunities', exact: true }).check()
    await page.getByRole('searchbox', { name: 'Search term' }).fill('bosque')
    await page.getByRole('button', { name: 'Search', exact: true }).click()
    await expect(page).toHaveURL('/funding/explore?query=bosque')
  })

  test('inicio de referencia abre navegación móvil y enfoca el buscador', async ({ page }) => {
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
    await expect(page.getByRole('searchbox', { name: 'Término de búsqueda' })).toBeFocused()
    await expect(nav).toHaveCount(0)
  })

  test('inicio de referencia presenta datos sintéticos publicados, progreso y mapa sin imágenes privadas', async ({ page }, testInfo) => {
    const base = { status: 3, projectStage: 2, summary: 'Iniciativa sintética para la prueba visual.', startDate: null, endDate: null,
      budgetTotal: 100000, confirmedFunding: 35000, currency: 'USD', fundingGap: 65000, publicationStatus: 2,
      publishedAtUtc: '2026-09-01T00:00:00Z', organization: { publicId: '11111111-2222-3333-4444-666666666666', name: 'Organización sintética', websiteUrl: null } }
    const items = ['Restauración de ecosistemas', 'Educación para comunidades rurales', 'Desarrollo de la pesca sustentable'].map((title, index) => ({ ...base, publicId: `project-${index}`, slug: `project-${index}`, title }))
    await page.route('**/api/v1/marketplace/projects?*', route => route.fulfill({ json: { items: [...items, { ...items[0], title: 'Borrador privado', publicationStatus: 0 }], totalCount: 3, pageNumber: 1, pageSize: 3 } }))
    await page.route('**/api/v1/marketplace/project-map?*', route => route.fulfill({ json: { items: items.map((item, index) => ({ publicId: item.publicId, slug: item.slug, title: item.title, organizationName: 'Organización sintética', latitude: [-33, 40, -10][index], longitude: [-70, -4, 120][index], projectStatus: 3, projectStage: 2, fundingGap: 65000, currency: 'USD' })), totalCount: 3, withoutPublicLocationCount: 0, page: 1, pageSize: 100 } }))
    await page.setViewportSize({ width: 1536, height: 1024 })
    await page.goto('/')
    await expect(page.locator('.home-project-card')).toHaveCount(3)
    await expect(page.locator('.home-project-card img')).toHaveCount(0)
    await expect(page.getByText('Borrador privado')).toHaveCount(0)
    await expect(page.getByRole('progressbar')).toHaveCount(3)
    await expect(page.locator('.home-map-marker')).toHaveCount(3)
    await fits(page)
    await accessibility(page)
    await page.screenshot({ path: testInfo.outputPath('home-synthetic-data-1536.png'), fullPage: true })
    await page.setViewportSize({ width: 320, height: 1024 })
    await page.getByRole('combobox', { name: 'Idioma', exact: true }).selectOption('en')
    await page.getByRole('combobox', { name: 'Change theme', exact: true }).selectOption('dark')
    await fits(page)
    await accessibility(page)
  })

  test('inicio de referencia diferencia errores de una comunidad vacía y permite reintentar', async ({ page }) => {
    let attempts = 0
    await page.route('**/api/v1/marketplace/projects?*', route => {
      attempts++
      return attempts === 1 ? route.fulfill({ status: 503, json: { title: 'Internal diagnostic not for display' } }) : route.fulfill({ json: { items: [], totalCount: 0, pageNumber: 1, pageSize: 3 } })
    })
    await page.route('**/api/v1/marketplace/catalogs', route => route.fulfill({ status: 503, json: {} }))
    await page.goto('/')
    await expect(page.getByText('No pudimos cargar los proyectos.')).toBeVisible()
    await expect(page.getByText('Internal diagnostic not for display')).toHaveCount(0)
    await expect(page.getByRole('combobox', { name: 'País', exact: true })).toBeDisabled()
    await expect(page.getByRole('button', { name: 'Buscar', exact: true })).toBeEnabled()
    await page.getByRole('button', { name: 'Reintentar proyectos' }).click()
    await expect(page.getByText('El próximo gran proyecto puede ser el tuyo')).toBeVisible()
    await accessibility(page)
  })
}
