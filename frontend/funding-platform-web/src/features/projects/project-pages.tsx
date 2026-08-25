import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  Archive,
  ArrowLeft,
  CheckCircle2,
  CircleAlert,
  Clock3,
  Globe2,
  LoaderCircle,
  Plus,
  Save,
  Send,
  Target,
} from 'lucide-react'
import { useEffect, useState, type ReactNode } from 'react'
import { useForm } from 'react-hook-form'
import { Link, useNavigate, useParams } from 'react-router-dom'

import { ApiError } from '@/api/http-client'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { organizationApi, type CatalogOption, type OrganizationCatalogs } from '@/features/organizations/organization-api'
import {
  createProjectCommandId,
  projectApi,
  type ProjectDetails,
  type ProjectWriteInput,
} from '@/features/projects/project-api'

const selectClass = 'h-10 w-full rounded-lg border bg-background px-3 text-sm'
const textareaClass = 'min-h-28 w-full rounded-lg border bg-background px-3 py-2 text-sm'
const statusNames = ['Idea', 'Diseño', 'Buscando financiamiento', 'Financiado parcialmente', 'Financiado', 'En ejecución', 'Completado']
const publicationNames = ['Borrador', 'Pendiente de revisión', 'Publicado', 'Rechazado', 'Archivado']

function Field({ label, error, children }: { label: string; error?: string; children: ReactNode }) {
  return <label className="grid gap-1.5 text-sm font-semibold"><span>{label}</span>{children}{error && <span className="text-xs font-normal text-destructive" role="alert">{error}</span>}</label>
}

function errorMessage(error: unknown) {
  return error instanceof ApiError
    ? validationMessages(error)[0] ?? error.problem.detail ?? error.problem.title
    : 'No fue posible completar la operación. Intenta nuevamente.'
}

function validationMessages(error: unknown) {
  if (!(error instanceof ApiError) || !error.problem.errors) return []
  return Object.values(error.problem.errors).flat()
}

function formatDate(value: string | null) {
  return value
    ? new Intl.DateTimeFormat('es-CL', { dateStyle: 'medium' }).format(new Date(value))
    : null
}

function MultiChoice({ label, items, selected, onChange }: {
  label: string
  items: CatalogOption<number>[]
  selected: number[]
  onChange: (value: number[]) => void
}) {
  return <fieldset className="space-y-2"><legend className="text-sm font-semibold">{label}</legend>
    <div className="grid gap-2 sm:grid-cols-2">
      {items.map(item => <label className="flex cursor-pointer items-center gap-2 rounded-lg border bg-background px-3 py-2 text-sm" key={item.id}>
        <input checked={selected.includes(item.id)} onChange={() => onChange(selected.includes(item.id) ? selected.filter(id => id !== item.id) : [...selected, item.id])} type="checkbox" />
        {item.name}
      </label>)}
    </div>
  </fieldset>
}

function emptyProject(): ProjectWriteInput {
  return {
    title: '', summary: null, description: null, status: 0, startDate: null, endDate: null,
    budgetTotal: null, confirmedFunding: null, currency: null, countryIds: [], regionIds: [],
    categoryIds: [], beneficiaryTypeIds: [], projectTypeIds: [],
  }
}

function toInput(project: ProjectDetails): ProjectWriteInput {
  return {
    title: project.title, summary: project.summary, description: project.description,
    status: project.status, startDate: project.startDate, endDate: project.endDate,
    budgetTotal: project.budgetTotal, confirmedFunding: project.confirmedFunding,
    currency: project.currency, countryIds: project.countryIds, regionIds: project.regionIds,
    categoryIds: project.categoryIds, beneficiaryTypeIds: project.beneficiaryTypeIds,
    projectTypeIds: project.projectTypeIds,
  }
}

