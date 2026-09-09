import { expect, test, type Page } from '@playwright/test'
import { english, fits, mockWorkspace } from './workspace-checks'
import { workspaceOrganizationId, workspaceProfile, workspaceProject, workspaceProjectId } from '../src/test/fixtures/project-workspace'

export function registerValidationTests(checkAccessibility: (page: Page) => Promise<void>) {
  for (const width of [320, 1024]) {
    for (const scope of ['organization', 'project'] as const) {
      test(`códigos API conservan errores y borrador de ${scope} a ${width}px`, async ({ page }) => {
        await mockWorkspace(page)
        await page.setViewportSize({ width, height: 900 })
        const organization = scope === 'organization'
        const path = organization ? '/organization/profile' : `/projects/${workspaceProjectId}`
        const endpoint = `/api/v1/organizations/${workspaceOrganizationId}/${organization ? 'profile' : `projects/${workspaceProjectId}`}`
        const field = organization ? 'name' : 'title'
        const code = organization ? 'name-length' : 'project-title-length'
        const es = organization ? 'El nombre es obligatorio y admite hasta 250 caracteres.' : 'El título debe tener entre 3 y 250 caracteres.'
        const en = organization ? 'Name is required and must not exceed 250 characters.' : 'The title must be between 3 and 250 characters.'
        const draft = 'Borrador privado Ñandú pendiente'
        const writes: { body: Record<string, unknown>; etag?: string }[] = []
        await page.route(`**${endpoint}`, async route => {
          if (route.request().method() === 'GET') return route.fallback()
          expect(route.request().method()).toBe('PUT')
          writes.push({ body: route.request().postDataJSON(), etag: route.request().headers()['if-match'] })
          await route.fulfill({ status: 400, json: {
            title: 'PRIVATE-DIAGNOSTIC', status: 400,
            errors: { [field]: ['PRIVATE-DIAGNOSTIC'] },
            validationIssues: { [field]: [{ code }] },
          } })
        })
        await page.goto(path)
        await page.getByLabel(organization ? /Nombre público/ : /Título/).fill(draft)
        await page.getByRole('button', { name: organization ? 'Guardar' : 'Guardar cambios', exact: true }).click()
        await expect(page.getByText(es, { exact: true })).toHaveCount(2)
        await english(page)
        await expect(page.getByText(en, { exact: true })).toHaveCount(2)
        await expect(page.getByLabel(organization ? /Public name/ : /Title/)).toHaveValue(draft)
        await expect(page.getByLabel(organization ? /Public name/ : /Title/)).toHaveAttribute('aria-invalid', 'true')
        await expect(page.getByText('PRIVATE-DIAGNOSTIC')).toHaveCount(0)
        await checkAccessibility(page)
        await fits(page)
        await page.getByRole('combobox', { name: 'Language', exact: true }).selectOption('es')
        await expect(page.getByText(es, { exact: true })).toHaveCount(2)
        await page.getByRole('combobox', { name: 'Cambiar tema', exact: true }).selectOption('dark')
        await checkAccessibility(page)
        await fits(page)
        expect(writes).toHaveLength(1)
        expect(writes[0].body[field]).toBe(draft)
        expect(writes[0].etag).toBe(organization ? workspaceProfile.eTag : workspaceProject.eTag)
      })
    }
  }
}
