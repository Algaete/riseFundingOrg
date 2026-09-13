import { expect, test, type Page } from '@playwright/test'
import { english, fits, mockWorkspace, readOnlyJson } from './workspace-checks'
import { workspaceOrganizationId } from '../src/test/fixtures/project-workspace'

const catalogs = { countries: [{ id: 152, code: 'CL', name: 'Chile' }], fundingCategories: [{ id: 4, code: 'water', name: 'Agua y saneamiento' }], projectTypes: [], sustainableDevelopmentGoals: [], currencies: [] }
const publicProject = { publicId: 'project', slug: 'agua-segura', title: 'Agua segura — proyecto sintético', summary: 'Iniciativa pública de prueba.', organization: { name: 'Organización sintética' }, publicationStatus: 2 }
const publicFund = { id: 'fund', slug: 'fondo-sintetico', title: 'Fondo de prueba', summary: 'Convocatoria sintética abierta.', sourceName: 'Fuente de prueba' }

async function publicSources(page: Page) {
  const calls: { path: string; query: string }[] = []
  await page.route('**/api/v1/marketplace/catalogs', readOnlyJson(catalogs))
  for (const path of ['marketplace/projects', 'funding-discovery']) await page.route(`**/api/v1/${path}?*`, route => {
    expect(route.request().method()).toBe('GET')
    const url = new URL(route.request().url())
    calls.push({ path, query: url.search })
    const current = Number(url.searchParams.get('page'))
    const size = Number(url.searchParams.get('pageSize'))
    return route.fulfill({ json: { items: [path === 'marketplace/projects' ? publicProject : publicFund], totalCount: 21, page: current, pageNumber: current, pageSize: size } })
  })
  return calls
}