function ProjectForm({ organizationId, catalogs, project, onDirtyChange }: {
  organizationId: string
  catalogs: OrganizationCatalogs
  project?: ProjectDetails
  onDirtyChange?: (dirty: boolean) => void
}) {
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const { register, handleSubmit, watch, setValue, setError, clearErrors, reset, formState } = useForm<ProjectWriteInput>({
    defaultValues: project ? toInput(project) : emptyProject(),
  })
  useEffect(() => { if (project) reset(toInput(project)) }, [project, reset])
  useEffect(() => { onDirtyChange?.(formState.isDirty) }, [formState.isDirty, onDirtyChange])
  const save = useMutation({
    mutationFn: (input: ProjectWriteInput) => project
      ? projectApi.update(organizationId, project.publicId, project.eTag, input)
      : projectApi.create(organizationId, input),
    onSuccess: async result => {
      await queryClient.invalidateQueries({ queryKey: ['projects', organizationId] })
      await queryClient.invalidateQueries({ queryKey: ['project', organizationId, result.publicId] })
      if (!project) void navigate(`/projects/${result.publicId}`, { replace: true })
      else reset(toInput(result as ProjectDetails))
    },
    onError: error => {
      if (!(error instanceof ApiError)) return
      const endDateError = error.problem.errors?.endDate?.[0]
      if (endDateError) setError('endDate', { type: 'server', message: endDateError })
    },
  })
  const countries = watch('countryIds') ?? []
  const regions = watch('regionIds') ?? []
  const categories = watch('categoryIds') ?? []
  const beneficiaries = watch('beneficiaryTypeIds') ?? []
  const projectTypes = watch('projectTypeIds') ?? []
  const visibleRegions = catalogs.regions.filter(region => countries.includes(region.countryId))
  const optionalNumber = { setValueAs: (value: string) => value === '' ? null : Number(value) }
  const contentLocked = Boolean(project && [1, 2, 4].includes(project.publicationStatus))

  return <form className="space-y-5" onSubmit={handleSubmit(input => {
    clearErrors('endDate')
    if (input.startDate && input.endDate && input.endDate < input.startDate) {
      setError('endDate', { type: 'validate', message: 'La fecha de término no puede ser anterior al inicio.' }, { shouldFocus: true })
      return
    }
    save.mutate(input)
  })}>
    <Card><CardHeader><CardTitle>{project ? 'Editar proyecto' : 'Nuevo proyecto'}</CardTitle></CardHeader>
      <CardContent><fieldset className="grid gap-5 disabled:opacity-70" disabled={contentLocked}>
        <Field label="Título"><Input {...register('title', { required: true, minLength: 3, maxLength: 250 })} placeholder="Ej. Agua segura para comunidades rurales" /></Field>
        <Field label="Resumen"><textarea className={textareaClass} {...register('summary')} placeholder="Describe el objetivo en pocas líneas" /></Field>
        <Field label="Descripción"><textarea className={textareaClass} {...register('description')} placeholder="Problema, solución, resultados e impacto esperado" /></Field>
        <div className="grid gap-4 sm:grid-cols-3">
          <Field label="Estado"><select className={selectClass} {...register('status', { valueAsNumber: true })}>{statusNames.map((name, value) => <option key={name} value={value}>{name}</option>)}</select></Field>
          <Field label="Inicio"><Input type="date" {...register('startDate', { setValueAs: value => value || null })} /></Field>
          <Field error={formState.errors.endDate?.message} label="Término"><Input aria-invalid={Boolean(formState.errors.endDate)} type="date" {...register('endDate', { setValueAs: value => value || null })} /></Field>
        </div>
        <div className="grid gap-4 sm:grid-cols-3">
          <Field label="Presupuesto total"><Input min="0" step="0.01" type="number" {...register('budgetTotal', optionalNumber)} /></Field>
          <Field label="Financiamiento confirmado"><Input min="0" step="0.01" type="number" {...register('confirmedFunding', optionalNumber)} /></Field>
          <Field label="Moneda"><select className={selectClass} {...register('currency', { setValueAs: value => value || null })}><option value="">Sin presupuesto</option>{catalogs.currencies.map(item => <option key={item.code} value={item.code}>{item.code} · {item.name}</option>)}</select></Field>
        </div>
        <MultiChoice label="Países" items={catalogs.countries} selected={countries} onChange={value => {
          setValue('countryIds', value, { shouldDirty: true })
          const allowed = catalogs.regions.filter(region => value.includes(region.countryId)).map(region => region.id)
          setValue('regionIds', regions.filter(id => allowed.includes(id)), { shouldDirty: true })
        }} />
        {visibleRegions.length > 0 && <MultiChoice label="Regiones" items={visibleRegions} selected={regions} onChange={value => setValue('regionIds', value, { shouldDirty: true })} />}
        <MultiChoice label="Áreas de impacto" items={catalogs.fundingCategories} selected={categories} onChange={value => setValue('categoryIds', value, { shouldDirty: true })} />
        <MultiChoice label="Población beneficiaria" items={catalogs.beneficiaryTypes} selected={beneficiaries} onChange={value => setValue('beneficiaryTypeIds', value, { shouldDirty: true })} />
        <MultiChoice label="Tipo de proyecto" items={catalogs.projectTypes} selected={projectTypes} onChange={value => setValue('projectTypeIds', value, { shouldDirty: true })} />
        {contentLocked && <p className="rounded-lg bg-muted p-3 text-sm">El contenido está bloqueado mientras el proyecto está {publicationNames[project!.publicationStatus].toLowerCase()}. Así la versión revisada no puede cambiar silenciosamente.</p>}
        {save.isError && <p className="rounded-lg bg-destructive/10 p-3 text-sm text-destructive">{errorMessage(save.error)}</p>}
        {save.isSuccess && project && <p className="rounded-lg bg-accent p-3 text-sm font-medium text-accent-foreground">Proyecto guardado y versionado.</p>}
      </fieldset></CardContent>
    </Card>
    {!contentLocked && <div className="flex justify-end"><Button disabled={save.isPending || (Boolean(project) && !formState.isDirty)} type="submit">{save.isPending ? <LoaderCircle className="size-4 animate-spin" /> : <Save className="size-4" />}{project ? 'Guardar cambios' : 'Crear proyecto'}</Button></div>}
  </form>
}

