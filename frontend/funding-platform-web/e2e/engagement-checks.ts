import { expect, test, type Page } from '@playwright/test'
import { english, fits, mockWorkspace, readOnlyJson } from './workspace-checks'
import { workspaceCatalogs, workspaceOrganizationId, workspaceProfile, workspaceProjectId } from '../src/test/fixtures/project-workspace'

const storyId = '61111111-1111-1111-1111-111111111111'
const story = {
  id: storyId, organizationId: workspaceOrganizationId, organizationName: workspaceProfile.name,
  projectTitle: null, projectSlug: null, status: 1, revision: 2, updatedAtUtc: '2026-09-22T00:00:00Z',
  content: { title: 'TEST · Aprendizajes del humedal', summary: 'Relato sintético para control de calidad.',
    body: 'La comunidad compartió aprendizajes sobre el cuidado del humedal y la protección de su biodiversidad.',
    kind: 'learning', projectId: null, categoryIds: [1], goalIds: [6], countryIds: [152], containsPersonalExperiences: false },
}

export function registerEngagementTests(accessibility: (page: Page) => Promise<void>) {
  for (const width of [320, 1280]) {
    test(`servicios y cotización sin cobro ES/EN a ${width}px`, async ({ page }) => {
      await page.setViewportSize({ width, height: 900 })
      await page.route('**/api/v1/marketplace/catalogs', readOnlyJson(workspaceCatalogs))
      await page.goto('/services')
      await expect(page.getByRole('heading', { name: 'Servicios profesionales', exact: true })).toBeVisible()
      await expect(page.getByRole('link', { name: 'Solicitar cotización', exact: true })).toHaveCount(7)
      await fits(page); await accessibility(page)
      await page.getByRole('article').filter({ has: page.getByRole('heading', { name: 'Traducción de proyectos y documentos', exact: true }) }).getByRole('link').click()
      await expect(page).toHaveURL('/contact?service=translation')
      await expect(page.getByRole('combobox', { name: 'Servicio *', exact: true })).toHaveValue('translation')
      await page.getByLabel('Nombre *', { exact: true }).fill('TEST · Ana')
      await english(page)
      await expect(page.getByLabel('Name *', { exact: true })).toHaveValue('TEST · Ana')
      await expect(page.getByRole('combobox', { name: 'Service *', exact: true })).toHaveValue('translation')
      await expect(page.getByRole('button', { name: 'Send request', exact: true })).toBeDisabled()
      await fits(page); await accessibility(page)
      await page.getByRole('combobox', { name: 'Change theme', exact: true }).selectOption('dark')
      await accessibility(page)
    })

    test(`contacto conserva clave en reintento y registra recibo privado a ${width}px`, async ({ page }) => {
      await page.setViewportSize({ width, height: 900 })
      await page.route('**/api/v1/marketplace/catalogs', readOnlyJson(workspaceCatalogs))
      const writes: Record<string, unknown>[] = []
      await page.route('**/api/v1/inquiries', async route => {
        expect(route.request().method()).toBe('POST')
        const data = route.request().postDataJSON(); writes.push(data)
        await route.fulfill(writes.length === 1 ? { status: 503, json: { title: 'PRIVATE DIAGNOSTIC', status: 503 } }
          : { json: { requestId: data.requestId, wasReplay: true } })
      })
      await page.goto('/contact')
      await page.getByLabel('Nombre *', { exact: true }).fill('TEST · Ana')
      await page.getByLabel('Correo electrónico *', { exact: true }).fill('test@example.invalid')
      await page.getByRole('combobox', { name: 'País *', exact: true }).selectOption('152')
      await page.getByLabel(/Describe tu necesidad/).fill('Quisiera orientación para mi proyecto sintético.')
      await page.getByRole('checkbox').check()
      await page.getByRole('button', { name: 'Enviar solicitud', exact: true }).click()
      await expect(page.getByRole('alert')).toContainText('No pudimos completar')
      await expect(page.getByText('PRIVATE DIAGNOSTIC', { exact: true })).toHaveCount(0)
      await page.getByRole('button', { name: 'Enviar solicitud', exact: true }).click()
      await expect(page.getByRole('heading', { name: 'Solicitud registrada', exact: true })).toBeVisible()
      expect(writes).toHaveLength(2); expect(writes[0].requestId).toBe(writes[1].requestId)
      expect(writes[0].organization).toBeNull(); expect(writes[0].projectReference).toBeNull()
      await fits(page); await accessibility(page)
    })

    test(`historias públicas relacionadas ES/EN a ${width}px`, async ({ page }) => {
      await page.setViewportSize({ width, height: 900 })
      await page.route('**/api/v1/marketplace/catalogs', readOnlyJson(workspaceCatalogs))
      await page.route('**/api/v1/stories?*', readOnlyJson({ items: [story], totalCount: 1, page: 1 }))
      await page.route(`**/api/v1/stories/${storyId}`, readOnlyJson(story))
      await page.goto('/stories')
      await page.getByRole('link', { name: 'Leer historia', exact: true }).click()
      await expect(page.getByRole('heading', { name: story.content.title, exact: true })).toBeVisible()
      await expect(page.getByRole('link', { name: workspaceProfile.name, exact: true })).toHaveAttribute('href', `/marketplace/organizations/${workspaceOrganizationId}`)
      await fits(page); await accessibility(page); await english(page)
      await expect(page.getByText('Lessons learned', { exact: true })).toBeVisible()
      await expect(page.getByText(story.content.body, { exact: true })).toBeVisible()
      await fits(page); await accessibility(page)
    })

    test(`historias de organización guardan y piden consentimiento a ${width}px`, async ({ page }) => {
      await mockWorkspace(page)
      await page.setViewportSize({ width, height: 900 })
      await page.route('**/api/v1/marketplace/catalogs', readOnlyJson(workspaceCatalogs))
      let saved: typeof story | undefined
      await page.route(`**/api/v1/organizations/${workspaceOrganizationId}/stories?*`, route => route.fulfill({ json: { items: saved ? [saved] : [], totalCount: saved ? 1 : 0, page: 1 } }))
      await page.route(`**/api/v1/organizations/${workspaceOrganizationId}/stories/*`, async route => {
        expect(route.request().method()).toBe('PUT')
        const data = route.request().postDataJSON()
        expect(data.expectedRevision).toBe(0); expect(data.content.projectId).toBe(workspaceProjectId)
        saved = { ...story, id: new URL(route.request().url()).pathname.split('/').pop()!, content: data.content, status: 0, revision: 1 }
        await route.fulfill({ status: 204 })
      })
      await page.goto('/organization/stories')
      await page.getByRole('combobox', { name: 'Organización', exact: true }).selectOption(workspaceOrganizationId)
      await page.getByRole('button', { name: 'Nueva historia', exact: true }).click()
      await page.getByLabel('Título *', { exact: true }).fill('TEST · Historia en terreno')
      await page.getByLabel('Historia *', { exact: true }).fill('Aprendizajes de nuestro trabajo con la comunidad local.')
      await page.getByRole('combobox', { name: 'Tipo de historia *', exact: true }).selectOption('beneficiaries')
      await page.getByRole('combobox', { name: 'Proyecto relacionado (opcional)', exact: true }).selectOption(workspaceProjectId)
      await fits(page); await accessibility(page)
      await page.getByRole('button', { name: 'Guardar borrador', exact: true }).click()
      const publish = page.getByRole('button', { name: 'Publicar historia', exact: true })
      await expect(publish).toBeDisabled()
      await page.getByLabel(/tiene autorización/).check(); await expect(publish).toBeDisabled()
      await page.getByLabel(/contamos con consentimiento/).check(); await expect(publish).toBeEnabled()
      await english(page); await expect(page.getByRole('button', { name: 'Publish story', exact: true })).toBeEnabled()
      await fits(page); await accessibility(page)
    })
  }
}
