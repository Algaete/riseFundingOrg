import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
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
import { Link, useNavigate, useParams } from 'react-router-dom'

import { ApiError } from '@/api/http-client'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import {
  createProjectCommandId,
  projectReviewApi,
  publicProjectApi,
  type ProjectReviewDetails,
  type ProjectReviewDecision,
  type ProjectReviewQueueItem,
  type PublicProjectCatalogItem,
} from '@/features/projects/project-api'

const projectStatusNames = [
  'Idea',
  'Diseño',
  'Buscando financiamiento',
  'Financiado parcialmente',
  'Financiado',
  'En ejecución',
  'Completado',
]

function errorMessage(error: unknown) {
  return error instanceof ApiError
    ? error.problem.detail ?? error.problem.title
    : 'No fue posible completar la operación. Intenta nuevamente.'
}

function formatDate(value: string) {
  return new Intl.DateTimeFormat('es-CL', { dateStyle: 'long' }).format(new Date(value))
}

function formatDateOnly(value: string) {
  const [year, month, day] = value.split('-').map(Number)
  return new Intl.DateTimeFormat('es-CL', { dateStyle: 'long' })
    .format(new Date(year, month - 1, day))
}

function formatMoney(value: number | null, currency: string | null) {
  if (value === null || !currency) return 'No informado'
  return new Intl.NumberFormat('es-CL', {
    style: 'currency',
    currency,
    maximumFractionDigits: currency === 'CLP' ? 0 : 2,
  }).format(value)
}

function ReviewCard({ item }: { item: ProjectReviewQueueItem }) {
  return <Card>
    <CardHeader>
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <p className="text-xs font-bold uppercase tracking-[0.16em] text-primary">{item.organizationName}</p>
          <CardTitle className="mt-1 text-xl">{item.title}</CardTitle>
        </div>
        <span className="rounded-full bg-accent px-3 py-1 text-xs font-semibold text-accent-foreground">{item.completeness}% completo</span>
      </div>
    </CardHeader>
    <CardContent className="space-y-4">
      <p className="text-sm leading-6 text-muted-foreground">{item.summary ?? 'El proyecto no tiene resumen.'}</p>
      <dl className="grid gap-3 text-sm sm:grid-cols-3">
        <div><dt className="text-muted-foreground">Estado</dt><dd className="font-semibold">{projectStatusNames[item.projectStatus] ?? 'Sin clasificar'}</dd></div>
        <div><dt className="text-muted-foreground">Enviado</dt><dd className="font-semibold">{formatDate(item.submittedAtUtc)}</dd></div>
        <div><dt className="text-muted-foreground">Actualizado</dt><dd className="font-semibold">{formatDate(item.updatedAtUtc)}</dd></div>
      </dl>
      <Button asChild><Link to={`/admin/projects/${item.projectId}`}><ShieldCheck className="size-4" />Revisar proyecto completo</Link></Button>
    </CardContent>
  </Card>
}

export function AdminProjectReviewPage() {
  const [page, setPage] = useState(1)
  const queue = useQuery({
    queryKey: ['project-review-queue', page],
    queryFn: ({ signal }) => projectReviewApi.list(page, 20, signal),
  })

  if (queue.isPending) return <p className="flex items-center gap-2" role="status"><LoaderCircle className="size-5 animate-spin" /> Cargando revisión de proyectos…</p>
  if (queue.isError) return <p className="rounded-lg bg-destructive/10 p-4 text-destructive">{errorMessage(queue.error)}</p>

  const result = queue.data
  const lastPage = Math.max(1, Math.ceil(result.totalCount / result.pageSize))
  return <div className="space-y-6">
    <div>
      <p className="text-sm font-bold uppercase tracking-[0.16em] text-primary">Moderación</p>
      <h1 className="mt-1 text-3xl font-bold">Proyectos pendientes</h1>
      <p className="mt-2 max-w-3xl text-muted-foreground">Solo una aprobación administrativa vuelve público un proyecto. Cada decisión queda auditada y se procesa con idempotencia.</p>
    </div>
    {result.items.length === 0
      ? <Card><CardContent className="p-10 text-center"><ShieldCheck className="mx-auto size-10 text-primary" /><h2 className="mt-3 text-xl font-bold">Revisión al día</h2><p className="mt-2 text-muted-foreground">No hay proyectos esperando moderación.</p></CardContent></Card>
      : <div className="grid gap-5">{result.items.map(item => <ReviewCard item={item} key={item.projectId} />)}</div>}
    {lastPage > 1 && <div className="flex items-center justify-between"><Button disabled={page === 1} onClick={() => setPage(value => value - 1)} variant="outline">Anterior</Button><p className="text-sm text-muted-foreground">Página {page} de {lastPage}</p><Button disabled={page === lastPage} onClick={() => setPage(value => value + 1)} variant="outline">Siguiente</Button></div>}
  </div>
}

