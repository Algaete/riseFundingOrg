import i18n from '@/i18n'

export function interfaceLocale() {
  return i18n.resolvedLanguage === 'en' ? 'en-US' : 'es-CL'
}

// A civil date has no timezone. Interpret and format it in UTC so every browser
// sees the same calendar day, including UTC-12/UTC+14 and daylight-saving changes.
export function formatDateValue(value: string | Date | null | undefined,
  options: Intl.DateTimeFormatOptions = { dateStyle: 'medium' }, missing = '—'): string {
  if (!value) return missing
  const civil = typeof value === 'string' ? /^(\d{4})-(\d{2})-(\d{2})$/.exec(value) : null
  const date = value instanceof Date ? value : new Date(civil ? value + 'T12:00:00Z' : value)
  if (Number.isNaN(date.getTime()) || (civil && (
    date.getUTCFullYear() !== Number(civil[1]) || date.getUTCMonth() + 1 !== Number(civil[2]) ||
    date.getUTCDate() !== Number(civil[3])))) return i18n.t('formats.invalidDate')
  const format = { ...options }
  if (civil) {
    format.timeZone = 'UTC'
    delete format.timeStyle
    delete format.hour
    delete format.minute
    delete format.second
    delete format.timeZoneName
  }
  try { return new Intl.DateTimeFormat(interfaceLocale(), format).format(date) }
  catch { return i18n.t('formats.invalidDate') }
}

export function formatNumber(value: number, options: Intl.NumberFormatOptions = {}): string {
  return Number.isFinite(value) ? new Intl.NumberFormat(interfaceLocale(), options).format(value) : '—'
}

export function formatMoneyValue(value: number | null, currency: string | null, missing = '—'): string {
  if (value === null || !Number.isFinite(value) || !currency) return missing
  try {
    // ISO currency metadata determines minor units: CLP/JPY 0, USD 2, KWD 3.
    // No FX conversion and no rounding or mutation of stored amounts.
    return new Intl.NumberFormat(interfaceLocale(), { style: 'currency', currency }).format(value)
  } catch { return missing }
}
