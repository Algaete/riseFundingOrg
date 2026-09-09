import { useState, type FormEvent } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { useTranslation } from 'react-i18next'
import { organizationApi } from '@/features/organizations/organization-api'
import { projectApi } from '@/features/projects/project-api'
import { funderOwnerScope } from '@/features/funder-workspace/editorial-scope'
import { button, control, panel, Field, Paging, LoadState, useCollaborationActor } from '@/features/collaboration/collaboration-ui'
import { catalogName } from '@/i18n/catalog-labels'
import { formatDateValue } from '@/i18n/formats'
import { discoveryMatchingApi, validDiscoveryInput, type DiscoveryRequest } from './discovery-matching-api'

export function DiscoveryMatchingPage() {
  const { t } = useTranslation()
  const actor = useCollaborationActor()
  const [parameters] = useSearchParams()
  const rawKind = Number(parameters.get('kind'))
  const initialKind = [1,2,3,4].includes(rawKind) ? rawKind as 1 | 2 | 3 | 4 : 1
  const [sourceKind, setSourceKind] = useState<1 | 2 | 3 | 4>(initialKind)
  const [sourceId, setSourceId] = useState(parameters.get('id') ?? '')
  const [organizationId, setOrganizationId] = useState('')
  const [targetKind, setTargetKind] = useState<1 | 2 | 3>(initialKind >= 3 ? 1 : 2)
  const [sourcePage, setSourcePage] = useState(1)
  const [criteria, setCriteria] = useState({ country: '', category: '', minimum: '', maximum: '', currency: '', stage: '' })
  const [request, setRequest] = useState<DiscoveryRequest | null>(null)
  const [invalid, setInvalid] = useState(false)
  const organizations = useQuery({ queryKey: ['ecosystem', actor, 'organizations'], queryFn: ({ signal }) => organizationApi.list(signal), enabled: sourceKind <= 2 })
  const catalogs = useQuery({ queryKey: ['organization-catalogs'], queryFn: ({ signal }) => organizationApi.catalogs(signal) })
  const choices = useQuery({ queryKey: ['ecosystem', actor, 'sources', sourceKind, organizationId, sourcePage], enabled: sourceKind >= 3 || (sourceKind === 1 && Boolean(organizationId)),
    queryFn: async ({ signal }) => {
      if (sourceKind === 1) { const projects = await projectApi.list(organizationId, signal); return { items: projects.filter(item => item.publicationStatus !== 4).map(item => ({ id: item.publicId, name: item.title })), total: projects.length } }
      if (sourceKind === 3) { const funders = await funderOwnerScope.apis.funders.list({ page: sourcePage, pageSize: 20 }, signal); return { items: funders.items.map(item => ({ id: item.funderId, name: item.name })), total: funders.totalCount } }
      const opportunities = await funderOwnerScope.apis.opportunities.list({ page: sourcePage, pageSize: 20 }, signal)
      return { items: opportunities.items.map(item => ({ id: item.opportunityId, name: item.title })), total: opportunities.totalCount }
    } })
  const results = useQuery({ queryKey: ['ecosystem', actor, 'results', request], enabled: Boolean(request),
    queryFn: ({ signal }) => discoveryMatchingApi.search(request!, signal), refetchOnWindowFocus: false, retry: false })
  const sourceOptions = sourceKind === 2 ? organizations.data?.map(item => ({ id: item.publicId, name: item.name })) : choices.data?.items
  function evaluate(event: FormEvent) {
    event.preventDefault()
    const next: DiscoveryRequest = { sourceKind, sourceId, targetKind, page: 1, pageSize: 20 }
    if (sourceKind === 3) next.criteria = { countryId: criteria.country ? Number(criteria.country) : undefined,
      categoryId: criteria.category ? Number(criteria.category) : undefined, minimumAmount: criteria.minimum ? Number(criteria.minimum) : undefined,
      maximumAmount: criteria.maximum ? Number(criteria.maximum) : undefined, currency: criteria.currency || undefined,
      projectStage: criteria.stage ? Number(criteria.stage) : undefined }
    setInvalid(!validDiscoveryInput(next))
    if (validDiscoveryInput(next)) setRequest(next)
  }
  return <div className="space-y-6"><header className="space-y-3"><h1 className="text-2xl font-bold">{t('ecosystem.title')}</h1><p>{t('ecosystem.intro')}</p>
    <nav className="flex flex-wrap gap-3"><Link className={button} to="/matching">{t('ecosystem.legacy')}</Link><Link className={button} to="/marketplace/map">{t('ecosystem.map')}</Link></nav></header>
    <form className={panel} onSubmit={evaluate} noValidate>
      <div className="grid gap-4 sm:grid-cols-2">
        <Field label={t('ecosystem.sourceKind')}><select className={control} value={sourceKind} onChange={e => { const kind = Number(e.target.value) as 1 | 2 | 3 | 4; setSourceKind(kind); setTargetKind(kind >= 3 ? 1 : 2); setSourceId(''); setSourcePage(1); setRequest(null) }}>
          {(['project','organization','funder','opportunity'] as const).map((key, index) => <option key={key} value={index + 1}>{t(`ecosystem.${key}`)}</option>)}</select></Field>
        {sourceKind === 1 && <Field label={t('ecosystem.organizationPicker')}><select className={control} value={organizationId} onChange={e => { setOrganizationId(e.target.value); setSourceId('') }}><option value="">{t('ecosystem.choose')}</option>{organizations.data?.map(item => <option key={item.publicId} value={item.publicId}>{item.name}</option>)}</select></Field>}
        <Field label={t('ecosystem.source')} required><select className={control} aria-required value={sourceId} onChange={e => setSourceId(e.target.value)}><option value="">{t('ecosystem.choose')}</option>
          {sourceId && !sourceOptions?.some(item => item.id === sourceId) && <option value={sourceId}>{t('ecosystem.existing')}</option>}
          {sourceOptions?.map(item => <option key={item.id} value={item.id}>{item.name}</option>)}</select></Field>
        <Field label={t('ecosystem.target')}><select className={control} value={targetKind} onChange={e => setTargetKind(Number(e.target.value) as 1 | 2 | 3)}>
          {sourceKind >= 3 ? <option value={1}>{t('ecosystem.projects')}</option> : <><option value={2}>{t('ecosystem.organizations')}</option><option value={3}>{t('ecosystem.professionals')}</option></>}</select></Field>
      </div>
      <LoadState pending={(sourceKind === 1 && Boolean(organizationId) || sourceKind >= 3) && choices.isPending} error={choices.error ?? organizations.error ?? catalogs.error} retry={() => Promise.all([...(sourceKind >= 3 || sourceKind === 1 && organizationId ? [choices.refetch()] : []), ...(sourceKind <= 2 ? [organizations.refetch()] : []), catalogs.refetch()])} />
      {sourceKind >= 3 && choices.data && <Paging page={sourcePage} total={choices.data.total} setPage={setSourcePage} />}
      {sourceKind === 3 && <fieldset className="space-y-4"><legend className="font-semibold">{t('ecosystem.criteria')}</legend><p>{t('ecosystem.criteriaHelp')}</p>
        <div className="grid gap-4 sm:grid-cols-2">
          <Field label={t('ecosystem.country')}><select className={control} value={criteria.country} onChange={e => setCriteria(current => ({ ...current, country: e.target.value }))}><option value="">{t('ecosystem.any')}</option>{catalogs.data?.countries.map(item => <option key={item.id} value={item.id}>{catalogName('countries', item)}</option>)}</select></Field>
          <Field label={t('ecosystem.category')}><select className={control} value={criteria.category} onChange={e => setCriteria(current => ({ ...current, category: e.target.value }))}><option value="">{t('ecosystem.any')}</option>{catalogs.data?.fundingCategories.map(item => <option key={item.id} value={item.id}>{catalogName('fundingCategories', item)}</option>)}</select></Field>
          {(['minimum','maximum'] as const).map(key => <Field key={key} label={t(`ecosystem.${key}`)}><input type="number" min={0} max={999999999999} className={control} value={criteria[key]} onChange={e => setCriteria(current => ({ ...current, [key]: e.target.value }))} /></Field>)}
          <Field label={t('ecosystem.currency')}><select className={control} value={criteria.currency} onChange={e => setCriteria(current => ({ ...current, currency: e.target.value }))}><option value="">{t('ecosystem.any')}</option>{catalogs.data?.currencies.map(item => <option key={item.code} value={item.code}>{item.code}</option>)}</select></Field>
          <Field label={t('ecosystem.stage')}><select className={control} value={criteria.stage} onChange={e => setCriteria(current => ({ ...current, stage: e.target.value }))}><option value="">{t('ecosystem.any')}</option>{(['stageIdea','stagePilot','stageImplementation','stageScaling','stageConsolidation','stageEvaluation'] as const).map((key, value) => <option key={value} value={value}>{t(`projects.${key}`)}</option>)}</select></Field>
        </div></fieldset>}
      {invalid && <p role="alert">{t('ecosystem.invalid')}</p>}<button className={button} disabled={results.isFetching}>{t('ecosystem.search')}</button>
    </form><p className={panel}>{t('ecosystem.disclaimer')}</p>
    {request && <LoadState pending={results.isPending} error={results.error} retry={() => results.refetch()} />}
    {results.data && <section className="space-y-4" aria-live="polite"><h2 className="text-xl font-semibold">{results.data.sourceName}</h2>
      <p>{t('ecosystem.evaluated', { engine: results.data.engineVersion, date: formatDateValue(results.data.evaluatedAtUtc, { dateStyle: 'medium', timeStyle: 'short' }) })}</p>
      {results.data.isTruncated && <p role="status">{t('ecosystem.truncated', { total: results.data.totalCandidateCount })}</p>}
      {results.data.items.length === 0 && <p>{t('ecosystem.empty')}</p>}
      {results.data.items.map(item => <article className={panel} key={item.id}><h3 className="text-lg font-semibold">{item.name}</h3><p>{item.summary}</p>
        <p>{item.score === null ? t('ecosystem.unknownScore') : t('ecosystem.score', { score: item.score })} · {t('ecosystem.coverage', { coverage: item.evidenceCoverage })}</p>
        <p>{t(`ecosystem.${({ aligned: 'aligned', gaps: 'gaps', 'partial-evidence': 'partialEvidence', 'insufficient-data': 'insufficientData' } as const)[item.classification]}`)}</p>
        <ul className="space-y-2">{item.reasons.map(rule => <li key={rule.code}><span className="font-medium">{t(`ecosystem.rules.${rule.code}`)}: </span>{t(`ecosystem.outcomes.${rule.outcome}`)}
          {rule.evidence.length > 0 && <p className="text-sm">{t('ecosystem.evidence', { values: rule.evidence.map(value => {
            const collection = rule.code === 'geography' ? 'countries' : rule.code === 'sector' ? 'fundingCategories' : rule.code === 'organization-type' ? 'organizationTypes' : null
            const entry = collection ? catalogs.data?.[collection].find(option => option.id === Number(value)) : null
            return entry && collection ? catalogName(collection, entry) : value
          }).join(' · ') })}</p>}</li>)}</ul>
        {item.href.startsWith('/') && !item.href.startsWith('//') && <Link className={button} to={item.href}>{t('ecosystem.view')}</Link>}
      </article>)}
      <Paging page={results.data.page} total={results.data.totalCount} disabled={results.isFetching} setPage={page => setRequest(current => current ? { ...current, page } : null)} />
    </section>}
  </div>
}
