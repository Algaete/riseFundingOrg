import { useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Field, control, button } from '@/features/collaboration/collaboration-ui'
import { catalogName } from '@/i18n/catalog-labels'
import type { FundingDiscoveryCatalogs, PartnerGeography } from './funding-discovery-api'

export function PartnerGeographyFields({ value, catalogs, onChange }: {
  value?: PartnerGeography | null; catalogs?: FundingDiscoveryCatalogs; onChange: (value: PartnerGeography) => void
}) {
  const { t } = useTranslation()
  const [search, setSearch] = useState('')
  const geography = value ?? { scope: 0, countryIds: [], regionCodes: [] }
  const available = Boolean(catalogs?.partnerRegions && catalogs.partnerGeographyVersion)
  const update = (next: PartnerGeography) => onChange({ ...next, catalogVersion: catalogs?.partnerGeographyVersion })
  const countryName = (id: number) => {
    const country = catalogs?.countries.find(item => item.id === id)
    return country ? catalogName('countries', country) : t('fundingDiscovery.geography.unavailableCountry', { id })
  }
  return <fieldset className="min-w-0 space-y-3 rounded-lg border p-4" disabled={!available}>
    <legend className="font-semibold">{t('fundingDiscovery.geography.title')}</legend>
    <p className="text-sm">{t('fundingDiscovery.geography.help')}</p>
    {!available && <p role="status">{t('fundingDiscovery.geography.catalogUnavailable')}</p>}
    <Field label={t('fundingDiscovery.geography.scope')}><select className={control} value={geography.scope} onChange={event => {
      const scope = Number(event.target.value) as PartnerGeography['scope']
      update({ ...geography, scope, countryIds: scope === 2 ? geography.countryIds : [], regionCodes: scope === 2 ? geography.regionCodes : [] })
    }}>{([0, 1, 2] as const).map(scope => <option key={scope} value={scope}>{t(`fundingDiscovery.geography.scopes.${scope}`)}</option>)}</select></Field>
    {geography.scope === 2 && <>
      <p className="text-sm">{t('fundingDiscovery.geography.union')}</p>
      <fieldset className="space-y-2"><legend className="mb-2 font-medium">{t('fundingDiscovery.geography.regionsTitle')}</legend>
        {[...new Set([...(catalogs?.partnerRegions?.map(item => item.code) ?? []), ...geography.regionCodes])].map(code =>
          <label key={code} className="flex items-center gap-2"><input type="checkbox" checked={geography.regionCodes.includes(code)} onChange={event => update({ ...geography,
            regionCodes: event.target.checked ? [...geography.regionCodes, code] : geography.regionCodes.filter(item => item !== code) })} />
            {t(`fundingDiscovery.geography.regions.${code}`, { defaultValue: code })}</label>)}
      </fieldset>
      <p className="text-sm text-muted-foreground">{t('fundingDiscovery.geography.distinction')}</p>
      <Field label={t('fundingDiscovery.geography.search')}><input className={control} value={search} maxLength={120} onChange={event => setSearch(event.target.value)} /></Field>
      <fieldset className="max-h-52 space-y-2 overflow-y-auto rounded-lg border p-3"><legend>{t('fundingDiscovery.geography.countriesTitle')}</legend>
        {catalogs?.countries.filter(item => catalogName('countries', item).toLocaleLowerCase().includes(search.toLocaleLowerCase())).map(item =>
          <label key={item.id} className="flex items-center gap-2"><input type="checkbox" checked={geography.countryIds.includes(item.id)} onChange={event => update({ ...geography,
            countryIds: event.target.checked ? [...geography.countryIds, item.id] : geography.countryIds.filter(id => id !== item.id) })} />{countryName(item.id)}</label>)}
      </fieldset>
      {geography.countryIds.length > 0 && <div className="flex flex-wrap gap-2" aria-label={t('fundingDiscovery.geography.selected')}>
        {geography.countryIds.map(id => <button type="button" key={id} className="max-w-full break-words rounded-lg border px-3 py-2 text-sm" aria-label={t('fundingDiscovery.geography.remove', { country: countryName(id) })}
          onClick={() => update({ ...geography, countryIds: geography.countryIds.filter(country => country !== id) })}>{countryName(id)} ×</button>)}
      </div>}
      {geography.countryIds.length + geography.regionCodes.length === 0 && <p role="status">{t('fundingDiscovery.geography.choose')}</p>}
      {geography.regionCodes.length > 0 && geography.catalogVersion !== catalogs?.partnerGeographyVersion &&
        <button type="button" className={button} onClick={() => update(geography)}>{t('fundingDiscovery.geography.reconfirm')}</button>}
    </>}
  </fieldset>
}
