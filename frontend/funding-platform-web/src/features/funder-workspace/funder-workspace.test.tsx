import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import { createMemoryRouter } from 'react-router-dom'
import { describe, expect, it, vi } from 'vitest'
import { createAppQueryClient } from '@/api/query-client'
import { App } from '@/App'
import { appRoutes } from '@/router'
import { setAuthenticatedSession } from '@/features/auth/auth-session'
import { editorialCatalogs, editorialFunder, editorialOpportunity } from '@/test/fixtures/editorial-workspace'
import { funderOwnerScope } from './editorial-scope'

function mount(path: string, status: 0 | 1 = 0) {
  setAuthenticatedSession({ status: 'authenticated', accessToken: 'owner-synthetic', accessTokenExpiresAtUtc: '2099-01-01T00:00:00Z', user: { publicId: 'owner-synthetic', email: 'owner@example.invalid', displayName: 'Financiador', roles: ['Professional'], mfaEnabled: false, preferredLocale: 'es-CL' } })
  const funder = editorialFunder({ publicationStatus: status })
  const opportunity = editorialOpportunity({ publicationStatus: status })
  const calls: string[] = []
  vi.stubGlobal('fetch', vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = new URL(String(input), 'http://localhost'); calls.push(`${init?.method ?? 'GET'} ${url.pathname}`)
    let data: unknown
    if (url.pathname === '/api/v1/catalogs') data = editorialCatalogs
    else if (url.pathname === '/api/v1/funder-workspace/funders') data = { items: [funder], totalCount: 1, page: 1, pageSize: 20 }
    else if (url.pathname === `/api/v1/funder-workspace/funders/${funder.funderId}`) data = funder
    else if (url.pathname === `/api/v1/funder-workspace/funding-opportunities/${opportunity.opportunityId}`) data = opportunity
    else if (url.pathname === '/api/v1/funder-workspace/funding-sources') data = [{ id: 7, name: 'Portal', providerType: 0, baseUrl: null, isEnabled: true }]
    else throw new Error(`Unexpected ${url.pathname}`)
    return new Response(JSON.stringify(data), { headers: { 'Content-Type': 'application/json' } })
  }))
  const client = createAppQueryClient()
  client.setQueryData(['admin-funder', funder.funderId], { ...funder, name: 'Secret admin cache' })
  const router = createMemoryRouter(appRoutes, { initialEntries: [path] })
  render(<App router={router} queryClient={client} />)
  return { calls, router }
}

describe('funder owner workspace', () => {
  it('uses owner data and never the admin cache or API', async () => {
    const funder = editorialFunder()
    const { calls } = mount(`/funder-workspace/funders/${funder.funderId}`)
    await screen.findByRole('textbox', { name: 'Nombre' })
    expect(screen.queryByText('Secret admin cache')).not.toBeInTheDocument()
    expect(calls.every(call => !call.includes('/admin/'))).toBe(true)
    expect(screen.getByRole('textbox', { name: 'Nombre' })).toHaveAttribute('aria-required', 'true')
  })

  it('pending owner profile has no administrative review controls', async () => {
    mount(`/funder-workspace/funders/${editorialFunder().funderId}`, 1)
    await screen.findByRole('textbox', { name: 'Nombre' })
    expect(screen.getByRole('textbox', { name: 'Nombre' })).toBeDisabled()
    expect(screen.queryByRole('button', { name: /Aprobar/ })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /Rechazar/ })).not.toBeInTheDocument()
    expect(screen.queryByRole('textbox', { name: /Motivo del rechazo/ })).not.toBeInTheDocument()
  })

  it('owner editor offers only primary ownership and does not expose co-funder roles', async () => {
    mount(`/funder-workspace/funding/${editorialOpportunity().opportunityId}`)
    await screen.findByRole('textbox', { name: 'Título' })
    expect(screen.getByRole('combobox', { name: 'Rol' }).querySelectorAll('option')).toHaveLength(1)
    expect(screen.getByRole('combobox', { name: 'Rol' })).toHaveValue('1')
    fireEvent.change(screen.getByRole('textbox', { name: 'Título' }), { target: { value: 'Borrador local' } })
    await waitFor(() => expect(screen.getByRole('textbox', { name: 'Título' })).toHaveValue('Borrador local'))
  })

  it('owner API refuses review without sending any HTTP request', async () => {
    const fetch = vi.fn(); vi.stubGlobal('fetch', fetch)
    await expect(funderOwnerScope.apis.funders.review('id', 'etag', 'key', 'approve')).rejects.toThrow('Owner review is not allowed')
    expect(fetch).not.toHaveBeenCalled()
    expect(funderOwnerScope.key('admin-funders')).not.toBe('admin-funders')
  })
})
