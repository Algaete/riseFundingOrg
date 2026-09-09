import i18n from '@/i18n'
import { billingEs } from '@/i18n/billing/es'
import { workspaceLocale } from '@/i18n/workspace-messages'

function ownKey<T extends object>(object: T, key: string): key is Extract<keyof T, string> {
  return Object.prototype.hasOwnProperty.call(object, key)
}

export function planDescription(code: string, description: string | null) {
  // Only translate the exact bundled seed copy. Preserve custom catalog content.
  return ownKey(billingEs.descriptions, code) && description === billingEs.descriptions[code]
    ? i18n.t(`billing.descriptions.${code}`) : description
}

export function featureName(code: string, name: string) {
  const key = code.replaceAll('.', '_')
  return ownKey(billingEs.features, key) && name === billingEs.features[key]
    ? i18n.t(`billing.features.${key}`) : name
}

export function usageAmount(value: number, unit: string | null) {
  if (unit === 'items') return i18n.t('billing.units.items', { count: value })
  if (unit === 'items/month') return i18n.t('billing.units.monthly', { count: value })
  return [value.toLocaleString(workspaceLocale()), unit].filter(Boolean).join(' ')
}

export function billingMoney(amount: number, currency: string) {
  try {
    return new Intl.NumberFormat(workspaceLocale(), {
      style: 'currency', currency, maximumFractionDigits: currency === 'CLP' ? 0 : 2,
    }).format(amount)
  } catch {
    return `${amount.toLocaleString(workspaceLocale())} ${currency}`
  }
}

export function billingDate(value: string | null) {
  if (!value || Number.isNaN(new Date(value).getTime())) return i18n.t('billing.noDate')
  return new Intl.DateTimeFormat(workspaceLocale(), { dateStyle: 'long' }).format(new Date(value))
}
