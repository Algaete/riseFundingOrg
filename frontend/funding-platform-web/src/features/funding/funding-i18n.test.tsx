import { QueryClientProvider } from '@tanstack/react-query'
import { act, fireEvent, render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter } from 'react-router-dom'
import type { ReactNode } from 'react'

import { ApiError } from '@/api/http-client'
import { createAppQueryClient } from '@/api/query-client'
import { fundingOpportunitiesApi } from './funding-opportunities-api'
import { FundingCard, FundingCatalogPage, FundingOpportunityDetailView } from './funding-pages'
import { setInterfaceLanguage } from '@/i18n'
import { discoveryOpportunity } from '@/test/fixtures/public-discovery'

function renderPublic(node: ReactNode) {
  const client = createAppQueryClient()
  client.setDefaultOptions({ queries: { retry: false, staleTime: 30_000 } })
  render(<QueryClientProvider client={client}><MemoryRouter>{node}</MemoryRouter></QueryClientProvider>)
}

describe('funding catalog language changes', () => {
  afterEach(() => { vi.restoreAllMocks(); vi.useRealTimers() })

  it('preserves unsent search text, server page and source content without additional requests', async () => {
    const search = vi.spyOn(fundingOpportunitiesApi, 'search').mockImplementation(async (_query, page) => ({ items: [discoveryOpportunity], totalCount: 25, pageNumber: page ?? 1, pageSize: 12 }))
    renderPublic(<FundingCatalogPage />)
    await screen.findByRole('heading', { name: discoveryOpportunity.title })
    await userEvent.click(screen.getByRole('button', { name: 'Siguiente' }))
    await screen.findByText('Página 2 de 3')
    fireEvent.change(screen.getByRole('textbox', { name: 'Buscar oportunidades' }), { target: { value: '  Salud Ñandú  ' } })
    await act(() => setInterfaceLanguage('en'))
    expect(screen.getByRole('textbox', { name: 'Search opportunities' })).toHaveValue('  Salud Ñandú  ')
    expect(screen.getByText('Page 2 of 3')).toBeVisible()
    expect(screen.getByText('Quality 96/100')).toBeVisible()
    expect(screen.getByText('Atribución original de la fuente.')).toBeVisible()
    expect(screen.getByRole('img', { name: 'Thematic visual: Health and well-being' })).toBeVisible()
    expect(screen.getByRole('link', { name: 'View full details' })).toHaveAttribute('href', `/funding/${discoveryOpportunity.slug}`)
    expect(search).toHaveBeenCalledTimes(2)
    await userEvent.click(screen.getByRole('button', { name: 'Search' }))
    await waitFor(() => expect(search).toHaveBeenLastCalledWith('Salud Ñandú', 1, 12, expect.any(AbortSignal)))
    expect(search).toHaveBeenCalledTimes(3)
  })

  it('keeps the external confirmation, keyboard focus and exact destination across language changes', async () => {
    renderPublic(<FundingOpportunityDetailView item={discoveryOpportunity} backTo="/funding" />)
    await userEvent.click(screen.getByRole('button', { name: 'Ir a postular' }))
    const close = screen.getByRole('button', { name: 'Cerrar confirmación' })
    expect(close).toHaveFocus()
    await act(() => setInterfaceLanguage('en'))
    expect(screen.getByRole('dialog', { name: 'You are leaving FundingPlatform' })).toBeVisible()
    expect(close).toHaveFocus()
    expect(screen.getByRole('link', { name: 'Continue to apply.example.invalid' })).toHaveAttribute('href', discoveryOpportunity.applicationUrl)
    expect(screen.getByRole('link', { name: 'Continue to apply.example.invalid' })).toHaveAttribute('rel', 'noopener noreferrer')
    expect(screen.getByRole('link', { name: 'Continue to apply.example.invalid' })).toHaveAttribute('target', '_blank')
    expect(screen.getByText('Estatutos y presupuesto.')).toBeVisible()
    await userEvent.keyboard('{Escape}')
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
  })

  it.each(['javascript:alert(1)', 'https://user:password@example.invalid', 'ftp://example.invalid/file'])('keeps unsafe application destination %s unavailable in English', async applicationUrl => {
    await setInterfaceLanguage('en')
    renderPublic(<FundingOpportunityDetailView item={{ ...discoveryOpportunity, applicationUrl }} backTo="/funding" />)
    expect(screen.queryByRole('button', { name: 'Apply on external site' })).not.toBeInTheDocument()
    expect(screen.queryByRole('link', { name: /Continue to/ })).not.toBeInTheDocument()
  })

  it.each([
    [{ closeDate: '2026-08-22' }, 'Vigente', 'Open'],
    [{ closeDate: '2026-08-21' }, 'Cerrada', 'Closed'],
    [{ openDate: '2026-08-23' }, 'Próximamente', 'Coming soon'],
    [{ closeDate: null, deadlineType: 2 }, 'Vigente', 'Open'],
    [{ closeDate: null, deadlineType: 0 }, 'Plazo no informado', 'Deadline not reported'],
    [{ closeAtUtc: '2026-08-22T20:00:00Z', deadlinePrecision: 2 }, 'Cerrada', 'Closed'],
    [{ closeAtUtc: '2026-08-22T20:00:01Z', deadlinePrecision: 2 }, 'Vigente', 'Open'],
    [{ closeAtUtc: null, deadlinePrecision: 2 }, 'Plazo no informado', 'Deadline not reported'],
  ] as const)('preserves availability rules %j', async (overrides, spanish, english) => {
    vi.useFakeTimers()
    vi.setSystemTime(new Date('2026-08-22T20:00:00Z'))
    renderPublic(<FundingCard opportunity={{ ...discoveryOpportunity, ...overrides }} />)
    expect(screen.getByText(spanish)).toBeVisible()
    await act(() => setInterfaceLanguage('en'))
    expect(screen.getByText(english)).toBeVisible()
  })

  it('localizes date and amount fallbacks, while preserving the Grants.gov notice', async () => {
    renderPublic(<FundingCard opportunity={{ ...discoveryOpportunity, minimumAmount: null, closeDate: '2030-01-01', sourceName: 'Grants.gov', sourceAttribution: null }} />)
    const notice = screen.getByText(/This product uses the Grants.gov API/)
    expect(notice).toHaveAttribute('lang', 'en')
    await act(() => setInterfaceLanguage('en'))
    expect(screen.getByText('Jan 1, 2030')).toBeVisible()
    expect(screen.getByText('Up to $100,000.00')).toBeVisible()
    expect(notice).toBeVisible()
  })

  it('translates a visible error, retries only on request, and displays the empty state', async () => {
    const search = vi.spyOn(fundingOpportunitiesApi, 'search')
      .mockRejectedValueOnce(new ApiError({ title: 'Do not expose diagnostics', status: 503 }, new Response(null, { status: 503 })))
      .mockResolvedValue({ items: [], totalCount: 0, pageNumber: 1, pageSize: 12 })
    renderPublic(<FundingCatalogPage />)
    await screen.findByRole('alert')
    await act(() => setInterfaceLanguage('en'))
    expect(screen.getByRole('alert')).toHaveTextContent('The service is unavailable right now. Try again later.')
    expect(screen.queryByText(/Do not expose/)).not.toBeInTheDocument()
    expect(search).toHaveBeenCalledOnce()
    await userEvent.click(screen.getByRole('button', { name: 'Retry' }))
    expect(await screen.findByText('No opportunities found')).toBeVisible()
    expect(search).toHaveBeenCalledTimes(2)
  })
})
