import { expect, test, type Page } from '@playwright/test'
import { english, fits, mockWorkspace, readOnlyJson } from './workspace-checks'
import { enrichmentInput } from '../src/features/projects/project-enrichment'
import type { ProjectDetails, ProjectWriteInput } from '../src/features/projects/project-api'
import { workspaceOrganizationId, workspaceProject, workspaceProjectId, workspacePublicProject } from '../src/test/fixtures/project-workspace'

// Registered within public.spec.ts: every API call is mocked and guarded.
export function registerProjectEnrichmentTests(checkAccessibility: (page: Page) => Promise<void>) {
  for (const width of [320, 1024]) {
    test(`proyecto enriquecido guarda y reabre versión ES/EN a ${width}px`, async ({ page }) => {
      await mockWorkspace(page)
      let persisted: ProjectDetails = { ...workspaceProject, enrichment: enrichmentInput() }
      let writes = 0
      await page.route(`**/api/v1/organizations/${workspaceOrganizationId}/projects/${workspaceProjectId}`, async route => {
        if (route.request().method() === 'PUT') {
          expect(route.request().headers()['if-match']).toBe(workspaceProject.eTag)
          const input = route.request().postDataJSON() as ProjectWriteInput
          expect(input.enrichment).toMatchObject({ problem: 'Problema Ñandú', beneficiaryCount: 1200,
            latitude: -33.456789, longitude: -70.654321, locationVisibility: 0, seekingConsortium: true,
            impactIndicators: [{ name: 'Acceso al agua', unit: 'hogares', baseline: 0, target: 1200 }] })
          writes++
          persisted = { ...persisted, ...input, enrichment: enrichmentInput(input.enrichment), projectVersion: 2, eTag: '"0000000000000002"' }
        } else expect(route.request().method()).toBe('GET')
        await route.fulfill({ json: persisted })
      })
      await page.setViewportSize({ width, height: 900 })
      await page.goto(`/projects/${workspaceProjectId}`)
      await page.getByLabel('Problema que aborda').fill('Problema Ñandú')
      await page.getByLabel('Solución propuesta').fill('Agua segura')
      await page.getByLabel('Cantidad de beneficiarios').fill('1200')
      await page.getByLabel('Latitud', { exact: true }).fill('-33.456789')
      await page.getByLabel(/^Longitud/).fill('-70.654321')
      await page.getByLabel('¿Busca formar o integrar un consorcio?').selectOption('true')
      await page.getByRole('button', { name: 'Agregar indicador' }).click()
      await page.getByLabel(/Nombre del indicador/).fill('Acceso al agua')
      await page.getByLabel(/Unidad de medida/).fill('hogares')
      await page.getByLabel('Línea base').fill('0')
      await page.getByLabel('Meta', { exact: true }).fill('1200')
      await fits(page)
      await english(page)
      await expect(page.getByLabel('Problem addressed')).toHaveValue('Problema Ñandú')
      await expect(page.getByLabel(/Latitude/)).toHaveValue('-33.456789')
      await expect(page.getByRole('button', { name: 'Submit for review' })).toBeDisabled()
      await checkAccessibility(page)
      await fits(page)
      await page.getByRole('button', { name: 'Save changes' }).click()
      await expect(page.getByText('Project saved with a new version.')).toBeVisible()
      expect(writes).toBe(1)
      await page.reload()
      await expect(page.getByLabel('Problem addressed')).toHaveValue('Problema Ñandú')
      await expect(page.getByLabel(/Indicator name/)).toHaveValue('Acceso al agua')
      await expect(page.getByLabel(/Latitude/)).toHaveValue('-33.456789')
      await expect(page.getByRole('button', { name: 'Save changes' })).toBeDisabled()
      await fits(page)
    })
  }

  test('ficha pública enriquecida accesible sin ubicación privada a 320px', async ({ page }) => {
    await mockWorkspace(page)
    await page.route('**/api/v1/projects/proyecto-sintetico', readOnlyJson({ ...workspacePublicProject,
      enrichment: { ...enrichmentInput(), problem: 'Problema territorial', solution: 'Solución comunitaria',
        beneficiaryCount: 1200, seekingConsortium: true, soughtPartners: 'Municipios',
        impactIndicators: [{ name: 'Acceso al agua', unit: 'hogares', baseline: 0, target: 1200 }] },
    }))
    await page.setViewportSize({ width: 320, height: 900 })
    await page.goto('/projects/public/proyecto-sintetico')
    await expect(page.getByText('Problema territorial')).toBeVisible()
    await expect(page.getByText(/Coordenadas privadas|Ubicación aproximada/)).toHaveCount(0)
    await checkAccessibility(page)
    await fits(page)
    await english(page)
    await expect(page.getByText('Impact indicators', { exact: true })).toBeVisible()
    await expect(page.getByText('Number of beneficiaries:').locator('..')).toContainText('1,200')
    await checkAccessibility(page)
    await fits(page)
  })
}
