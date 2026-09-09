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

it('makes public pricing a read-only catalog with a real subscription link, not a no-op checkout', async () => {
  const create = vi.spyOn(billingApi, 'createCheckout')
  trackingPage(<PublicPricingPage />, '/pricing')
  await screen.findByText('Plan gratuito')
  await language('en')
  expect(screen.getByText('Free plan')).toBeInTheDocument()
  expect(screen.queryByRole('button', { name: /checkout/ })).not.toBeInTheDocument()
  expect(screen.getByRole('link', { name: 'View subscription' })).toHaveAttribute('href', '/subscription')
  expect(screen.getByText('$12,500.50')).toBeInTheDocument()
  expect(screen.getByText('Initial free plan to validate the MVP.')).toBeInTheDocument()
  expect(create).not.toHaveBeenCalled()
  expect(billingApi.plans).toHaveBeenCalledTimes(1)
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
