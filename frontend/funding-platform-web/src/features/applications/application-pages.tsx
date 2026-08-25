import { keepPreviousData, useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  CalendarDays,
  CheckCircle2,
  ChevronLeft,
  ChevronRight,
  CircleAlert,
  ClipboardList,
  ExternalLink,
  LoaderCircle,
  Pencil,
  Plus,
  Save,
  X,
} from 'lucide-react'
import { useCallback, useEffect, useMemo, useRef, useState, type FormEvent } from 'react'
import { Link, useSearchParams } from 'react-router-dom'

import { ApiError } from '@/api/http-client'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import {
  applicationApi,
  applicationStatuses,
  applicationStatusNames,
  createApplicationCommandId,
  type ApplicationStatus,
  type FundingApplication,
  type FundingApplicationCreate,
  type FundingApplicationUpdate,
} from '@/features/applications/application-api'
import { organizationFundingApi } from '@/features/funding/organization-funding-api'
import { organizationApi } from '@/features/organizations/organization-api'
import { projectApi } from '@/features/projects/project-api'

const selectClass = 'h-10 w-full rounded-lg border bg-background px-3 text-sm'
const textareaClass = 'min-h-28 w-full rounded-lg border bg-background px-3 py-2 text-sm'
const defaultPageSize = 12

function parsePage(value: string | null) {
  const parsed = Number(value)
  return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : 1
}

function parseStatus(value: string | null): ApplicationStatus | undefined {
  if (value === null || value.trim() === '') return undefined
  const parsed = Number(value)
  return applicationStatuses.includes(parsed as ApplicationStatus)
    ? parsed as ApplicationStatus
    : undefined
}

function formatDateOnly(value: string | null) {
  if (!value) return null
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value)
  if (!match) return null
  return new Intl.DateTimeFormat('es-CL', { dateStyle: 'medium' })
    .format(new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3]), 12))
}

function formatMoney(value: number | null, currency: string | null) {
  if (value === null || !currency) return 'Sin monto registrado'
  try {
    return new Intl.NumberFormat('es-CL', {
      style: 'currency', currency, maximumFractionDigits: currency === 'CLP' ? 0 : 2,
    }).format(value)
  } catch {
    return `${value.toLocaleString('es-CL')} ${currency}`
  }
}

function mutationErrorMessage(error: unknown) {
  if (!(error instanceof ApiError)) return 'No fue posible guardar. Comprueba la conexión e intenta nuevamente.'
  const validation = Object.values(error.problem.errors ?? {}).flat()[0]
  if (validation) return validation
  switch (error.response.status) {
    case 400: return error.problem.detail ?? 'Revisa los campos e intenta nuevamente.'
    case 401: return 'Tu sesión terminó. Inicia sesión nuevamente para continuar.'
    case 404: return 'La postulación, el proyecto o el fondo ya no está disponible para tu organización.'
    case 409: return error.problem.detail ?? 'Ya existe una postulación con ese proyecto y fondo, o la solicitud se procesó con otros datos.'
    case 412: return 'Otra persona actualizó esta postulación. Recargamos la versión vigente: revísala antes de volver a guardar.'
    case 428: return 'Falta la versión de seguridad. Recarga la postulación antes de guardar.'
    default: return error.problem.detail ?? error.problem.title
  }
}

function toOptionalNumber(value: string) {
  if (!value.trim()) return null
  const parsed = Number(value)
  return Number.isFinite(parsed) ? parsed : null
}

function OrganizationRequired() {
  return <Card><CardContent className="space-y-4 p-8 text-center"><h1 className="text-2xl font-bold">Primero crea tu organización</h1><p className="text-sm text-muted-foreground">Las postulaciones siempre pertenecen a una organización y a uno de sus proyectos.</p><Button asChild><Link to="/onboarding">Crear organización</Link></Button></CardContent></Card>
}

