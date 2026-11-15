import { act, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { PublicPricingPage, SubscriptionWorkspacePage } from './billing-pages'
import { billingApi } from './billing-api'
import { organizationApi } from '@/features/organizations/organization-api'
import { workspaceOrganizationId, workspaceProfile } from '@/test/fixtures/project-workspace'
import { trackingCheckout, trackingPlans, trackingSubscription, trackingUsage } from '@/test/fixtures/tracking-workspace'
import { language, problem, trackingPage } from '@/test/tracking-test-harness'

beforeEach(() => {
  vi.spyOn(organizationApi, 'list').mockResolvedValue([{ ...workspaceProfile, updatedAtUtc: '2027-02-01T12:00:00Z' }])
  vi.spyOn(billingApi, 'plans').mockResolvedValue(trackingPlans)
  vi.spyOn(billingApi, 'current').mockResolvedValue(trackingSubscription)
  vi.spyOn(billingApi, 'usage').mockResolvedValue(trackingUsage)
})
afterEach(() => { vi.restoreAllMocks(); vi.useRealTimers() })

it('shows the pilot offer and requires a budget selection before displaying indicative CLP prices', async () => {
  const create = vi.spyOn(billingApi, 'createCheckout')
  const user = userEvent.setup()
  trackingPage(<PublicPricingPage />, '/pricing')
  expect(screen.getByRole('link', { name: 'Registrar mi ONG gratis' })).toHaveAttribute('href', '/register')
  expect(screen.queryByText(/9.990/)).not.toBeInTheDocument()
  await user.selectOptions(screen.getByRole('combobox'), '0')
  expect(screen.getByText('$9.990 CLP')).toBeInTheDocument()
  expect(screen.getByText('$95.904 CLP')).toBeInTheDocument()
  await user.selectOptions(screen.getByRole('combobox'), '2')
  expect(screen.getByText('$19.990 CLP')).toBeInTheDocument()
  await language('en')
  expect(screen.getByRole('combobox')).toHaveValue('2')
  expect(screen.getByText('Premium · Coming soon')).toBeInTheDocument()
  expect(screen.getByRole('link', { name: 'Ask about special plans' })).toHaveAttribute('href', '/contact')
  expect(screen.queryByRole('button', { name: /checkout/i })).not.toBeInTheDocument()
  expect(create).not.toHaveBeenCalled()
  expect(billingApi.plans).not.toHaveBeenCalled()
})

it('does not initiate checkout on language change and retries the same price/idempotency key after uncertainty', async () => {
  const create = vi.spyOn(billingApi, 'createCheckout').mockRejectedValueOnce(problem(503, 'payment-provider-unavailable')).mockResolvedValue(trackingCheckout)
  const user = userEvent.setup()
  trackingPage(<SubscriptionWorkspacePage />, '/subscription')
  await screen.findByText('Uso y límites')
  await language('en')
  expect(create).not.toHaveBeenCalled()
  expect(billingApi.current).toHaveBeenCalledTimes(1)
  await user.click(screen.getByRole('button', { name: 'Try sandbox checkout' }))
  await screen.findByText(/We could not confirm the provider/)
  await language('es')
  expect(screen.getByRole('alert')).toHaveTextContent('No pudimos confirmar la respuesta del proveedor')
  await user.click(screen.getByRole('button', { name: 'Probar checkout sandbox' }))
  expect(await screen.findByText(/Checkout creado/)).toBeInTheDocument()
  expect(create).toHaveBeenCalledTimes(2)
  expect(create.mock.calls[0]).toEqual(create.mock.calls[1])
  expect(create.mock.calls[0].slice(0, 2)).toEqual([workspaceOrganizationId, 2])
  expect(create.mock.calls[0][2]).toMatch(/^[0-9a-f]{32}$/)
  await language('en')
  expect(screen.getByText(/Checkout created; wait/)).toBeInTheDocument()
})

it('keeps cancellation and resumption explicit and uses the authoritative ETag', async () => {
  const active = { ...trackingSubscription, planCode: 'PROFESSIONAL', planName: 'Professional', status: 'active' as const, freeFallback: false }
  vi.mocked(billingApi.current).mockResolvedValue(active)
  const cancel = vi.spyOn(billingApi, 'cancel').mockImplementation(async () => {
    const updated = { ...active, cancelAtPeriodEnd: true, eTag: '"next"' }
    vi.mocked(billingApi.current).mockResolvedValue(updated)
    return updated
  })
  const resume = vi.spyOn(billingApi, 'resume').mockResolvedValue(active)
  const user = userEvent.setup()
  trackingPage(<SubscriptionWorkspacePage />, '/subscription')
  await screen.findByRole('button', { name: 'Cancelar al fin del período' })
  await language('en')
  expect(cancel).not.toHaveBeenCalled()
  await user.click(screen.getByRole('button', { name: 'Cancel at period end' }))
  await screen.findByRole('button', { name: 'Resume renewal' })
  expect(cancel).toHaveBeenCalledExactlyOnceWith(workspaceOrganizationId, active.eTag)
  await language('es')
  expect(resume).not.toHaveBeenCalled()
  await user.click(screen.getByRole('button', { name: 'Reanudar renovación' }))
  expect(resume).toHaveBeenCalledExactlyOnceWith(workspaceOrganizationId, '"next"')
})

it('keeps pending checkout polling read-only and never activates a plan from the return URL', async () => {
  vi.useFakeTimers({ toFake: ['setInterval', 'clearInterval'] })
  const read = vi.spyOn(billingApi, 'checkout').mockResolvedValue(trackingCheckout)
  const create = vi.spyOn(billingApi, 'createCheckout')
  const { router, unmount } = trackingPage(<SubscriptionWorkspacePage />, '/subscription?checkout=' + trackingCheckout.id)
  await screen.findByText('Checkout: Pendiente de confirmación')
  await language('en')
  expect(screen.getByText('Checkout: Pending confirmation')).toBeInTheDocument()
  expect(router.state.location.search).toBe('?checkout=' + trackingCheckout.id)
  expect(read).toHaveBeenCalledTimes(1)
  await act(async () => { await vi.advanceTimersByTimeAsync(5000) })
  expect(read).toHaveBeenCalledTimes(2)
  expect(create).not.toHaveBeenCalled()
  expect(billingApi.current).toHaveBeenCalledTimes(1)
  expect(screen.getByText('Free', { selector: 'p.font-semibold' })).toBeInTheDocument()
  unmount()
})

it('does not allow checkout for members or when the current subscription cannot be loaded', async () => {
  vi.mocked(organizationApi.list).mockResolvedValue([{ ...workspaceProfile, membershipRole: 'member', updatedAtUtc: '2027-02-01T12:00:00Z' }])
  trackingPage(<SubscriptionWorkspacePage />, '/subscription')
  await language('en')
  expect(await screen.findByRole('button', { name: 'Try sandbox checkout' })).toBeDisabled()
  expect(screen.getByText('Only an organization administrator can change the plan.')).toBeInTheDocument()
})

it('shows retryable read errors and does not confuse organization errors with an empty workspace', async () => {
  vi.mocked(organizationApi.list).mockRejectedValueOnce(problem(503)).mockResolvedValue([{ ...workspaceProfile, updatedAtUtc: '2027-02-01T12:00:00Z' }])
  vi.mocked(billingApi.current).mockRejectedValue(problem(503))
  vi.mocked(billingApi.usage).mockRejectedValue(problem(503))
  const user = userEvent.setup()
  trackingPage(<SubscriptionWorkspacePage />, '/subscription')
  await screen.findByRole('alert')
  await language('en')
  expect(screen.getByRole('alert')).toHaveTextContent('We could not load your organization.')
  expect(screen.queryByRole('link', { name: 'Get started' })).not.toBeInTheDocument()
  await user.click(screen.getByRole('button', { name: 'Retry' }))
  await waitFor(() => expect(screen.getByText('We could not load the subscription.')).toBeInTheDocument())
  expect(screen.getByText('We could not load usage and limits.')).toBeInTheDocument()
  expect(screen.getByRole('button', { name: 'Try sandbox checkout' })).toBeDisabled()
})