function ReviewDecisionActions({ project }: { project: ProjectReviewDetails }) {
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const [reason, setReason] = useState('')
  const review = useMutation({
    mutationFn: ({ decision, idempotencyKey }: {
      decision: ProjectReviewDecision
      idempotencyKey: string
    }) => projectReviewApi.review(
      project.projectId,
      project.eTag,
      idempotencyKey,
      decision,
      decision === 'reject' ? reason.trim() : null,
    ),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ['project-review-queue'] })
      void navigate('/admin/projects', { replace: true })
    },
    retry: 1,
  })

  if (project.publicationStatus !== 1) {
    return <p className="rounded-lg bg-muted p-3 text-sm">Este proyecto ya no está pendiente. Vuelve a la cola para obtener su estado vigente.</p>
  }

  return <Card><CardHeader><CardTitle>Decisión editorial</CardTitle></CardHeader><CardContent className="space-y-4">
    <p className="text-sm leading-6 text-muted-foreground">Comprueba que el contenido sea claro, coherente y apropiado para publicación. La moderación no certifica legalmente las afirmaciones ni garantiza financiamiento.</p>
    <label className="grid gap-1.5 text-sm font-semibold"><span>Motivo si solicitas correcciones</span><textarea className="min-h-28 rounded-lg border bg-background px-3 py-2 font-normal" maxLength={1000} onChange={event => setReason(event.target.value)} placeholder="Indica una corrección concreta para que la organización pueda reenviar." value={reason} /></label>
    {review.error && <p className="rounded-lg bg-destructive/10 p-3 text-sm text-destructive">{errorMessage(review.error)}</p>}
    <div className="flex flex-wrap gap-3"><Button disabled={review.isPending} onClick={() => review.mutate({ decision: 'approve', idempotencyKey: createProjectCommandId() })} type="button"><CheckCircle2 className="size-4" />Aprobar y publicar</Button><Button disabled={review.isPending || reason.trim().length < 10} onClick={() => review.mutate({ decision: 'reject', idempotencyKey: createProjectCommandId() })} type="button" variant="outline"><XCircle className="size-4" />Solicitar correcciones</Button></div>
  </CardContent></Card>
}

