import { expect, test, type Page } from '@playwright/test'
import { english, fits } from './workspace-checks'
import { editorialCatalogs, editorialFunder, editorialOpportunity, editorialProject, editorialProjectQueueItem } from '../src/test/fixtures/editorial-workspace'
import type { PublicationStatus } from '../src/features/funding/admin-funding-api'

// Exact synthetic routes only. public.spec.ts aborts every other API request.
async function mockEditorial(page: Page, status: PublicationStatus = 0) {
  await page.route('**/api/v1/auth/refresh', route => route.fulfill({
    json: {
      status: 'authenticated', accessToken: 'synthetic-ui-only', accessTokenExpiresAtUtc: new Date(Date.now() + 600_000).toISOString(),
      user: { publicId: '33333333-3333-3333-3333-333333333333', email: 'editorial@example.invalid', displayName: 'Admin Ñandú', preferredLocale: 'es-CL', roles: ['Admin'], mfaEnabled: false },
    },
  }))
  let reads = 0
  const item = editorialOpportunity({ publicationStatus: status })
  const funder = editorialFunder()
  const fixtures: [string, unknown][] = [
    ['catalogs', editorialCatalogs],
    ['admin/funding-sources', [{ id: 7, name: 'Manual editorial', providerType: 0, isEnabled: true, baseUrl: null }]],
    ['admin/funders/' + funder.funderId, funder],
    ['admin/funders?*', { items: [funder], totalCount: 41, page: 1, pageSize: 20 }],
    ['admin/funding-opportunities/' + item.opportunityId, item],
    ['admin/funding-opportunities?*', { items: [item], totalCount: 41, page: 1, pageSize: 20 }],
    ['admin/projects/review-queue?*', { items: [editorialProjectQueueItem], totalCount: 41, page: 1, pageSize: 20 }],
    ['admin/projects/' + editorialProject.projectId, editorialProject],
  ]
  for (const [path, data] of fixtures) await page.route('**/api/v1/' + path, route => {
    expect(route.request().method()).toBe('GET')
    reads++
    return route.fulfill({ json: data })
  })
  return () => reads
}

