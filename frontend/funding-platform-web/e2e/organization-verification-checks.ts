import { expect, test, type Page } from '@playwright/test'
import type { OrganizationVerification } from '../src/features/admin-organizations/admin-organizations-api'
import { operationsDate, operationsIds, operationsOrganization, operationsVerification } from '../src/test/fixtures/operations-workspace'
import { english, fits } from './workspace-checks'

// Synthetic browser fixtures; the public suite denies every other API call.
async function setup(page: Page, conflictOnce = false) {
  let snapshot: OrganizationVerification = { ...operationsVerification }
  let organization = { ...operationsOrganization }
  const decisions: unknown[] = []
  const path = `/api/v1/admin/organizations/${operationsIds.organization}`
  await page.route('**/api/v1/auth/refresh', route => route.fulfill({ json: {
    status: 'authenticated', accessToken: 'synthetic-ui-only', accessTokenExpiresAtUtc: '2099-01-01T00:00:00Z',
    user: { publicId: operationsIds.user, email: 'reviewer@example.invalid', displayName: 'Revisora TEST', preferredLocale: 'es-CL', roles: ['Admin'], mfaEnabled: true },
  } }))
  await page.route(url => url.pathname === path, route => {
    expect(route.request().method()).toBe('GET')
    return route.fulfill({ json: organization })
  })
  await page.route(url => url.pathname === `${path}/verification`, route => {
    if (route.request().method() === 'GET') return route.fulfill({ json: snapshot })
    expect(route.request().method()).toBe('POST')
    const body = route.request().postDataJSON()
    decisions.push(body)
    if (conflictOnce && decisions.length === 1) {
      organization = { ...organization, profileVersion: 4 }
      snapshot = { ...snapshot, revision: 1, profileVersion: 4, recordedStatus: 1,
        reviewedProfileVersion: 3, needsReverification: true }
      return route.fulfill({ status: 409, json: { code: 'organization-verification-conflict' } })
    }
    expect(body.expectedRevision).toBe(snapshot.revision)
    expect(body.expectedProfileVersion).toBe(organization.profileVersion)
    snapshot = { ...snapshot, status: body.status, recordedStatus: body.status,
      revision: snapshot.revision + 1, reviewedProfileVersion: organization.profileVersion,
      reason: body.reason, reviewedAtUtc: operationsDate, reviewedByUserPublicId: operationsIds.user,
      reviewedByName: 'Revisora TEST', needsReverification: false,
      history: [{ revision: snapshot.revision + 1, status: body.status,
        profileVersion: organization.profileVersion, reason: body.reason,
        reviewedAtUtc: operationsDate, reviewedByUserPublicId: operationsIds.user, reviewedByName: 'Revisora TEST' }, ...(snapshot.history ?? [])] }
    return route.fulfill({ json: snapshot })
  })
  return decisions
}

export function registerOrganizationVerificationTests(accessibility: (page: Page) => Promise<void>) {
  for (const width of [320, 1280]) {
    test(`ORGVERIFY private decision requires reason and explicit confirmation at ${width}px`, async ({ page }, testInfo) => {
      const decisions = await setup(page)
      await page.setViewportSize({ width, height: 1000 })
      await page.goto(`/admin/organizations/${operationsIds.organization}`)
      await expect(page.getByRole('button', { name: 'Marcar como verificada', exact: true })).toBeDisabled()
      await page.getByLabel(/Motivo de la nueva decisión/).fill('Verificación sintética de identidad y sitio institucional.')
      await english(page)
      await expect(page.getByLabel(/Reason for the new decision/)).toHaveValue('Verificación sintética de identidad y sitio institucional.')
      await page.getByRole('button', { name: 'Mark as verified', exact: true }).click()
      await expect(page.getByRole('region', { name: 'Decision confirmation' })).toBeVisible()
      expect(decisions).toHaveLength(0)
      await page.getByRole('button', { name: 'Cancel', exact: true }).click()
      expect(decisions).toHaveLength(0)
      await page.getByRole('button', { name: 'Mark as verified', exact: true }).click()
      await page.getByRole('button', { name: 'Confirm decision', exact: true }).click()
      await expect(page.getByText('Decision saved in the private history.', { exact: true })).toBeVisible()
      expect(decisions).toEqual([{ status: 1, reason: 'Verificación sintética de identidad y sitio institucional.', expectedRevision: 0, expectedProfileVersion: 3 }])
      await page.getByText('Private decision history', { exact: true }).click()
      await expect(page.getByRole('main').getByText('Revisora TEST', { exact: true })).toBeVisible()
      await accessibility(page)
      await fits(page)
      await page.screenshot({ path: testInfo.outputPath(`verification-${width}.png`), fullPage: true })
      await page.getByRole('combobox', { name: 'Change theme', exact: true }).selectOption('dark')
      await accessibility(page)
      await fits(page)
    })

    test(`ORGVERIFY conflict requires reload and a new decision at ${width}px`, async ({ page }) => {
      const decisions = await setup(page, true)
      await page.setViewportSize({ width, height: 1000 })
      await page.goto(`/admin/organizations/${operationsIds.organization}`)
      await expect(page.getByLabel(/Motivo de la nueva decisión/)).toBeVisible()
      await english(page)
      await page.getByLabel(/Reason for the new decision/).fill('Primera decisión sintética.')
      await page.getByRole('button', { name: 'Mark as verified', exact: true }).click()
      await page.getByRole('button', { name: 'Confirm decision', exact: true }).click()
      await expect(page.getByRole('alert')).toContainText('Your decision has not been resubmitted.')
      expect(decisions).toHaveLength(1)
      await expect(page.getByRole('button', { name: 'Mark as verified', exact: true })).toBeDisabled()
      await expect(page.getByRole('region', { name: 'Decision confirmation' })).toHaveCount(0)
      await page.getByRole('button', { name: 'Reload profile and verification', exact: true }).click()
      await expect(page.getByLabel(/Reason for the new decision/)).toBeEnabled()
      await expect(page.getByLabel(/Reason for the new decision/)).toHaveValue('')
      expect(decisions).toHaveLength(1)
      await page.getByLabel(/Reason for the new decision/).fill('Nueva revisión sintética del perfil actualizado.')
      await page.getByRole('button', { name: 'Reject verification', exact: true }).click()
      await page.getByRole('button', { name: 'Confirm decision', exact: true }).click()
      await expect(page.getByText('Decision saved in the private history.', { exact: true })).toBeVisible()
      expect(decisions).toHaveLength(2)
      expect(decisions[1]).toMatchObject({ status: 2, expectedRevision: 1, expectedProfileVersion: 4 })
      await accessibility(page)
      await fits(page)
    })
  }
}
