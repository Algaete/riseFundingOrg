import { ProjectEnrichmentSummary } from './project-enrichment-summary'
import { formatDateValue, formatMoneyValue, formatNumber } from '@/i18n/formats'
import { useMutation, useQuery, useQueryClient, type UseQueryResult } from '@tanstack/react-query'
import {
  ArrowLeft,
  Building2,
  CalendarDays,
  CheckCircle2,
  CircleAlert,
  ExternalLink,
  Globe2,
  LoaderCircle,
  MapPin,
  ShieldCheck,
  Target,
  WalletCards,
  XCircle,
} from 'lucide-react'
import { useEffect, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { catalogName, catalogLanguage, type CatalogKind } from '@/i18n/catalog-labels'
import { workspaceMessage, formatWorkspaceDate } from '@/i18n/workspace-messages'
import { Link, useNavigate, useParams } from 'react-router-dom'

import i18n from '@/i18n'
import { adminErrorMessage, isConcurrencyConflict } from '@/i18n/editorial-messages'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import {
  createProjectCommandId,
  projectReviewApi,
  publicProjectApi,
  type ProjectReviewDetails,
  type ProjectReviewDecision,
  type ProjectReviewQueueItem,
  type PublicProject,
  type PublicProjectCatalogItem,
} from '@/features/projects/project-api'

const projectStatusNames = [
  'Idea',
  'Diseño',
  'Buscando financiamiento',
  'Financiado parcialmente',
  'Financiado',
  'En ejecución',
  'Finalizado',
]
const projectStageNames = [
  'Idea / diseño',
  'Piloto',
  'Implementación',
  'Escalamiento',
  'Consolidación',
  'Evaluación',
]

function projectStageName(stage: number | null) {
  return stage === null ? 'Sin definir' : projectStageNames[stage] ?? 'Sin definir'
}

function errorMessage(error: unknown) {
  return adminErrorMessage(error)
}

function formatDate(value: string) {
  return formatDateValue(value, { dateStyle: 'long' })
}

function formatMoney(value: number | null, currency: string | null) {
  return formatMoneyValue(value, currency, i18n.t('editorial.notReported'))
}

function ReviewCard({ item }: { item: ProjectReviewQueueItem }) {
  useTranslation()
  return <Card>
    <CardHeader>
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <p className="text-xs font-bold uppercase tracking-[0.16em] text-primary">{item.organizationName}</p>
          <CardTitle className="mt-1 text-xl">{item.title}</CardTitle>
        </div>
        <span className="rounded-full bg-accent px-3 py-1 text-xs font-semibold text-accent-foreground">{i18n.t('adminProjects.complete', { value: formatNumber(item.completeness) })}</span>
      </div>
    </CardHeader>
    <CardContent className="space-y-4">
      <p className="text-sm leading-6 text-muted-foreground">{item.summary ?? i18n.t('adminProjects.noSummary')}</p>
      <dl className="grid gap-3 text-sm sm:grid-cols-4">
        <div><dt className="text-muted-foreground">{i18n.t('adminProjects.status')}</dt><dd className="font-semibold">{projectStatusNames[item.projectStatus] ? workspaceMessage(projectStatusNames[item.projectStatus]) : i18n.t('adminProjects.unclassified')}</dd></div>
        <div><dt className="text-muted-foreground">{i18n.t('adminProjects.stage')}</dt><dd className="font-semibold">{workspaceMessage(projectStageName(item.projectStage))}</dd></div>
        <div><dt className="text-muted-foreground">{i18n.t('adminProjects.submitted')}</dt><dd className="font-semibold">{formatDate(item.submittedAtUtc)}</dd></div>
        <div><dt className="text-muted-foreground">{i18n.t('adminProjects.updated')}</dt><dd className="font-semibold">{formatDate(item.updatedAtUtc)}</dd></div>
      </dl>
      <Button asChild><Link to={`/admin/projects/${item.projectId}`}><ShieldCheck className="size-4" />{i18n.t('adminProjects.fullReview')}</Link></Button>
    </CardContent>
  </Card>
}

export function AdminProjectReviewPage() {
  useTranslation()
  const [page, setPage] = useState(1)
  const queue = useQuery({
    queryKey: ['project-review-queue', page],
    queryFn: ({ signal }) => projectReviewApi.list(page, 20, signal),
  })

  if (queue.isPending) return <p className="flex items-center gap-2" role="status"><LoaderCircle className="size-5 animate-spin" /> {i18n.t('adminProjects.loadingQueue')}</p>
  if (queue.isError) return <p className="rounded-lg bg-destructive/10 p-4 text-foreground" role="alert">{errorMessage(queue.error)}</p>

  const result = queue.data
  const lastPage = Math.max(1, Math.ceil(result.totalCount / result.pageSize))
  return <div className="space-y-6">
    <div>
      <p className="text-sm font-bold uppercase tracking-[0.16em] text-primary">{i18n.t('adminProjects.moderation')}</p>
      <h1 className="mt-1 text-3xl font-bold">{i18n.t('adminProjects.pending')}</h1>
      <p className="mt-2 max-w-3xl text-muted-foreground">{i18n.t('adminProjects.intro')}</p>
    </div>
    {result.items.length === 0
      ? <Card><CardContent className="p-10 text-center"><ShieldCheck className="mx-auto size-10 text-primary" /><h2 className="mt-3 text-xl font-bold">{i18n.t('adminProjects.upToDate')}</h2><p className="mt-2 text-muted-foreground">{i18n.t('adminProjects.empty')}</p></CardContent></Card>
      : <div className="grid gap-5">{result.items.map(item => <ReviewCard item={item} key={item.projectId} />)}</div>}
    {lastPage > 1 && <div className="flex flex-wrap items-center justify-between gap-3"><Button disabled={page === 1} onClick={() => setPage(value => value - 1)} variant="outline">{i18n.t('editorial.previous')}</Button><p className="text-sm text-muted-foreground">{i18n.t('editorial.page', { page, total: lastPage })}</p><Button disabled={page === lastPage} onClick={() => setPage(value => value + 1)} variant="outline">{i18n.t('editorial.next')}</Button></div>}
  </div>
}

function ReviewDecisionActions({ project }: { project: ProjectReviewDetails }) {
  useTranslation()
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const [reason, setReason] = useState('')
  const review = useMutation({
    // Capture the entire command on click: a retry must not read edited form
    // state or a newer ETag under the same idempotency key.
    mutationFn: ({ decision, idempotencyKey, projectId, eTag, reason: submittedReason }: {
      decision: ProjectReviewDecision
      idempotencyKey: string
      projectId: string
      eTag: string
      reason: string | null
    }) => projectReviewApi.review(projectId, eTag, idempotencyKey, decision, submittedReason),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ['project-review-queue'] })
      void navigate('/admin/projects', { replace: true })
    },
    retry: 1,
  })

  if (project.publicationStatus !== 1) {
    return <p className="rounded-lg bg-muted p-3 text-sm">{i18n.t('adminProjects.notPending')}</p>
  }

  return <Card><CardHeader><CardTitle>{i18n.t('adminProjects.decision')}</CardTitle></CardHeader><CardContent className="space-y-4">
    <p className="text-sm leading-6 text-muted-foreground">{i18n.t('adminProjects.decisionHelp')}</p>
    <label className="grid gap-1.5 text-sm font-semibold"><span>{i18n.t('adminProjects.reason')}</span><textarea className="min-h-28 rounded-lg border bg-background px-3 py-2 font-normal" maxLength={1000} onChange={event => setReason(event.target.value)} placeholder={i18n.t('adminProjects.reasonPlaceholder')} value={reason} /></label>
    {review.error && <div className="rounded-lg bg-destructive/10 p-3 text-sm text-foreground" role="alert"><p>{errorMessage(review.error)}</p>{isConcurrencyConflict(review.error) && <Button className="mt-3" onClick={() => void queryClient.invalidateQueries({ queryKey: ['project-review-detail', project.projectId] })} type="button" variant="outline">{i18n.t('editorial.reload')}</Button>}</div>}
    <div className="flex flex-wrap gap-3"><Button disabled={review.isPending} onClick={() => review.mutate({ decision: 'approve', idempotencyKey: createProjectCommandId(), projectId: project.projectId, eTag: project.eTag, reason: null })} type="button"><CheckCircle2 className="size-4" />{i18n.t('editorial.approve')}</Button><Button disabled={review.isPending || reason.trim().length < 10} onClick={() => review.mutate({ decision: 'reject', idempotencyKey: createProjectCommandId(), projectId: project.projectId, eTag: project.eTag, reason: reason.trim() })} type="button" variant="outline"><XCircle className="size-4" />{i18n.t('adminProjects.requestCorrections')}</Button></div>
  </CardContent></Card>
}

