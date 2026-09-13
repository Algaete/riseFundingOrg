import { expect, test, type Page } from '@playwright/test'
import { editorialCatalogs } from '../src/test/fixtures/editorial-workspace'
import { matchingDetail, matchingHistory, matchingRunId, workspaceOrganizationId, workspaceProjectId } from '../src/test/fixtures/matching-network'
import { gapRecommendations } from '../src/test/fixtures/gap-recommendations'
import { mockEditorial } from './editorial-checks'
import { english, fits, mockWorkspace, readOnlyJson } from './workspace-checks'

const version = 'partner-geography-2026-09-12'
const catalogs = { ...editorialCatalogs, countries: [{ id: 250, code: 'FR', name: 'Francia' }, { id: 826, code: 'GB', name: 'Reino Unido de Gran Bretaña e Irlanda del Norte' }],
  partnerRegions: [{ code: 'M49-150' }, { code: 'EU' }], partnerGeographyVersion: version }
export function registerPartnerGeographyTests(accessibility: (page: Page) => Promise<void>) {
  for (const width of [320, 1024]) {
    test(`geografía de socios edición explícita ES/EN a ${width}px`, async ({ page }, info) => {
      await mockEditorial(page)
      await page.setViewportSize({ width, height: 900 })
      await page.route('**/api/v1/funding-discovery/catalogs', readOnlyJson(catalogs))
      const id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
      let writes = 0
      await page.route(`**/api/v1/admin/funding-discovery/${id}`, route => {
        if (route.request().method() === 'GET') return route.fulfill({ json: { opportunityId: id, title: 'Fondo de socios', contentVersion: 2,
          reviewedContentVersion: 2, data: { funderKind: 3, requiresConsortium: true, requiresInternationalPartner: true, evidenceUrl: 'https://example.invalid/terms' },
          eTag: '"0102030405060708"', sourceUrls: ['https://example.invalid/terms'] } })
        expect(route.request().method()).toBe('PUT')
        expect(route.request().headers()['if-match']).toBe('"0102030405060708"')
        expect(route.request().headers()['idempotency-key']).toBeTruthy()
        expect(route.request().postDataJSON()).toMatchObject({ contentVersion: 2, data: { partnerGeography: { scope: 2, countryIds: [826], regionCodes: ['EU'], catalogVersion: version } } })
        writes++
        return route.fulfill({ status: 412, json: { title: 'Version conflict', status: 412 } })
      })
      await page.goto(`/admin/funding/${id}/discovery`)
      await expect(page.getByRole('combobox', { name: 'Alcance geográfico de los socios' })).toHaveValue('0')
      await page.getByRole('combobox', { name: 'Alcance geográfico de los socios' }).selectOption('2')
      await expect(page.getByRole('button', { name: 'Confirmar clasificación', exact: true })).toBeDisabled()
      await page.getByRole('checkbox', { name: 'Unión Europea (27 países)' }).check()
      await page.getByRole('checkbox', { name: /Reino Unido/ }).check()
      await page.getByRole('textbox', { name: 'Buscar un país' }).fill('Francia')
      await expect(page.getByRole('button', { name: /Quitar Reino Unido/ })).toBeVisible()
      expect(writes).toBe(0)
      await fits(page); await accessibility(page)
      await page.screenshot({ path: info.outputPath(`partner-geography-${width}-es.png`), fullPage: true })
      await english(page)
      await expect(page.getByRole('checkbox', { name: 'European Union (27 countries)' })).toBeChecked()
      await expect(page.getByRole('checkbox', { name: 'Europe (UN M49)', exact: true })).not.toBeChecked()
      expect(writes).toBe(0)
      await page.getByRole('button', { name: 'Confirm classification', exact: true }).click()
      await expect(page.getByRole('alert')).toBeVisible()
      await expect(page.getByRole('checkbox', { name: 'European Union (27 countries)' })).toBeChecked()
      await expect(page.getByRole('button', { name: /Remove United Kingdom/ })).toBeVisible()
      expect(writes).toBe(1)
      await fits(page); await accessibility(page)
      await page.getByRole('combobox', { name: 'Change theme', exact: true }).selectOption('dark')
      await accessibility(page)
    })
    test(`geografía de socios matching bajo demanda ES/EN a ${width}px`, async ({ page }) => {
      await mockWorkspace(page)
      await page.setViewportSize({ width, height: 900 })
      const path = `**/api/v1/organizations/${workspaceOrganizationId}/projects/${workspaceProjectId}/matching-runs`
      await page.route(path + '?*', readOnlyJson(matchingHistory))
      await page.route(path + '/' + matchingRunId, readOnlyJson(matchingDetail))
      await page.route('**/api/v1/funding-discovery/catalogs', readOnlyJson(catalogs))
      let requests = 0
      await page.route('**/api/v1/matching/gap-recommendations', route => {
        expect(route.request().method()).toBe('POST'); requests++
        return route.fulfill({ json: { ...gapRecommendations, geographyState: 'specific', partnerGeography: { scope: 2, countryIds: [], regionCodes: ['EU'], catalogVersion: version } } })
      })
      await page.goto(`/matching?projectId=${workspaceProjectId}&runId=${matchingRunId}`)
      const panel = page.getByRole('region', { name: 'Cómo abordar los requisitos' })
      await expect(panel).toBeVisible(); expect(requests).toBe(0)
      await panel.getByRole('button', { name: 'Buscar apoyos para este fondo' }).click()
      await expect(panel.getByText('Unión Europea (27 países)', { exact: true })).toBeVisible()
      await expect(panel.getByText('Sede declarada: Francia.')).toBeVisible()
      await expect(panel.getByText('El país de sede coincide con la selección geográfica revisada.')).toBeVisible()
      await fits(page); await accessibility(page)
      await english(page)
      await expect(page.getByText('European Union (27 countries)', { exact: true })).toBeVisible()
      await expect(page.getByText('Declared headquarters: France.')).toBeVisible()
      expect(requests).toBe(1)
      await fits(page); await accessibility(page)
    })
  }
}