function ProjectPublicationPanel({
  organizationId,
  organizationReady,
  project,
  hasUnsavedChanges,
  onChanged,
}: {
  organizationId: string
  organizationReady: boolean
  project: ProjectDetails
  hasUnsavedChanges: boolean
  onChanged: () => Promise<unknown>
}) {
  const [confirmArchive, setConfirmArchive] = useState(false)
  const submit = useMutation({
    mutationFn: (idempotencyKey: string) => projectApi.requestPublication(
      organizationId,
      project.publicId,
      project.eTag,
      idempotencyKey,
    ),
    onSuccess: onChanged,
    retry: 1,
  })
  const archive = useMutation({
    mutationFn: (idempotencyKey: string) => projectApi.archive(
      organizationId,
      project.publicId,
      project.eTag,
      idempotencyKey,
    ),
    onSuccess: onChanged,
    retry: 1,
  })
  const checks = [
    { label: 'Perfil de la organización al 80% o más', ready: organizationReady },
    { label: 'Resumen del proyecto', ready: Boolean(project.summary?.trim()) },
    { label: 'Descripción del proyecto', ready: Boolean(project.description?.trim()) },
    { label: 'Presupuesto y moneda', ready: Boolean(project.budgetTotal && project.budgetTotal > 0 && project.currency) },
    { label: 'País o territorio', ready: project.countryIds.length > 0 },
    { label: 'Área de impacto', ready: project.categoryIds.length > 0 },
    { label: 'Población beneficiaria', ready: project.beneficiaryTypeIds.length > 0 },
    { label: 'Tipo de proyecto', ready: project.projectTypeIds.length > 0 },
  ]
  const canSubmit = project.publicationStatus === 0 || project.publicationStatus === 3
  const canArchive = project.publicationStatus !== 4
  const mutationError = submit.error ?? archive.error
  const serverIssues = validationMessages(mutationError)

  return <Card>
    <CardHeader className="sm:flex sm:flex-row sm:items-start sm:justify-between sm:space-y-0">
      <div><p className="text-xs font-bold uppercase tracking-[0.16em] text-primary">Publicación moderada</p><CardTitle className="mt-1">{publicationNames[project.publicationStatus]}</CardTitle></div>
      <span className="rounded-full bg-muted px-3 py-1 text-xs font-semibold">Completitud local {Math.round(checks.filter(check => check.ready).length / checks.length * 100)}%</span>
    </CardHeader>
    <CardContent className="space-y-5">
      {project.publicationStatus === 1 && <p className="flex items-center gap-2 rounded-lg bg-accent p-3 text-sm"><Clock3 className="size-4" /> En revisión desde {formatDate(project.submittedAtUtc) ?? 'hoy'}. El contenido permanecerá bloqueado.</p>}
      {project.publicationStatus === 2 && <p className="flex items-center gap-2 rounded-lg bg-accent p-3 text-sm"><CheckCircle2 className="size-4" /> Publicado el {formatDate(project.publishedAtUtc) ?? 'día de aprobación'}.</p>}
      {project.publicationStatus === 3 && <p className="rounded-lg bg-destructive/10 p-3 text-sm text-destructive"><strong>Revisión rechazada.</strong> {project.rejectionReason ?? 'Corrige el contenido indicado antes de reenviar.'}</p>}
      {project.publicationStatus === 4 && <p className="rounded-lg bg-muted p-3 text-sm">Este proyecto fue archivado y ya no es visible públicamente.</p>}

      {canSubmit && <div><h2 className="text-sm font-bold">Antes de enviarlo</h2><ul className="mt-2 grid gap-2 sm:grid-cols-2">{checks.map(check => <li className="flex items-start gap-2 text-sm" key={check.label}>{check.ready ? <CheckCircle2 className="mt-0.5 size-4 shrink-0 text-primary" /> : <CircleAlert className="mt-0.5 size-4 shrink-0 text-muted-foreground" />}<span>{check.label}</span></li>)}</ul></div>}
      {hasUnsavedChanges && <p className="rounded-lg bg-muted p-3 text-sm">Guarda tus cambios antes de solicitar la revisión.</p>}
      {mutationError && <div className="rounded-lg bg-destructive/10 p-3 text-sm text-destructive"><p>{errorMessage(mutationError)}</p>{serverIssues.length > 0 && <ul className="mt-2 list-disc pl-5">{serverIssues.map(message => <li key={message}>{message}</li>)}</ul>}</div>}

      <div className="flex flex-wrap gap-3">
        {canSubmit && <Button disabled={submit.isPending || archive.isPending || hasUnsavedChanges} onClick={() => submit.mutate(createProjectCommandId())} type="button">{submit.isPending ? <LoaderCircle className="size-4 animate-spin" /> : <Send className="size-4" />}Enviar a revisión</Button>}
        {project.publicationStatus === 2 && <Button asChild variant="outline"><Link to={`/marketplace/projects/${project.slug}`}><Globe2 className="size-4" />Ver perfil público</Link></Button>}
        {canArchive && !confirmArchive && <Button disabled={submit.isPending || archive.isPending} onClick={() => setConfirmArchive(true)} type="button" variant="ghost"><Archive className="size-4" />Archivar</Button>}
        {canArchive && confirmArchive && <><Button disabled={archive.isPending} onClick={() => archive.mutate(createProjectCommandId())} type="button" variant="outline">{archive.isPending ? <LoaderCircle className="size-4 animate-spin" /> : <Archive className="size-4" />}Confirmar archivo</Button><Button onClick={() => setConfirmArchive(false)} type="button" variant="ghost">Cancelar</Button></>}
      </div>
    </CardContent>
  </Card>
}