export function AdminProjectReviewDetailPage() {
  useTranslation()
  const { projectId } = useParams()
  const project = useQuery({
    queryKey: ['project-review-detail', projectId],
    queryFn: ({ signal }) => projectReviewApi.get(projectId!, signal),
    enabled: Boolean(projectId),
    retry: false,
  })

  if (project.isPending) return <p className="flex items-center gap-2" role="status"><LoaderCircle className="size-5 animate-spin" /> {i18n.t('adminProjects.loadingDetail')}</p>
  if (project.isError || !project.data) return <div className="space-y-4"><p className="rounded-lg bg-destructive/10 p-4 text-foreground" role="alert">{errorMessage(project.error)}</p><Button asChild variant="outline"><Link to="/admin/projects"><ArrowLeft className="size-4" />{i18n.t('adminProjects.back')}</Link></Button></div>

  const data = project.data
  return <div className="space-y-6">
    <Button asChild variant="ghost"><Link to="/admin/projects"><ArrowLeft className="size-4" />{i18n.t('adminProjects.back')}</Link></Button>
    <div><div className="flex flex-wrap items-center gap-3"><p className="text-sm font-bold uppercase tracking-[0.16em] text-primary">{i18n.t('adminProjects.reviewOf', { name: data.organization.name })}</p><span className="rounded-full bg-accent px-3 py-1 text-xs font-semibold">{i18n.t('adminProjects.complete', { value: data.completeness })}</span></div><h1 className="mt-2 text-3xl font-bold">{data.title}</h1><p className="mt-3 max-w-4xl text-lg leading-8 text-muted-foreground">{data.summary}</p></div>
    <div className="grid gap-6 lg:grid-cols-[1fr_20rem]">
      <div className="space-y-6"><Card><CardHeader><CardTitle>{i18n.t('adminProjects.description')}</CardTitle></CardHeader><CardContent className="space-y-5"><p className="whitespace-pre-line leading-7 text-muted-foreground">{data.description}</p><ProjectEnrichmentSummary value={data.enrichment} privateView /></CardContent></Card><Card><CardHeader><CardTitle>{i18n.t('adminProjects.scope')}</CardTitle></CardHeader><CardContent className="space-y-5"><LocalizedTaxonomyList title={i18n.t('adminProjects.territories')} groups={[{ catalog: 'countries', values: data.countries }, { catalog: 'regions', values: data.regions }]} /><LocalizedTaxonomyList title={i18n.t('adminProjects.impact')} groups={[{ catalog: 'fundingCategories', values: data.categories }]} /><LocalizedTaxonomyList title={i18n.t('adminFunding.beneficiaries')} groups={[{ catalog: 'beneficiaryTypes', values: data.beneficiaryTypes }]} /><LocalizedTaxonomyList title={i18n.t('adminFunding.projectTypes')} groups={[{ catalog: 'projectTypes', values: data.projectTypes }]} /><LocalizedTaxonomyList title={i18n.t('adminProjects.sdgs')} groups={[{ catalog: 'sustainableDevelopmentGoals', values: data.sustainableDevelopmentGoals ?? [] }]} /></CardContent></Card></div>
      <aside className="space-y-4"><Card><CardHeader><CardTitle>{i18n.t('adminProjects.funding')}</CardTitle></CardHeader><CardContent className="space-y-3 text-sm"><p className="flex justify-between gap-3"><span className="text-muted-foreground">{i18n.t('adminProjects.budget')}</span><strong>{formatMoney(data.budgetTotal, data.currency)}</strong></p><p className="flex justify-between gap-3"><span className="text-muted-foreground">{i18n.t('adminProjects.confirmed')}</span><strong>{formatMoney(data.confirmedFunding, data.currency)}</strong></p><p className="flex justify-between gap-3 border-t pt-3"><span className="text-muted-foreground">{i18n.t('adminProjects.gap')}</span><strong className="text-primary">{formatMoney(data.fundingGap, data.currency)}</strong></p></CardContent></Card><Card><CardContent className="space-y-3 p-5 text-sm"><p><span className="text-muted-foreground">{i18n.t('adminProjects.status')}: </span><strong>{projectStatusNames[data.projectStatus] ? workspaceMessage(projectStatusNames[data.projectStatus]) : i18n.t('adminProjects.unclassified')}</strong></p><p><span className="text-muted-foreground">{i18n.t('adminProjects.stage')}: </span><strong>{workspaceMessage(projectStageName(data.projectStage))}</strong></p><p><span className="text-muted-foreground">{i18n.t('adminProjects.submitted')}: </span><strong>{data.submittedAtUtc ? formatDate(data.submittedAtUtc) : i18n.t('editorial.noDate')}</strong></p><p><span className="text-muted-foreground">{i18n.t('adminProjects.updated')}: </span><strong>{formatDate(data.updatedAtUtc)}</strong></p></CardContent></Card></aside>
    </div>
    <ReviewDecisionActions project={data} />
  </div>
}

