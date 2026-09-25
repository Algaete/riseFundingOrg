import AxeBuilder from '@axe-core/playwright'
import { expect, test } from '@playwright/test'
import { mockEditorial } from './editorial-checks'
import { english, fits } from './workspace-checks'
import { editorialOpportunity } from '../src/test/fixtures/editorial-workspace'
import type { FundingTranslation, FundingTranslationWrite, TranslationField } from '../src/features/funding/funding-translations-api'

const translationFields: TranslationField[] = ['title', 'summary', 'description', 'eligibilityDescription', 'requirements',
  'objectives', 'allowedActivities', 'excludedActivities', 'restrictions', 'targetOrganizationsDescription', 'targetPopulationsDescription']

// Run with VITE_FUNDING_TRANSLATIONS_ENABLED=true. All API requests are mocked;
// unexpected endpoints, especially generation, abort and fail the test.
for (const width of [320, 1280]) {
  test(`ESEN reviewed editor works without paid generation at ${width}px`, async ({ page }) => {
    const unexpected: string[] = []
    await page.route('**/api/v1/**', route => {
      unexpected.push(new URL(route.request().url()).pathname)
      return route.abort('blockedbyclient')
    })
    await mockEditorial(page)
    const original = editorialOpportunity()
    let saved: FundingTranslation | null = null
    let writes = 0
    await page.route('**/api/v1/admin/funding-opportunities/' + original.opportunityId + '/translations/es', route => {
      if (route.request().method() === 'GET') return route.fulfill({ json: { translation: saved, generationAvailable: false } })
      expect(route.request().method()).toBe('PUT')
      expect(route.request().headers()['if-match']).toBe(original.eTag)
      const data = route.request().postDataJSON() as FundingTranslationWrite
      expect(data.sourceContentVersion).toBe(original.contentVersion)
      expect(data.expectedRevision).toBe(0)
      expect(data.reviewed).toBe(true)
      expect(Object.keys(data.text)).toHaveLength(11)
      saved = { language: 'es', sourceContentVersion: data.sourceContentVersion, revision: 1, reviewed: true, text: data.text, updatedAtUtc: '2026-09-25T12:00:00Z' }
      writes++
      return route.fulfill({ json: saved })
    })
    await page.setViewportSize({ width, height: 900 })
    await page.goto('/admin/funding/' + original.opportunityId + '/translations')
    await expect(page.getByText('Generación automática no habilitada:', { exact: false })).toBeVisible()
    await expect(page.getByRole('button', { name: 'Generar propuesta automática' })).toHaveCount(0)
    const approve = page.getByRole('button', { name: 'Guardar traducción revisada', exact: true })
    await expect(approve).toBeDisabled()
    for (const field of translationFields) {
      if (original[field]?.trim()) await page.locator('#translation-' + field).fill('Texto sintético revisado: ' + field)
    }
    expect(writes).toBe(0)
    await expect(approve).toBeDisabled()
    await page.getByRole('checkbox', { name: /^Revisé todos los textos/ }).check()
    await approve.click()
    await expect(page.getByText('Traducción guardada.', { exact: true })).toBeVisible()
    expect(writes).toBe(1)
    await english(page)
    await expect(page.locator('#translation-title')).toHaveValue('Texto sintético revisado: title')
    await expect(page.getByText('Translation saved.', { exact: true })).toBeVisible()
    await fits(page)
    expect((await new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa', 'wcag21aa']).analyze()).violations).toEqual([])
    await page.screenshot({ path: test.info().outputPath(`translations-${width}.png`), fullPage: true })
    expect(writes).toBe(1)
    expect(unexpected).toEqual([])
  })
}
