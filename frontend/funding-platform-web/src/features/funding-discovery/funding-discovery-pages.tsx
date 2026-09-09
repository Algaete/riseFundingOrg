import { useState, type FormEvent } from 'react'
import { Link, useParams, useSearchParams } from 'react-router-dom'
import { useMutation, useQuery } from '@tanstack/react-query'
import { useTranslation } from 'react-i18next'
import { Field, Feedback, LoadState, Paging, button, control, panel, useCollaborationActor } from '@/features/collaboration/collaboration-ui'
import { executeEditorialCommand } from '@/features/funding/editorial-command-cache'
import { catalogName } from '@/i18n/catalog-labels'
import { formatDateValue, formatMoneyValue } from '@/i18n/formats'
import { fundingDiscoveryApi, type ClassificationAdmin, type DiscoveryClassification } from './funding-discovery-api'

const catalogFields = { countryId: 'countries', regionId: 'regions', categoryId: 'fundingCategories', fundingTypeId: 'fundingTypes', organizationTypeId: 'organizationTypes', languageId: 'languages' } as const
const booleanFields = ['requiresConsortium', 'requiresInternationalPartner'] as const
function KindOptions() { const { t } = useTranslation(); return <>{([1,2,3,4,5,6] as const).map(kind => <option key={kind} value={kind}>{t(`fundingDiscovery.kinds.${kind}`)}</option>)}</> }
function SafeSource({ url, label }: { url: string; label: string }) {
  try { const parsed = new URL(url); return ['https:', 'http:'].includes(parsed.protocol) && !parsed.username && !parsed.password ? <a className="break-all underline" href={url} rel="noopener noreferrer" target="_blank">{label}</a> : <span>{label}</span> } catch { return <span>{label}</span> }
}
export function FundingExplorerPage() {
  const { t } = useTranslation()
  const [params, setParams] = useSearchParams()
  const [invalid, setInvalid] = useState(false)
  const catalogs = useQuery({ queryKey: ['funding-discovery-catalogs'], queryFn: ({ signal }) => fundingDiscoveryApi.catalogs(signal) })
  const query = new URLSearchParams(params); if (!query.has('page')) query.set('page', '1'); query.set('pageSize', '20')
  const results = useQuery({ queryKey: ['funding-discovery', query.toString()], queryFn: ({ signal }) => fundingDiscoveryApi.search(query, signal), retry: false })
  function search(event: FormEvent<HTMLFormElement>) {
    event.preventDefault(); const values = new FormData(event.currentTarget); const next = new URLSearchParams()
    values.forEach((value, key) => { if (String(value).trim()) next.set(key, String(value).trim()) })
    next.set('onlyOpen', values.has('onlyOpen') ? 'true' : 'false'); next.set('page', '1')
    const min = next.get('minimumAmount'), max = next.get('maximumAmount'), from = next.get('closingFrom'), to = next.get('closingTo')
    const valid = !((min || max) && !next.get('currency')) && !(min && max && Number(min) > Number(max)) && !(from && to && from > to)
    setInvalid(!valid); if (valid) setParams(next)
  }
  return <div className="mx-auto max-w-6xl space-y-6 px-4 py-8"><header className="space-y-3"><h1 className="text-3xl font-bold">{t('fundingDiscovery.title')}</h1><p>{t('fundingDiscovery.intro')}</p><Link className={button} to="/funding">{t('fundingDiscovery.back')}</Link></header>
    <form key={`${params.toString()}:${Boolean(catalogs.data)}`} onSubmit={search} className={panel}><fieldset disabled={!catalogs.data} className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
      <Field label={t('fundingDiscovery.query')}><input className={control} name="query" maxLength={300} defaultValue={params.get('query') ?? ''} /></Field>
      {(Object.entries(catalogFields) as [keyof typeof catalogFields, typeof catalogFields[keyof typeof catalogFields]][]).map(([key, catalog]) => <Field key={key} label={t(`fundingDiscovery.${key}`)}><select className={control} name={key} defaultValue={params.get(key) ?? ''}><option value="">{t('fundingDiscovery.any')}</option>{catalogs.data?.[catalog].map(item => <option key={item.id} value={item.id}>{catalogName(catalog, item)}</option>)}</select></Field>)}
      <Field label={t('fundingDiscovery.funderKind')}><select className={control} name="funderKind" defaultValue={params.get('funderKind') ?? ''}><option value="">{t('fundingDiscovery.any')}</option><KindOptions /></select></Field>
      {booleanFields.map(key => <Field key={key} label={t(`fundingDiscovery.${key}`)}><select className={control} name={key} defaultValue={params.get(key) ?? ''}><option value="">{t('fundingDiscovery.any')}</option><option value="true">{t('fundingDiscovery.yes')}</option><option value="false">{t('fundingDiscovery.no')}</option></select></Field>)}
      {(['minimumAmount','maximumAmount'] as const).map(key => <Field key={key} label={t(`fundingDiscovery.${key}`)}><input className={control} name={key} type="number" min={0} max={999999999999} step="0.01" defaultValue={params.get(key) ?? ''} /></Field>)}
      <Field label={t('fundingDiscovery.currency')}><select className={control} name="currency" defaultValue={params.get('currency') ?? ''}><option value="">{t('fundingDiscovery.any')}</option>{catalogs.data?.currencies.map(item => <option key={item.code}>{item.code}</option>)}</select></Field>
      {(['closingFrom','closingTo'] as const).map(key => <Field key={key} label={t(`fundingDiscovery.${key}`)}><input className={control} name={key} type="date" defaultValue={params.get(key) ?? ''} /></Field>)}
    </fieldset><label className="flex items-center gap-2"><input disabled={!catalogs.data} type="checkbox" name="onlyOpen" defaultChecked={params.get('onlyOpen') !== 'false'} />{t('fundingDiscovery.onlyOpen')}</label>
      <LoadState pending={catalogs.isPending} error={catalogs.error} retry={() => catalogs.refetch()} />
      {invalid && <p role="alert">{t('fundingDiscovery.invalid')}</p>}<button className={button} disabled={results.isFetching}>{t('fundingDiscovery.search')}</button></form>
    <p>{t('fundingDiscovery.disclaimer')}</p><LoadState pending={results.isPending} error={results.error} retry={() => results.refetch()} />
    {results.data && <section className="space-y-4" aria-live="polite">{results.data.items.length === 0 && <p>{t('fundingDiscovery.empty')}</p>}
      {results.data.items.map(item => <article key={item.id} className={panel}><h2 className="text-xl font-semibold">{item.title}</h2><p>{item.summary}</p>
        <p>{item.classification?.funderKind ? t(`fundingDiscovery.kinds.${item.classification.funderKind as 1 | 2 | 3 | 4 | 5 | 6}`) : t('fundingDiscovery.unknown')}</p>
        {booleanFields.map(key => <p key={key}>{t(`fundingDiscovery.${key}`)}: {t(`fundingDiscovery.${item.classification?.[key] === null || item.classification?.[key] === undefined ? 'unknown' : item.classification[key] ? 'yes' : 'no'}`)}</p>)}
        <p>{item.minimumAmount === null && item.maximumAmount === null ? t('fundingDiscovery.unknown') : `${item.minimumAmount === null ? '—' : formatMoneyValue(item.minimumAmount, item.currency)} – ${item.maximumAmount === null ? '—' : formatMoneyValue(item.maximumAmount, item.currency)}`}</p>
        <p>{t('fundingDiscovery.closingTo')}: {item.closeDate ? formatDateValue(item.closeDate) : t('fundingDiscovery.unknown')}</p>
        <p>{item.lastVerifiedAtUtc ? t('fundingDiscovery.updated', { date: formatDateValue(item.lastVerifiedAtUtc) }) : t('fundingDiscovery.neverVerified')}</p>
        <SafeSource url={item.sourceUrl} label={`${t('fundingDiscovery.source')}: ${item.sourceName}`} />
        <nav className="flex flex-wrap gap-3"><Link className={button} to={`/funding/${encodeURIComponent(item.slug)}`}>{t('fundingDiscovery.view')}</Link><Link className={button} to={`/matching/ecosystem?kind=4&id=${item.id}`}>{t('fundingDiscovery.matching')}</Link></nav>
      </article>)}<Paging page={results.data.page} total={results.data.totalCount} disabled={results.isFetching} setPage={page => { const next = new URLSearchParams(params); next.set('page', String(page)); setParams(next) }} />
    </section>}
  </div>
}
export function FundingClassificationPage() {
  const { id = '' } = useParams(); const actor = useCollaborationActor(); const { t } = useTranslation()
  const query = useQuery({ queryKey: ['funding-classification', actor, id], queryFn: ({ signal }) => fundingDiscoveryApi.get(id, signal), retry: false, refetchOnWindowFocus: false })
  return <div className="space-y-5"><h1 className="text-2xl font-bold">{t('fundingDiscovery.adminTitle')}</h1><Link className={button} to={`/admin/funding/${id}`}>{t('fundingDiscovery.back')}</Link>
    <LoadState pending={query.isPending} error={query.error} retry={() => query.refetch()} />{query.data && <ClassificationForm key={`${query.data.eTag}-${query.data.contentVersion}`} item={query.data} reload={() => query.refetch()} />}</div>
}
function ClassificationForm({ item, reload }: { item: ClassificationAdmin; reload: () => Promise<unknown> }) {
  const { t } = useTranslation(); const actor = useCollaborationActor(); const [saved, setSaved] = useState(false)
  const [data, setData] = useState<DiscoveryClassification>(item.data ?? { funderKind: null, requiresConsortium: null, requiresInternationalPartner: null, evidenceUrl: null })
  const [eTag, setETag] = useState(item.eTag)
  const save = useMutation({ mutationFn: () => executeEditorialCommand(`classification:${actor}:${item.opportunityId}`, { data, eTag, contentVersion: item.contentVersion }, key => fundingDiscoveryApi.review(item.opportunityId, item.contentVersion, data, eTag, key)),
    onSuccess: result => { setETag(result.eTag); setSaved(true) } })
  return <form className={panel} onSubmit={event => { event.preventDefault(); setSaved(false); save.mutate() }}><h2 className="text-xl font-semibold">{item.title}</h2><p>{t('fundingDiscovery.adminHelp')}</p>
    {item.reviewedContentVersion !== null && item.reviewedContentVersion !== item.contentVersion && <p role="status">{t('fundingDiscovery.stale')}</p>}
    <Field label={t('fundingDiscovery.funderKind')}><select className={control} value={data.funderKind ?? ''} onChange={e => setData(current => ({ ...current, funderKind: e.target.value ? Number(e.target.value) : null }))}><option value="">{t('fundingDiscovery.unknown')}</option><KindOptions /></select></Field>
    {booleanFields.map(key => <Field key={key} label={t(`fundingDiscovery.${key}`)}><select className={control} value={data[key] === null ? '' : String(data[key])} onChange={e => setData(current => ({ ...current, [key]: e.target.value === '' ? null : e.target.value === 'true' }))}><option value="">{t('fundingDiscovery.unknown')}</option><option value="true">{t('fundingDiscovery.yes')}</option><option value="false">{t('fundingDiscovery.no')}</option></select></Field>)}
    <Field label={t('fundingDiscovery.evidenceUrl')} required><select required className={control} value={data.evidenceUrl ?? ''} onChange={e => setData(current => ({ ...current, evidenceUrl: e.target.value }))}><option value="">{t('fundingDiscovery.unknown')}</option>{item.sourceUrls.filter(url => url.startsWith('https://')).map(url => <option key={url} value={url}>{url}</option>)}</select></Field>
    <Feedback error={save.error} />{saved && <p role="status">{t('fundingDiscovery.saved')}</p>}<div className="flex flex-wrap gap-3"><button className={button} disabled={save.isPending}>{t('fundingDiscovery.save')}</button><button type="button" className={button} disabled={save.isPending} onClick={() => void reload()}>{t('fundingDiscovery.reload')}</button></div>
  </form>
}
