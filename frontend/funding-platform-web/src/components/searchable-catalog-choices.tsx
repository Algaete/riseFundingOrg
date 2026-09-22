import { useId, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Input } from '@/components/ui/input'
import { catalogLanguage, catalogName, type CatalogKind } from '@/i18n/catalog-labels'
import type { CatalogOption } from '@/features/organizations/organization-api'

const normalize = (value: string) => value.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLocaleLowerCase().trim()

export function SearchableCatalogChoices({ catalog, label, items, selected, onChange }: {
  catalog: CatalogKind; label: string; items: CatalogOption<number>[]; selected: number[]
  onChange: (value: number[]) => void
}) {
  const { t } = useTranslation()
  const id = useId()
  const [search, setSearch] = useState('')
  const query = normalize(search)
  const chosen = items.filter(item => selected.includes(item.id))
  const available = items.filter(item => !selected.includes(item.id) && normalize(`${catalogName(catalog, item)} ${item.code ?? ''}`).includes(query))
  const choice = (item: CatalogOption<number>) => <label className="flex cursor-pointer items-center gap-2 rounded-lg border bg-background px-3 py-2 text-sm" key={item.id}>
    <input type="checkbox" checked={selected.includes(item.id)} onChange={() => onChange(selected.includes(item.id) ? selected.filter(value => value !== item.id) : [...selected, item.id])} />
    <span lang={catalogLanguage(catalog, item)}>{catalogName(catalog, item)}</span>
  </label>
  return <fieldset className="space-y-3">
    <legend className="text-sm font-semibold">{label}</legend>
    <label className="grid gap-1 text-sm" htmlFor={id}>{t('projects.searchCountries')}
      <Input id={id} type="search" value={search} onChange={event => setSearch(event.target.value)} placeholder={t('projects.searchCountriesPlaceholder')} />
    </label>
    {chosen.length > 0 && <div role="group" className="grid gap-2 sm:grid-cols-2" aria-label={t('projects.selectedCountries')}>{chosen.map(choice)}</div>}
    <div role="group" className="grid max-h-52 gap-2 overflow-y-auto sm:grid-cols-2" aria-label={t('projects.countryResults')}>{available.map(choice)}</div>
    {available.length === 0 && <p role="status" className="text-sm text-muted-foreground">{t('projects.noCountryResults')}</p>}
  </fieldset>
}