function ApplicationCard({ application, onEdit }: { application: FundingApplication; onEdit: () => void }) {
  const closeDate = formatDateOnly(application.fundingOpportunity.closeDate)
  return <Card>
    <CardHeader>
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div><p className="text-xs font-bold uppercase tracking-[0.14em] text-primary">{application.project.title}</p><CardTitle className="mt-1 text-xl">{application.fundingOpportunity.title}</CardTitle><p className="mt-1 text-sm text-muted-foreground">{application.fundingOpportunity.sponsorName}</p></div>
        <span className="rounded-full bg-accent px-3 py-1 text-xs font-semibold text-accent-foreground">{applicationStatusNames[application.status]}</span>
      </div>
    </CardHeader>
    <CardContent className="space-y-4">
      <dl className="grid gap-3 text-sm sm:grid-cols-3">
        <div><dt className="text-muted-foreground">Cierre del fondo</dt><dd className="font-semibold">{closeDate ?? 'Sin fecha exacta'}</dd></div>
        <div><dt className="text-muted-foreground">Fecha de postulación</dt><dd className="font-semibold">{formatDateOnly(application.applicationDate) ?? 'Por definir'}</dd></div>
        <div><dt className="text-muted-foreground">Monto solicitado</dt><dd className="font-semibold">{formatMoney(application.requestedAmount, application.currency)}</dd></div>
      </dl>
      {application.notes && <p className="line-clamp-2 text-sm leading-6 text-muted-foreground">{application.notes}</p>}
      <div className="flex flex-wrap gap-2"><Button onClick={onEdit} size="sm" variant="outline"><Pencil className="size-4" />Ver y editar</Button><Button asChild size="sm" variant="ghost"><Link to={`/opportunities/${application.fundingOpportunity.slug}`}>Ver fondo <ExternalLink className="size-4" /></Link></Button><Button asChild size="sm" variant="ghost"><Link to={`/projects/${application.project.publicId}`}>Ver proyecto</Link></Button></div>
    </CardContent>
  </Card>
}

