import { expect, test, type Page } from '@playwright/test'
import { collaborationOrganizations, matchingDetail, matchingHistory, matchingRunId, networkConnection, networkConnections, networkDirectory, networkOrganization, networkPreference, workspaceOrganizationId, workspaceProjectId } from '../src/test/fixtures/matching-network'
import { english, fits, mockWorkspace, readOnlyJson } from './workspace-checks'

const runPath = `**/api/v1/organizations/${workspaceOrganizationId}/projects/${workspaceProjectId}/matching-runs`
const networkPath = `**/api/v1/organizations/${workspaceOrganizationId}/network`

async function mockMatching(page: Page) {
  await mockWorkspace(page)
  const reads: string[] = []
  await page.route(runPath + '?*', route => {
    expect(route.request().method()).toBe('GET')
    const url = new URL(route.request().url())
    reads.push(url.search)
    return route.fulfill({ json: { ...matchingHistory, pageNumber: Number(url.searchParams.get('page')) } })
  })
  await page.route(runPath + '/' + matchingRunId, readOnlyJson({
    ...matchingDetail,
    items: [
      ...matchingDetail.items,
      { ...matchingDetail.items[0], fundingOpportunity: { ...matchingDetail.items[0].fundingOpportunity, publicId: 'incompatible', title: 'Fondo excluyente original' }, classification: 1, compatibilityScore: null, hardGateStatus: 1, isCurrent: true, ruleResults: [] },
      { ...matchingDetail.items[0], fundingOpportunity: { ...matchingDetail.items[0].fundingOpportunity, publicId: 'compatible', title: 'Fondo compatible original' }, classification: 0, compatibilityScore: 85, hardGateStatus: 0, isCurrent: true, ruleResults: [] },
    ],
  }))
  return reads
}

async function mockNetwork(page: Page, member = false) {
  await mockWorkspace(page, { publicationStatus: 2 })
  await page.route('**/api/v1/organizations', readOnlyJson([{ ...collaborationOrganizations[0], membershipRole: member ? 'member' : 'admin' }]))
  await page.route(networkPath + '/settings', readOnlyJson(networkPreference))
  const reads: string[] = []
  await page.route(networkPath + '/directory?*', route => {
    expect(route.request().method()).toBe('GET')
    reads.push(route.request().url())
    return route.fulfill({ json: networkDirectory })
  })
  await page.route(networkPath + '/connections?*', route => {
    expect(route.request().method()).toBe('GET')
    reads.push(route.request().url())
    return route.fulfill({ json: { ...networkConnections, items: [{ ...networkConnection, canRespond: !member, canBlock: !member }] } })
  })
  return reads
}