export function AdminProjectReviewDetailPage() {
  const { projectId } = useParams()
  const project = useQuery({
    queryKey: ['project-review-detail', projectId],
    queryFn: ({ signal }) => projectReviewApi.get(projectId!, signal),
    enabled: Boolean(projectId),
    retry: false,
  })

  if (project.isPending) return <p className="flex items-center gap-2" role="status"><LoaderCircle className="size-5 animate-spin" /> Cargando proyecto para revisión…</p>
  if (project.isError || !project.data) return <div className="space-y-4"><p className="rounded-lg bg-destructive/10 p-4 text-destructive">{errorMessage(project.error)}</p><Button asChild variant="outline"><Link to="/admin/projects"><ArrowLeft className="size-4" />Volver a la cola</Link></Button></div>

  const data = project.data
  return <div className="space-y-6">
    <Button asChild variant="ghost"><Link to="/admin/projects"><ArrowLeft className="size-4" />Volver a la cola</Link></Button>
    <div><div className="flex flex-wrap items-center gap-3"><p className="text-sm font-bold uppercase tracking-[0.16em] text-primary">Revisión de {data.organization.name}</p><span className="rounded-full bg-accent px-3 py-1 text-xs font-semibold">{data.completeness}% completo</span></div><h1 className="mt-2 text-3xl font-bold">{data.title}</h1><p className="mt-3 max-w-4xl text-lg leading-8 text-muted-foreground">{data.summary}</p></div>
    <div className="grid gap-6 lg:grid-cols-[1fr_20rem]">
      <div className="space-y-6"><Card><CardHeader><CardTitle>Descripción presentada</CardTitle></CardHeader><CardContent><p className="whitespace-pre-line leading-7 text-muted-foreground">{data.description}</p></CardContent></Card><Card><CardHeader><CardTitle>Alcance declarado</CardTitle></CardHeader><CardContent className="space-y-5"><TaxonomyList title="Territorios" values={[...data.countries, ...data.regions]} /><TaxonomyList title="Áreas de impacto" values={data.categories} /><TaxonomyList title="Poblaciones beneficiarias" values={data.beneficiaryTypes} /><TaxonomyList title="Tipos de proyecto" values={data.projectTypes} /></CardContent></Card></div>
      <aside className="space-y-4"><Card><CardHeader><CardTitle>Financiamiento</CardTitle></CardHeader><CardContent className="space-y-3 text-sm"><p className="flex justify-between gap-3"><span className="text-muted-foreground">Presupuesto</span><strong>{formatMoney(data.budgetTotal, data.currency)}</strong></p><p className="flex justify-between gap-3"><span className="text-muted-foreground">Confirmado</span><strong>{formatMoney(data.confirmedFunding, data.currency)}</strong></p><p className="flex justify-between gap-3 border-t pt-3"><span className="text-muted-foreground">Brecha</span><strong className="text-primary">{formatMoney(data.fundingGap, data.currency)}</strong></p></CardContent></Card><Card><CardContent className="space-y-3 p-5 text-sm"><p><span className="text-muted-foreground">Estado: </span><strong>{projectStatusNames[data.projectStatus]}</strong></p><p><span className="text-muted-foreground">Enviado: </span><strong>{data.submittedAtUtc ? formatDate(data.submittedAtUtc) : 'Sin fecha'}</strong></p><p><span className="text-muted-foreground">Actualizado: </span><strong>{formatDate(data.updatedAtUtc)}</strong></p></CardContent></Card></aside>
    </div>
    <ReviewDecisionActions project={data} />
  </div>
}

function TaxonomyList({ title, values }: { title: string; values: PublicProjectCatalogItem[] }) {
  if (values.length === 0) return null
  return <div><h2 className="text-sm font-bold uppercase tracking-wide text-muted-foreground">{title}</h2><div className="mt-2 flex flex-wrap gap-2">{values.map(value => <span className="rounded-full border bg-card px-3 py-1.5 text-sm" key={`${title}-${value.id}`}>{value.name}</span>)}</div></div>
}

