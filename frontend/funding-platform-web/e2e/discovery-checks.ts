import { expect, test, type Page } from '@playwright/test'
import { discoveryOpportunity, discoveryOrganization, discoveryProject, discoveryProjectDetail } from '../src/test/fixtures/public-discovery'
import { workspaceCatalogs } from '../src/test/fixtures/project-workspace'
import { english, fits, readOnlyJson } from './workspace-checks'

async function mockDiscovery(page: Page) {
  const fundingReads: string[] = []
  const projectReads: string[] = []
  await page.route('**/api/v1/funding-opportunities?*', route => {
    expect(route.request().method()).toBe('GET')
    expect(route.request().headers().authorization).toBeUndefined()
    const url = new URL(route.request().url())
    fundingReads.push(url.search)
    return route.fulfill({ json: { items: [discoveryOpportunity], totalCount: 25, pageNumber: Number(url.searchParams.get('pageNumber')), pageSize: 12 } })
  })
  await page.route(`**/api/v1/funding-opportunities/${discoveryOpportunity.slug}`, readOnlyJson(discoveryOpportunity))
  await page.route('**/api/v1/marketplace/catalogs', readOnlyJson(workspaceCatalogs))
  await page.route('**/api/v1/marketplace/projects?*', route => {
    expect(route.request().method()).toBe('GET')
    expect(route.request().headers().authorization).toBeUndefined()
    const url = new URL(route.request().url())
    projectReads.push(url.search)
    return route.fulfill({ json: { items: [discoveryProject, { ...discoveryProject, publicId: 'private-draft', title: 'Private draft', publicationStatus: 0 }], totalCount: 25, pageNumber: Number(url.searchParams.get('page')), pageSize: 12 } })
  })
  await page.route(`**/api/v1/marketplace/projects/${discoveryProject.slug}`, readOnlyJson(discoveryProjectDetail))
  await page.route(`**/api/v1/marketplace/organizations/${discoveryOrganization.publicId}`, readOnlyJson({ ...discoveryOrganization, contactEmail: 'private@example.invalid', taxIdentifier: 'private-tax-id' }))
  return { fundingReads, projectReads }
}

