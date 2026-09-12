import { expect, test, type Page } from '@playwright/test'
import { mockWorkspace, english, fits, readOnlyJson } from './workspace-checks'
import { workspaceCatalogs, workspaceOrganizationId, workspaceProjectId } from '../src/test/fixtures/project-workspace'

export function registerEcosystemTests(accessibility: (page: Page) => Promise<void>) {
  test('matching abre mapa con proyectos de la página sin origen privado ni puntajes', async ({ page }) => {
    await mockWorkspace(page)
    const sourceId = '22222222-2222-2222-2222-222222222222'
    const projectIds = ['11111111-1111-1111-1111-111111111111', '44444444-4444-4444-4444-444444444444']
    await page.route('**/api/v1/funder-workspace/funders?*', readOnlyJson({ items: [{ funderId: sourceId, name: 'Financiador sintético' }], totalCount: 1, page: 1, pageSize: 20 }))
    await page.route('**/api/v1/matching/discovery', route => route.fulfill({ json: {
      sourceName: 'Origen privado', engineVersion: 'ecosystem-rules-v1', evaluatedAtUtc: '2026-09-01T12:00:00Z', totalCount: 50, totalCandidateCount: 50, isTruncated: false, page: 1, pageSize: 20,
      items: projectIds.map((id, n) => ({ id, name: `Proyecto ${n}`, summary: 'Resumen público', href: `/marketplace/projects/project-${n}`, score: 80, evidenceCoverage: 90, classification: 'aligned', reasons: [] })),
    } }))
    await page.route('**/api/v1/marketplace/catalogs', readOnlyJson(workspaceCatalogs))
    const mapReads: URLSearchParams[] = []
    await page.route('**/api/v1/marketplace/project-map?*', route => {
      mapReads.push(new URL(route.request().url()).searchParams)
      return route.fulfill({ json: { items: [], totalCount: 0, withoutPublicLocationCount: 1, page: 1, pageSize: 100 } })
    })
    await page.goto(`/matching/ecosystem?kind=3&id=${sourceId}`)
    await page.getByRole('button', { name: 'Evaluar coincidencias' }).click()
    const link = page.getByRole('link', { name: 'Ver estos resultados en el mapa', exact: true })
    await expect(link).toBeVisible()
    const href = await link.getAttribute('href')
    expect(href).not.toContain(sourceId)
    expect(href).not.toMatch(/criteria|score|sourceId|kind=/)
    await link.click()
    await expect.poll(() => mapReads.length).toBe(1)
    expect(mapReads[0].getAll('projectIds')).toEqual(projectIds)
    expect([...mapReads[0].keys()].sort()).toEqual(['page', 'pageSize', 'projectIds', 'projectIds'])
    await expect(page.getByRole('heading', { name: 'Mapa de proyectos', exact: true })).toBeVisible()
    await expect(page.getByText('Origen privado', { exact: true })).toHaveCount(0)
    await accessibility(page)
  })

  for (const width of [320, 1024]) {
    test(`ecosistema explica datos faltantes y brechas sin invitar ES/EN a ${width}px`, async ({ page }) => {
      await mockWorkspace(page)
      await page.setViewportSize({ width, height: 900 })
      const searches: Record<string, unknown>[] = []
      await page.route('**/api/v1/matching/discovery', route => {
        expect(route.request().method()).toBe('POST')
        searches.push(route.request().postDataJSON())
        return route.fulfill({ json: { sourceName: 'Proyecto Ñandú', engineVersion: 'ecosystem-rules-v1', evaluatedAtUtc: '2026-09-01T12:00:00Z',
          totalCount: 1, totalCandidateCount: 300, isTruncated: true, page: 1, pageSize: 20,
          items: [{ id: 'professional', name: 'Profesional GIS', summary: 'Ingeniería territorial', href: '/collaboration/consortia?professionalId=professional',
            score: 40, evidenceCoverage: 70, classification: 'gaps', reasons: [
              { code: 'geography', outcome: 'gap', weight: 30, evidence: [] },
              { code: 'sector', outcome: 'unknown', weight: 30, evidence: [] },
              { code: 'skills', outcome: 'match', weight: 40, evidence: ['gis'] },
              { code: 'availability', outcome: 'verify', weight: 0, evidence: [] },
            ] }],
        } })
      })
      await page.goto('/matching/ecosystem')
      await page.getByRole('button', { name: 'Evaluar coincidencias' }).click()
      await expect(page.getByRole('alert')).toBeVisible()
      expect(searches).toHaveLength(0)
      await page.getByRole('combobox', { name: 'Organización del proyecto', exact: true }).selectOption(workspaceOrganizationId)
      await page.getByRole('combobox', { name: 'Seleccionar origen *', exact: true }).selectOption(workspaceProjectId)
      await page.getByRole('combobox', { name: 'Qué buscas', exact: true }).selectOption('3')
      await page.getByRole('button', { name: 'Evaluar coincidencias' }).click()
      await expect(page.getByText('Se detectaron brechas', { exact: true })).toBeVisible()
      expect(searches).toHaveLength(1)
      expect(searches[0]).toMatchObject({ sourceKind: 1, sourceId: workspaceProjectId, targetKind: 3 })
      await english(page)
      await expect(page.getByRole('heading', { name: 'Profesional GIS' })).toBeVisible()
      await expect(page.getByText('gis', { exact: false })).not.toHaveCount(0)
      expect(searches).toHaveLength(1)
      await accessibility(page); await fits(page)
    })
  }
}
