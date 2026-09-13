import { expect, test, type Page } from '@playwright/test'
import { mockWorkspace, english, fits, readOnlyJson } from './workspace-checks'
import { workspaceOrganizationId, workspaceProjectId } from '../src/test/fixtures/project-workspace'
import type { ConsortiumDetails, OwnProfessional } from '../src/features/collaboration/collaboration-api'

const consortiumId = 'c1111111-1111-1111-1111-111111111111'
const participantId = 'd1111111-1111-1111-1111-111111111111'
const profileId = 'e1111111-1111-1111-1111-111111111111'
const firstTag = '"0102030405060708"'
const nextTag = '"1112131415161718"'
function fixture(owner = true): ConsortiumDetails {
  return { consortium: { consortiumId, projectId: workspaceProjectId, projectTitle: 'Proyecto Ñandú', projectSlug: 'proyecto-sintetico',
    projectIsPublic: true, name: 'Consorcio Ñandú', summary: 'Alianza de datos y territorio.', leadOrganizationId: workspaceOrganizationId,
    leadOrganizationName: 'Fundación Ñandú', status: 0, canManage: owner, canViewRoster: owner, hasPendingInvitation: !owner,
    acceptedCount: 0, eTag: firstTag, updatedAtUtc: '2026-09-01T00:00:00Z' },
    participants: [{ participantId, kind: 2, targetId: profileId, displayName: 'Profesional Ñandú', contribution: 'Análisis territorial',
      message: 'Queremos colaborar en el proyecto.', status: 0, canRespond: !owner, canLeave: false, canCancel: owner,
      canRemove: false, eTag: firstTag, updatedAtUtc: '2026-09-01T00:00:00Z' }] }
}
async function mockConsortium(page: Page, owner = true) {
  await mockWorkspace(page, { empty: !owner })
  const data = fixture(owner)
  const writes: { body: Record<string, unknown>; headers: Record<string, string>; path: string }[] = []
  await page.route('**/api/v1/consortia?*', readOnlyJson({ items: [data.consortium], totalCount: 1, page: 1, pageSize: 20 }))
  await page.route('**/api/v1/professionals?*', readOnlyJson({ items: [{ profileId, data: { displayName: 'Profesional Ñandú', headline: 'Ingeniería', biography: null, skills: ['GIS'], countryId: null, languageIds: [], categoryIds: [], isDiscoverable: true, allowsInvitations: true } }], totalCount: 1, page: 1, pageSize: 20 }))
  await page.route(`**/api/v1/organizations/${workspaceOrganizationId}/network/connections?*`, readOnlyJson({ items: [], totalCount: 0, page: 1, pageSize: 20 }))
  await page.route('**/api/v1/consortia', async route => {
    expect(route.request().method()).toBe('POST')
    writes.push({ body: route.request().postDataJSON(), headers: route.request().headers(), path: 'create' })
    await route.fulfill({ status: 201, json: { entityId: consortiumId, eTag: firstTag, wasReplay: false } })
  })
  await page.route(`**/api/v1/consortia/${consortiumId}**`, async route => {
    const request = route.request()
    if (request.method() === 'GET') return route.fulfill({ json: data })
    const body = request.postDataJSON()
    writes.push({ body, headers: request.headers(), path: new URL(request.url()).pathname })
    if (request.method() === 'PUT') Object.assign(data.consortium, body, { eTag: nextTag })
    else if (request.method() === 'PATCH') {
      Object.assign(data.participants[0], { status: body.action, canRespond: false, canLeave: body.action === 1, eTag: nextTag })
      Object.assign(data.consortium, { hasPendingInvitation: false, canViewRoster: body.action === 1, acceptedCount: body.action === 1 ? 1 : 0, eTag: nextTag })
    } else {
      expect(request.method()).toBe('POST')
      data.consortium.eTag = nextTag
    }
    return route.fulfill({ json: { entityId: request.method() === 'PUT' ? consortiumId : participantId, eTag: nextTag, wasReplay: false } })
  })
  return { writes, data }
}
export function registerCollaborationTests(accessibility: (page: Page) => Promise<void>) {
  for (const width of [320, 1024]) {
    test(`colaboración lista nula permite crear el primer consorcio ES/EN a ${width}px`, async ({ page }) => {
      const { writes } = await mockConsortium(page)
      const errors: string[] = []
      page.on('pageerror', error => errors.push(error.message))
      await page.route('**/api/v1/consortia?*', readOnlyJson({ items: null, totalCount: 0, page: 1, pageSize: 20 }))
      await page.setViewportSize({ width, height: 900 })
      await page.goto('/collaboration/consortia')
      await expect(page.getByText('No hay resultados.', { exact: true })).toBeVisible()
      await page.getByRole('combobox', { name: 'Organización coordinadora *', exact: true }).selectOption(workspaceOrganizationId)
      await page.getByRole('combobox', { name: 'Proyecto *', exact: true }).selectOption(workspaceProjectId)
      await page.getByLabel('Nombre del consorcio *', { exact: true }).fill('TEST · Primer consorcio')
      await english(page)
      await expect(page.getByText('No results.', { exact: true })).toBeVisible()
      await accessibility(page); await fits(page)
      await page.getByRole('button', { name: 'Create consortium', exact: true }).click()
      await expect(page).toHaveURL(new RegExp(`/collaboration/consortia/${consortiumId}$`))
      expect(writes).toHaveLength(1)
      expect(writes[0].body.name).toBe('TEST · Primer consorcio')
      expect(errors).toEqual([])
    })

    test(`colaboración detalle sin participantes ni candidatos no se rompe a ${width}px`, async ({ page }) => {
      const { writes, data } = await mockConsortium(page)
      const errors: string[] = []
      page.on('pageerror', error => errors.push(error.message))
      await page.route(`**/api/v1/consortia/${consortiumId}`, readOnlyJson({ ...data, participants: null }))
      await page.route(`**/api/v1/organizations/${workspaceOrganizationId}/network/connections?*`, readOnlyJson({ items: null, totalCount: 0, page: 1, pageSize: 20 }))
      await page.route('**/api/v1/professionals?*', readOnlyJson({ items: null, totalCount: 0, page: 1, pageSize: 20 }))
      await page.setViewportSize({ width, height: 900 })
      await page.goto(`/collaboration/consortia/${consortiumId}`)
      await expect(page.getByRole('heading', { name: 'Participantes', exact: true })).toBeVisible()
      await expect(page.getByText(/No hay destinatarios disponibles/)).toBeVisible()
      await page.getByRole('combobox', { name: 'Destinatario', exact: true }).selectOption('2')
      await expect(page.getByText(/No hay destinatarios disponibles/)).toBeVisible()
      await english(page)
      await expect(page.getByText(/No recipients are available/)).toBeVisible()
      await accessibility(page); await fits(page)
      expect(writes).toHaveLength(0)
      expect(errors).toEqual([])
    })

    test(`colaboración perfil opt-in y opcionales ES/EN a ${width}px`, async ({ page }) => {
      await mockWorkspace(page, { empty: true })
      await page.setViewportSize({ width, height: 900 })
      let profile: OwnProfessional | null = null
      const writes: { body: Record<string, unknown>; headers: Record<string, string> }[] = []
      await page.route('**/api/v1/me/professional-profile', route => {
        if (route.request().method() === 'GET') return route.fulfill({ json: profile })
        const body = route.request().postDataJSON()
        writes.push({ body, headers: route.request().headers() })
        profile = { profileId, data: body, eTag: nextTag, updatedAtUtc: '2026-09-01T00:00:00Z' }
        return route.fulfill({ json: { entityId: profileId, eTag: nextTag, wasReplay: false } })
      })
      await page.goto('/professional/profile')
      await page.getByRole('button', { name: 'Guardar', exact: true }).click()
      await expect(page.getByRole('alert')).toContainText('Completa el nombre')
      expect(writes).toHaveLength(0)
      await page.getByLabel('Nombre público *', { exact: true }).fill('Nombre Ñandú')
      await page.getByLabel('Especialidad o presentación breve *', { exact: true }).fill('Ingeniería social')
      await english(page)
      await expect(page.getByLabel('Public name *', { exact: true })).toHaveValue('Nombre Ñandú')
      await expect(page.getByLabel('Allow consortium invitations', { exact: true })).toBeDisabled()
      await expect(page.getByRole('main')).not.toHaveAttribute('lang', 'es')
      await page.getByRole('button', { name: 'Save', exact: true }).click()
      await expect(page.getByRole('status')).toContainText('Changes saved.')
      expect(writes).toHaveLength(1)
      expect(writes[0].headers['if-none-match']).toBe('*')
      expect(writes[0].body.isDiscoverable).toBe(false)
      expect(writes[0].body.biography).toBeNull()
      await page.getByLabel('Show my profile in the directory', { exact: true }).check()
      await page.getByLabel('Allow consortium invitations', { exact: true }).check()
      await page.getByRole('button', { name: 'Save', exact: true }).click()
      await expect.poll(() => writes.length).toBe(2)
      expect(writes[1].headers['if-match']).toBe(nextTag)
      expect(writes[1].body.allowsInvitations).toBe(true)
      await accessibility(page); await fits(page)
    })
    test(`colaboración invitación requiere confirmación y conserva borrador ES/EN a ${width}px`, async ({ page }) => {
      const { writes } = await mockConsortium(page)
      await page.setViewportSize({ width, height: 900 })
      await page.goto(`/collaboration/consortia/${consortiumId}?professionalId=${profileId}`)
      await page.getByLabel('Aporte esperado *', { exact: true }).fill('Datos territoriales')
      await page.getByLabel('Mensaje de invitación *', { exact: true }).fill('Colaboremos en datos territoriales.')
      await english(page)
      await expect(page.getByLabel('Expected contribution *', { exact: true })).toHaveValue('Datos territoriales')
      expect(writes).toHaveLength(0)
      await page.getByRole('button', { name: 'Send invitation', exact: true }).click()
      await expect(page.getByText('Invitation sent.', { exact: true })).toBeVisible()
      expect(writes).toHaveLength(1)
      expect(writes[0].body.targetId).toBe(profileId)
      expect(writes[0].body.kind).toBe(2)
      expect(writes[0].headers['if-match']).toBe(firstTag)
      expect(writes[0].headers['idempotency-key']).toBeTruthy()
      await accessibility(page); await fits(page)
    })
    test(`colaboración receptor acepta sin acceso a gestión a ${width}px`, async ({ page }) => {
      const { writes } = await mockConsortium(page, false)
      await page.setViewportSize({ width, height: 900 })
      await page.goto(`/collaboration/consortia/${consortiumId}`)
      await expect(page.getByText('Hasta aceptar la invitación solo puedes ver tu propia participación, no la lista de integrantes.')).toBeVisible()
      await expect(page.getByRole('button', { name: 'Enviar invitación' })).toHaveCount(0)
      await expect(page.getByRole('textbox', { name: 'Nombre del consorcio *' })).toHaveCount(0)
      await page.getByRole('button', { name: 'Aceptar', exact: true }).click()
      expect(writes).toHaveLength(0)
      await english(page)
      await page.getByRole('button', { name: 'Confirm', exact: true }).click()
      await expect(page.getByRole('button', { name: 'Leave consortium', exact: true })).toBeVisible()
      expect(writes).toHaveLength(1)
      expect(writes[0].body.action).toBe(1)
      expect(writes[0].headers['if-match']).toBe(firstTag)
      await accessibility(page); await fits(page)
      await page.getByRole('combobox', { name: 'Change theme', exact: true }).selectOption('dark')
      await accessibility(page)
    })
    test(`colaboración crea consorcio y no activa sin aceptaciones a ${width}px`, async ({ page }) => {
      const { writes } = await mockConsortium(page)
      await page.setViewportSize({ width, height: 900 })
      await page.goto('/collaboration/consortia')
      await page.getByRole('combobox', { name: 'Organización coordinadora *', exact: true }).selectOption(workspaceOrganizationId)
      await page.getByRole('combobox', { name: 'Proyecto *', exact: true }).selectOption(workspaceProjectId)
      await page.getByLabel('Nombre del consorcio *', { exact: true }).fill('Alianza Ñandú')
      await english(page)
      await page.getByRole('button', { name: 'Create consortium', exact: true }).click()
      await expect(page).toHaveURL(new RegExp(`/collaboration/consortia/${consortiumId}$`))
      expect(writes).toHaveLength(1)
      expect(writes[0].body.projectId).toBe(workspaceProjectId)
      await expect(page.getByRole('combobox', { name: 'Status', exact: true }).locator('option[value="1"]')).toHaveJSProperty('disabled', true)
      await page.getByRole('combobox', { name: 'Status', exact: true }).selectOption('2')
      await page.getByRole('button', { name: 'Save', exact: true }).click()
      expect(writes).toHaveLength(1)
      await page.getByRole('button', { name: 'Confirm', exact: true }).click()
      await expect(page.getByRole('combobox', { name: 'Status', exact: true })).toHaveCount(0)
      expect(writes).toHaveLength(2)
      expect(writes[1].body.status).toBe(2)
      await accessibility(page); await fits(page)
    })
  }
  test('colaboración invita organizaciones conectadas con consentimiento separado', async ({ page }) => {
    const { writes } = await mockConsortium(page)
    const organizationId = 'f1111111-1111-1111-1111-111111111111'
    await page.route(`**/api/v1/organizations/${workspaceOrganizationId}/network/connections?*`, route => {
      expect(new URL(route.request().url()).searchParams.get('status')).toBe('accepted')
      return route.fulfill({ json: { items: [{ status: 'accepted', counterpartyIsPublic: true, counterpartyOrganizationId: organizationId, counterpartyOrganizationName: 'Organización aliada' }], totalCount: 1, page: 1, pageSize: 20 } })
    })
    await page.goto(`/collaboration/consortia/${consortiumId}`)
    await page.getByRole('combobox', { name: 'Destinatario *', exact: true }).selectOption(organizationId)
    await page.getByLabel('Aporte esperado *', { exact: true }).fill('Capacidad territorial')
    await page.getByLabel('Mensaje de invitación *', { exact: true }).fill('Colaboremos en capacidades territoriales.')
    expect(writes).toHaveLength(0)
    await page.getByRole('button', { name: 'Enviar invitación', exact: true }).click()
    await expect(page.getByText('Invitación enviada.', { exact: true })).toBeVisible()
    expect(writes[0].body.kind).toBe(1)
    expect(writes[0].body.targetId).toBe(organizationId)
    expect(writes[0].body).not.toHaveProperty('status')
    await accessibility(page)
  })
  test('colaboración mantiene borrador ante conflicto y no muestra texto privado del servidor', async ({ page }) => {
    await mockWorkspace(page, { empty: true })
    const writes: Record<string, string>[] = []
    await page.route('**/api/v1/me/professional-profile', route => {
      if (route.request().method() === 'GET') return route.fulfill({ json: null })
      writes.push(route.request().headers())
      return route.fulfill({ status: 412, json: { title: 'private database text', detail: 'private database text', status: 412, type: 'https://fundingplatform.local/problems/collaboration-version-conflict' } })
    })
    await page.goto('/professional/profile')
    await page.getByLabel('Nombre público *', { exact: true }).fill('Borrador Ñandú')
    await page.getByLabel('Especialidad o presentación breve *', { exact: true }).fill('Experiencia social')
    await page.getByRole('button', { name: 'Guardar', exact: true }).click()
    await expect(page.getByRole('alert')).toContainText('La información cambió.')
    await english(page)
    await expect(page.getByRole('alert')).toContainText('The information changed.')
    await expect(page.getByLabel('Public name *', { exact: true })).toHaveValue('Borrador Ñandú')
    await expect(page.getByText('private database text')).toHaveCount(0)
    expect(writes).toHaveLength(1)
    await page.getByRole('button', { name: 'Save', exact: true }).click()
    await expect.poll(() => writes.length).toBe(2)
    expect(writes[1]['idempotency-key']).toBe(writes[0]['idempotency-key'])
    await accessibility(page)
  })

  test('colaboración directorio filtra y no crea solicitudes al explorar', async ({ page }) => {
    const { writes } = await mockConsortium(page)
    await page.goto('/professionals')
    await expect(page.getByRole('heading', { name: 'Profesional Ñandú', exact: true })).toBeVisible()
    await english(page)
    await page.getByRole('textbox', { name: 'Name, specialty or skill', exact: true }).fill('Ingeniería')
    const searched = page.waitForRequest(request => request.url().includes('professionals?') && request.url().includes('q='))
    await page.getByRole('button', { name: 'Search', exact: true }).click()
    await searched
    await page.getByRole('link', { name: 'Choose a consortium to invite', exact: true }).click()
    await expect(page).toHaveURL(new RegExp(`professionalId=${profileId}`))
    expect(writes).toHaveLength(0)
    await accessibility(page); await fits(page)
  })
}
