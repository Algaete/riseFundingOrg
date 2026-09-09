import { expect, test, type Page } from '@playwright/test'
import { english, fits, mockWorkspace, readOnlyJson } from './workspace-checks'
import { bilingualCatalogs, bilingualProfile } from '../src/test/fixtures/catalog-workspace'
import { workspaceOrganizationId, workspaceProject, workspaceProjectId, workspacePublicProject } from '../src/test/fixtures/project-workspace'

async function mockCatalogs(page: Page, empty = false) {
  await mockWorkspace(page, { empty })
  let reads = 0
  await page.route('**/api/v1/catalogs', route => {
    expect(route.request().method()).toBe('GET')
    reads++
    return route.fulfill({ json: bilingualCatalogs })
  })
  await page.route('**/api/v1/organizations/' + workspaceOrganizationId + '/profile', readOnlyJson(bilingualProfile))
  return () => reads
}

export function registerCatalogTests(accessibility: (page: Page) => Promise<void>) {
  for (const width of [320, 1024]) {
    test(`I18N05A onboarding catalogs preserve draft and identifiers at ${width}px`, async ({ page }) => {
      const reads = await mockCatalogs(page, true)
      await page.setViewportSize({ width, height: 900 })
      await page.goto('/onboarding')
      await page.getByLabel(/Nombre público/).fill('Organización Ñandú pendiente')
      await page.getByLabel(/Tipo de organización/).selectOption('2')
      await english(page)
      await expect(page.getByLabel(/Public name/)).toHaveValue('Organización Ñandú pendiente')
      await expect(page.getByLabel(/Organization type/)).toHaveValue('2')
      await expect(page.getByRole('option', { name: 'Foundation', exact: true })).toHaveAttribute('lang', 'en')
      expect(reads()).toBe(1)
      await accessibility(page)
      await fits(page)
      await page.getByRole('combobox', { name: 'Change theme', exact: true }).selectOption('dark')
      await accessibility(page)
      await page.getByRole('combobox', { name: 'Language', exact: true }).selectOption('es')
      await expect(page.getByRole('option', { name: 'Fundación', exact: true })).toHaveAttribute('lang', 'es')
      expect(reads()).toBe(1)
    })

    test(`I18N05A organization catalogs preserve legacy and private values at ${width}px`, async ({ page }) => {
      const reads = await mockCatalogs(page)
      await page.setViewportSize({ width, height: 900 })
      await page.goto('/organization/profile')
      await expect(page.getByLabel(/Tamaño del equipo/)).toHaveValue('2')
      await english(page)
      await expect(page.getByLabel(/Team size/)).toHaveValue('2')
      await expect(page.getByRole('option', { name: 'Small (previous range; confirm a new one)', exact: true })).toHaveAttribute('lang', 'en')
      await expect(page.getByRole('button', { name: 'Save', exact: true })).toBeDisabled()
      await accessibility(page)
      await fits(page)
      await page.getByRole('button', { name: /Impact$/ }).click()
      await expect(page.getByRole('checkbox', { name: 'Program (previous value; confirm a new type)', exact: true })).toBeChecked()
      await expect(page.getByRole('checkbox', { name: 'Environment and biodiversity', exact: true })).toBeChecked()
      await expect(page.getByText('Cultura Ñandú', { exact: true })).toBeVisible()
      const impact = page.getByRole('group', { name: /Impact areas/ })
      await impact.getByRole('textbox').fill('Opción Ñandú pendiente')
      await accessibility(page)
      await fits(page)
      await page.getByRole('combobox', { name: 'Language', exact: true }).selectOption('es')
      await expect(page.getByRole('group', { name: /Áreas de impacto/ }).getByRole('textbox')).toHaveValue('Opción Ñandú pendiente')
      await expect(page.getByRole('button', { name: 'Guardar', exact: true })).toBeDisabled()
      await page.getByRole('button', { name: /Financiamiento$/ }).click()
      await english(page)
      await expect(page.getByRole('checkbox', { name: 'Governments / public funds', exact: true })).toBeChecked()
      await expect(page.getByRole('checkbox', { name: 'International cooperation', exact: true })).toBeChecked()
      await expect(page.getByRole('checkbox', { name: 'Spanish', exact: true })).toBeChecked()
      await expect(page.getByRole('checkbox', { name: 'English', exact: true })).toBeChecked()
      const languages = page.getByRole('group', { name: /Working languages/ })
      await languages.getByRole('button', { name: 'Add another option', exact: true }).click()
      await languages.getByRole('textbox').fill('Spanish')
      await languages.getByRole('textbox').press('Enter')
      await expect(languages.getByRole('alert')).toHaveText('That option already exists in the list. Select it there.')
      await page.getByRole('combobox', { name: 'Change theme', exact: true }).selectOption('dark')
      await accessibility(page)
      await fits(page)
      expect(reads()).toBe(1)
    })

    test(`I18N05A project catalogs include 17 SDGs without clearing draft or selections at ${width}px`, async ({ page }) => {
      const reads = await mockCatalogs(page)
      await page.setViewportSize({ width, height: 900 })
      await page.goto('/projects/' + workspaceProjectId)
      await page.getByLabel(/Título/).fill('Proyecto Ñandú pendiente')
      await page.getByRole('checkbox', { name: /ODS 17 ·/ }).check()
      await english(page)
      const sdgs = page.getByRole('group', { name: /Related SDGs/ })
      await expect(sdgs.getByRole('checkbox')).toHaveCount(17)
      await expect(page.getByRole('checkbox', { name: 'SDG 6 · Clean Water and Sanitation', exact: true })).toBeChecked()
      await expect(page.getByRole('checkbox', { name: 'SDG 17 · Partnerships for the Goals', exact: true })).toBeChecked()
      await expect(page.getByLabel(/Title/)).toHaveValue('Proyecto Ñandú pendiente')
      await expect(page.getByLabel(/Currency/)).toHaveValue('USD')
      await expect(page.getByRole('option', { name: 'USD · US dollar', exact: true })).toHaveAttribute('lang', 'en')
      await expect(page.getByRole('button', { name: 'Submit for review', exact: true })).toBeDisabled()
      await accessibility(page)
      await fits(page)
      await page.getByRole('combobox', { name: 'Change theme', exact: true }).selectOption('dark')
      await accessibility(page)
      await page.getByRole('combobox', { name: 'Language', exact: true }).selectOption('es')
      await expect(page.getByRole('checkbox', { name: /ODS 17 · Alianzas/ })).toBeChecked()
      expect(reads()).toBe(1)
    })

    test(`I18N05A public project distinguishes reviewed and custom source labels at ${width}px`, async ({ page }) => {
      await mockCatalogs(page)
      await page.route('**/api/v1/projects/proyecto-sintetico', readOnlyJson({
        ...workspacePublicProject,
        categories: [
          bilingualCatalogs.fundingCategories[0],
          { id: 99, code: 'EDUCATION', name: 'Educación comunitaria Ñandú' },
        ],
        sustainableDevelopmentGoals: bilingualCatalogs.sustainableDevelopmentGoals,
      }))
      await page.setViewportSize({ width, height: 900 })
      await page.goto('/projects/public/proyecto-sintetico')
      await expect(page.getByRole('heading', { name: workspaceProject.title })).toBeVisible()
      await english(page)
      await expect(page.getByText('Environment and biodiversity', { exact: true })).toHaveAttribute('lang', 'en')
      await expect(page.getByText('Educación comunitaria Ñandú', { exact: true })).toHaveAttribute('lang', 'es')
      await expect(page.getByText('Partnerships for the Goals', { exact: true })).toHaveAttribute('lang', 'en')
      await expect(page.getByText(workspaceProject.description, { exact: true })).toBeVisible()
      await accessibility(page)
      await fits(page)
      await page.getByRole('combobox', { name: 'Change theme', exact: true }).selectOption('dark')
      await accessibility(page)
    })
  }

  test('I18N05A explicit project save serializes unchanged catalog IDs and ETag', async ({ page }) => {
    await mockCatalogs(page)
    let writes = 0
    await page.route('**/api/v1/organizations/' + workspaceOrganizationId + '/projects/' + workspaceProjectId, async route => {
      const request = route.request()
      if (request.method() === 'GET') return route.fulfill({ json: workspaceProject })
      expect(request.method()).toBe('PUT')
      expect(request.headers()['if-match']).toBe(workspaceProject.eTag)
      expect(request.postDataJSON()).toMatchObject({ countryIds: [152], regionIds: [7], categoryIds: [1], projectTypeIds: [4], sustainableDevelopmentGoalIds: [6, 17], currency: 'USD' })
      expect(request.postDataJSON()).not.toHaveProperty('locale')
      writes++
      await route.fulfill({ json: { ...workspaceProject, ...request.postDataJSON() } })
    })
    await page.goto('/projects/' + workspaceProjectId)
    await page.getByRole('checkbox', { name: /ODS 17 ·/ }).check()
    await english(page)
    expect(writes).toBe(0)
    await page.getByRole('button', { name: 'Save changes', exact: true }).click()
    await expect(page.getByText('Project saved with a new version.', { exact: true })).toBeVisible()
    expect(writes).toBe(1)
    await page.getByRole('combobox', { name: 'Language', exact: true }).selectOption('es')
    expect(writes).toBe(1)
  })
}