export function registerEditorialTests(accessibility: (page: Page) => Promise<void>) {
  async function bothThemes(page: Page) {
    await accessibility(page)
    const overflow = await page.locator('main *').evaluateAll(elements => elements.filter(element => {
      const rect = element.getBoundingClientRect()
      return rect.width > 0 && rect.right > window.innerWidth + 1
    }).slice(0, 12).map(element => ({ tag: element.tagName, name: element.getAttribute('name'), classes: element.className, width: element.getBoundingClientRect().width })))
    expect(overflow, 'Editorial content must fit without horizontal scrolling').toEqual([])
    await fits(page)
    await page.getByRole('combobox', { name: 'Change theme', exact: true }).selectOption('dark')
    await accessibility(page)
    await fits(page)
  }

  for (const width of [320, 1024]) {
    test(`I18N05C funder creation keeps draft and visible errors at ${width}px`, async ({ page }) => {
      const reads = await mockEditorial(page)
      await page.setViewportSize({ width, height: 900 })
      await page.goto('/admin/funders/new')
      await page.getByRole('textbox', { name: 'Alias conocidos' }).fill('Alias Ñandú, Fundación Original')
      await page.getByRole('button', { name: 'Crear financiador' }).click()
      await expect(page.getByRole('alert')).toHaveText('El nombre debe tener al menos 2 caracteres.')
      const before = reads()
      await english(page)
      await expect(page.getByRole('alert')).toHaveText('The name must contain at least 2 characters.')
      await expect(page.getByRole('textbox', { name: 'Known aliases' })).toHaveValue('Alias Ñandú, Fundación Original')
      await expect(page.getByRole('main')).not.toHaveAttribute('lang', 'es')
      await bothThemes(page)
      await page.getByRole('combobox', { name: 'Language', exact: true }).selectOption('es')
      await expect(page.getByRole('alert')).toHaveText('El nombre debe tener al menos 2 caracteres.')
      expect(reads()).toBe(before)
    })

    test(`I18N05C funding editor retains IDs money dates and dirty state at ${width}px`, async ({ page }) => {
      const reads = await mockEditorial(page)
      await page.setViewportSize({ width, height: 900 })
      await page.goto('/admin/funding/' + editorialOpportunity().opportunityId)
      await page.getByRole('textbox', { name: 'Título', exact: true }).fill('Edición original Ñandú')
      await expect(page.getByRole('combobox', { name: 'Rol', exact: true })).toHaveValue('1')
      const before = reads()
      await english(page)
      await expect(page.getByRole('textbox', { name: 'Title', exact: true })).toHaveValue('Edición original Ñandú')
      await expect(page.getByRole('combobox', { name: 'Currency', exact: true })).toHaveValue('USD')
      await expect(page.getByRole('combobox', { name: 'Geographic scope', exact: true })).toHaveValue('1')
      await expect(page.getByRole('checkbox', { name: 'Chile', exact: true })).toBeChecked()
      await expect(page.getByRole('checkbox', { name: 'Health', exact: true })).toBeChecked()
      await expect(page.getByRole('combobox', { name: 'Role', exact: true })).toHaveValue('1')
      await expect(page.getByRole('option', { name: 'Subvención con aporte', exact: true })).toHaveAttribute('lang', 'es')
      await expect(page.getByLabel(/Exact closing time/)).toHaveValue('2027-02-01T02:59:59.123')
      await expect(page.getByRole('button', { name: 'Submit for review' })).toBeDisabled()
      await bothThemes(page)
      expect(reads()).toBe(before)
    })

    test(`I18N05C readiness error is translated without another submission at ${width}px`, async ({ page }) => {
      await mockEditorial(page)
      let writes = 0
      await page.route('**/api/v1/admin/funding-opportunities/' + editorialOpportunity().opportunityId + '/submit-review', route => {
        writes++
        expect(route.request().method()).toBe('POST')
        expect(route.request().headers()['if-match']).toBe(editorialOpportunity().eTag)
        expect(route.request().headers()['idempotency-key']).toMatch(/^[0-9a-f-]{36}$/i)
        return route.fulfill({ status: 422, json: {
          type: 'https://fundingplatform.local/problems/opportunity-not-ready', title: 'PRIVATE SQL DETAIL',
          errors: { readiness: ['A published primary funder is required.', 'Unknown geographic scope cannot be published.', 'PRIVATE SQL DETAIL'] },
        } })
      })
      await page.setViewportSize({ width, height: 900 })
      await page.goto('/admin/funding/' + editorialOpportunity().opportunityId)
      await page.getByRole('button', { name: 'Enviar a revisión' }).click()
      await expect(page.getByRole('alert')).toContainText('Publica el financiador principal')
      await english(page)
      await expect(page.getByRole('alert')).toContainText('Publish the primary funder')
      await expect(page.getByRole('alert')).toContainText('Set the geographic scope to specific or global.')
      await expect(page.getByText('PRIVATE SQL DETAIL')).toHaveCount(0)
      await expect(page.getByRole('link', { name: 'Correct funder and scope' })).toHaveAttribute('href', '#financiadores-alcance')
      await bothThemes(page)
      expect(writes).toBe(1)
    })

    test(`I18N05C published funder correction remains explicit at ${width}px`, async ({ page }) => {
      await mockEditorial(page)
      await page.setViewportSize({ width, height: 900 })
      await page.goto('/admin/funders/' + editorialFunder().funderId)
      await expect(page.getByRole('textbox', { name: 'Nombre', exact: true })).toBeDisabled()
      await english(page)
      await expect(page.getByRole('textbox', { name: 'Name', exact: true })).toBeDisabled()
      await bothThemes(page)
      await page.getByRole('button', { name: 'Correct publication' }).click()
      const dialog = page.getByRole('dialog', { name: 'Start editorial correction' })
      await expect(dialog).toContainText('temporarily remove the funder from the public catalog')
      await expect(dialog.getByRole('button', { name: 'Withdraw and start correction' })).toBeDisabled()
      await dialog.getByRole('textbox').fill('Corregir enlace Ñandú')
      await expect(dialog.getByRole('button', { name: 'Withdraw and start correction' })).toBeEnabled()
      await accessibility(page)
      await fits(page)
      await dialog.getByRole('button', { name: 'Cancel' }).click()
      await expect(dialog).toHaveCount(0)
      await expect(page.getByText('This content is visible in the public catalog.')).toBeVisible()
    })

    test(`I18N05C editorial lists keep filters and pagination at ${width}px`, async ({ page }) => {
      await mockEditorial(page)
      await page.setViewportSize({ width, height: 900 })
      await page.goto('/admin/funding')
      await page.getByRole('textbox', { name: 'Buscar oportunidades' }).fill('consulta Ñandú')
      await page.getByRole('combobox', { name: 'Filtrar por estado' }).selectOption('1')
      await english(page)
      await expect(page.getByRole('textbox', { name: 'Search opportunities' })).toHaveValue('consulta Ñandú')
      await expect(page.getByRole('combobox', { name: 'Filter by status' })).toHaveValue('1')
      await expect(page.getByText('Closing Jan 31, 2027')).toBeVisible()
      await bothThemes(page)
      await page.goto('/admin/funders')
      await expect(page.getByRole('heading', { name: 'Funders', exact: true })).toBeVisible()
      await expect(page.getByText('Page 1 of 3')).toBeVisible()
      await accessibility(page)
      await fits(page)
    })

    test(`I18N05C project review keeps original content and unsent reason at ${width}px`, async ({ page }) => {
      await mockEditorial(page)
      await page.setViewportSize({ width, height: 900 })
      await page.goto('/admin/projects')
      await english(page)
      await expect(page.getByRole('heading', { name: 'Pending projects' })).toBeVisible()
      await expect(page.getByText('87% complete')).toBeVisible()
      await bothThemes(page)
      await page.getByRole('link', { name: 'Review full project' }).click()
      await expect(page.getByRole('heading', { name: editorialProject.title })).toBeVisible()
      await page.getByRole('textbox', { name: 'Reason for requesting corrections' }).fill('Borrador sin enviar Ñandú')
      await expect(page.getByText('Environment', { exact: true })).toHaveAttribute('lang', 'en')
      await expect(page.getByText(editorialProject.description!, { exact: true })).toBeVisible()
      await accessibility(page)
      await fits(page)
      await page.getByRole('combobox', { name: 'Language', exact: true }).selectOption('es')
      await expect(page.getByRole('textbox', { name: 'Motivo si solicitas correcciones' })).toHaveValue('Borrador sin enviar Ñandú')
    })
  }
}
