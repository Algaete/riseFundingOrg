import { keepPreviousData, useQuery } from '@tanstack/react-query'
import {
  ArrowLeft,
  CalendarDays,
  ChevronLeft,
  ChevronRight,
  CircleDollarSign,
  Cpu,
  ExternalLink,
  HandHeart,
  HeartPulse,
  Landmark,
  Leaf,
  LoaderCircle,
  Newspaper,
  Search,
  ShieldAlert,
  ShieldCheck,
  Scale,
  type LucideIcon,
  X,
} from 'lucide-react'
import { type FormEvent, type ReactNode, useEffect, useRef, useState } from 'react'
import { Link, useParams } from 'react-router-dom'

import { ApiError } from '@/api/http-client'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import {
  fundingOpportunitiesApi,
  type FundingOpportunityDetail,
  type FundingOpportunityListItem,
} from '@/features/funding/funding-opportunities-api'

const pageSize = 12

interface VisualProfile {
  label: string
  icon: LucideIcon
  background: string
}

function getVisualProfile(opportunity: FundingOpportunityListItem): VisualProfile {
  const searchable = [
    opportunity.title,
    opportunity.summary,
    opportunity.sponsorName,
  ]
    .filter(Boolean)
    .join(' ')
    .toLocaleLowerCase()

  if (/health|salud|hiv|tuberculosis|\btb\b|laborator|nutrition/.test(searchable)) {
    return {
      label: 'Salud y bienestar',
      icon: HeartPulse,
      background: 'from-rose-700 via-rose-600 to-orange-500',
    }
  }
  if (/journal|media|information|documenting|periodis/.test(searchable)) {
    return {
      label: 'Información y periodismo',
      icon: Newspaper,
      background: 'from-indigo-800 via-blue-700 to-cyan-500',
    }
  }
  if (/human rights|freedom|democra|women|violence|justice|derechos/.test(searchable)) {
    return {
      label: 'Derechos y democracia',
      icon: Scale,
      background: 'from-violet-800 via-purple-700 to-fuchsia-500',
    }
  }
  if (/technology|innovation|university|research|science|cyber|tecnolog/.test(searchable)) {
    return {
      label: 'Innovación y conocimiento',
      icon: Cpu,
      background: 'from-slate-800 via-sky-700 to-teal-500',
    }
  }
  if (/dam|infrastructure|housing|construction|transport|vivienda/.test(searchable)) {
    return {
      label: 'Infraestructura y territorio',
      icon: Landmark,
      background: 'from-stone-800 via-amber-700 to-yellow-500',
    }
  }
  if (/environment|climate|conservation|agricultur|natural|ambiente/.test(searchable)) {
    return {
      label: 'Ambiente y resiliencia',
      icon: Leaf,
      background: 'from-emerald-900 via-green-700 to-lime-500',
    }
  }

  return {
    label: 'Impacto social',
    icon: HandHeart,
    background: 'from-emerald-800 via-teal-700 to-cyan-500',
  }
}

function FundingVisual({
  opportunity,
  detail = false,
}: {
  opportunity: FundingOpportunityListItem
  detail?: boolean
}) {
  const profile = getVisualProfile(opportunity)
  const Icon = profile.icon

  return (
    <div
      aria-label={`Visual temático: ${profile.label}`}
      className={`relative overflow-hidden bg-gradient-to-br ${profile.background} ${detail ? 'h-64' : 'h-40'}`}
      role="img"
    >
      <div className="absolute -right-12 -top-16 size-48 rounded-full border-[28px] border-white/10" />
      <div className="absolute -bottom-20 left-10 size-44 rounded-full bg-white/10 blur-sm" />
      <div className="relative flex h-full items-end justify-between gap-4 p-5 text-white sm:p-6">
        <div>
          <span className="rounded-full border border-white/30 bg-black/15 px-3 py-1 text-xs font-semibold backdrop-blur">
            Categoría orientativa
          </span>
          <p className="mt-3 text-lg font-bold">{profile.label}</p>
        </div>
        <Icon
          aria-hidden="true"
          className={detail ? 'size-24 opacity-90' : 'size-16 opacity-90'}
          strokeWidth={1.35}
        />
      </div>
    </div>
  )
}

function parseDate(value: string) {
  return /^\d{4}-\d{2}-\d{2}$/.test(value)
    ? new Date(`${value}T12:00:00Z`)
    : new Date(value)
}

