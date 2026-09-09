import { expect, test, type Page } from '@playwright/test'
import { editorialCatalogs, editorialFunder, editorialOpportunity } from '../src/test/fixtures/editorial-workspace'
import { english, fits } from './workspace-checks'
import type { PublicationStatus } from '../src/features/funding/admin-funding-api'

async function mockOwner(page: Page, status: PublicationStatus = 0) {
  await page.route('**/api/v1/auth/refresh', route => route.fulfill({ json: {
    status: 'authenticated', accessToken: 'synthetic-owner', accessTokenExpiresAtUtc: '2099-01-01T00:00:00Z',
    user: { publicId: '33333333-3333-3333-3333-333333333333', email: 'owner@example.invalid', displayName: 'Financiador', roles: ['Professional'], preferredLocale: 'es-CL', mfaEnabled: false },
  } }))
  let funder = editorialFunder({ publicationStatus: status })
  let opportunity = editorialOpportunity({ publicationStatus: status })
  const writes: { method: string; path: string; body: Record<string, unknown>; headers: Record<string, string> }[] = []
  await page.route('**/api/v1/catalogs', route => route.fulfill({ json: editorialCatalogs }))
  await page.route('**/api/v1/funder-workspace/**', route => {
    const request = route.request(); const url = new URL(request.url())
    const path = url.pathname.replace('/api/v1/funder-workspace/', '')
    if (request.method() !== 'GET') {
      expect(['POST', 'PUT']).toContain(request.method())
      expect(path).not.toContain('reviews')
      const body = request.postDataJSON()
      writes.push({ method: request.method(), path, body, headers: request.headers() })
      if (path === 'funders') {
        funder = { ...funder, name: body.name, publicationStatus: 0 }
        return route.fulfill({ status: 201, json: { entityId: funder.funderId, publicationStatus: 0, contentVersion: 1, eTag: funder.eTag, wasReplay: false } })
      }
      expect(path).toBe(`funding-opportunities/${opportunity.opportunityId}`)
      opportunity = { ...opportunity, ...body, publicationStatus: 0, contentVersion: 4, eTag: '"A1A2A3A4A5A6A7A8"' }
      return route.fulfill({ json: { entityId: opportunity.opportunityId, publicationStatus: 0, contentVersion: 4, eTag: opportunity.eTag, wasReplay: false } })
    }
    if (path === 'funding-sources') return route.fulfill({ json: [{ id: 7, name: 'Portal', providerType: 0, baseUrl: null, isEnabled: true }] })
    if (path === 'funders') return route.fulfill({ json: { items: [funder], totalCount: 1, page: 1, pageSize: 20 } })
    if (path === `funders/${funder.funderId}`) return route.fulfill({ json: funder })
    if (path === `funding-opportunities/${opportunity.opportunityId}`) return route.fulfill({ json: opportunity })
    if (path === 'funding-opportunities') return route.fulfill({ json: { items: [opportunity], totalCount: 1, page: 1, pageSize: 20 } })
    throw new Error(`Unexpected owner path: ${path}`)
  })
  return writes
}

export function registerFunderWorkspaceTests(accessibility: (page: Page) => Promise<void>) {
  for (const width of [320, 1024]) {
    test(`financiador crea perfil propio sin rol Admin a ${width}px`, async ({ page }) => {
      const writes = await mockOwner(page)
      await page.setViewportSize({ width, height: 900 })
      await page.goto('/funder-workspace/funders/new')
      await page.getByRole('textbox', { name: 'Nombre', exact: true }).fill('Fundación propia Ñandú')
      await english(page)
      await expect(page.getByRole('textbox', { name: 'Name', exact: true })).toHaveValue('Fundación propia Ñandú')
      await expect(page.getByRole('main')).not.toHaveAttribute('lang', 'es')
      expect(writes).toHaveLength(0)
      await page.getByRole('button', { name: 'Create funder', exact: true }).click()
      await expect(page).toHaveURL(new RegExp(`/funder-workspace/funders/${editorialFunder().funderId}$`))
      expect(writes).toHaveLength(1)
      expect(writes[0].headers['idempotency-key']).toBeTruthy()
      await accessibility(page); await fits(page)
    })

    test(`financiador edita fondo con ETag y conserva borrador ES/EN a ${width}px`, async ({ page }) => {
      const writes = await mockOwner(page)
      await page.setViewportSize({ width, height: 900 })
      await page.goto(`/funder-workspace/funding/${editorialOpportunity().opportunityId}`)
      await page.getByRole('textbox', { name: 'Título', exact: true }).fill('Fondo propio Ñandú')
      await english(page)
      await expect(page.getByRole('textbox', { name: 'Title', exact: true })).toHaveValue('Fondo propio Ñandú')
      await expect(page.getByRole('combobox', { name: 'Role', exact: true }).locator('option')).toHaveCount(1)
      expect(writes).toHaveLength(0)
      await page.getByRole('button', { name: 'Save changes', exact: true }).click()
      await expect.poll(() => writes.length).toBe(1)
      expect(writes[0].headers['if-match']).toBe(editorialOpportunity().eTag)
      expect(writes[0].body.title).toBe('Fondo propio Ñandú')
      await accessibility(page); await fits(page)
      await page.getByRole('combobox', { name: 'Change theme', exact: true }).selectOption('dark')
      await accessibility(page)
    })

    test(`financiador espera revisión sin botones de aprobación a ${width}px`, async ({ page }) => {
      await mockOwner(page, 1)
      await page.setViewportSize({ width, height: 900 })
      await page.goto(`/funder-workspace/funding/${editorialOpportunity().opportunityId}`)
      await expect(page.getByRole('textbox', { name: 'Título', exact: true })).toBeDisabled()
      await english(page)
      await expect(page.getByRole('button', { name: /Approve|Reject/ })).toHaveCount(0)
      await expect(page.getByRole('textbox', { name: 'Rejection reason', exact: true })).toHaveCount(0)
      await accessibility(page); await fits(page)
    })
  }
}
