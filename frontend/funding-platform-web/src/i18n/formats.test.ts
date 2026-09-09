import { formatDateValue, formatMoneyValue, formatNumber } from './formats'
import { setInterfaceLanguage } from './index'

it.each(['Pacific/Kiritimati', 'Etc/GMT+12', 'America/Santiago', 'UTC'])('keeps civil dates unchanged in %s', async timeZone => {
  const input = '2024-02-29'
  expect(formatDateValue(input, { dateStyle: 'long', timeZone })).toBe('29 de febrero de 2024')
  await setInterfaceLanguage('en')
  expect(formatDateValue(input, { dateStyle: 'long', timeZone })).toBe('February 29, 2024')
  expect(input).toBe('2024-02-29')
})

it.each(['2023-02-29', '2026-02-30', '2026-13-01', 'not-a-date', new Date(NaN)])('handles invalid dates safely: %s', async value => {
  expect(formatDateValue(value)).toBe('Fecha inválida')
  await setInterfaceLanguage('en')
  expect(formatDateValue(value)).toBe('Invalid date')
})

it('formats timestamps in the requested timezone without changing the instant', async () => {
  await setInterfaceLanguage('en')
  const instant = new Date('2026-09-09T01:30:00Z')
  expect(formatDateValue(instant, { dateStyle: 'long', timeZone: 'America/Santiago' })).toBe('September 8, 2026')
  expect(formatDateValue(instant, { hour: '2-digit', minute: '2-digit', hourCycle: 'h23', timeZone: 'UTC' })).toBe('01:30')
  expect(instant.toISOString()).toBe('2026-09-09T01:30:00.000Z')
  expect(formatDateValue(null, {}, 'No date')).toBe('No date')
  expect(formatDateValue(instant, { timeZone: 'NOT-A-ZONE' })).toBe('Invalid date')
})

it('does not invent times for civil dates', async () => {
  await setInterfaceLanguage('en')
  expect(formatDateValue('2026-09-09', { dateStyle: 'long', timeStyle: 'short' })).toBe('September 9, 2026')
})

it.each([['CLP', 0], ['JPY', 0], ['USD', 2], ['KWD', 3]] as const)('uses ISO minor units for %s', async (currency, decimals) => {
  const amount = 12345.678
  for (const [language, locale] of [['es', 'es-CL'], ['en', 'en-US']] as const) {
    await setInterfaceLanguage(language)
    const formatter = new Intl.NumberFormat(locale, { style: 'currency', currency })
    expect(formatter.resolvedOptions().maximumFractionDigits).toBe(decimals)
    expect(formatMoneyValue(amount, currency)).toBe(formatter.format(amount))
  }
  expect(amount).toBe(12345.678)
})

it('localizes decimals and handles missing, malformed and non-finite amounts', async () => {
  expect(formatNumber(12345.67)).toBe('12.345,67')
  await setInterfaceLanguage('en')
  expect(formatNumber(12345.67)).toBe('12,345.67')
  expect(formatMoneyValue(12, 'PRIVATE-CURRENCY', 'Not reported')).toBe('Not reported')
  expect(formatMoneyValue(null, 'USD')).toBe('—')
  expect(formatMoneyValue(Infinity, 'USD')).toBe('—')
  expect(formatMoneyValue(NaN, 'USD')).toBe('—')
  expect(formatMoneyValue(0, 'USD')).toBe('$0.00')
  expect(formatNumber(Infinity)).toBe('—')
})