function CreateApplicationPanel({
  organizationId,
  initialOpportunityId,
  onClose,
  onCreated,
}: {
  organizationId: string
  initialOpportunityId: string
  onClose: () => void
  onCreated: (application: FundingApplication) => void
}) {
  const queryClient = useQueryClient()
  const projects = useQuery({
    queryKey: ['projects', organizationId],
    queryFn: ({ signal }) => projectApi.list(organizationId, signal),
  })
  const opportunities = useQuery({
    queryKey: ['organization-funding', organizationId, 'application-selector'],
    queryFn: ({ signal }) => organizationFundingApi.search(organizationId, {
      onlyOpen: false,
      sort: 'closing-soon',
      pageNumber: 1,
      pageSize: 50,
    }, signal),
  })
  const selectedOpportunity = useQuery({
    queryKey: ['organization-funding', organizationId, 'detail', initialOpportunityId],
    queryFn: ({ signal }) => organizationFundingApi.getByIdOrSlug(organizationId, initialOpportunityId, signal),
    enabled: Boolean(initialOpportunityId && !opportunities.data?.items.some((item) => item.publicId === initialOpportunityId)),
    retry: false,
  })
  const catalogs = useQuery({
    queryKey: ['organization-catalogs'],
    queryFn: ({ signal }) => organizationApi.catalogs(signal),
    staleTime: 60 * 60 * 1000,
  })
  const [projectId, setProjectId] = useState('')
  const [fundingOpportunityId, setFundingOpportunityId] = useState(initialOpportunityId)
  const [notes, setNotes] = useState('')
  const [applicationDate, setApplicationDate] = useState('')
  const [requestedAmount, setRequestedAmount] = useState('')
  const [currency, setCurrency] = useState('')
  const [resultDate, setResultDate] = useState('')
  const command = useRef<{ fingerprint: string; key: string } | null>(null)

  const create = useMutation({
    mutationFn: (input: FundingApplicationCreate) => {
      const fingerprint = JSON.stringify(input)
      if (command.current?.fingerprint !== fingerprint) {
        command.current = { fingerprint, key: createApplicationCommandId() }
      }
      return applicationApi.create(organizationId, input, command.current.key)
    },
    onSuccess: async (application) => {
      command.current = null
      await queryClient.invalidateQueries({ queryKey: ['applications', organizationId] })
      await queryClient.invalidateQueries({ queryKey: ['calendar', organizationId] })
      onCreated(application)
    },
  })

  const allOpportunities = useMemo(() => {
    const values = [...(opportunities.data?.items ?? [])]
    if (selectedOpportunity.data && !values.some((item) => item.publicId === selectedOpportunity.data.publicId)) {
      values.unshift(selectedOpportunity.data)
    }
    return values
  }, [opportunities.data, selectedOpportunity.data])

  function submit(event: FormEvent) {
    event.preventDefault()
    if (!projectId || !fundingOpportunityId) return
    create.mutate({
      projectId,
      fundingOpportunityId,
      notes: notes.trim() || null,
      applicationDate: applicationDate || null,
      requestedAmount: toOptionalNumber(requestedAmount),
      currency: currency || null,
      resultDate: resultDate || null,
    })
  }

  return <Card className="border-primary/30">
    <CardHeader><div className="flex items-start justify-between gap-3"><div><p className="text-xs font-bold uppercase tracking-[0.14em] text-primary">Nueva postulación</p><CardTitle className="mt-1">Vincula un proyecto con un fondo</CardTitle></div><Button aria-label="Cerrar formulario" onClick={onClose} size="icon" variant="ghost"><X className="size-4" /></Button></div></CardHeader>
    <CardContent><form className="grid gap-5" onSubmit={submit}>
      <div className="grid gap-4 md:grid-cols-2">
        <label className="grid gap-1.5 text-sm font-semibold">Proyecto <span className="text-xs font-normal text-muted-foreground">Obligatorio</span><select aria-label="Proyecto para postular" className={selectClass} onChange={(event) => setProjectId(event.target.value)} required value={projectId}><option value="">Selecciona un proyecto</option>{projects.data?.filter((project) => project.publicationStatus !== 4).map((project) => <option key={project.publicId} value={project.publicId}>{project.title}</option>)}</select></label>
        <label className="grid gap-1.5 text-sm font-semibold">Fondo <span className="text-xs font-normal text-muted-foreground">Obligatorio</span><select aria-label="Fondo para postular" className={selectClass} onChange={(event) => setFundingOpportunityId(event.target.value)} required value={fundingOpportunityId}><option value="">Selecciona un fondo publicado</option>{allOpportunities.map((opportunity) => <option key={opportunity.publicId} value={opportunity.publicId}>{opportunity.title} · {opportunity.primaryFunderName}</option>)}</select></label>
      </div>
      {projects.data?.length === 0 && <p className="rounded-lg bg-muted p-3 text-sm">Necesitas crear al menos un proyecto antes de iniciar una postulación. <Link className="font-semibold text-primary underline" to="/projects">Crear proyecto</Link></p>}
      <label className="grid gap-1.5 text-sm font-semibold">Notas<textarea className={textareaClass} maxLength={5000} onChange={(event) => setNotes(event.target.value)} placeholder="Próximos pasos, documentos pendientes o acuerdos internos" value={notes} /></label>
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <label className="grid gap-1.5 text-sm font-semibold">Fecha planificada<Input onChange={(event) => setApplicationDate(event.target.value)} type="date" value={applicationDate} /></label>
        <label className="grid gap-1.5 text-sm font-semibold">Monto solicitado<Input min="0.0001" onChange={(event) => setRequestedAmount(event.target.value)} step="0.0001" type="number" value={requestedAmount} /></label>
        <label className="grid gap-1.5 text-sm font-semibold">Moneda<select className={selectClass} onChange={(event) => setCurrency(event.target.value)} value={currency}><option value="">Sin informar</option>{catalogs.data?.currencies.map((item) => <option key={item.code} value={item.code}>{item.code} · {item.name}</option>)}</select></label>
        <label className="grid gap-1.5 text-sm font-semibold">Fecha de resultado<Input onChange={(event) => setResultDate(event.target.value)} type="date" value={resultDate} /></label>
      </div>
      {create.isError && <p className="rounded-lg bg-destructive/10 p-3 text-sm text-destructive" role="alert">{mutationErrorMessage(create.error)}</p>}
      <p className="text-xs leading-5 text-muted-foreground">Se creará con estado “Interesado”. Esto organiza tu trabajo; no envía información al sitio del financiador.</p>
      <div className="flex justify-end"><Button disabled={create.isPending || !projectId || !fundingOpportunityId} type="submit">{create.isPending ? <LoaderCircle className="size-4 animate-spin" /> : <Plus className="size-4" />}Iniciar postulación</Button></div>
    </form></CardContent>
  </Card>
}

