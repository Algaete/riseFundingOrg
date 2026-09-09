import { expect, test, type Page } from '@playwright/test'
import { english, fits, mockWorkspace } from './workspace-checks'
import { consumerCatalogs, consumerOpportunity, consumerPublicOrganization, consumerNetworkOrganization } from '../src/test/fixtures/catalog-consumers'
import { workspaceOrganizationId, workspaceProjectId } from '../src/test/fixtures/project-workspace'
import { networkDirectory, networkPreference, networkConnections } from '../src/test/fixtures/matching-network'
import { trackingApplication, trackingApplications } from '../src/test/fixtures/tracking-workspace'

// Inherits public.spec.ts's deny-by-default API guard. These mocks accept only reads.
async function countedRead(page: Page, path: string, json: unknown) {
  let reads = 0
  await page.route('**/api/v1/' + path, route => {
    expect(route.request().method()).toBe('GET')
    reads++
    return route.fulfill({ json })
  })
  return () => reads
}

export function registerCatalogConsumerTests(accessibility: (page: Page) => Promise<void>) {
  async function auditBothThemes(page: Page) {
    await accessibility(page)
    await fits(page)
    await page.getByRole('combobox', { name: 'Change theme', exact: true }).selectOption('dark')
    await accessibility(page)
    await fits(page)
  }

  for (const width of [320, 1024]) {
    test(`I18N05B funding classifications keep eligibility and original source labels at ${width}px`, async ({ page }) => {
      await mockWorkspace(page)
      const catalogs = await countedRead(page, 'catalogs', consumerCatalogs)
      const detail = await countedRead(page, 'organizations/' + workspaceOrganizationId + '/funding-opportunities/' + consumerOpportunity.slug, consumerOpportunity)
      await page.setViewportSize({ width, height: 900 })
      await page.goto('/opportunities/' + consumerOpportunity.slug)
      await expect(page.getByRole('heading', { name: 'Condiciones publicadas' })).toBeVisible()
      await english(page)
      await expect(page.getByText('Foundation · eligible', { exact: true })).toBeVisible()
      await expect(page.getByText('Foundation · excluded', { exact: true })).toBeVisible()
      await expect(page.getByText('Grant', { exact: true })).toHaveAttribute('lang', 'en')
      await expect(page.getByText('Environment and biodiversity', { exact: true })).toHaveAttribute('lang', 'en')
      await expect(page.getByText('Other', { exact: true })).toHaveCount(2)
      for (const name of ['Educación comunitaria Ñandú', 'Nueva área Ñandú', 'Medio ambiente']) {
        await expect(page.getByText(name, { exact: true })).toHaveAttribute('lang', 'es')
      }
      await expect(page.getByText(consumerOpportunity.allowedActivities, { exact: true })).toHaveAttribute('lang', 'es')
      await expect(page.getByRole('link', { name: 'Start application', exact: true })).toHaveAttribute('href', '/applications?new=1&fundingOpportunityId=' + consumerOpportunity.publicId)
      await auditBothThemes(page)
      await page.getByRole('combobox', { name: 'Language', exact: true }).selectOption('es')
      await expect(page.getByText('Medio ambiente y biodiversidad', { exact: true })).toHaveAttribute('lang', 'es')
      expect(catalogs()).toBe(1)
      expect(detail()).toBe(1)
    })

    test(`I18N05B public organization keeps taxonomy identity and privacy at ${width}px`, async ({ page }) => {
      const reads = await countedRead(page, 'marketplace/organizations/' + consumerPublicOrganization.publicId, {
        ...consumerPublicOrganization, contactEmail: 'private@example.invalid', taxIdentifier: 'private-tax-id',
      })
      await page.setViewportSize({ width, height: 900 })
      await page.goto('/marketplace/organizations/' + consumerPublicOrganization.publicId)
      await expect(page.getByRole('heading', { name: consumerPublicOrganization.name, exact: true })).toBeVisible()
      await english(page)
      await expect(page.getByText('Foundation', { exact: true })).toHaveAttribute('lang', 'en')
      await expect(page.getByText('Environment and biodiversity', { exact: true })).toHaveAttribute('lang', 'en')
      await expect(page.getByText('Other', { exact: true })).toHaveCount(2)
      await expect(page.getByText('Educación comunitaria Ñandú', { exact: true })).toHaveAttribute('lang', 'es')
      await expect(page.getByText(consumerPublicOrganization.description, { exact: true })).toBeVisible()
      await expect(page.getByText(/private@example|private-tax-id/)).toHaveCount(0)
      await auditBothThemes(page)
      await page.getByRole('combobox', { name: 'Language', exact: true }).selectOption('es')
      await expect(page.getByText('Otros', { exact: true })).toHaveCount(2)
      expect(reads()).toBe(1)
    })

    test(`I18N05B network catalogs preserve unknown territories and unsent invitations at ${width}px`, async ({ page }) => {
      await mockWorkspace(page, { publicationStatus: 2 })
      const path = 'organizations/' + workspaceOrganizationId + '/network/'
      await countedRead(page, path + 'settings', networkPreference)
      await countedRead(page, path + 'connections?*', networkConnections)
      const reads = await countedRead(page, path + 'directory?*', { ...networkDirectory, items: [consumerNetworkOrganization] })
      await page.setViewportSize({ width, height: 900 })
      await page.goto('/network')
      await page.getByRole('button', { name: 'Conectar', exact: true }).click()
      await page.getByRole('combobox', { name: 'Proyecto público opcional', exact: true }).selectOption(workspaceProjectId)
      await page.getByRole('textbox', { name: 'Mensaje privado', exact: true }).fill('Borrador Ñandú para colaborar, sin enviar.')
      await english(page)
      await expect(page.getByText('Foundation', { exact: true })).toHaveAttribute('lang', 'en')
      await expect(page.getByText('Environment and biodiversity', { exact: true })).toHaveAttribute('lang', 'en')
      for (const name of ['Territorio Ñandú', 'Educación comunitaria Ñandú', 'Nueva área Ñandú']) {
        await expect(page.getByText(name, { exact: true })).toHaveAttribute('lang', 'es')
      }
      await expect(page.getByRole('combobox', { name: 'Optional public project', exact: true })).toHaveValue(workspaceProjectId)
      await expect(page.getByRole('textbox', { name: 'Private message', exact: true })).toHaveValue('Borrador Ñandú para colaborar, sin enviar.')
      await auditBothThemes(page)
      await page.getByRole('combobox', { name: 'Language', exact: true }).selectOption('es')
      await expect(page.getByText('Fundación', { exact: true })).toHaveAttribute('lang', 'es')
      expect(reads()).toBe(1)
    })

    for (const editing of [false, true]) {
      test(`I18N05B application currency preserves draft and code (editing=${editing}) at ${width}px`, async ({ page }) => {
        await mockWorkspace(page)
        const path = 'organizations/' + workspaceOrganizationId
        const catalogs = await countedRead(page, 'catalogs', consumerCatalogs)
        await countedRead(page, path + '/applications?*', trackingApplications)
        await countedRead(page, path + '/applications/' + trackingApplication.publicId, { ...trackingApplication, currency: 'EUR' })
        await countedRead(page, path + '/funding-opportunities?*', { items: [consumerOpportunity], totalCount: 1, pageNumber: 1, pageSize: 50, searchMode: 'filtered' })
        await page.setViewportSize({ width, height: 900 })
        await page.goto(editing ? '/applications?applicationId=' + trackingApplication.publicId : '/applications?new=1')
        if (editing) await expect(page.getByRole('combobox', { name: 'Moneda', exact: true })).toHaveValue('EUR')
        else {
          await page.getByLabel('Proyecto para postular', { exact: true }).selectOption(workspaceProjectId)
          await page.getByLabel('Fondo para postular', { exact: true }).selectOption(consumerOpportunity.publicId)
          await page.getByRole('combobox', { name: 'Moneda', exact: true }).selectOption('EUR')
        }
        await page.getByRole('textbox', { name: editing ? 'Notas de la postulación' : 'Notas', exact: true }).fill('Borrador Ñandú sin guardar.')
        const originalUrl = page.url()
        await english(page)
        await expect(page.getByRole('combobox', { name: 'Currency', exact: true })).toHaveValue('EUR')
        await expect(page.getByRole('option', { name: 'EUR · Euro de prueba Ñandú', exact: true })).toHaveAttribute('lang', 'es')
        await expect(page.getByRole('option', { name: 'USD · US dollar', exact: true })).toHaveAttribute('lang', 'en')
        await expect(page.getByRole('textbox', { name: editing ? 'Application notes' : 'Notes', exact: true })).toHaveValue('Borrador Ñandú sin guardar.')
        await auditBothThemes(page)
        await page.getByRole('combobox', { name: 'Language', exact: true }).selectOption('es')
        await expect(page.getByRole('combobox', { name: 'Moneda', exact: true })).toHaveValue('EUR')
        expect(page.url()).toBe(originalUrl)
        expect(catalogs()).toBe(1)
      })
    }
  }
}