export function registerDiscoveryLanguageTests(checkAccessibility: (page: Page) => Promise<void>) {
  for (const width of [320, 1024]) {
    test(`catálogo público ES/EN conserva búsqueda y página a ${width}px`, async ({ page }) => {
      const { fundingReads } = await mockDiscovery(page)
      await page.setViewportSize({ width, height: 900 })
      await page.goto('/funding')
      await expect(page.getByRole('heading', { name: discoveryOpportunity.title })).toBeVisible()
      await page.getByRole('textbox', { name: 'Buscar oportunidades' }).fill('Salud Ñandú')
      await fits(page)
      await english(page)
      await expect(page.getByRole('textbox', { name: 'Search opportunities' })).toHaveValue('Salud Ñandú')
      await expect(page.getByText('Atribución original de la fuente.')).toBeVisible()
      await expect(page.getByRole('main')).not.toHaveAttribute('lang', 'es')
      await checkAccessibility(page)
      await fits(page)
      expect(fundingReads).toHaveLength(1)
      await page.getByRole('button', { name: 'Next', exact: true }).click()
      await expect(page.getByText('Page 2 of 3')).toBeVisible()
      await page.getByRole('button', { name: 'Search', exact: true }).click()
      await expect(page.getByText('Page 1 of 3')).toBeVisible()
      expect(fundingReads).toHaveLength(3)
      expect(new URLSearchParams(fundingReads[2]).get('query')).toBe('Salud Ñandú')
      await page.getByRole('combobox', { name: 'Change theme', exact: true }).selectOption('dark')
      await checkAccessibility(page)
    })

    test(`ficha de fondo ES/EN confirma salida externa a ${width}px`, async ({ page }) => {
      await mockDiscovery(page)
      await page.setViewportSize({ width, height: 900 })
      await page.goto(`/funding/${discoveryOpportunity.slug}`)
      await expect(page.getByRole('heading', { name: discoveryOpportunity.title })).toBeVisible()
      await english(page)
      await expect(page.getByRole('heading', { name: 'Application requirements' })).toBeVisible()
      await expect(page.getByText('Estatutos y presupuesto.')).toBeVisible()
      await checkAccessibility(page)
      await fits(page)
      await page.getByRole('button', { name: 'Apply on external site' }).click()
      await expect(page.getByRole('dialog', { name: 'You are leaving FundingPlatform' })).toBeVisible()
      await expect(page.getByRole('button', { name: 'Close confirmation' })).toBeFocused()
      await expect(page.getByRole('link', { name: 'Continue to apply.example.invalid' })).toHaveAttribute('href', discoveryOpportunity.applicationUrl)
      await checkAccessibility(page)
      await fits(page)
      // Never follow external links or start an application in this synthetic suite.
      await page.keyboard.press('Escape')
      await expect(page.getByRole('dialog')).toHaveCount(0)
    })

    test(`marketplace ES/EN mantiene filtros y excluye borradores a ${width}px`, async ({ page }) => {
      const { projectReads } = await mockDiscovery(page)
      await page.setViewportSize({ width, height: 900 })
      await page.goto('/marketplace?q=Ñandú&countryId=152&categoryId=1&projectTypeId=4&status=2&currency=USD&sort=funding-gap-desc&page=2')
      await expect(page.getByRole('heading', { name: discoveryProject.title })).toBeVisible()
      await fits(page)
      await english(page)
      await expect(page.getByRole('heading', { name: 'Project marketplace' })).toBeVisible()
      await expect(page.getByRole('combobox', { name: 'Country', exact: true })).toHaveValue('152')
      await expect(page.getByRole('combobox', { name: 'Sort by', exact: true })).toHaveValue('funding-gap-desc')
      await expect(page.getByRole('option', { name: 'Environment' })).toHaveAttribute('lang', 'en')
      await expect(page.getByText('Page 2 of 3')).toBeVisible()
      await expect(page.getByText('Private draft')).toHaveCount(0)
      await expect(page.getByText('$75,000.00')).toBeVisible()
      await checkAccessibility(page)
      await fits(page)
      expect(projectReads).toHaveLength(1)
      await page.getByRole('button', { name: 'Next', exact: true }).click()
      await expect(page.getByText('Page 3 of 3')).toBeVisible()
      expect(new URL(page.url()).searchParams.get('countryId')).toBe('152')
      await page.getByRole('combobox', { name: 'Change theme', exact: true }).selectOption('dark')
      await checkAccessibility(page)
    })

    test(`perfil público y detalle canónico ES/EN sin datos privados a ${width}px`, async ({ page }) => {
      await mockDiscovery(page)
      await page.setViewportSize({ width, height: 900 })
      await page.goto(`/marketplace/organizations/${discoveryOrganization.publicId}`)
      await expect(page.getByRole('heading', { name: discoveryOrganization.name, exact: true })).toBeVisible()
      await english(page)
      await expect(page.getByRole('heading', { name: 'Projects by Fundación Ñandú' })).toBeVisible()
      await expect(page.getByText(discoveryOrganization.description)).toBeVisible()
      await expect(page.getByText(/private@example|private-tax-id/)).toHaveCount(0)
      await expect(page.getByRole('main')).not.toHaveAttribute('lang', 'es')
      await checkAccessibility(page)
      await fits(page)
      await page.getByRole('link', { name: 'View project', exact: true }).click()
      await expect(page.getByRole('heading', { name: 'About the project' })).toBeVisible()
      await expect(page.getByRole('heading', { name: discoveryProject.title })).toBeVisible()
      await expect(page.getByText('January 1, 2027 — December 31, 2027')).toBeVisible()
      await checkAccessibility(page)
      await fits(page)
    })
  }
}