export function registerMatchingNetworkLanguageTests(checkAccessibility: (page: Page) => Promise<void>) {
  for (const width of [320, 1024]) {
    test(`matching ES/EN conserva reglas, historial y puntajes a ${width}px`, async ({ page }) => {
      const reads = await mockMatching(page)
      await page.setViewportSize({ width, height: 900 })
      await page.goto(`/matching?projectId=${workspaceProjectId}&runId=${matchingRunId}&page=2&context=original`)
      await expect(page.getByRole('heading', { name: 'Fondo Ñandú original', exact: true })).toBeVisible()
      await page.getByText('Ver desglose de 2 reglas', { exact: true }).click()
      const location = page.url()
      await fits(page)
      await english(page)
      await expect(page.getByRole('heading', { name: 'Project compatibility', exact: true })).toBeVisible()
      await expect(page.getByRole('combobox', { name: /Project to compare/ })).toHaveValue(workspaceProjectId)
      await expect(page.getByRole('heading', { name: 'Geography', exact: true })).toBeVisible()
      await expect(page.getByText('Unknown does not count as passed.', { exact: true })).toBeVisible()
      await expect(page.getByLabel('Indicative score 42.5 out of 100', { exact: true })).toBeVisible()
      await expect(page.getByRole('progressbar', { name: 'Data coverage 62.5%', exact: true }).first()).toHaveAttribute('value', '62.5')
      await expect(page.getByText('Incompatible', { exact: true })).toBeVisible()
      await expect(page.getByText('Not applicable', { exact: true })).toBeVisible()
      await expect(page.getByText('Compatible', { exact: true })).toBeVisible()
      await expect(page.getByText('Score contribution: 5 out of 10 possible points', { exact: true })).toBeVisible()
      await expect(page.getByText(/private@example|internal-01|SECRET-PARAMETER/)).toHaveCount(0)
      await expect(page.getByRole('main')).not.toHaveAttribute('lang', 'es')
      expect(page.url()).toBe(location)
      expect(reads).toHaveLength(1)
      await checkAccessibility(page)
      await fits(page)
      await page.getByRole('button', { name: 'Next history page', exact: true }).click()
      await expect(page.getByText('Page 3 of 3', { exact: true })).toBeVisible()
      expect(new URL(page.url()).searchParams.get('context')).toBe('original')
      expect(reads).toHaveLength(2)
      await page.getByRole('combobox', { name: 'Change theme', exact: true }).selectOption('dark')
      await checkAccessibility(page)
      await fits(page)
      // No calculation endpoint is mocked: any accidental write fails the parent guard.
    })

    test(`red ES/EN conserva invitación privada y filtros sin enviarlos a ${width}px`, async ({ page }) => {
      const reads = await mockNetwork(page)
      await page.setViewportSize({ width, height: 900 })
      await page.goto('/network')
      await page.getByRole('button', { name: 'Conectar', exact: true }).click()
      await page.getByRole('combobox', { name: 'Propósito', exact: true }).selectOption('consortium-exploration')
      await page.getByRole('combobox', { name: 'Proyecto público opcional', exact: true }).selectOption(workspaceProjectId)
      await page.getByRole('textbox', { name: 'Mensaje privado', exact: true }).fill('Invitación original Ñandú para colaborar.')
      await page.getByRole('textbox', { name: 'Buscar organizaciones', exact: true }).fill('Búsqueda no enviada')
      await page.getByRole('button', { name: 'Recibidas', exact: true }).click()
      await expect.poll(() => reads.length).toBe(3)
      await fits(page)
      await english(page)
      await expect(page.getByRole('heading', { name: 'Invite ' + networkOrganization.name, exact: true })).toBeVisible()
      await expect(page.getByRole('textbox', { name: 'Private message', exact: true })).toHaveValue('Invitación original Ñandú para colaborar.')
      await expect(page.getByRole('combobox', { name: 'Purpose', exact: true })).toHaveValue('consortium-exploration')
      await expect(page.getByRole('combobox', { name: 'Optional public project', exact: true })).toHaveValue(workspaceProjectId)
      await expect(page.getByRole('textbox', { name: 'Search organizations', exact: true })).toHaveValue('Búsqueda no enviada')
      await expect(page.getByRole('button', { name: 'Incoming', exact: true })).toHaveAttribute('aria-pressed', 'true')
      await expect(page.getByRole('button', { name: 'Join the directory and receive requests', exact: true })).toBeEnabled()
      await expect(page.getByText('1 public project', { exact: true })).toBeVisible()
      await expect(page.getByText('Medio ambiente', { exact: true })).toHaveAttribute('lang', 'es')
      await expect(page.getByRole('main')).not.toHaveAttribute('lang', 'es')
      expect(reads).toHaveLength(3)
      await checkAccessibility(page)
      await fits(page)
      await page.getByRole('combobox', { name: 'Change theme', exact: true }).selectOption('dark')
      await checkAccessibility(page)
      await fits(page)
      // No POST/PUT/PATCH handler: language changes must not send invitations or change visibility.
    })

    test(`red ES/EN mantiene permisos de miembro a ${width}px`, async ({ page }) => {
      const reads = await mockNetwork(page, true)
      await page.setViewportSize({ width, height: 900 })
      await page.goto('/network')
      await expect(page.getByRole('heading', { name: networkOrganization.name, exact: true })).toBeVisible()
      await english(page)
      await expect(page.getByRole('button', { name: 'Join the directory and receive requests', exact: true })).toBeDisabled()
      await expect(page.getByText('Members can explore the network, but only NGO administrators can change visibility or respond.', { exact: true })).toBeVisible()
      for (const name of ['Connect', 'Accept', 'Reject', 'Cancel', 'Block']) await expect(page.getByRole('button', { name, exact: true })).toHaveCount(0)
      await checkAccessibility(page)
      await fits(page)
      expect(reads).toHaveLength(2)
    })
  }

  test('matching ES/EN reintenta un cálculo sintético con la misma clave', async ({ page }) => {
    await mockMatching(page)
    const keys: string[] = []
    await page.route(runPath, route => {
      expect(route.request().method()).toBe('POST')
      expect(route.request().postData()).toBeNull()
      expect(route.request().headers().authorization).toBe('Bearer synthetic-ui-only')
      keys.push(route.request().headers()['idempotency-key'])
      return keys.length === 1
        ? route.fulfill({ status: 503, json: { status: 503, title: 'SECRET-DIAGNOSTIC' } })
        : route.fulfill({ json: { run: matchingDetail, wasReplay: true } })
    })
    await page.setViewportSize({ width: 320, height: 900 })
    await page.goto(`/matching?projectId=${workspaceProjectId}`)
    await page.getByRole('button', { name: 'Calcular versión actual', exact: true }).click()
    await expect(page.getByRole('heading', { name: 'No pudimos completar el cálculo', exact: true })).toBeVisible()
    await english(page)
    await expect(page.getByRole('alert')).toContainText('The service is unavailable right now. Try again later.')
    expect(keys).toHaveLength(1)
    await checkAccessibility(page)
    await fits(page)
    await page.getByRole('button', { name: 'Retry calculation', exact: true }).click()
    await expect(page.getByText('The same calculation was safely retrieved.', { exact: true })).toBeVisible()
    expect(keys).toHaveLength(2)
    expect(keys[0]).toMatch(/^[0-9a-f-]{36}$/i)
    expect(keys[1]).toBe(keys[0])
    await checkAccessibility(page)
  })

  test('red ES/EN distingue errores de privacidad y solo reintenta la lectura', async ({ page }) => {
    await mockNetwork(page)
    let requests = 0
    await page.route(networkPath + '/settings', route => {
      expect(route.request().method()).toBe('GET')
      requests += 1
      return requests <= 2 ? route.fulfill({ status: 503, json: { status: 503, title: 'SECRET-DIAGNOSTIC' } }) : route.fulfill({ json: networkPreference })
    })
    await page.setViewportSize({ width: 320, height: 900 })
    await page.goto('/network')
    await expect(page.getByRole('alert')).toBeVisible()
    await english(page)
    await expect(page.getByRole('alert')).toContainText('The service is unavailable right now. Try again later.')
    await expect(page.getByRole('button', { name: 'Join the directory and receive requests', exact: true })).toHaveCount(0)
    expect(requests).toBe(2) // Existing query retry policy; language itself adds no retry.
    await checkAccessibility(page)
    await fits(page)
    await page.getByRole('button', { name: 'Retry', exact: true }).click()
    await expect(page.getByRole('button', { name: 'Join the directory and receive requests', exact: true })).toBeVisible()
    expect(requests).toBe(3)
    await checkAccessibility(page)
  })
}
