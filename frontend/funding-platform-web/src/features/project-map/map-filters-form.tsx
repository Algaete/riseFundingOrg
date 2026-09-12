import { useTranslation } from 'react-i18next'
import { Button } from '@/components/ui/button'
import { catalogName } from '@/i18n/catalog-labels'
import type { MarketplaceCatalogs } from '@/features/marketplace/marketplace-api'
import { mapNeeds } from './map-filters'

const input = 'h-10 min-w-0 w-full max-w-full rounded-lg border bg-background px-3'
export function MapFiltersForm({ search, catalogs, apply, clear }: {
  search: URLSearchParams; catalogs?: MarketplaceCatalogs; apply: (query: URLSearchParams) => void; clear: () => void
}) {
  const { t } = useTranslation()
  const stages = ['stageIdea', 'stagePilot', 'stageImplementation', 'stageScaling', 'stageConsolidation', 'stageEvaluation'] as const
  const statuses = ['statusIdea', 'statusDesign', 'statusSeeking', 'statusPartial', 'statusFunded', 'statusRunning', 'statusFinished'] as const
  const collections = { countryId: 'countries', categoryId: 'fundingCategories', sustainableDevelopmentGoalId: 'sustainableDevelopmentGoals', organizationTypeId: 'organizationTypes' } as const
  return <form className="grid gap-3 rounded-xl border bg-card p-4 sm:grid-cols-2 lg:grid-cols-3" onSubmit={event => {
    event.preventDefault()
    const next = new URLSearchParams()
    for (const [key, value] of new FormData(event.currentTarget)) if (String(value).trim()) next.set(key, String(value).trim())
    for (const id of search.getAll('projectIds')) next.append('projectIds', id)
    apply(next)
  }}>
    <label className="grid min-w-0 gap-1 text-sm font-semibold">{t('projectMap.search')}<input name="q" maxLength={200} className={input} defaultValue={search.get('q') ?? ''} /></label>
    {(Object.keys(collections) as (keyof typeof collections)[]).map(key => <label key={key} className="grid min-w-0 gap-1 text-sm font-semibold">{t(`projectMap.${key}`)}
      <select name={key} defaultValue={search.get(key) ?? ''} className={input}><option value="">{t('projectMap.all')}</option>{catalogs?.[collections[key]]?.map(item => <option key={item.id} value={item.id}>{catalogName(collections[key], item)}</option>)}</select>
    </label>)}
    {(['projectStage', 'projectStatus'] as const).map(key => <label key={key} className="grid min-w-0 gap-1 text-sm font-semibold">{t(`projectMap.${key}`)}<select className={input} name={key} defaultValue={search.get(key) ?? ''}><option value="">{t('projectMap.all')}</option>{(key === 'projectStage' ? stages : statuses).map((label, value) => <option key={label} value={value}>{t(`projects.${label}`)}</option>)}</select></label>)}
    <fieldset className="grid min-w-0 gap-3 rounded-lg border p-3 sm:col-span-2 lg:col-span-3 sm:grid-cols-3">
      <legend className="px-1 font-semibold">{t('projectMap.amountTitle')}</legend>
      {(['minimumFundingGap', 'maximumFundingGap'] as const).map(key => <label key={key} className="grid min-w-0 gap-1 text-sm font-semibold">{t(`projectMap.${key}`)}<input name={key} className={input} type="number" min="0" max="999999999999" step="0.0001" defaultValue={search.get(key) ?? ''} /></label>)}
      <label className="grid min-w-0 gap-1 text-sm font-semibold">{t('projectMap.currency')}<select className={input} name="currency" defaultValue={search.get('currency') ?? ''}><option value="">{t('projectMap.all')}</option>{catalogs?.currencies.map(item => <option key={item.code} value={item.code}>{item.code}</option>)}</select></label>
      <p className="text-sm text-muted-foreground sm:col-span-3">{t('projectMap.amountHelp')}</p>
    </fieldset>
    <fieldset className="grid min-w-0 gap-3 sm:col-span-2 lg:col-span-3 sm:grid-cols-2">
      <legend className="mb-2 font-semibold">{t('projectMap.needsTitle')}</legend>
      {mapNeeds.map(key => <label key={key} className="flex items-center gap-2 text-sm"><input type="checkbox" name={key} value="true" defaultChecked={search.get(key) === 'true'} className="size-4 shrink-0" />{t(`projectMap.${key}`)}</label>)}
      <p className="text-sm text-muted-foreground sm:col-span-2">{t('projectMap.needsHelp')}</p>
    </fieldset>
    <Button type="submit">{t('projectMap.apply')}</Button><Button type="button" variant="outline" onClick={clear}>{t('projectMap.clear')}</Button>
  </form>
}
