import { ApiError } from '@/api/http-client'
import i18n, { setInterfaceLanguage } from '@/i18n'
import { applicationStatusLabel, checkoutStatusLabel, notificationStatusLabel, subscriptionStatusLabel, trackingErrorMessage } from './tracking-messages'
import { billingDate, billingMoney, featureName, planDescription, usageAmount } from './billing-messages'

describe('tracking and billing presentation boundaries', () => {
  it.each(['es', 'en'])('localizes all protocol statuses in %s without returning raw unknown codes', async language => {
    await setInterfaceLanguage(language)
    for (const code of [0, 1, 2, 3, 4, 5] as const) expect(applicationStatusLabel(code)).not.toMatch(/dashboard\./)
    for (const code of ['pending', 'processing', 'sent', 'retry-scheduled', 'unknown', 'permanent-failed', 'skipped'])
      expect(notificationStatusLabel(code)).not.toMatch(/alerts\./)
    for (const code of ['free', 'pending', 'trialing', 'active', 'pastdue', 'canceled', 'expired'])
      expect(subscriptionStatusLabel(code)).not.toMatch(/billing\./)
    for (const code of ['creating', 'pending', 'completed', 'failed', 'expired'])
      expect(checkoutStatusLabel(code)).not.toMatch(/billing\./)
    for (const label of [notificationStatusLabel, checkoutStatusLabel, subscriptionStatusLabel])
      for (const code of ['future-private-code', 'toString', '__proto__']) expect(label(code)).toBe(i18n.t('tracking.unknown'))
  })

  it.each([
    [401, '', 'tracking.sessionExpired'], [403, '', 'tracking.forbidden'],
    [404, '', 'applications.notFound'], [410, '', 'applications.notFound'],
    [422, '', 'tracking.invalid'], [400, '', 'tracking.invalid'],
    [409, 'idempotency-conflict', 'tracking.idempotency'],
    [409, 'funding-application-conflict', 'applications.duplicate'],
    [409, 'funding-application-concurrency-conflict', 'tracking.conflict'],
    [412, '', 'applications.concurrency'], [428, '', 'tracking.precondition'],
    [429, '', 'tracking.rateLimited'], [503, '', 'tracking.writeUncertain'],
  ] as const)('safely maps application HTTP %s / %s', async (status, type, key) => {
    const error = new ApiError({ status, type: 'https://fundingplatform.local/problems/' + type, title: 'PRIVATE', detail: 'PRIVATE', errors: { field: ['PRIVATE'] } }, new Response(null, { status }))
    for (const language of ['es', 'en']) {
      await setInterfaceLanguage(language)
      expect(trackingErrorMessage(error, 'applications', 'write')).toBe(i18n.t(key))
      expect(trackingErrorMessage(error, 'applications', 'write')).not.toContain('PRIVATE')
    }
  })

  it.each([
    ['alerts', 503, 'alerts-disabled', 'alerts.emailDisabled'],
    ['billing', 503, 'billing-disabled', 'billing.disabled'],
    ['billing', 503, 'payment-provider-unavailable', 'billing.providerUnavailable'],
    ['billing', 409, 'checkout-already-open', 'billing.alreadyOpen'],
    ['billing', 409, 'subscription-invalid-transition', 'billing.invalidTransition'],
  ] as const)('maps only the known %s protocol problem %s %s', async (scope, status, code, key) => {
    await setInterfaceLanguage('en')
    const error = new ApiError({ status, type: 'https://fundingplatform.local/problems/' + code, title: 'PRIVATE' }, new Response(null, { status }))
    expect(trackingErrorMessage(error, scope, 'write')).toBe(i18n.t(key))
    const unknown = new ApiError({ status, type: 'https://untrusted.invalid/' + code, title: 'PRIVATE' }, new Response(null, { status }))
    expect(trackingErrorMessage(unknown, scope, 'write')).not.toBe(i18n.t(key))
  })

  it('formats without conversion and only translates exact bundled catalog copy', async () => {
    await setInterfaceLanguage('en')
    expect(billingMoney(12500.5, 'USD')).toBe('$12,500.50')
    expect(billingMoney(12500, 'CLP')).toContain('12,500')
    expect(billingMoney(12500.5, 'CUSTOM')).toBe('12,500.5 CUSTOM')
    expect(billingDate(null)).toBe('No date')
    expect(billingDate('invalid')).toBe('No date')
    expect(featureName('alerts.max', 'Límite de alertas')).toBe('Alert limit')
    expect(featureName('alerts.max', 'Límite personalizado Ñandú')).toBe('Límite personalizado Ñandú')
    expect(planDescription('FREE', 'Plan gratuito inicial para validar el MVP.')).toBe('Initial free plan to validate the MVP.')
    expect(planDescription('FREE', 'Condiciones Ñandú')).toBe('Condiciones Ñandú')
    expect(planDescription('FREE', null)).toBeNull()
    expect(usageAmount(1, 'items')).toBe('1 item')
    expect(usageAmount(20, 'items/month')).toBe('20 items/month')
    expect(usageAmount(1234, 'cupos Ñandú')).toBe('1,234 cupos Ñandú')
  })
})
