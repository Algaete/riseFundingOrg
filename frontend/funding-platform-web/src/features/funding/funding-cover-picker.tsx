import { useTranslation } from 'react-i18next'
import { fundingCoverKeys, resolveFundingCover } from './funding-covers'
import { FundingCover } from './funding-cover'

export function FundingCoverPicker({ value, onChange, error }: {
  value: string; onChange: (key: string) => void; error?: string
}) {
  const { t } = useTranslation()
  return <fieldset id="funding-field-coverKey" aria-describedby="funding-cover-help" className="rounded-xl border bg-card p-5">
    <legend className="px-2 text-lg font-bold">{t('adminFunding.coverTitle')}</legend>
    <p id="funding-cover-help" className="mb-4 text-sm leading-relaxed text-muted-foreground">{t('adminFunding.coverHelp')}</p>
    <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 xl:grid-cols-5">
      {fundingCoverKeys.map(key => <label key={key} className={`min-w-0 cursor-pointer overflow-hidden rounded-xl border bg-background focus-within:ring-2 focus-within:ring-ring ${value === key ? 'border-primary ring-2 ring-primary/25' : 'border-border'}`}>
        <div aria-hidden="true"><FundingCover coverKey={key} compact /></div>
        <span className="flex items-start gap-2 p-3 text-sm font-medium">
          <input type="radio" name="coverKey" value={key} checked={value === key} onChange={() => onChange(key)}
            aria-invalid={Boolean(error)} aria-describedby={error ? 'funding-cover-error' : undefined} className="mt-0.5 accent-primary" />
          <span>{t(key === 'auto' ? 'adminFunding.coverAuto' : `fundingCatalog.${resolveFundingCover(key).label}`)}</span>
        </span>
      </label>)}
    </div>
    {error && <p id="funding-cover-error" role="alert" className="mt-3 text-sm text-destructive">{error}</p>}
    <p className="mt-4 text-xs leading-relaxed text-muted-foreground">{t('adminFunding.coverUploadsPending')}</p>
  </fieldset>
}
