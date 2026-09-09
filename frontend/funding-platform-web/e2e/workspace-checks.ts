import { expect, test, type Page, type Route } from '@playwright/test'
import { workspaceCatalogs, workspaceOrganizationId, workspaceProfile, workspaceProject, workspaceProjectId, workspacePublicProject } from '../src/test/fixtures/project-workspace'

// Registered inside public.spec.ts so its deny-by-default API guard also applies.
export function readOnlyJson(data: unknown) {
  return (route: Route) => {
    expect(route.request().method()).toBe('GET')
    return route.fulfill({ json: data })
  }
}

export async function mockWorkspace(page: Page, { empty = false, publicationStatus = 0, email = 'synthetic@example.invalid' } = {}) {
  await page.route('**/api/v1/auth/refresh', route => route.fulfill({
    json: {
      status: 'authenticated', accessToken: 'synthetic-ui-only', accessTokenExpiresAtUtc: new Date(Date.now() + 600_000).toISOString(),
      user: { publicId: '33333333-3333-3333-3333-333333333333', email, displayName: 'Prueba', preferredLocale: 'es-CL', roles: ['Professional'], mfaEnabled: false },
    },
  }))
  await page.route('**/api/v1/catalogs', readOnlyJson(workspaceCatalogs))
  await page.route('**/api/v1/organizations', readOnlyJson(empty ? [] : [{ ...workspaceProfile, updatedAtUtc: '2026-09-01T12:00:00Z' }]))
  await page.route(`**/api/v1/organizations/${workspaceOrganizationId}/profile`, readOnlyJson(workspaceProfile))
  await page.route(`**/api/v1/organizations/${workspaceOrganizationId}/projects`, readOnlyJson([{ ...workspaceProject, publicationStatus }]))
  await page.route(`**/api/v1/organizations/${workspaceOrganizationId}/projects/${workspaceProjectId}`, readOnlyJson({ ...workspaceProject, publicationStatus }))
  await page.route('**/api/v1/projects/proyecto-sintetico', readOnlyJson(workspacePublicProject))
}

export async function english(page: Page) {
  await page.getByRole('combobox', { name: 'Idioma', exact: true }).selectOption('en')
}

export async function fits(page: Page) {
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true)
}

export function registerWorkspaceLanguageTests(checkAccessibility: (page: Page) => Promise<void>) {
  for (const width of [320, 1024]) {
    test(`onboarding ES/EN accesible sin perder datos a ${width}px`, async ({ page }) => {
      await mockWorkspace(page, { empty: true })
      await page.setViewportSize({ width, height: 900 })
      await page.goto('/onboarding')
      await page.getByLabel(/Nombre público/).fill('Organización Ñandú')
      await english(page)
      await expect(page.getByRole('heading', { name: 'Create your organization’s workspace' })).toBeVisible()
      await expect(page.getByLabel(/Public name/)).toHaveValue('Organización Ñandú')
      await expect(page.getByRole('main')).not.toHaveAttribute('lang', 'es')
      await checkAccessibility(page)
      await fits(page)
    })

    test(`perfil de organización completo ES/EN a ${width}px`, async ({ page }) => {
      await mockWorkspace(page)
      await page.setViewportSize({ width, height: 900 })
      await page.goto('/organization/profile')
      await page.getByLabel(/Nombre público/).fill('Nombre editado Ñandú')
      await fits(page)
      await english(page)
      await expect(page.getByLabel(/Public name/)).toHaveValue('Nombre editado Ñandú')
      await checkAccessibility(page)
      await fits(page)
      await page.getByRole('button', { name: /Impact$/ }).click()
      await expect(page.getByText('Cultura Ñandú')).toBeVisible()
      await expect(page.getByText('Environment', { exact: true })).toHaveAttribute('lang', 'en')
      await checkAccessibility(page)
      await fits(page)
      await page.getByRole('button', { name: /Funding$/ }).click()
      await page.getByLabel(/Usual range/).selectOption('100k-500k')
      await expect(page.getByLabel(/Minimum funding/)).toHaveValue('100000')
      await checkAccessibility(page)
      await fits(page)
      await page.getByRole('combobox', { name: 'Language', exact: true }).selectOption('es')
      await expect(page.getByLabel(/Rango habitual/)).toHaveValue('100k-500k')
      await fits(page)
      await page.getByRole('combobox', { name: 'Cambiar tema', exact: true }).selectOption('dark')
      await checkAccessibility(page)
    })

    test(`edición de proyectos ES/EN conserva borrador a ${width}px`, async ({ page }) => {
      await mockWorkspace(page)
      await page.setViewportSize({ width, height: 900 })
      await page.goto(`/projects/${workspaceProjectId}`)
      await page.getByLabel(/Título/).fill('Título editado Ñandú')
      await page.getByLabel('Etapa del proyecto').selectOption('3')
      await english(page)
      await expect(page.getByLabel(/Title/)).toHaveValue('Título editado Ñandú')
      await expect(page.getByLabel('Project stage')).toHaveValue('3')
      await expect(page.getByRole('button', { name: 'Submit for review' })).toBeDisabled()
      await expect(page.getByRole('main')).not.toHaveAttribute('lang', 'es')
      await checkAccessibility(page)
      await fits(page)
      await page.getByRole('combobox', { name: 'Change theme', exact: true }).selectOption('dark')
      await checkAccessibility(page)
    })

    test(`ficha pública de proyecto ES/EN conserva fuente y fechas a ${width}px`, async ({ page }) => {
      await mockWorkspace(page)
      await page.setViewportSize({ width, height: 900 })
      await page.goto('/projects/public/proyecto-sintetico')
      await english(page)
      await expect(page.getByRole('heading', { name: 'About the project' })).toBeVisible()
      await expect(page.getByRole('heading', { name: workspaceProject.title })).toBeVisible()
      await expect(page.getByText('January 1, 2027 — December 31, 2027')).toBeVisible()
      await expect(page.getByText('$75,000.00')).toBeVisible()
      await expect(page.getByText('Clean Water and Sanitation')).toHaveAttribute('lang', 'en')
      await checkAccessibility(page)
      await fits(page)
    })
  }

  test('formulario de proyecto nuevo valida en ambos idiomas sin publicar', async ({ page }) => {
    await mockWorkspace(page)
    await page.goto('/projects')
    await english(page)
    await page.getByRole('button', { name: 'New project' }).click()
    await page.getByRole('button', { name: 'Create project' }).click()
    await expect(page.getByText('Enter the project title.')).toBeVisible()
    await page.getByRole('combobox', { name: 'Language', exact: true }).selectOption('es')
    await expect(page.getByText('Ingresa el título del proyecto.')).toBeVisible()
    await checkAccessibility(page)
  })
}