function formatDate(value: string | null) {
  if (!value) return 'Sin fecha informada'
  const date = parseDate(value)
  if (Number.isNaN(date.getTime())) return 'Fecha no disponible'
  return new Intl.DateTimeFormat('es-CL', {
    day: 'numeric',
    month: 'short',
    year: 'numeric',
    timeZone: 'UTC',
  }).format(date)
}

function formatDateTime(value: string | null) {
  if (!value) return 'Sin verificación informada'
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return 'Fecha no disponible'
  return new Intl.DateTimeFormat('es-CL', {
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(date)
}

function formatAmount(opportunity: FundingOpportunityListItem) {
  if (!opportunity.currency) return 'Monto no informado'

  try {
    const formatter = new Intl.NumberFormat('es-CL', {
      style: 'currency',
      currency: opportunity.currency,
      maximumFractionDigits: 0,
    })

    if (opportunity.minimumAmount !== null && opportunity.maximumAmount !== null) {
      return `${formatter.format(opportunity.minimumAmount)} – ${formatter.format(opportunity.maximumAmount)}`
    }
    if (opportunity.maximumAmount !== null) {
      return `Hasta ${formatter.format(opportunity.maximumAmount)}`
    }
    if (opportunity.minimumAmount !== null) {
      return `Desde ${formatter.format(opportunity.minimumAmount)}`
    }
  } catch {
    return 'Monto no informado'
  }
  return 'Monto no informado'
}

function availability(opportunity: FundingOpportunityListItem) {
  const now = new Date()
  const today = now.toISOString().slice(0, 10)
  const openDate = opportunity.openDate?.slice(0, 10)
  const closeDate = opportunity.closeDate?.slice(0, 10)
  if (openDate && openDate > today) return 'Próximamente'
  if (opportunity.deadlineType === 2) return 'Vigente'
  if (opportunity.deadlinePrecision === 2) {
    if (!opportunity.closeAtUtc) return 'Plazo no informado'
    const closeAtUtc = new Date(opportunity.closeAtUtc)
    if (!Number.isNaN(closeAtUtc.getTime())) {
      return closeAtUtc.getTime() <= now.getTime() ? 'Cerrada' : 'Vigente'
    }
    return 'Plazo no informado'
  }
  if (closeDate && closeDate < today) return 'Cerrada'
  return closeDate ? 'Vigente' : 'Plazo no informado'
}

function qualityScore(value: number) {
  if (!Number.isFinite(value)) return 0
  return Math.max(0, Math.min(100, Math.round(value)))
}

function SourceAttribution({ opportunity }: { opportunity: FundingOpportunityListItem }) {
  const attribution = opportunity.sourceAttribution?.trim()
    || (opportunity.sourceName.trim().toLocaleLowerCase() === 'grants.gov'
      ? 'This product uses the Grants.gov API but is not endorsed or certified by the U.S. Department of Health and Human Services.'
      : `Información provista por ${opportunity.sourceName}. Confirma las bases y plazos en la publicación original.`)

  return (
    <div className="rounded-xl border bg-muted/55 px-4 py-3 text-xs leading-relaxed text-muted-foreground">
      <span className="font-bold text-foreground">Fuente: {opportunity.sourceName}.</span>{' '}
      {attribution}
      {opportunity.sourceUrl && (
        <>
          {' '}
          <a
            className="font-semibold text-primary underline underline-offset-2"
            href={opportunity.sourceUrl}
            rel="noopener noreferrer"
            target="_blank"
          >
            Consultar fuente
          </a>
        </>
      )}
    </div>
  )
}

export function FundingCard({
  opportunity,
  detailHref = `/funding/${opportunity.slug}`,
  action,
}: {
  opportunity: FundingOpportunityListItem
  detailHref?: string
  action?: ReactNode
}) {
  return (
    <Card
      className="flex h-full flex-col overflow-hidden transition hover:-translate-y-0.5 hover:shadow-md"
      data-testid={`funding-card-${opportunity.publicId}`}
    >
      <FundingVisual opportunity={opportunity} />
      <CardHeader className="space-y-4">
        <div className="flex items-start justify-between gap-3">
          <span className="rounded-full bg-accent px-3 py-1 text-xs font-bold text-accent-foreground">
            {availability(opportunity)}
          </span>
          <span className="text-xs font-medium text-muted-foreground">
            Calidad {qualityScore(opportunity.dataQualityScore)}/100
          </span>
        </div>
        <div>
          <p className="mb-2 text-xs font-bold uppercase tracking-wide text-primary">
            {opportunity.sponsorName}
          </p>
          <CardTitle className="text-xl leading-tight">
            <Link className="hover:text-primary" to={detailHref}>
              {opportunity.title}
            </Link>
          </CardTitle>
        </div>
      </CardHeader>
      <CardContent className="flex flex-1 flex-col gap-5">
        <p className="line-clamp-4 text-sm leading-6 text-muted-foreground">
          {opportunity.summary ?? 'La fuente no publicó un resumen.'}
        </p>
        <dl className="mt-auto grid gap-3 text-sm">
          <div className="flex items-start gap-3">
            <CalendarDays className="mt-0.5 size-4 shrink-0 text-primary" />
            <div>
              <dt className="font-semibold">Cierre</dt>
              <dd className="text-muted-foreground">{formatDate(opportunity.closeDate)}</dd>
            </div>
          </div>
          <div className="flex items-start gap-3">
            <CircleDollarSign className="mt-0.5 size-4 shrink-0 text-primary" />
            <div>
              <dt className="font-semibold">Financiamiento</dt>
              <dd className="text-muted-foreground">{formatAmount(opportunity)}</dd>
            </div>
          </div>
        </dl>
        <div className="grid gap-2 sm:grid-cols-2">
          <Button asChild className={action ? undefined : 'sm:col-span-2'} size="sm">
            <Link to={detailHref}>Ver ficha completa</Link>
          </Button>
          {action}
        </div>
        <SourceAttribution opportunity={opportunity} />
      </CardContent>
    </Card>
  )
}

function errorMessage(error: unknown) {
  return error instanceof ApiError
    ? error.problem.detail ?? error.problem.title
    : 'Comprueba que la API esté ejecutándose y vuelve a intentarlo.'
}

function safeExternalDestination(value: string) {
  try {
    const destination = new URL(value)
    if (
      (destination.protocol !== 'https:' && destination.protocol !== 'http:')
      || destination.username
      || destination.password
    ) return null
    return { href: destination.href, hostname: destination.hostname }
  } catch {
    return null
  }
}

function ApplicationExitInterstitial({ url }: { url: string }) {
  const [open, setOpen] = useState(false)
  const closeButton = useRef<HTMLButtonElement>(null)
  const destination = safeExternalDestination(url)

  useEffect(() => {
    if (!open) return
    closeButton.current?.focus()
    const closeOnEscape = (event: KeyboardEvent) => {
      if (event.key === 'Escape') setOpen(false)
    }
    document.addEventListener('keydown', closeOnEscape)
    return () => document.removeEventListener('keydown', closeOnEscape)
  }, [open])

  if (!destination) return null

  return (
    <>
      <Button onClick={() => setOpen(true)} type="button">
        Ir a postular <ExternalLink className="size-4" />
      </Button>
      {open && (
        <div className="fixed inset-0 z-50 grid place-items-center bg-black/65 p-4">
          <div
            aria-describedby="external-site-description"
            aria-labelledby="external-site-title"
            aria-modal="true"
            className="w-full max-w-lg rounded-2xl border bg-background p-6 shadow-2xl"
            role="dialog"
          >
            <div className="flex items-start justify-between gap-4">
              <div className="flex items-start gap-3">
                <ShieldAlert className="mt-0.5 size-6 shrink-0 text-amber-600" />
                <div>
                  <h2 className="text-xl font-bold" id="external-site-title">Vas a salir de FundingPlatform</h2>
                  <p className="mt-2 text-sm leading-6 text-muted-foreground" id="external-site-description">
                    Verifica que el sitio corresponda a la entidad convocante. Nunca compartas tu contraseña de FundingPlatform en páginas externas.
                  </p>
                </div>
              </div>
              <Button
                aria-label="Cerrar confirmación"
                ref={closeButton}
                onClick={() => setOpen(false)}
                size="sm"
                type="button"
                variant="ghost"
              >
                <X className="size-4" />
              </Button>
            </div>
            <div className="mt-5 rounded-xl border bg-muted p-4">
              <p className="text-xs font-bold uppercase tracking-wide text-muted-foreground">Sitio de destino</p>
              <p className="mt-1 break-all font-mono text-sm font-semibold">{destination.hostname}</p>
            </div>
            <div className="mt-5 flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
              <Button onClick={() => setOpen(false)} type="button" variant="outline">Volver</Button>
              <Button asChild>
                <a
                  href={destination.href}
                  onClick={() => setOpen(false)}
                  rel="noopener noreferrer"
                  target="_blank"
                >
                  Continuar a {destination.hostname} <ExternalLink className="size-4" />
                </a>
              </Button>
            </div>
          </div>
        </div>
      )}
    </>
  )
}

export function FundingCatalogPage() {
  const [draftQuery, setDraftQuery] = useState('')
  const [query, setQuery] = useState('')
  const [page, setPage] = useState(1)
  const opportunities = useQuery({
    queryKey: ['funding-opportunities', query, page, pageSize],
    queryFn: ({ signal }) => fundingOpportunitiesApi.search(query, page, pageSize, signal),
    placeholderData: keepPreviousData,
  })

  function submitSearch(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setPage(1)
    setQuery(draftQuery.trim())
  }

  const lastPage = opportunities.data
    ? Math.max(1, Math.ceil(opportunities.data.totalCount / opportunities.data.pageSize))
    : 1

  return (
    <div className="mx-auto max-w-7xl space-y-6 px-4 py-8 sm:px-6 lg:py-12">
      <div className="rounded-2xl border bg-card p-6 shadow-sm sm:p-8">
        <div className="max-w-3xl space-y-3">
          <p className="text-sm font-bold uppercase tracking-[0.16em] text-primary">
            Convocatorias verificables
          </p>
          <h1 className="text-3xl font-bold tracking-tight sm:text-4xl">
            Oportunidades de financiamiento
          </h1>
          <p className="text-base leading-7 text-muted-foreground">
            Explora oportunidades publicadas y revisa siempre su procedencia, calidad
            y condiciones originales antes de postular.
          </p>
        </div>
        <form className="mt-6 flex max-w-2xl flex-col gap-2 sm:flex-row" onSubmit={submitSearch}>
          <label className="sr-only" htmlFor="funding-search">
            Buscar oportunidades
          </label>
          <div className="relative flex-1">
            <Search className="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
            <input
              className="h-11 w-full rounded-lg border bg-background pl-10 pr-3 text-sm"
              id="funding-search"
              onChange={(event) => setDraftQuery(event.target.value)}
              placeholder="Buscar por título, organismo o descripción"
              value={draftQuery}
            />
          </div>
          <Button type="submit">Buscar</Button>
        </form>
      </div>

      {opportunities.isPending && (
        <div className="space-y-4" role="status">
          <p className="flex items-center gap-2 text-sm text-muted-foreground">
            <LoaderCircle className="size-4 animate-spin" /> Cargando oportunidades…
          </p>
          <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3" aria-label="Cargando oportunidades">
            {[1, 2, 3, 4, 5, 6].map((item) => (
              <div className="h-96 animate-pulse rounded-xl border bg-card" key={item} />
            ))}
          </div>
        </div>
      )}

      {opportunities.isError && (
        <Card className="border-destructive/40">
          <CardContent className="p-6" role="alert">
            <p className="font-semibold">No fue posible cargar las oportunidades.</p>
            <p className="mt-1 text-sm text-muted-foreground">{errorMessage(opportunities.error)}</p>
            <Button className="mt-4" onClick={() => void opportunities.refetch()} variant="outline">
              Reintentar
            </Button>
          </CardContent>
        </Card>
      )}

      {opportunities.data && (
        <section aria-busy={opportunities.isFetching} className="space-y-5">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <p className="text-sm text-muted-foreground">
              <span className="font-bold text-foreground">{opportunities.data.totalCount}</span>{' '}
              oportunidades publicadas
            </p>
            <p className="flex items-center gap-2 text-xs text-muted-foreground">
              {opportunities.isFetching
                ? <><LoaderCircle className="size-4 animate-spin" /> Actualizando…</>
                : <><ShieldCheck className="size-4 text-primary" /> Datos trazables por fuente</>}
            </p>
          </div>
          {opportunities.data.items.length === 0 ? (
            <Card>
              <CardContent className="p-8 text-center">
                <h2 className="font-semibold">No encontramos oportunidades</h2>
                <p className="mt-2 text-sm text-muted-foreground">
                  Prueba con un término más amplio o limpia la búsqueda.
                </p>
              </CardContent>
            </Card>
          ) : (
            <div className="grid gap-5 md:grid-cols-2 xl:grid-cols-3">
              {opportunities.data.items.map((opportunity) => (
                <FundingCard key={opportunity.publicId} opportunity={opportunity} />
              ))}
            </div>
          )}

          {opportunities.data.totalCount > opportunities.data.pageSize && (
            <nav aria-label="Paginación de oportunidades" className="flex items-center justify-between rounded-xl border bg-card p-3 sm:justify-end sm:gap-4">
              <Button
                disabled={page <= 1 || opportunities.isFetching}
                onClick={() => setPage((value) => Math.max(1, value - 1))}
                type="button"
                variant="outline"
              >
                <ChevronLeft className="size-4" /> Anterior
              </Button>
              <p className="text-sm text-muted-foreground">
                Página <strong className="text-foreground">{opportunities.data.pageNumber}</strong> de {lastPage}
              </p>
              <Button
                disabled={page >= lastPage || opportunities.isFetching}
                onClick={() => setPage((value) => Math.min(lastPage, value + 1))}
                type="button"
                variant="outline"
              >
                Siguiente <ChevronRight className="size-4" />
              </Button>
            </nav>
          )}
        </section>
      )}
    </div>
  )
}

export function FundingOpportunityDetailView({
  item,
  backTo,
  backLabel = 'Volver a oportunidades',
  action,
  additionalDetails,
}: {
  item: FundingOpportunityDetail
  backTo: string
  backLabel?: string
  action?: ReactNode
  additionalDetails?: ReactNode
}) {
  return (
    <div className="space-y-6">
      <Button asChild size="sm" variant="ghost">
        <Link to={backTo}>
          <ArrowLeft className="size-4" /> {backLabel}
        </Link>
      </Button>

      <div className="grid gap-6 lg:grid-cols-[minmax(0,1fr)_20rem]">
        <article className="overflow-hidden rounded-2xl border bg-card shadow-sm">
          <FundingVisual detail opportunity={item} />
          <div className="space-y-6 p-6 sm:p-8">
            <header className="space-y-4 border-b pb-6">
              <div className="flex flex-wrap items-center gap-2 text-xs font-bold">
                <span className="rounded-full bg-accent px-3 py-1 text-accent-foreground">
                  {availability(item)}
                </span>
                <span className="text-muted-foreground">Calidad {qualityScore(item.dataQualityScore)}/100</span>
                {item.externalId && <span className="text-muted-foreground">N.º {item.externalId}</span>}
              </div>
              <p className="font-bold uppercase tracking-wide text-primary">{item.sponsorName}</p>
              <h1 className="text-3xl font-bold leading-tight tracking-tight sm:text-4xl">{item.title}</h1>
              {item.summary && <p className="text-lg leading-8 text-muted-foreground">{item.summary}</p>}
            </header>

            <section>
              <h2 className="text-xl font-bold">Descripción</h2>
              <p className="mt-3 whitespace-pre-line text-base leading-8 text-muted-foreground">
                {item.description ?? item.summary ?? 'Sin descripción publicada.'}
              </p>
            </section>

            {item.eligibilityDescription && (
              <section className="rounded-xl bg-muted p-5">
                <h2 className="text-xl font-bold">Quiénes pueden postular</h2>
                <p className="mt-3 whitespace-pre-line text-sm leading-7 text-muted-foreground">{item.eligibilityDescription}</p>
              </section>
            )}

            {item.requirements && (
              <section>
                <h2 className="text-xl font-bold">Requisitos de postulación</h2>
                <p className="mt-3 whitespace-pre-line text-base leading-8 text-muted-foreground">{item.requirements}</p>
              </section>
            )}

            {item.objectives && (
              <section>
                <h2 className="text-xl font-bold">Áreas de financiamiento</h2>
                <p className="mt-3 whitespace-pre-line text-muted-foreground">{item.objectives}</p>
              </section>
            )}

            {additionalDetails}

            {item.funders.length > 0 && (
              <section>
                <h2 className="text-xl font-bold">Entidades financiadoras</h2>
                <ul className="mt-3 grid gap-2 sm:grid-cols-2">
                  {item.funders.map((funder) => (
                    <li className="rounded-lg border px-4 py-3 text-sm" key={`${funder.funderId}-${funder.role}`}>
                      <strong>{funder.name}</strong>
                      <span className="ml-2 text-xs text-muted-foreground">
                        {funder.role === 1 ? 'Principal' : funder.role === 2 ? 'Cofinanciador' : 'Administrador'}
                      </span>
                    </li>
                  ))}
                </ul>
              </section>
            )}
          </div>
        </article>

        <aside className="space-y-4">
          {action}
          <Card>
            <CardHeader><CardTitle>Datos de postulación</CardTitle></CardHeader>
            <CardContent>
              <dl className="space-y-4 text-sm">
                <div><dt className="font-semibold">Apertura</dt><dd className="mt-1 text-muted-foreground">{formatDate(item.openDate)}</dd></div>
                <div><dt className="font-semibold">Cierre</dt><dd className="mt-1 text-muted-foreground">{formatDate(item.closeDate)}</dd></div>
                <div><dt className="font-semibold">Monto</dt><dd className="mt-1 text-muted-foreground">{formatAmount(item)}</dd></div>
                <div><dt className="font-semibold">Cofinanciamiento</dt><dd className="mt-1 text-muted-foreground">{item.requiresCofunding === null ? 'No informado' : item.requiresCofunding ? 'Sí' : 'No'}</dd></div>
              </dl>
              <div className="mt-6 grid gap-2">
                {item.applicationUrl && (
                  <ApplicationExitInterstitial url={item.applicationUrl} />
                )}
                {item.sourceUrl && (
                  <Button asChild variant="outline">
                    <a href={item.sourceUrl} rel="noopener noreferrer" target="_blank">Ver fuente original</a>
                  </Button>
                )}
              </div>
            </CardContent>
          </Card>
          <Card>
            <CardHeader><CardTitle>Verificación de datos</CardTitle></CardHeader>
            <CardContent className="space-y-3 text-sm">
              <p><span className="text-muted-foreground">Última verificación: </span><strong>{formatDateTime(item.lastVerifiedAtUtc)}</strong></p>
              <p><span className="text-muted-foreground">Calidad de datos: </span><strong>{qualityScore(item.dataQualityScore)}/100</strong></p>
              <p className="text-xs leading-5 text-muted-foreground">El puntaje refleja completitud y trazabilidad; no garantiza elegibilidad ni adjudicación.</p>
            </CardContent>
          </Card>
          <SourceAttribution opportunity={item} />
        </aside>
      </div>
    </div>
  )
}

export function FundingOpportunityDetailPage() {
  const { slug = '' } = useParams()
  const opportunity = useQuery({
    queryKey: ['funding-opportunity', slug],
    queryFn: ({ signal }) => fundingOpportunitiesApi.getBySlug(slug, signal),
    enabled: Boolean(slug),
    retry: false,
  })

  useEffect(() => {
    if (!opportunity.data) return
    const previousTitle = document.title
    document.title = `${opportunity.data.title} · FundingPlatform`
    return () => { document.title = previousTitle }
  }, [opportunity.data])

  if (opportunity.isPending) {
    return (
      <div className="mx-auto max-w-7xl px-4 py-8 sm:px-6" role="status">
        <p className="mb-4 flex items-center gap-2 text-sm text-muted-foreground">
          <LoaderCircle className="size-4 animate-spin" /> Cargando oportunidad…
        </p>
        <div className="h-[32rem] animate-pulse rounded-2xl border bg-card" />
      </div>
    )
  }

  if (opportunity.isError || !opportunity.data) {
    return (
      <div className="mx-auto max-w-3xl px-4 py-12 sm:px-6">
        <Card>
          <CardContent className="space-y-4 p-8" role="alert">
            <h1 className="text-2xl font-bold">No pudimos abrir esta oportunidad</h1>
            <p className="text-sm text-muted-foreground">{errorMessage(opportunity.error)}</p>
            <Button asChild variant="outline">
              <Link to="/funding">Volver al catálogo</Link>
            </Button>
          </CardContent>
        </Card>
      </div>
    )
  }

  return (
    <div className="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:py-12">
      <FundingOpportunityDetailView backTo="/funding" item={opportunity.data} />
    </div>
  )
}