function useWorkspace() {
  const organizations = useQuery({ queryKey: ['organizations'], queryFn: ({ signal }) => organizationApi.list(signal) })
  const catalogs = useQuery({ queryKey: ['organization-catalogs'], queryFn: ({ signal }) => organizationApi.catalogs(signal), staleTime: 60 * 60 * 1000 })
  return { organizations, catalogs, organization: organizations.data?.[0] }
}

export function ProjectsPage() {
  const [creating, setCreating] = useState(false)
  const { organizations, catalogs, organization } = useWorkspace()
  const projects = useQuery({
    queryKey: ['projects', organization?.publicId],
    queryFn: ({ signal }) => projectApi.list(organization!.publicId, signal),
    enabled: Boolean(organization),
  })
  if (organizations.isPending || catalogs.isPending || (organization && projects.isPending)) return <p className="flex items-center gap-2"><LoaderCircle className="size-5 animate-spin" /> Cargando proyectos…</p>
  if (organizations.isError || catalogs.isError || projects.isError) return <p>No fue posible cargar los proyectos.</p>
  if (!organization) return <Card><CardContent className="p-8"><h1 className="text-xl font-bold">Primero crea tu organización</h1><Button asChild className="mt-4"><Link to="/onboarding">Ir al onboarding</Link></Button></CardContent></Card>

  return <div className="space-y-6">
    <div className="flex flex-wrap items-end justify-between gap-4"><div><p className="text-sm font-bold uppercase tracking-[0.16em] text-primary">FASE 5</p><h1 className="mt-1 text-3xl font-bold">Proyectos de {organization.name}</h1><p className="mt-2 text-muted-foreground">Cada proyecto conserva su propia necesidad de financiamiento y su historial.</p></div><Button onClick={() => setCreating(value => !value)}><Plus className="size-4" />{creating ? 'Cerrar formulario' : 'Nuevo proyecto'}</Button></div>
    {creating && catalogs.data && <ProjectForm catalogs={catalogs.data} organizationId={organization.publicId} />}
    {!projects.data?.length && !creating && <Card><CardContent className="p-8 text-center"><Target className="mx-auto size-10 text-primary" /><h2 className="mt-3 text-xl font-bold">Aún no hay proyectos</h2><p className="mt-2 text-muted-foreground">Crea el primero para preparar el matching de fondos.</p></CardContent></Card>}
    <div className="grid gap-4 lg:grid-cols-2">{projects.data?.map(project => <Card key={project.publicId}><CardContent className="p-5"><div className="flex items-start justify-between gap-3"><div><p className="text-xs font-bold uppercase tracking-wide text-primary">{statusNames[project.status]}</p><h2 className="mt-1 text-xl font-bold">{project.title}</h2></div><div className="flex flex-col items-end gap-1"><span className="rounded-full bg-muted px-2.5 py-1 text-xs">{publicationNames[project.publicationStatus]}</span><span className="text-xs text-muted-foreground">v{project.projectVersion}</span></div></div><p className="mt-3 line-clamp-2 text-sm text-muted-foreground">{project.summary ?? 'Sin resumen todavía.'}</p><div className="mt-4 flex items-center justify-between gap-3"><p className="text-sm">Brecha: <strong>{project.fundingGap === null ? 'Sin definir' : `${new Intl.NumberFormat('es-CL').format(project.fundingGap)} ${project.currency}`}</strong></p><Button asChild size="sm" variant="outline"><Link to={`/projects/${project.publicId}`}>{[1, 2, 4].includes(project.publicationStatus) ? 'Ver' : 'Editar'}</Link></Button></div></CardContent></Card>)}</div>
  </div>
}

