import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { expect, test, type Page } from '@playwright/test'
import { mockEditorial } from './editorial-checks'
import { english, fits, mockWorkspace, readOnlyJson } from './workspace-checks'
import { editorialCatalogs, editorialFunder } from '../src/test/fixtures/editorial-workspace'

// The actual versioned seed, not a hand-picked list that would miss the Chile-only bug.
const sql = readFileSync(resolve(process.cwd(), '../../database/Migrations/048_world_country_catalog.sql'), 'utf8')
const countries = [...sql.matchAll(/\((\d+), '([A-Z]{2})', '[A-Z]{3}', N'((?:[^']|'')+)'\)/g)]
  .map(row => ({ id: Number(row[1]), code: row[2], name: row[3].replaceAll("''", "'") })).reverse()

export function registerWorldCountryTests(accessibility: (page: Page) => Promise<void>) {
  for (const scope of ['admin', 'funder-workspace']) for (const width of [320, 1280]) {
    test(`financiadores países del mundo selecciona y guarda ES/EN ${scope} a ${width}px`, async ({ page }, testInfo) => {
      if (scope === 'admin') await mockEditorial(page)
      else await mockWorkspace(page)
      expect(countries).toHaveLength(249)
      await page.route('**/api/v1/catalogs', readOnlyJson({ ...editorialCatalogs, countries }))
      let funder = editorialFunder({ publicationStatus: 0 })
      const selectedCountries: number[] = []
      await page.route(`**/api/v1/${scope}/funders`, async route => {
        expect(route.request().method()).toBe('POST')
        const data = route.request().postDataJSON()
        expect(route.request().headers()['idempotency-key']).toBeTruthy()
        selectedCountries.push(data.countryId)
        funder = { ...funder, ...data }
        await route.fulfill({ status: 201, json: { entityId: funder.funderId, publicationStatus: 0, contentVersion: 1, eTag: funder.eTag, wasReplay: false } })
      })
      await page.route(`**/api/v1/${scope}/funders/${funder.funderId}`, async route => {
        if (route.request().method() === 'GET') return route.fulfill({ json: funder })
        expect(route.request().method()).toBe('PUT')
        expect(route.request().headers()['if-match']).toBe(funder.eTag)
        const data = route.request().postDataJSON()
        selectedCountries.push(data.countryId)
        funder = { ...funder, ...data, contentVersion: 2, eTag: '"0000000000000002"' }
        return route.fulfill({ json: { entityId: funder.funderId, publicationStatus: 0, contentVersion: 2, eTag: funder.eTag, wasReplay: false } })
      })
      await page.setViewportSize({ width, height: 900 })
      await page.goto(`/${scope}/funders/new`)
      const select = page.getByRole('combobox', { name: 'País', exact: true })
      await expect(select.locator('option')).toHaveCount(250)
      await expect(select.locator('option[value="840"]')).toHaveText('Estados Unidos de América')
      await expect(select.locator('option[value="392"]')).toHaveText('Japón')
      await expect(select.locator('option[value="76"]')).toHaveText('Brasil')
      await select.selectOption('840')
      await fits(page); await accessibility(page)
      await english(page)
      await expect(page.getByRole('combobox', { name: 'Country', exact: true })).toHaveValue('840')
      await expect(page.getByRole('option', { name: 'United States of America', exact: true })).toHaveAttribute('value', '840')
      expect(selectedCountries).toEqual([])
      await page.getByRole('textbox', { name: 'Name', exact: true }).fill('Worldwide synthetic funder')
      await page.getByRole('button', { name: 'Create funder', exact: true }).click()
      await expect(page).toHaveURL(`/${scope}/funders/${funder.funderId}`)
      await expect(page.getByRole('combobox', { name: 'Country', exact: true })).toHaveValue('840')
      await page.getByRole('combobox', { name: 'Country', exact: true }).selectOption('392')
      await page.getByRole('button', { name: 'Save changes', exact: true }).click()
      await expect.poll(() => selectedCountries).toEqual([840, 392])
      await page.reload()
      await expect(page.getByRole('combobox', { name: 'Country', exact: true })).toHaveValue('392')
      await page.getByRole('combobox', { name: 'Change theme', exact: true }).selectOption('dark')
      await fits(page); await accessibility(page)
      await page.screenshot({ path: testInfo.outputPath(`world-countries-${scope}-${width}.png`), fullPage: true })
    })
  }
}
