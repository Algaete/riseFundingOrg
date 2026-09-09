import { expect, test, type Page } from '@playwright/test'
import { dashboardApplications, dashboardCalendar, dashboardOrganizations } from '../src/test/fixtures/dashboard-workspace'
import { workspaceProject } from '../src/test/fixtures/project-workspace'
import { english, fits, mockWorkspace, readOnlyJson } from './workspace-checks'

async function mockDashboard(page: Page, partial: boolean) {
  await mockWorkspace(page)
  const reads: string[] = []
  await page.route('**/api/v1/organizations', readOnlyJson(dashboardOrganizations))
  await page.route('**/api/v1/organizations/*/*', async route => {
    expect(route.request().method()).toBe('GET')
    const url = new URL(route.request().url())
    reads.push(`${url.pathname}${url.search}`)
    const id = url.pathname.split('/').at(-2)
    expect(dashboardOrganizations.map(item => item.publicId)).toContain(id)
    const module = url.pathname.split('/').at(-1)
    if (module === 'projects') return route.fulfill({ json: [workspaceProject] })
    if (module === 'applications') {
      expect(url.searchParams.get('pageSize')).toBe('5')
      return route.fulfill({ json: dashboardApplications })
    }
    if (module === 'calendar') return partial
      ? route.fulfill({ status: 503, json: { title: 'Synthetic failure', status: 503 } })
      : route.fulfill({ json: dashboardCalendar })
    expect(module).toBe('saved-searches')
    return route.fulfill({ json: { items: [], totalCount: 2, page: 1, pageSize: 1 } })
  })
  return reads
}

// Registered under the public suite's deny-by-default API request guard.
export function registerDashboardAccountLanguageTests(checkAccessibility: (page: Page) => Promise<void>) {
  for (const width of [320, 1024]) {
    for (const partial of [false, true]) {
      test(`resumen ES/EN ${partial ? 'parcial' : 'completo'} conserva contexto a ${width}px`, async ({ page }) => {
        const reads = await mockDashboard(page, partial)
        const id = dashboardOrganizations[1].publicId
        await page.setViewportSize({ width, height: 900 })
        await page.goto(`/dashboard?organizationId=${id}&keep=original`)
        await expect(page.getByText('Fondo Agua Ñandú', { exact: true })).toBeVisible()
        await expect(page.getByRole('button', { name: 'Actualizar', exact: true })).toBeEnabled()
        await fits(page)
        const beforeLanguage = [...reads]
        await english(page)
        await expect(page.getByRole('heading', { name: 'Overview', exact: true })).toBeVisible()
        await expect(page.getByRole('combobox', { name: 'Overview organization' })).toHaveValue(id)
        await expect(page.getByText('1,234')).toBeVisible()
        await expect(page.getByText('Agua segura Ñandú · Preparing application')).toBeVisible()
        await expect(page.getByRole('link', { name: 'View all applications' })).toHaveAttribute('href', `/applications?organizationId=${id}`)
        await expect(page.getByRole('main')).not.toHaveAttribute('lang', 'es')
        if (partial) await expect(page.getByRole('status')).toHaveText('One metric could not be refreshed. The remaining data is still available.')
        else await expect(page.getByText('Sep 20, 2026')).toBeVisible()
        await checkAccessibility(page)
        await fits(page)
        await page.getByRole('combobox', { name: 'Change theme', exact: true }).selectOption('dark')
        await checkAccessibility(page)
        expect(reads).toEqual(beforeLanguage)
        expect(new URL(page.url()).searchParams.get('keep')).toBe('original')
        await page.getByRole('combobox', { name: 'Language', exact: true }).selectOption('es')
        await expect(page.getByRole('combobox', { name: 'Organización del resumen' })).toHaveValue(id)
        expect(reads).toEqual(beforeLanguage)
      })
    }

    for (const enabled of [false, true]) {
      test(`Mi cuenta ES/EN con SSO ${enabled ? 'habilitado simulado' : 'apagado'} a ${width}px`, async ({ page }) => {
        const email = 'synthetic.long.account.name@example.invalid'
        await mockWorkspace(page, { email })
        let providerReads = 0
        await page.route('**/api/v1/auth/external/providers', route => {
          providerReads++
          return readOnlyJson([{ code: 'entra', displayName: 'Microsoft', enabled }])(route)
        })
        await page.setViewportSize({ width, height: 900 })
        await page.goto('/account?sso=link_failed')
        await expect(page.getByRole('heading', { name: 'Mi cuenta' })).toBeVisible()
        if (enabled) await expect(page.getByRole('button', { name: `Vincular Microsoft a ${email}` })).toBeEnabled()
        else await expect(page.getByText('Microsoft SSO está preparado, pendiente de configurar en Entra.')).toBeVisible()
        await fits(page)
        await english(page)
        await expect(page.getByRole('heading', { name: 'My account' })).toBeVisible()
        await expect(page.getByText(email, { exact: true })).toBeVisible()
        await expect(page.getByRole('alert')).toHaveText('We could not link Microsoft. Check whether you selected the correct personal or work account.')
        if (enabled) await expect(page.getByRole('button', { name: `Link Microsoft to ${email}` })).toBeEnabled()
        else await expect(page.getByRole('button', { name: /Link Microsoft/ })).toHaveCount(0)
        await expect(page.getByRole('main')).not.toHaveAttribute('lang', 'es')
        await checkAccessibility(page)
        await fits(page)
        await page.getByRole('combobox', { name: 'Change theme', exact: true }).selectOption('dark')
        await checkAccessibility(page)
        expect(providerReads).toBe(1)
        // Any link-intent request would fail the inherited API guard.
      })
    }
  }

  test('Mi cuenta distingue fallo de consulta y reintenta sólo la lectura ES/EN', async ({ page }) => {
    await mockWorkspace(page)
    let providerReads = 0
    await page.route('**/api/v1/auth/external/providers', route => {
      expect(route.request().method()).toBe('GET')
      providerReads++
      return providerReads === 1
        ? route.fulfill({ status: 503, json: { title: 'Synthetic error', status: 503 } })
        : readOnlyJson([])(route)
    })
    await page.setViewportSize({ width: 320, height: 900 })
    await page.goto('/account')
    await expect(page.getByRole('alert')).toHaveText('No pudimos comprobar si Microsoft está habilitado. Intenta nuevamente.')
    await english(page)
    await expect(page.getByRole('alert')).toHaveText('We could not check whether Microsoft is enabled. Try again.')
    await expect(page.getByText(/awaiting configuration/)).toHaveCount(0)
    await checkAccessibility(page)
    expect(providerReads).toBe(1)
    await page.getByRole('button', { name: 'Retry' }).click()
    await expect(page.getByText('Microsoft SSO is prepared and awaiting configuration in Entra.')).toBeVisible()
    expect(providerReads).toBe(2)
    await fits(page)
  })
}
