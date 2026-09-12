import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { createElement } from 'react'
import { act, fireEvent, render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { createMemoryRouter } from 'react-router-dom'
import { App } from '../src/App'
import { appRoutes } from '../src/router'
import { createAppQueryClient } from '../src/api/query-client'
import { setAuthenticatedSession } from '../src/features/auth/auth-session'
import { setInterfaceLanguage } from '../src/i18n'
import { editorialCatalogs, editorialFunder } from '../src/test/fixtures/editorial-workspace'

const sql = readFileSync(resolve(process.cwd(), '../../database/Migrations/048_world_country_catalog.sql'), 'utf8')
const countries = [...sql.matchAll(/\((\d+), '([A-Z]{2})', '[A-Z]{3}', N'((?:[^']|'')+)'\)/g)]
  .map(row => ({ id: Number(row[1]), code: row[2], name: row[3].replaceAll("''", "'") })).reverse()

describe('worldwide funder country selector', () => {
  afterEach(() => vi.unstubAllGlobals())

  it.each(['admin', 'funder-workspace'])('offers all seeded countries, translates and persists selection in %s', async scope => {
    expect(countries).toHaveLength(249)
    setAuthenticatedSession({ status: 'authenticated', accessToken: 'synthetic-test-only', accessTokenExpiresAtUtc: '2099-01-01T00:00:00Z',
      user: { publicId: 'synthetic', email: 'synthetic@example.invalid', displayName: 'Synthetic', preferredLocale: 'es', roles: [scope === 'admin' ? 'Admin' : 'Professional'], mfaEnabled: false } })
    const writes = []
    let saved = editorialFunder({ publicationStatus: 0 })
    vi.stubGlobal('fetch', vi.fn(async (input, options) => {
      const path = new URL(String(input), 'http://localhost').pathname
      if (path === '/api/v1/catalogs' && options.method === 'GET') return Response.json({ ...editorialCatalogs, countries })
      if (path === `/api/v1/${scope}/funders` && options.method === 'POST') {
        const data = JSON.parse(options.body)
        writes.push(data)
        saved = { ...saved, ...data }
        return Response.json({ entityId: saved.funderId, publicationStatus: 0, contentVersion: 1, eTag: saved.eTag, wasReplay: false }, { status: 201 })
      }
      if (path === `/api/v1/${scope}/funders/${saved.funderId}` && options.method === 'GET') return Response.json(saved)
      throw new Error(`Unexpected request ${options.method} ${path}`)
    }))
    const router = createMemoryRouter(appRoutes, { initialEntries: [`/${scope}/funders/new`] })
    render(createElement(App, { router, queryClient: createAppQueryClient() }))
    const select = await screen.findByRole('combobox', { name: 'País' })
    expect(select.options).toHaveLength(250) // 249 countries + optional unreported value
    const names = Array.from(select.options).slice(1).map(option => option.textContent)
    expect(names).toEqual([...names].sort(new Intl.Collator('es', { sensitivity: 'base' }).compare))
    for (const code of ['CL', 'AR', 'BR', 'PE', 'US', 'GB', 'ES', 'JP', 'IN', 'ZA', 'AU', 'TW']) {
      const country = countries.find(item => item.code === code)
      fireEvent.change(select, { target: { value: String(country.id) } })
      expect(select).toHaveValue(String(country.id))
    }
    fireEvent.change(select, { target: { value: '840' } })
    await act(async () => { await setInterfaceLanguage('en') })
    expect(screen.getByRole('combobox', { name: 'Country' })).toHaveValue('840')
    expect(screen.getByRole('option', { name: 'United States of America' })).toHaveAttribute('value', '840')
    expect(screen.getByRole('option', { name: 'Japan' })).toHaveAttribute('value', '392')
    const english = Array.from(select.options).slice(1).map(option => option.textContent)
    expect(english).toEqual([...english].sort(new Intl.Collator('en', { sensitivity: 'base' }).compare))
    expect(writes).toHaveLength(0)
    const user = userEvent.setup()
    await user.type(screen.getByRole('textbox', { name: 'Name' }), 'Synthetic worldwide funder')
    await user.click(screen.getByRole('button', { name: 'Create funder' }))
    await waitFor(() => expect(writes).toHaveLength(1))
    expect(writes[0].countryId).toBe(840)
    await waitFor(() => expect(router.state.location.pathname).toBe(`/${scope}/funders/${saved.funderId}`))
    expect(await screen.findByRole('combobox', { name: 'Country' })).toHaveValue('840')
  })
})