export function ProjectDetailPage() {
  const { projectId } = useParams()
  const [hasUnsavedChanges, setHasUnsavedChanges] = useState(false)
  const { organizations, catalogs, organization } = useWorkspace()
  const project = useQuery({
    queryKey: ['project', organization?.publicId, projectId],
    queryFn: ({ signal }) => projectApi.get(organization!.publicId, projectId!, signal),
    enabled: Boolean(organization && projectId),
  })
  if (organizations.isPending || catalogs.isPending || project.isPending) return <p className="flex items-center gap-2"><LoaderCircle className="size-5 animate-spin" /> Cargando proyecto…</p>
  if (!organization || !catalogs.data || project.isError || !project.data) return <p>No encontramos el proyecto o no tienes acceso.</p>
  return <div className="space-y-5"><Button asChild variant="ghost"><Link to="/projects"><ArrowLeft className="size-4" /> Volver a proyectos</Link></Button><div><p className="text-sm text-muted-foreground">Versión {project.data.projectVersion}</p><h1 className="text-3xl font-bold">{project.data.title}</h1>{project.data.fundingGap !== null && <p className="mt-2 text-muted-foreground">Brecha actual: {new Intl.NumberFormat('es-CL').format(project.data.fundingGap)} {project.data.currency}</p>}</div><ProjectPublicationPanel hasUnsavedChanges={hasUnsavedChanges} onChanged={async () => { await project.refetch(); await organizations.refetch() }} organizationId={organization.publicId} organizationReady={organization.profileStatus === 2 && organization.profileCompleteness >= 80} project={project.data} /><ProjectForm catalogs={catalogs.data} onDirtyChange={setHasUnsavedChanges} organizationId={organization.publicId} project={project.data} /></div>
}
