import { expect, test, type Page } from '@playwright/test'
import { english, fits, mockWorkspace, readOnlyJson } from './workspace-checks'
import { workspaceOrganizationId, workspaceProject } from '../src/test/fixtures/project-workspace'
import { organizationOpportunity } from '../src/test/fixtures/organization-funding'
import {
  trackingApplication, trackingApplications, trackingCalendar, trackingCheckout, trackingNotifications,
  trackingPlans, trackingSearchDetail, trackingSearches, trackingSubscription, trackingUsage,
} from '../src/test/fixtures/tracking-workspace'

async function mockTracking(page: Page) {
  await mockWorkspace(page)
  const org = '**/api/v1/organizations/' + workspaceOrganizationId
  await page.route(org + '/applications?*', readOnlyJson(trackingApplications))
  await page.route(org + '/applications/' + trackingApplication.publicId, readOnlyJson(trackingApplication))
  await page.route(org + '/funding-opportunities?*', readOnlyJson({ items: [organizationOpportunity], totalCount: 1, pageNumber: 1, pageSize: 50, searchMode: 'filtered' }))
  await page.route(org + '/calendar?*', readOnlyJson(trackingCalendar))
  await page.route(org + '/saved-searches?*', readOnlyJson(trackingSearches))
  await page.route(org + '/notification-logs?*', readOnlyJson(trackingNotifications))
  await page.route('**/api/v1/subscription-plans', readOnlyJson(trackingPlans))
  await page.route(org + '/subscription', readOnlyJson(trackingSubscription))
  await page.route(org + '/subscription/usage', readOnlyJson(trackingUsage))
  await page.route(org + '/subscription-checkouts/' + trackingCheckout.id, readOnlyJson({ ...trackingCheckout, status: 'failed' }))
}