function LocalizedTaxonomyList({ title, groups }: { title: string; groups: { catalog: CatalogKind; values: PublicProjectCatalogItem[] }[] }) {
  useTranslation()
  if (groups.every(group => group.values.length === 0)) return null
  return <div><h2 className="text-sm font-bold uppercase tracking-wide text-muted-foreground">{title}</h2><div className="mt-2 flex flex-wrap gap-2">{groups.flatMap(({ catalog, values }) => values.map(value => <span className="rounded-full border bg-card px-3 py-1.5 text-sm" key={`${catalog}-${value.id}`} lang={catalogLanguage(catalog, value)}>{catalogName(catalog, value)}</span>))}</div></div>
}

function formatPublicMoney(value: number | null, currency: string | null) {
  return formatMoneyValue(value, currency, i18n.t('projects.unspecified'))
}

export function PublicProjectView({
  project,
  backTo,
}: {
  project: UseQueryResult<PublicProject, Error>
  backTo: string
}) {
  const { t } = useTranslation()
  useEffect(() => {
    if (!project.data) return
    const previousTitle = document.title
    document.title = `${project.data.title} · FundingPlatform`
    return () => { document.title = previousTitle }
  }, [project.data])

  if (project.isPending) return <div className="grid min-h-[60vh] place-items-center"><p className="flex items-center gap-2" role="status"><LoaderCircle className="size-5 animate-spin" /> {t('projects.publicLoading')}</p></div>
  if (project.isError || !project.data) return <section className="mx-auto max-w-3xl px-4 py-20 text-center"><CircleAlert className="mx-auto size-10 text-muted-foreground" /><h1 className="mt-4 text-3xl font-bold">{t('projects.publicUnavailable')}</h1><p className="mt-3 text-muted-foreground">{t('projects.publicUnavailableHelp')}</p><Button className="mt-6" asChild variant="outline"><Link to={backTo}><ArrowLeft className="size-4" />{t('projects.backMarketplace')}</Link></Button></section>

  const data = project.data
  const website = data.organization.websiteUrl && /^https?:\/\//i.test(data.organization.websiteUrl)
    ? data.organization.websiteUrl
    : null

  return <article>
    <header className="relative overflow-hidden border-b bg-[radial-gradient(circle_at_top_left,var(--accent),transparent_60%)] px-4 py-16 sm:px-6 sm:py-24">
      <div className="absolute -right-20 -top-24 size-80 rounded-full border-[48px] border-primary/10" aria-hidden="true" />
      <div className="relative mx-auto max-w-5xl">
        <Link className="inline-flex items-center gap-2 text-sm font-semibold text-primary hover:underline" to={backTo}><ArrowLeft className="size-4" />{t('projects.marketplace')}</Link>
        <div className="mt-8 flex flex-wrap items-center gap-3 text-sm"><span className="rounded-full bg-primary px-3 py-1 font-semibold text-primary-foreground">{t('projects.publicBadge')}</span><span className="text-muted-foreground">{t('projects.publishedDate', { date: formatWorkspaceDate(data.publishedAtUtc, 'long') })}</span></div>
        <h1 className="mt-5 max-w-4xl text-4xl font-bold tracking-tight sm:text-6xl">{data.title}</h1>
        <p className="mt-5 max-w-3xl text-lg leading-8 text-muted-foreground">{data.summary ?? t('projects.publicSummary')}</p>
        <div className="mt-8 flex flex-wrap items-center gap-4"><Link className="inline-flex items-center gap-2 font-semibold hover:text-primary hover:underline" to={`/marketplace/organizations/${data.organization.publicId}`}><Building2 className="size-5 text-primary" />{data.organization.name}</Link>{website && <Button asChild variant="outline"><a href={website} rel="noopener noreferrer" target="_blank">{t('projects.officialSite')} <ExternalLink className="size-4" /></a></Button>}</div>
      </div>
    </header>

    <div className="mx-auto grid max-w-5xl gap-8 px-4 py-12 sm:px-6 lg:grid-cols-[1fr_19rem]">
      <div className="space-y-9">
        <section><h2 className="text-2xl font-bold">{t('projects.about')}</h2><p className="mt-4 whitespace-pre-line text-base leading-8 text-muted-foreground">{data.description ?? data.summary ?? t('projects.publicDescription')}</p></section>
        <ProjectEnrichmentSummary value={data.enrichment} />
        <section className="space-y-5"><LocalizedTaxonomyList title={t('projects.territories')} groups={[{ catalog: 'countries', values: data.countries }, { catalog: 'regions', values: data.regions }]} /><LocalizedTaxonomyList title={t('projects.impactAreas')} groups={[{ catalog: 'fundingCategories', values: data.categories }]} /><LocalizedTaxonomyList title={t('projects.beneficiaryPopulations')} groups={[{ catalog: 'beneficiaryTypes', values: data.beneficiaryTypes }]} /><LocalizedTaxonomyList title={t('projects.projectTypes')} groups={[{ catalog: 'projectTypes', values: data.projectTypes }]} /><LocalizedTaxonomyList title={t('projects.sdgs')} groups={[{ catalog: 'sustainableDevelopmentGoals', values: data.sustainableDevelopmentGoals ?? [] }]} /></section>
      </div>
      <aside className="space-y-4">
        <Card><CardHeader><CardTitle>{t('projects.fundingNeed')}</CardTitle></CardHeader><CardContent className="space-y-4"><div><p className="text-sm text-muted-foreground">{t('projects.fundingGap')}</p><p className="mt-1 text-2xl font-bold text-primary">{formatPublicMoney(data.fundingGap, data.currency)}</p></div><div className="grid gap-3 border-t pt-4 text-sm"><p className="flex items-center justify-between gap-3"><span className="text-muted-foreground">{t('projects.budget')}</span><strong>{formatPublicMoney(data.budgetTotal, data.currency)}</strong></p><p className="flex items-center justify-between gap-3"><span className="text-muted-foreground">{t('projects.confirmed')}</span><strong>{formatPublicMoney(data.confirmedFunding, data.currency)}</strong></p></div><p className="text-xs leading-5 text-muted-foreground">{t('projects.fundingDisclaimer')}</p></CardContent></Card>
        <Card><CardContent className="space-y-3 p-5"><p className="flex items-center gap-2 text-sm"><Target className="size-4 text-primary" /><strong>{workspaceMessage(projectStatusNames[data.projectStatus]) || t('projects.active')}</strong></p><p className="flex items-center gap-2 text-sm"><Target className="size-4 text-primary" /><span>{t('projects.stageLabel')} <strong>{workspaceMessage(projectStageName(data.projectStage))}</strong></span></p>{(data.startDate || data.endDate) && <p className="flex items-start gap-2 text-sm"><CalendarDays className="mt-0.5 size-4 shrink-0 text-primary" /><span>{data.startDate ? formatWorkspaceDate(data.startDate, 'long') : t('projects.noStart')} — {data.endDate ? formatWorkspaceDate(data.endDate, 'long') : t('projects.noEnd')}</span></p>}<p className="flex items-center gap-2 text-sm"><MapPin className="size-4 text-primary" />{data.countries.length ? <span>{data.countries.map((country, index) => <span key={country.id}>{index > 0 && ', '}<span lang={catalogLanguage('countries', country)}>{catalogName('countries', country)}</span></span>)}</span> : t('projects.coveragePending')}</p><p className="flex items-center gap-2 text-sm"><Globe2 className="size-4 text-primary" />{t('projects.moderated')}</p><p className="flex items-center gap-2 text-sm"><WalletCards className="size-4 text-primary" />{t('projects.noConversion')}</p></CardContent></Card>
      </aside>
    </div>
  </article>
}

export function PublicProjectPage() {
  const { slug = '' } = useParams()
  const project = useQuery({
    queryKey: ['public-project', slug],
    queryFn: ({ signal }) => publicProjectApi.get(slug, signal),
    enabled: Boolean(slug),
    retry: false,
  })
  return <PublicProjectView backTo="/marketplace" project={project} />
}