export function registerUnifiedSearchTests(accessibility: (page: Page) => Promise<void>) {
  for (const width of [320, 1280]) test(`búsqueda unificada pública ES/EN accesible a ${width}px`, async ({ page }, testInfo) => {
    const calls = await publicSources(page)
    await page.setViewportSize({ width, height: 900 })
    await page.goto('/search?scope=all&q=agua&countryId=152&categoryId=4')
    await expect(page.getByRole('link', { name: publicProject.title })).toBeVisible()
    await expect(page.getByRole('link', { name: publicFund.title })).toBeVisible()
    await expect(page.getByRole('region', { name: 'Profesionales', exact: true }).getByRole('link', { name: 'Ingresar' })).toBeVisible()
    await expect(page.getByRole('region', { name: 'Organizaciones y aliados' }).getByRole('link', { name: 'Ingresar' })).toBeVisible()
    expect(calls).toHaveLength(2)
    for (const call of calls) {
      const params = new URLSearchParams(call.query)
      expect(params.get(call.path === 'marketplace/projects' ? 'q' : 'query')).toBe('agua')
      expect(params.get(call.path === 'marketplace/projects' ? 'countryIds' : 'countryId')).toBe('152')
      expect(params.get(call.path === 'marketplace/projects' ? 'categoryIds' : 'categoryId')).toBe('4')
      expect(params.get('pageSize')).toBe('6')
    }
    await fits(page); await accessibility(page)
    await page.screenshot({ path: testInfo.outputPath(`unified-search-${width}-es.png`), fullPage: true })
    await page.getByRole('searchbox').fill('borrador sin enviar')
    await english(page)
    await expect(page.getByRole('heading', { name: 'Search FundingPlatform' })).toBeVisible()
    await expect(page.getByRole('searchbox')).toHaveValue('borrador sin enviar')
    await expect(page.getByRole('combobox', { name: 'Country', exact: true })).toHaveValue('152')
    expect(calls).toHaveLength(2)
    await page.getByRole('combobox', { name: 'Change theme', exact: true }).selectOption('dark')
    await fits(page); await accessibility(page)
    await page.getByRole('region', { name: 'Projects', exact: true }).getByRole('link', { name: 'View all' }).click()
    await expect(page).toHaveURL('/search?scope=projects&q=agua&countryId=152&categoryId=4')
    await page.getByRole('link', { name: 'Next', exact: true }).click()
    await expect(page).toHaveURL('/search?scope=projects&q=agua&countryId=152&categoryId=4&page=2')
    await expect(page.getByText('Page 2', { exact: true })).toBeVisible()
    await page.goBack()
    await expect(page.getByText('Page 1', { exact: true })).toBeVisible()
  })

  test('búsqueda unificada autenticada conserva membresía y perfiles opt-in', async ({ page }) => {
    await mockWorkspace(page)
    await publicSources(page)
    await page.route('**/api/v1/professionals?*', readOnlyJson({ items: [
      { profileId: 'professional', data: { displayName: 'Profesional de prueba', headline: 'Ingeniería social', biography: 'Experiencia sintética', skills: ['GIS'], isDiscoverable: true } },
      { profileId: 'private', data: { displayName: 'Perfil privado', isDiscoverable: false } },
    ], totalCount: 1, page: 1, pageSize: 6 }))
    const directoryCalls: string[] = []
    await page.route(`**/api/v1/organizations/${workspaceOrganizationId}/network/directory?*`, route => {
      expect(route.request().method()).toBe('GET')
      directoryCalls.push(route.request().url())
      return route.fulfill({ json: { items: [{ id: 'ally', name: 'Aliado sintético', description: 'Organización visible en la red.' }], totalCount: 1, page: 1, pageSize: 6 } })
    })
    await page.setViewportSize({ width: 320, height: 900 })
    await page.goto('/search?scope=all&q=agua&countryId=152&categoryId=4&organizationId=foreign')
    await expect(page.getByRole('link', { name: 'Aliado sintético' })).toHaveAttribute('href', '/marketplace/organizations/ally')
    await expect(page.getByRole('heading', { name: 'Profesional de prueba' })).toBeVisible()
    await expect(page.getByText('Perfil privado', { exact: true })).toHaveCount(0)
    expect(directoryCalls).toHaveLength(1)
    const params = new URL(directoryCalls[0]).searchParams
    expect(params.get('countryIds')).toBe('152')
    expect(params.get('categoryIds')).toBe('4')
    await page.getByText('Ver perfil profesional', { exact: true }).click()
    await expect(page.getByText('Experiencia sintética')).toBeVisible()
    await fits(page); await accessibility(page)
    await english(page)
    await expect(page.getByRole('combobox', { name: 'Find partners from my organization' })).toHaveValue(workspaceOrganizationId)
    expect(directoryCalls).toHaveLength(1)
    await fits(page); await accessibility(page)
  })

  test('búsqueda unificada limita consultas y recupera errores sin perder resultados', async ({ page }) => {
    const calls = await publicSources(page)
    await page.goto('/search')
    await expect(page.getByRole('searchbox')).toBeVisible()
    await page.getByRole('searchbox').fill('agua')
    expect(calls).toHaveLength(0)
    let attempts = 0
    await page.route('**/api/v1/funding-discovery?*', route => {
      expect(route.request().method()).toBe('GET')
      attempts++
      return attempts === 1 ? route.fulfill({ status: 503, json: { title: 'private diagnostics' } })
        : route.fulfill({ json: { items: [], totalCount: 0, page: 1, pageSize: 6 } })
    })
    await page.getByRole('button', { name: 'Buscar', exact: true }).click()
    await expect(page.getByRole('alert')).toContainText('No pudimos consultar esta sección')
    await expect(page.getByRole('link', { name: publicProject.title })).toBeVisible()
    await expect(page.getByText('private diagnostics')).toHaveCount(0)
    await page.getByRole('button', { name: 'Reintentar', exact: true }).click()
    await expect(page.getByRole('alert')).toHaveCount(0)
    expect(attempts).toBe(2)
    expect(calls).toHaveLength(1)
    await page.goto('/search?scope=all&page=2')
    await expect(page.getByRole('alert')).toContainText('Revisa los filtros')
    expect(attempts).toBe(2)
    expect(calls).toHaveLength(1)
    await accessibility(page)
  })
}