export function registerTrackingBillingTests(accessibility: (page: Page) => Promise<void>) {
  for (const width of [320, 1024]) {
    for (const area of ['applications', 'application-new', 'calendar', 'alerts', 'pricing', 'subscription', 'unsubscribe']) {
      test(`I18N04D ${area} ES/EN accessible and read-only at ${width}px`, async ({ page }) => {
        await mockTracking(page)
        await page.setViewportSize({ width, height: 900 })
        const path = {
          applications: '/applications?page=2&status=0&applicationId=' + trackingApplication.publicId,
          'application-new': '/applications?new=1',
          calendar: '/calendar?month=2027-02',
          alerts: '/alerts?new=true&q=agua&countryIds=152&currency=USD',
          pricing: '/pricing',
          subscription: '/subscription?checkout=' + trackingCheckout.id,
          unsubscribe: '/alerts/unsubscribe#token=synthetic-fragment-only',
        }[area]!
        await page.goto(path)
        if (area === 'applications') {
          await expect(page.getByLabel('Notas de la postulación')).toHaveValue('Notas Ñandú')
          await page.getByLabel('Notas de la postulación').fill('Borrador de prueba Ñandú')
        }
        if (area === 'application-new') {
          await page.getByLabel('Proyecto para postular').selectOption(workspaceProject.publicId)
          await page.getByLabel('Fondo para postular').selectOption(organizationOpportunity.publicId)
          await page.getByLabel('Notas', { exact: true }).fill('Borrador de prueba Ñandú')
        }
        if (area === 'alerts') {
          await page.getByLabel('Nombre', { exact: true }).fill('Búsqueda Ñandú')
          await page.getByLabel('Hora local').selectOption('21')
        }
        await expect(page.getByRole('heading', { level: 1 })).toBeVisible()
        const originalUrl = page.url()
        await accessibility(page)
        await fits(page)
        await english(page)
        await expect(page.getByRole('main')).not.toHaveAttribute('lang', 'es')
        await expect(page).toHaveURL(originalUrl)
        if (area === 'applications') {
          await expect(page.getByLabel('Application notes')).toHaveValue('Borrador de prueba Ñandú')
          await expect(page.getByLabel('Application status')).toHaveValue('0')
          await expect(page.getByLabel('Application date')).toHaveValue('2027-02-15')
          await expect(page.getByLabel('Requested amount')).toHaveValue('12500.5')
          await expect(page.getByText('Page 2 of 3')).toBeVisible()
        }
        if (area === 'application-new') {
          await expect(page.getByRole('textbox', { name: 'Notes', exact: true })).toHaveValue('Borrador de prueba Ñandú')
          await expect(page.getByLabel('Project for application')).toHaveValue(workspaceProject.publicId)
          await expect(page.getByLabel('Opportunity for application')).toHaveValue(organizationOpportunity.publicId)
        }
        if (area === 'applications' || area === 'application-new') {
          await expect(page.getByRole('option', { name: 'USD · US dollar', exact: true })).toHaveAttribute('lang', 'en')
        }
        if (area === 'calendar') {
          await expect(page.getByRole('heading', { name: 'Monday, February 15, 2027' })).toBeVisible()
          await expect(page.getByText('00:00 UTC')).toBeVisible()
          await expect(page.getByText('All day · Approximate date')).toBeVisible()
        }
        if (area === 'alerts') {
          await expect(page.getByLabel('Name', { exact: true })).toHaveValue('Búsqueda Ñandú')
          await expect(page.getByLabel('Local time')).toHaveValue('21')
          await expect(page.getByText('Retry scheduled')).toBeVisible()
        }
        if (area === 'pricing') {
          await expect(page.getByRole('link', { name: 'View subscription' })).toHaveAttribute('href', '/subscription')
          await expect(page.getByRole('button', { name: /checkout/ })).toHaveCount(0)
        }
        if (area === 'subscription') {
          await expect(page.getByText('Checkout: Failed', { exact: true })).toBeVisible()
          await expect(page.getByText('Current plan', { exact: true })).toBeVisible()
        }
        if (area === 'unsubscribe') {
          await expect(page.getByRole('button', { name: 'Confirm unsubscribe' })).toBeVisible()
          await expect(page.getByText('synthetic-fragment-only')).toHaveCount(0)
        }
        await accessibility(page)
        await fits(page)
        await page.getByRole('combobox', { name: 'Change theme', exact: true }).selectOption('dark')
        await accessibility(page)
        await fits(page)
      })
    }
  }

  test('I18N04D saves a search without email only after explicit confirmation', async ({ page }) => {
    await mockTracking(page)
    let writes = 0
    await page.route('**/api/v1/organizations/' + workspaceOrganizationId + '/saved-searches', async route => {
      expect(route.request().method()).toBe('POST')
      expect(route.request().headers()['idempotency-key']).toMatch(/^saved-search-/)
      expect(route.request().postDataJSON()).toMatchObject({ name: 'Agua Ñandú', query: 'agua', countryIds: [152], currency: 'USD' })
      writes++
      await route.fulfill({ status: 201, json: trackingSearchDetail })
    })
    await page.goto('/alerts?new=true&q=agua&countryIds=152&currency=USD')
    await page.getByLabel('Nombre', { exact: true }).fill('Agua Ñandú')
    await page.getByRole('checkbox').uncheck()
    await english(page)
    expect(writes).toBe(0)
    await page.getByRole('button', { name: 'Save', exact: true }).click()
    await expect(page.getByText('Search saved successfully.')).toBeVisible()
    expect(writes).toBe(1)
    await page.getByRole('combobox', { name: 'Language', exact: true }).selectOption('es')
    await expect(page.getByText('Búsqueda guardada correctamente.')).toBeVisible()
    expect(writes).toBe(1)
    await accessibility(page)
  })

  test('I18N04D pending checkout polls without language-triggered writes or plan activation', async ({ page }) => {
    await mockTracking(page)
    let reads = 0
    await page.route('**/api/v1/organizations/' + workspaceOrganizationId + '/subscription-checkouts/' + trackingCheckout.id, async route => {
      expect(route.request().method()).toBe('GET')
      reads++
      await route.fulfill({ json: { ...trackingCheckout, status: reads > 1 ? 'completed' : 'pending' } })
    })
    await page.goto('/subscription?checkout=' + trackingCheckout.id)
    await expect(page.getByText('Checkout: Pendiente de confirmación', { exact: true })).toBeVisible()
    await english(page)
    expect(reads).toBe(1)
    await expect(page.getByText('Checkout: Confirmed', { exact: true })).toBeVisible({ timeout: 10000 })
    expect(reads).toBe(2)
    await expect(page.getByText('Current plan', { exact: true })).toBeVisible()
    await expect(page.getByRole('button', { name: 'Try sandbox checkout' })).toBeVisible()
  })

  test('I18N04D load failure is localized, accessible and retryable without creating an organization', async ({ page }) => {
    await mockTracking(page)
    await page.route('**/api/v1/organizations', async route => {
      expect(route.request().method()).toBe('GET')
      await route.fulfill({ status: 503, json: { status: 503, title: 'PRIVATE-DIAGNOSTIC' } })
    })
    await page.goto('/subscription')
    await expect(page.getByRole('alert')).toContainText('No pudimos cargar tu organización.')
    await english(page)
    await expect(page.getByRole('alert')).toContainText('We could not load your organization.')
    await expect(page.getByRole('button', { name: 'Retry', exact: true })).toBeVisible()
    await expect(page.getByRole('link', { name: 'Get started', exact: true })).toHaveCount(0)
    await expect(page.getByText('PRIVATE-DIAGNOSTIC')).toHaveCount(0)
    await accessibility(page)
  })
}
