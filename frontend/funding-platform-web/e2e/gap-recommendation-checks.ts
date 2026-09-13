import { expect, test, type Page } from '@playwright/test'
import { matchingDetail, matchingHistory, matchingRunId, workspaceOrganizationId, workspaceProjectId } from '../src/test/fixtures/matching-network'
import { gapRecommendations, gapOrganizationId } from '../src/test/fixtures/gap-recommendations'
import { english, fits, mockWorkspace, readOnlyJson } from './workspace-checks'

export function registerGapRecommendationTests(accessibility: (page: Page) => Promise<void>) {
  for (const width of [320, 1024]) {
    test(`apoyos ligados al fondo bajo demanda ES/EN a ${width}px`, async ({ page }, info) => {
      await mockWorkspace(page)
      const path = `**/api/v1/organizations/${workspaceOrganizationId}/projects/${workspaceProjectId}/matching-runs`
      await page.route(path + '?*', readOnlyJson(matchingHistory))
      await page.route(path + '/' + matchingRunId, readOnlyJson(matchingDetail))
      let requests = 0
      await page.route('**/api/v1/matching/gap-recommendations', route => {
        expect(route.request().method()).toBe('POST')
        expect(route.request().postDataJSON()).toEqual({ projectId: workspaceProjectId, opportunityId: matchingDetail.items[0].fundingOpportunity.publicId })
        requests++
        return requests === 1 ? route.fulfill({ json: gapRecommendations })
          : route.fulfill({ status: 404, json: { title: 'Unavailable', status: 404 } })
      })
      await page.setViewportSize({ width, height: 900 })
      await page.goto(`/matching?projectId=${workspaceProjectId}&runId=${matchingRunId}`)
      const panel = page.getByRole('region', { name: 'Cómo abordar los requisitos' })
      await expect(panel).toBeVisible()
      expect(requests).toBe(0)
      await panel.getByRole('button', { name: 'Buscar apoyos para este fondo' }).click()
      await expect(panel.getByRole('heading', { name: 'Fundación Aliada Ñandú' })).toBeVisible()
      await expect(panel.getByRole('link', { name: 'Ver organización' })).toHaveAttribute('href', `/marketplace/organizations/${gapOrganizationId}`)
      await expect(panel.getByText(/no brechas verificadas ni requisitos cumplidos/)).toBeVisible()
      await fits(page)
      await accessibility(page)
      await panel.screenshot({ path: info.outputPath(`gap-support-${width}-es.png`) })
      await english(page)
      const translated = page.getByRole('region', { name: 'How to address requirements' })
      await expect(translated.getByText(/Source: reviewed opportunity requirement/)).toBeVisible()
      await expect(translated.getByText(/Source: need declared by the project/)).toBeVisible()
      expect(requests).toBe(1)
      await fits(page)
      await accessibility(page)
      await page.getByRole('combobox', { name: 'Change theme', exact: true }).selectOption('dark')
      await accessibility(page)
      await translated.getByRole('button', { name: 'Refresh suggestions' }).click()
      await expect(translated.getByRole('alert')).toContainText('no longer available')
      await expect(translated.getByRole('heading', { name: 'Fundación Aliada Ñandú' })).toHaveCount(0)
      expect(requests).toBe(2)
      // No invitation, match creation or persistence endpoint is mocked: the parent guard rejects all other writes.
    })
  }
}
