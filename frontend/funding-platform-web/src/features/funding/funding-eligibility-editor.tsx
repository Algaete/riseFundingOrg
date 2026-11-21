import { useTranslation } from 'react-i18next'
import type { FundingEligibilityPolicy } from './funding-eligibility-policy'

type Option = { id: number; name: string }
type Props = {
  value: FundingEligibilityPolicy
  onChange: (value: FundingEligibilityPolicy) => void
  sourceUrl: string
  categories: Option[]
  beneficiaries: Option[]
  currencies: Array<{ code: string; name: string }>
  invalid: boolean
}

export function FundingEligibilityEditor({ value, onChange, sourceUrl, categories, beneficiaries, currencies, invalid }: Props) {
  const { t } = useTranslation()
  const labels = 'adminFunding.eligibilityPolicy.'
  function update(change: Partial<NonNullable<FundingEligibilityPolicy>>) {
    if (value) onChange({ ...value, ...change })
  }
  const fieldClass = 'w-full rounded-md border border-input bg-background px-3 py-2 text-sm'
  return <fieldset className="grid gap-4 rounded-xl border p-4">
    <legend className="px-1 font-semibold">{t(`${labels}title`)}</legend>
    <p className="text-sm text-muted-foreground">{t(`${labels}help`)}</p>
    <label className="flex items-start gap-2"><input type="checkbox" checked={value !== null} onChange={event => onChange(event.target.checked ? {
      sourceUrl, projectBudgetLimit: null, organizationAnnualBudgetLimit: null,
      requiredCategoryIds: [], requiredBeneficiaryTypeIds: [], manualRequirements: [],
    } : null)} />{t(`${labels}reviewed`)}</label>
    {value && <>
      <label className="grid gap-1">{t(`${labels}source`)}<input className={fieldClass} type="url" value={value.sourceUrl} onChange={event => update({ sourceUrl: event.target.value })} /></label>
      {(['projectBudgetLimit', 'organizationAnnualBudgetLimit'] as const).map(key => {
        const limit = value[key]
        return <fieldset key={key} className="grid gap-3 rounded-lg border p-3">
          <legend className="px-1 text-sm font-medium">{t(`${labels}${key}`)}</legend>
          <label className="flex items-start gap-2"><input type="checkbox" checked={limit !== null} onChange={event => update({ [key]: event.target.checked ? { amount: 0, currency: 'USD', inclusive: false } : null })} />{t(`${labels}hasLimit`)}</label>
          {limit && <div className="grid gap-3 sm:grid-cols-3">
            <label className="grid gap-1">{t(`${labels}amount`)}<input className={fieldClass} type="number" min="0.0001" step="0.0001" value={limit.amount} onChange={event => update({ [key]: { ...limit, amount: Number(event.target.value) } })} /></label>
            <label className="grid gap-1">{t(`${labels}currency`)}<select className={fieldClass} value={limit.currency} onChange={event => update({ [key]: { ...limit, currency: event.target.value } })}>{currencies.map(currency => <option key={currency.code} value={currency.code}>{currency.code} · {currency.name}</option>)}</select></label>
            <label className="grid gap-1">{t(`${labels}boundary`)}<select className={fieldClass} value={limit.inclusive ? 'inclusive' : 'exclusive'} onChange={event => update({ [key]: { ...limit, inclusive: event.target.value === 'inclusive' } })}><option value="exclusive">{t(`${labels}exclusive`)}</option><option value="inclusive">{t(`${labels}inclusive`)}</option></select></label>
          </div>}
        </fieldset>
      })}
      {([{ key: 'requiredCategoryIds', options: categories.filter(item => item.id !== 16) },
        { key: 'requiredBeneficiaryTypeIds', options: beneficiaries.filter(item => item.id !== 12) }] as const).map(({ key, options }) => <fieldset key={key} className="grid gap-2 rounded-lg border p-3">
        <legend className="px-1 text-sm font-medium">{t(`${labels}${key}`)}</legend>
        <p className="text-sm text-muted-foreground">{t(`${labels}anyRequired`)}</p>
        <div className="grid gap-2 sm:grid-cols-2">{options.map(option => <label key={option.id} className="flex items-start gap-2"><input type="checkbox" checked={value[key].includes(option.id)} onChange={event => update({ [key]: event.target.checked ? [...value[key], option.id] : value[key].filter(id => id !== option.id) })} />{option.name}</label>)}</div>
      </fieldset>)}
      <label className="grid gap-1">{t(`${labels}manual`)}<textarea className={fieldClass} rows={4} value={value.manualRequirements.join('\n')} onChange={event => update({ manualRequirements: event.target.value.split('\n') })} onBlur={() => update({ manualRequirements: value.manualRequirements.map(text => text.trim()).filter(Boolean) })} /></label>
      <p className="text-sm text-muted-foreground">{t(`${labels}manualHelp`)}</p>
    </>}
    {invalid && <p role="alert" className="text-sm text-destructive">{t(`${labels}invalid`)}</p>}
  </fieldset>
}
