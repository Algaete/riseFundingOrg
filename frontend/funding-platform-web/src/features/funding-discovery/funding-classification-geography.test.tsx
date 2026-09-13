import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter, Route, Routes } from 'react-router-dom'
import { setAuthenticatedSession } from '@/features/auth/auth-session'
import { FundingClassificationPage } from './funding-discovery-pages'
import { fundingDiscoveryApi } from './funding-discovery-api'

it('removing a country clears the saved notice and the next explicit save uses the new ETag', async () => {
  setAuthenticatedSession({ status: 'authenticated', accessToken: 'synthetic', accessTokenExpiresAtUtc: '2099-01-01T00:00:00Z',
    user: { publicId: '33333333-3333-3333-3333-333333333333', email: 'admin@example.invalid', displayName: 'Admin', preferredLocale: 'es-CL', roles: ['Admin'], mfaEnabled: true } })
  const id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
  const version = 'partner-geography-2026-09-12'
  const data = { funderKind: 3, requiresConsortium: true, requiresInternationalPartner: true, evidenceUrl: 'https://example.invalid/terms',
    partnerGeography: { scope: 2 as const, countryIds: [826], regionCodes: ['EU'], catalogVersion: version } }
  const get = vi.spyOn(fundingDiscoveryApi, 'get').mockResolvedValue({ opportunityId: id, title: 'Fondo', contentVersion: 2, reviewedContentVersion: 2,
    data, eTag: '"0102030405060708"', sourceUrls: [data.evidenceUrl] })
  const catalogs = vi.spyOn(fundingDiscoveryApi, 'catalogs').mockResolvedValue({ countries: [{ id: 826, code: 'GB', name: 'Reino Unido de Gran Bretaña e Irlanda del Norte' }],
    regions: [], currencies: [], fundingCategories: [], fundingTypes: [], organizationTypes: [], languages: [], partnerRegions: [{ code: 'EU' }], partnerGeographyVersion: version })
  const save = vi.spyOn(fundingDiscoveryApi, 'review').mockResolvedValue({ eTag: '"0102030405060709"' })
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  const view = render(<MemoryRouter initialEntries={[`/admin/funding/${id}/discovery`]}><QueryClientProvider client={client}>
    <Routes><Route path="/admin/funding/:id/discovery" element={<FundingClassificationPage />} /></Routes>
  </QueryClientProvider></MemoryRouter>)
  try {
    const button = await screen.findByRole('button', { name: 'Confirmar clasificación' })
    await waitFor(() => expect(screen.getByRole('button', { name: /Quitar Reino Unido/ })).toBeEnabled())
    expect(save).not.toHaveBeenCalled()
    await userEvent.click(button)
    expect(await screen.findByText('Clasificación revisada y guardada.')).toBeVisible()
    await userEvent.click(screen.getByRole('button', { name: /Quitar Reino Unido/ }))
    expect(screen.queryByText('Clasificación revisada y guardada.')).not.toBeInTheDocument()
    expect(save).toHaveBeenCalledTimes(1)
    await userEvent.click(button)
    await waitFor(() => expect(save).toHaveBeenCalledTimes(2))
    expect(save.mock.calls[1]).toEqual([id, 2, { ...data, partnerGeography: { ...data.partnerGeography, countryIds: [] } }, '"0102030405060709"', expect.any(String)])
  } finally {
    view.unmount(); client.clear(); get.mockRestore(); catalogs.mockRestore(); save.mockRestore()
  }
})