function ApplicationEditor({ organizationId, applicationId, onClose, onSaved }: {
  organizationId: string
  applicationId: string
  onClose: () => void
  onSaved: (application: FundingApplication) => void
}) {
  const queryClient = useQueryClient()
  const application = useQuery({
    queryKey: ['applications', organizationId, 'detail', applicationId],
    queryFn: ({ signal }) => applicationApi.get(organizationId, applicationId, signal),
    retry: false,
  })
  const catalogs = useQuery({
    queryKey: ['organization-catalogs'],
    queryFn: ({ signal }) => organizationApi.catalogs(signal),
    staleTime: 60 * 60 * 1000,
  })
  const [status, setStatus] = useState<ApplicationStatus>(0)
  const [notes, setNotes] = useState('')
  const [applicationDate, setApplicationDate] = useState('')
  const [requestedAmount, setRequestedAmount] = useState('')
  const [currency, setCurrency] = useState('')
  const [resultDate, setResultDate] = useState('')
  const [concurrencyNotice, setConcurrencyNotice] = useState('')

  useEffect(() => {
    if (!application.data) return
    setStatus(application.data.status)
    setNotes(application.data.notes ?? '')
    setApplicationDate(application.data.applicationDate ?? '')
    setRequestedAmount(application.data.requestedAmount?.toString() ?? '')
    setCurrency(application.data.currency ?? '')
    setResultDate(application.data.resultDate ?? '')
  }, [application.data])

  const update = useMutation({
    mutationFn: (input: FundingApplicationUpdate) => applicationApi.update(
      organizationId,
      applicationId,
      application.data!.eTag,
      input,
    ),
    onSuccess: async (updated) => {
      setConcurrencyNotice('')
      queryClient.setQueryData(['applications', organizationId, 'detail', applicationId], updated)
      await queryClient.invalidateQueries({ queryKey: ['applications', organizationId, 'list'] })
      await queryClient.invalidateQueries({ queryKey: ['calendar', organizationId] })
      onSaved(updated)
    },
    onError: async (error) => {
      if (error instanceof ApiError && error.response.status === 412) {
        setConcurrencyNotice(mutationErrorMessage(error))
        await application.refetch()
      }
    },
  })

  if (application.isPending) return <Card><CardContent className="flex items-center gap-2 p-8" role="status"><LoaderCircle className="size-5 animate-spin" /> Cargando postulación…</CardContent></Card>
  if (application.isError || !application.data) return <Card><CardContent className="space-y-3 p-8" role="alert"><h2 className="text-xl font-bold">No pudimos abrir la postulación</h2><p className="text-sm text-muted-foreground">{mutationErrorMessage(application.error)}</p><Button onClick={onClose} variant="outline">Cerrar</Button></CardContent></Card>
  const data = application.data

  function submit(event: FormEvent) {
    event.preventDefault()
    update.mutate({
      status,
      notes: notes.trim() || null,
      applicationDate: applicationDate || null,
      requestedAmount: toOptionalNumber(requestedAmount),
      currency: currency || null,
      resultDate: resultDate || null,
    })
  }

  return <Card className="border-primary/30">
    <CardHeader><div className="flex items-start justify-between gap-3"><div><p className="text-xs font-bold uppercase tracking-[0.14em] text-primary">{data.project.title}</p><CardTitle className="mt-1">{data.fundingOpportunity.title}</CardTitle></div><Button aria-label="Cerrar editor" onClick={onClose} size="icon" variant="ghost"><X className="size-4" /></Button></div></CardHeader>
    <CardContent><form className="grid gap-5" onSubmit={submit}>
      <label className="grid gap-1.5 text-sm font-semibold">Estado<select aria-label="Estado de la postulación" className={selectClass} disabled={!data.canEdit} onChange={(event) => setStatus(Number(event.target.value) as ApplicationStatus)} value={status}>{applicationStatuses.map((value) => <option key={value} value={value}>{applicationStatusNames[value]}</option>)}</select></label>
      <label className="grid gap-1.5 text-sm font-semibold">Notas<textarea aria-label="Notas de la postulación" className={textareaClass} disabled={!data.canEdit} maxLength={5000} onChange={(event) => setNotes(event.target.value)} value={notes} /></label>
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <label className="grid gap-1.5 text-sm font-semibold">Fecha de postulación<Input disabled={!data.canEdit} onChange={(event) => setApplicationDate(event.target.value)} type="date" value={applicationDate} /></label>
        <label className="grid gap-1.5 text-sm font-semibold">Monto solicitado<Input disabled={!data.canEdit} min="0.0001" onChange={(event) => setRequestedAmount(event.target.value)} step="0.0001" type="number" value={requestedAmount} /></label>
        <label className="grid gap-1.5 text-sm font-semibold">Moneda<select className={selectClass} disabled={!data.canEdit} onChange={(event) => setCurrency(event.target.value)} value={currency}><option value="">Sin informar</option>{catalogs.data?.currencies.map((item) => <option key={item.code} value={item.code}>{item.code} · {item.name}</option>)}</select></label>
        <label className="grid gap-1.5 text-sm font-semibold">Fecha de resultado<Input disabled={!data.canEdit} onChange={(event) => setResultDate(event.target.value)} type="date" value={resultDate} /></label>
      </div>
      {concurrencyNotice && <p className="rounded-lg bg-amber-500/10 p-3 text-sm" role="alert">{concurrencyNotice}</p>}
      {update.isError && !concurrencyNotice && <p className="rounded-lg bg-destructive/10 p-3 text-sm text-destructive" role="alert">{mutationErrorMessage(update.error)}</p>}
      {!data.canEdit && <p className="rounded-lg bg-muted p-3 text-sm">Puedes consultar esta postulación, pero solo su responsable puede modificarla.</p>}
      <div className="flex justify-end"><Button disabled={!data.canEdit || update.isPending} type="submit">{update.isPending ? <LoaderCircle className="size-4 animate-spin" /> : <Save className="size-4" />}Guardar cambios</Button></div>
    </form></CardContent>
  </Card>
}