export function PublicProjectPage() {
  const { slug } = useParams()
  const project = useQuery({
    queryKey: ['public-project', slug],
    queryFn: ({ signal }) => publicProjectApi.get(slug!, signal),
    enabled: Boolean(slug),
    retry: false,
  })

  useEffect(() => {
    if (!project.data) return
    const previousTitle = document.title
    document.title = `${project.data.title} · FundingPlatform`
    return () => { document.title = previousTitle }
  }, [project.data])

  if (project.isPending) return <div className="grid min-h-[60vh] place-items-center"><p className="flex items-center gap-2" role="status"><LoaderCircle className="size-5 animate-spin" /> Cargando proyecto público…</p></div>
  if (project.isError || !project.data) return <section className="mx-auto max-w-3xl px-4 py-20 text-center"><CircleAlert className="mx-auto size-10 text-muted-foreground" /><h1 className="mt-4 text-3xl font-bold">Proyecto no disponible</h1><p className="mt-3 text-muted-foreground">No existe, todavía está en revisión o dejó de estar publicado.</p><Button className="mt-6" asChild variant="outline"><Link to="/"><ArrowLeft className="size-4" />Volver al inicio</Link></Button></section>

  const data = project.data
  const website = data.organization.websiteUrl && /^https?:\/\//i.test(data.organization.websiteUrl)
    ? data.organization.websiteUrl
    : null

  return <article>
    <header className="relative overflow-hidden border-b bg-[radial-gradient(circle_at_top_left,var(--accent),transparent_60%)] px-4 py-16 sm:px-6 sm:py-24">
      <div className="absolute -right-20 -top-24 size-80 rounded-full border-[48px] border-primary/10" aria-hidden="true" />
      <div className="relative mx-auto max-w-5xl">
        <Link className="inline-flex items-center gap-2 text-sm font-semibold text-primary hover:underline" to="/"><ArrowLeft className="size-4" />FundingPlatform</Link>
        <div className="mt-8 flex flex-wrap items-center gap-3 text-sm"><span className="rounded-full bg-primary px-3 py-1 font-semibold text-primary-foreground">Proyecto publicado</span><span className="text-muted-foreground">Publicado el {formatDate(data.publishedAtUtc)}</span></div>
        <h1 className="mt-5 max-w-4xl text-4xl font-bold tracking-tight sm:text-6xl">{data.title}</h1>
        <p className="mt-5 max-w-3xl text-lg leading-8 text-muted-foreground">{data.summary ?? 'Conoce este proyecto y su impacto esperado.'}</p>
        <div className="mt-8 flex flex-wrap items-center gap-4"><span className="inline-flex items-center gap-2 font-semibold"><Building2 className="size-5 text-primary" />{data.organization.name}</span>{website && <Button asChild variant="outline"><a href={website} rel="noopener noreferrer" target="_blank">Sitio oficial <ExternalLink className="size-4" /></a></Button>}</div>
      </div>
    </header>

    <div className="mx-auto grid max-w-5xl gap-8 px-4 py-12 sm:px-6 lg:grid-cols-[1fr_19rem]">
      <div className="space-y-9">
        <section><h2 className="text-2xl font-bold">Acerca del proyecto</h2><p className="mt-4 whitespace-pre-line text-base leading-8 text-muted-foreground">{data.description ?? data.summary ?? 'La organización aún no publicó una descripción extendida.'}</p></section>
        <section className="space-y-5"><TaxonomyList title="Territorios" values={[...data.countries, ...data.regions]} /><TaxonomyList title="Áreas de impacto" values={data.categories} /><TaxonomyList title="Poblaciones beneficiarias" values={data.beneficiaryTypes} /><TaxonomyList title="Tipos de proyecto" values={data.projectTypes} /></section>
      </div>
      <aside className="space-y-4">
        <Card><CardHeader><CardTitle>Necesidad financiera</CardTitle></CardHeader><CardContent className="space-y-4"><div><p className="text-sm text-muted-foreground">Brecha por financiar</p><p className="mt-1 text-2xl font-bold text-primary">{formatMoney(data.fundingGap, data.currency)}</p></div><div className="grid gap-3 border-t pt-4 text-sm"><p className="flex items-center justify-between gap-3"><span className="text-muted-foreground">Presupuesto</span><strong>{formatMoney(data.budgetTotal, data.currency)}</strong></p><p className="flex items-center justify-between gap-3"><span className="text-muted-foreground">Confirmado</span><strong>{formatMoney(data.confirmedFunding, data.currency)}</strong></p></div><p className="text-xs leading-5 text-muted-foreground">FundingPlatform informa la necesidad declarada; no procesa donaciones ni garantiza resultados.</p></CardContent></Card>
        <Card><CardContent className="space-y-3 p-5"><p className="flex items-center gap-2 text-sm"><Target className="size-4 text-primary" /><strong>{projectStatusNames[data.projectStatus] ?? 'Proyecto activo'}</strong></p>{(data.startDate || data.endDate) && <p className="flex items-start gap-2 text-sm"><CalendarDays className="mt-0.5 size-4 shrink-0 text-primary" /><span>{data.startDate ? formatDateOnly(data.startDate) : 'Sin inicio definido'} — {data.endDate ? formatDateOnly(data.endDate) : 'Sin término definido'}</span></p>}<p className="flex items-center gap-2 text-sm"><MapPin className="size-4 text-primary" />{data.countries.map(country => country.name).join(', ') || 'Cobertura por confirmar'}</p><p className="flex items-center gap-2 text-sm"><Globe2 className="size-4 text-primary" />Contenido moderado antes de publicarse</p><p className="flex items-center gap-2 text-sm"><WalletCards className="size-4 text-primary" />Montos sin conversión de moneda</p></CardContent></Card>
      </aside>
    </div>
  </article>
}