export function ApplicationsWorkspacePage() {
  const [searchParams, setSearchParams] = useSearchParams()
  const queryClient = useQueryClient()
  const organizations = useQuery({ queryKey: ['organizations'], queryFn: ({ signal }) => organizationApi.list(signal) })
  const organization = organizations.data?.[0]
  const projects = useQuery({
    queryKey: ['projects', organization?.publicId],
    queryFn: ({ signal }) => projectApi.list(organization!.publicId, signal),
    enabled: Boolean(organization),
  })
  const page = parsePage(searchParams.get('page'))
  const status = parseStatus(searchParams.get('status'))
  const projectId = searchParams.get('projectId') || undefined
  const initialOpportunityId = searchParams.get('fundingOpportunityId') || ''
  const [creating, setCreating] = useState(searchParams.get('new') === '1' || Boolean(initialOpportunityId))
  const [editingId, setEditingId] = useState(searchParams.get('applicationId') || '')
  const [success, setSuccess] = useState('')
  const criteria = useMemo(() => ({ status, projectId, page, pageSize: defaultPageSize }), [status, projectId, page])
  const applications = useQuery({
    queryKey: ['applications', organization?.publicId, 'list', criteria],
    queryFn: ({ signal }) => applicationApi.list(organization!.publicId, criteria, signal),
    enabled: Boolean(organization),
    placeholderData: keepPreviousData,
  })

  const replaceParameter = useCallback((key: string, value?: string, resetPage = true) => {
    setSearchParams((current) => {
      const next = new URLSearchParams(current)
      if (value) next.set(key, value)
      else next.delete(key)
      if (resetPage) next.delete('page')
      return next
    }, { replace: true })
  }, [setSearchParams])

  useEffect(() => {
    if (!applications.data || applications.isPlaceholderData) return
    const lastPage = Math.max(1, Math.ceil(applications.data.totalCount / applications.data.pageSize))
    if (page > lastPage) replaceParameter('page', String(lastPage), false)
  }, [applications.data, applications.isPlaceholderData, page, replaceParameter])

  if (organizations.isPending) return <p className="flex items-center gap-2" role="status"><LoaderCircle className="size-5 animate-spin" /> Cargando postulaciones…</p>
  if (organizations.isError) return <Card><CardContent className="p-8" role="alert">No pudimos cargar tu organización.</CardContent></Card>
  if (!organization) return <OrganizationRequired />
  const lastPage = applications.data ? Math.max(1, Math.ceil(applications.data.totalCount / applications.data.pageSize)) : 1

  function closeCreate() {
    setCreating(false)
    setSearchParams((current) => {
      const next = new URLSearchParams(current)
      next.delete('new')
      next.delete('fundingOpportunityId')
      return next
    }, { replace: true })
  }

  function openEditor(applicationId: string) {
    setCreating(false)
    setSuccess('')
    setEditingId(applicationId)
    setSearchParams((current) => {
      const next = new URLSearchParams(current)
      next.delete('new')
      next.delete('fundingOpportunityId')
      next.set('applicationId', applicationId)
      return next
    }, { replace: true })
  }

  function closeEditor() {
    setEditingId('')
    replaceParameter('applicationId', undefined, false)
  }

  function startCreate() {
    setSuccess('')
    setEditingId('')
    setCreating(true)
    setSearchParams((current) => {
      const next = new URLSearchParams(current)
      next.delete('applicationId')
      next.set('new', '1')
      return next
    }, { replace: true })
  }

  return <div className="space-y-6">
    <header className="flex flex-wrap items-end justify-between gap-4"><div><p className="text-sm font-bold uppercase tracking-[0.16em] text-primary">Seguimiento por proyecto</p><h1 className="mt-1 text-3xl font-bold">Postulaciones</h1><p className="mt-2 text-muted-foreground">Organiza el trabajo interno. FundingPlatform no presenta formularios en nombre de tu organización.</p></div><Button onClick={startCreate}><Plus className="size-4" />Nueva postulación</Button></header>

    {success && <p className="flex items-center gap-2 rounded-lg bg-accent p-3 text-sm font-medium text-accent-foreground" role="status"><CheckCircle2 className="size-4" />{success}</p>}
    {creating && <CreateApplicationPanel initialOpportunityId={initialOpportunityId} onClose={closeCreate} onCreated={(created) => { openEditor(created.publicId); setSuccess(`Postulación iniciada con éxito para “${created.fundingOpportunity.title}”.`) }} organizationId={organization.publicId} />}
    {editingId && <ApplicationEditor applicationId={editingId} onClose={closeEditor} onSaved={(updated) => { setSuccess(`Cambios guardados con éxito en “${updated.fundingOpportunity.title}”.`); void queryClient.invalidateQueries({ queryKey: ['applications', organization.publicId, 'list'] }) }} organizationId={organization.publicId} />}

    <section aria-label="Filtros de postulaciones" className="grid gap-3 rounded-xl border bg-card p-4 sm:grid-cols-2">
      <label className="grid gap-1 text-xs font-semibold">Estado<select className={selectClass} onChange={(event) => replaceParameter('status', event.target.value)} value={status ?? ''}><option value="">Todos</option>{applicationStatuses.map((value) => <option key={value} value={value}>{applicationStatusNames[value]}</option>)}</select></label>
      <label className="grid gap-1 text-xs font-semibold">Proyecto<select className={selectClass} onChange={(event) => replaceParameter('projectId', event.target.value)} value={projectId ?? ''}><option value="">Todos</option>{projects.data?.map((project) => <option key={project.publicId} value={project.publicId}>{project.title}</option>)}</select></label>
    </section>

    <p aria-live="polite" className="text-sm text-muted-foreground">{applications.data ? <><strong className="text-foreground">{applications.data.totalCount}</strong> postulaciones</> : 'Preparando postulaciones…'}{applications.isFetching && <span> · Actualizando…</span>}</p>
    {applications.isPending && <Card><CardContent className="flex items-center gap-2 p-8" role="status"><LoaderCircle className="size-5 animate-spin" /> Cargando postulaciones…</CardContent></Card>}
    {applications.isError && <Card className="border-destructive/40"><CardContent className="space-y-3 p-8" role="alert"><CircleAlert className="size-8 text-destructive" /><h2 className="text-xl font-bold">No pudimos cargar las postulaciones</h2><p className="text-sm text-muted-foreground">{mutationErrorMessage(applications.error)}</p><Button onClick={() => void applications.refetch()} variant="outline">Reintentar</Button></CardContent></Card>}
    {applications.data?.items.length === 0 && <Card><CardContent className="space-y-3 p-10 text-center"><ClipboardList className="mx-auto size-9 text-muted-foreground" /><h2 className="text-xl font-bold">No hay postulaciones con estos filtros</h2><p className="text-sm text-muted-foreground">Inicia una desde aquí o desde el detalle de un concurso.</p><Button onClick={startCreate} variant="outline"><Plus className="size-4" />Iniciar postulación</Button></CardContent></Card>}
    {applications.data && applications.data.items.length > 0 && <div className="grid gap-4">{applications.data.items.map((application) => <ApplicationCard application={application} key={application.publicId} onEdit={() => openEditor(application.publicId)} />)}</div>}
    {applications.data && lastPage > 1 && <nav aria-label="Paginación de postulaciones" className="flex items-center justify-end gap-3 rounded-xl border bg-card p-3"><Button disabled={page <= 1 || applications.isFetching} onClick={() => replaceParameter('page', String(page - 1), false)} variant="outline"><ChevronLeft className="size-4" />Anterior</Button><p className="text-sm text-muted-foreground">Página {applications.data.pageNumber} de {lastPage}</p><Button disabled={page >= lastPage || applications.isFetching} onClick={() => replaceParameter('page', String(page + 1), false)} variant="outline">Siguiente<ChevronRight className="size-4" /></Button></nav>}
    <Card><CardContent className="flex items-start gap-3 p-5 text-sm text-muted-foreground"><CalendarDays className="mt-0.5 size-5 shrink-0 text-primary" /><p>Las fechas planificadas, resultados y cierres vinculados también aparecen en el calendario de la organización.</p></CardContent></Card>
  </div>
}
