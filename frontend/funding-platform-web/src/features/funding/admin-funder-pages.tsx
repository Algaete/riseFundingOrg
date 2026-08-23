import { zodResolver } from '@hookform/resolvers/zod'
import { keepPreviousData, useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  ArrowLeft,
  Building2,
  ChevronLeft,
  ChevronRight,
  ExternalLink,
  LoaderCircle,
  Plus,
  RefreshCw,
  Save,
  Search,
} from 'lucide-react'
import { type FormEvent, useEffect, useState, type ReactNode } from 'react'
import { useForm } from 'react-hook-form'
import { Link, useNavigate, useParams } from 'react-router-dom'
import { z } from 'zod'

import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import {
  adminErrorMessage,
  adminValidationMessages,
  EditorialWorkflowPanel,
  formatAdminDate,
  isConcurrencyConflict,
  PublicationStatusBadge,
  publicationStatusLabels,
} from '@/features/funding/admin-editorial'
import {
  adminFundersApi,
  type AdminFunderDetail,
  type FunderWriteInput,
  type PublicationStatus,
} from '@/features/funding/admin-funding-api'
import { executeEditorialCommand } from '@/features/funding/editorial-command-cache'
import { organizationApi } from '@/features/organizations/organization-api'

const listPageSize = 20
const inputClass = 'h-10 w-full rounded-lg border bg-background px-3 text-sm'
const textareaClass = 'min-h-28 w-full rounded-lg border bg-background px-3 py-2 text-sm'

const optionalHttpUrl = z.string().trim().refine(
  (value) => value === '' || /^https?:\/\/[^\s]+$/i.test(value),
  'Ingresa una URL completa que comience con http:// o https://.',
)

const funderSchema = z.object({
  name: z.string().trim().min(2, 'El nombre debe tener al menos 2 caracteres.').max(250),
  description: z.string().trim().max(4000),
  websiteUrl: optionalHttpUrl,
  countryId: z.string(),
  aliasesText: z.string().max(2000),
})

type FunderFormValues = z.infer<typeof funderSchema>

function Field({ children, error, label }: { children: ReactNode; error?: string; label: string }) {
  return (
    <label className="grid gap-1.5 text-sm font-semibold">
      <span>{label}</span>
      {children}
      {error && <span className="text-xs font-normal text-destructive">{error}</span>}
    </label>
  )
}

function toFormValues(funder?: AdminFunderDetail): FunderFormValues {
  return {
    name: funder?.name ?? '',
    description: funder?.description ?? '',
    websiteUrl: funder?.websiteUrl ?? '',
    countryId: funder?.countryId?.toString() ?? '',
    aliasesText: funder?.aliases.join('\n') ?? '',
  }
}

function toWriteInput(values: FunderFormValues): FunderWriteInput {
  return {
    name: values.name.trim(),
    description: values.description.trim() || null,
    websiteUrl: values.websiteUrl.trim() || null,
    countryId: values.countryId ? Number(values.countryId) : null,
    aliases: [...new Set(
      values.aliasesText
        .split(/[\n,]/)
        .map((value) => value.trim())
        .filter(Boolean),
    )],
  }
}

function AdminFunderForm({ funder, onDirtyChange }: { funder?: AdminFunderDetail; onDirtyChange?: (dirty: boolean) => void }) {
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const catalogs = useQuery({
    queryKey: ['organization-catalogs'],
    queryFn: ({ signal }) => organizationApi.catalogs(signal),
    staleTime: 60 * 60 * 1000,
  })
  const form = useForm<FunderFormValues>({
    resolver: zodResolver(funderSchema),
    defaultValues: toFormValues(funder),
  })

  useEffect(() => { form.reset(toFormValues(funder)) }, [form, funder])
  useEffect(() => { onDirtyChange?.(form.formState.isDirty) }, [form.formState.isDirty, onDirtyChange])

  const save = useMutation({
    mutationFn: (values: FunderFormValues) => {
      const input = toWriteInput(values)
      const scope = funder ? `funder:${funder.funderId}:update` : 'funder:create'
      return executeEditorialCommand(scope, { eTag: funder?.eTag, input }, (idempotencyKey) => (
        funder
          ? adminFundersApi.update(funder.funderId, funder.eTag, input, idempotencyKey)
          : adminFundersApi.create(input, idempotencyKey)
      ))
    },
    onSuccess: async (result) => {
      await queryClient.invalidateQueries({ queryKey: ['admin-funders'] })
      if (!funder) {
        void navigate(`/admin/funders/${result.entityId}`, { replace: true })
        return
      }
      await queryClient.invalidateQueries({ queryKey: ['admin-funder', funder.funderId] })
    },
  })
  const locked = Boolean(funder && [1, 2, 4].includes(funder.publicationStatus))
  const serverValidation = adminValidationMessages(save.error)

  if (catalogs.isPending) {
    return <p className="flex items-center gap-2" role="status"><LoaderCircle className="size-4 animate-spin" /> Cargando países…</p>
  }
  if (catalogs.isError || !catalogs.data) {
    return <p className="rounded-lg bg-destructive/10 p-3 text-sm text-destructive" role="alert">No fue posible cargar los países disponibles.</p>
  }

  return (
    <form className="space-y-5" onSubmit={form.handleSubmit((values) => save.mutate(values))}>
      <Card>
        <CardHeader><CardTitle>{funder ? 'Datos del financiador' : 'Nuevo financiador'}</CardTitle></CardHeader>
        <CardContent>
          <fieldset className="grid gap-5 disabled:opacity-65" disabled={locked || save.isPending}>
            <Field error={form.formState.errors.name?.message} label="Nombre">
              <Input {...form.register('name')} autoComplete="organization" placeholder="Ej. Fundación para el Desarrollo" />
            </Field>
            <Field error={form.formState.errors.description?.message} label="Descripción">
              <textarea {...form.register('description')} className={textareaClass} placeholder="Misión, alcance y líneas de financiamiento" />
            </Field>
            <div className="grid gap-4 sm:grid-cols-2">
              <Field error={form.formState.errors.websiteUrl?.message} label="Sitio web oficial">
                <Input {...form.register('websiteUrl')} inputMode="url" placeholder="https://..." />
              </Field>
              <Field label="País">
                <select {...form.register('countryId')} className={inputClass}>
                  <option value="">Sin país informado</option>
                  {catalogs.data.countries.map((country) => <option key={country.id} value={country.id}>{country.name}</option>)}
                </select>
              </Field>
            </div>
            <Field error={form.formState.errors.aliasesText?.message} label="Alias conocidos">
              <textarea {...form.register('aliasesText')} className={textareaClass} placeholder="Un alias por línea; también puedes separarlos por coma" />
            </Field>
            {locked && (
              <p className="rounded-lg bg-muted p-3 text-sm">
                El contenido está bloqueado mientras permanece {publicationStatusLabels[funder!.publicationStatus].toLowerCase()}.
              </p>
            )}
          </fieldset>
          {save.isError && (
            <div className="mt-5 rounded-lg bg-destructive/10 p-3 text-sm text-destructive" role="alert">
              <p>{adminErrorMessage(save.error)}</p>
              {serverValidation.length > 0 && <ul className="mt-2 list-disc pl-5">{serverValidation.map((message) => <li key={message}>{message}</li>)}</ul>}
              {isConcurrencyConflict(save.error) && funder && (
                <Button className="mt-3" onClick={() => void queryClient.invalidateQueries({ queryKey: ['admin-funder', funder.funderId] })} size="sm" type="button" variant="outline">
                  <RefreshCw className="size-4" /> Cargar versión vigente
                </Button>
              )}
            </div>
          )}
        </CardContent>
      </Card>
      {!locked && (
        <div className="flex justify-end">
          <Button disabled={save.isPending || (Boolean(funder) && !form.formState.isDirty)} type="submit">
            {save.isPending ? <LoaderCircle className="size-4 animate-spin" /> : <Save className="size-4" />}
            {funder ? 'Guardar cambios' : 'Crear financiador'}
          </Button>
        </div>
      )}
    </form>
  )
}

export function AdminFundersPage() {
  const [draftQuery, setDraftQuery] = useState('')
  const [query, setQuery] = useState('')
  const [status, setStatus] = useState<PublicationStatus | ''>('')
  const [page, setPage] = useState(1)
  const funders = useQuery({
    queryKey: ['admin-funders', query, status, page],
    queryFn: ({ signal }) => adminFundersApi.list({ query, status: status === '' ? null : status, includeInactive: true, page, pageSize: listPageSize }, signal),
    placeholderData: keepPreviousData,
  })

  function search(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setPage(1)
    setQuery(draftQuery.trim())
  }

  const lastPage = funders.data ? Math.max(1, Math.ceil(funders.data.totalCount / funders.data.pageSize)) : 1

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <p className="text-sm font-bold uppercase tracking-[0.16em] text-primary">Administración</p>
          <h1 className="mt-1 text-3xl font-bold">Financiadores</h1>
          <p className="mt-2 max-w-3xl text-muted-foreground">Normaliza organismos, alias y sitios oficiales antes de asociarlos a convocatorias.</p>
        </div>
        <Button asChild><Link to="/admin/funders/new"><Plus className="size-4" /> Nuevo financiador</Link></Button>
      </div>

      <Card>
        <CardContent className="p-4">
          <form className="grid gap-3 sm:grid-cols-[1fr_14rem_auto]" onSubmit={search}>
            <label className="relative">
              <span className="sr-only">Buscar financiadores</span>
              <Search className="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
              <Input className="pl-9" onChange={(event) => setDraftQuery(event.target.value)} placeholder="Nombre o alias" value={draftQuery} />
            </label>
            <label>
              <span className="sr-only">Filtrar por estado</span>
              <select
                className={inputClass}
                onChange={(event) => { setStatus(event.target.value === '' ? '' : Number(event.target.value) as PublicationStatus); setPage(1) }}
                value={status}
              >
                <option value="">Todos los estados</option>
                {(Object.entries(publicationStatusLabels) as [string, string][]).map(([value, label]) => <option key={value} value={value}>{label}</option>)}
              </select>
            </label>
            <Button type="submit">Buscar</Button>
          </form>
        </CardContent>
      </Card>

      {funders.isPending && <p className="flex items-center gap-2" role="status"><LoaderCircle className="size-5 animate-spin" /> Cargando financiadores…</p>}
      {funders.isError && (
        <Card><CardContent className="space-y-3 p-6" role="alert"><p className="text-destructive">{adminErrorMessage(funders.error)}</p><Button onClick={() => void funders.refetch()} variant="outline">Reintentar</Button></CardContent></Card>
      )}
      {funders.data && (
        <section aria-busy={funders.isFetching} className="space-y-4">
          <p className="text-sm text-muted-foreground"><strong className="text-foreground">{funders.data.totalCount}</strong> financiadores</p>
          {funders.data.items.length === 0 ? (
            <Card><CardContent className="p-10 text-center"><Building2 className="mx-auto size-10 text-primary" /><h2 className="mt-3 text-xl font-bold">No hay financiadores</h2><p className="mt-2 text-muted-foreground">Crea el primero o cambia los filtros.</p></CardContent></Card>
          ) : (
            <div className="grid gap-4 lg:grid-cols-2">
              {funders.data.items.map((funder) => (
                <Card key={funder.funderId}>
                  <CardContent className="space-y-4 p-5">
                    <div className="flex items-start justify-between gap-3">
                      <div><h2 className="text-xl font-bold">{funder.name}</h2><p className="mt-1 text-xs text-muted-foreground">Versión {funder.contentVersion} · {formatAdminDate(funder.updatedAtUtc)}</p></div>
                      <PublicationStatusBadge status={funder.publicationStatus} />
                    </div>
                    <p className="line-clamp-2 text-sm text-muted-foreground">{funder.description ?? 'Sin descripción.'}</p>
                    <div className="flex flex-wrap gap-2">
                      <Button asChild size="sm" variant="outline"><Link to={`/admin/funders/${funder.funderId}`}>Gestionar</Link></Button>
                      {funder.websiteUrl && <Button asChild size="sm" variant="ghost"><a href={funder.websiteUrl} rel="noopener noreferrer" target="_blank">Sitio oficial <ExternalLink className="size-3.5" /></a></Button>}
                    </div>
                  </CardContent>
                </Card>
              ))}
            </div>
          )}
          {funders.data.totalCount > funders.data.pageSize && (
            <nav aria-label="Paginación de financiadores" className="flex items-center justify-end gap-3">
              <Button disabled={page <= 1 || funders.isFetching} onClick={() => setPage((value) => value - 1)} variant="outline"><ChevronLeft className="size-4" />Anterior</Button>
              <p className="text-sm">Página {funders.data.page} de {lastPage}</p>
              <Button disabled={page >= lastPage || funders.isFetching} onClick={() => setPage((value) => value + 1)} variant="outline">Siguiente<ChevronRight className="size-4" /></Button>
            </nav>
          )}
        </section>
      )}
    </div>
  )
}

export function AdminFunderDetailPage() {
  const { id = '' } = useParams()
  const creating = id === 'new'
  const [dirty, setDirty] = useState(false)
  const queryClient = useQueryClient()
  const funder = useQuery({
    queryKey: ['admin-funder', id],
    queryFn: ({ signal }) => adminFundersApi.get(id, signal),
    enabled: Boolean(id) && !creating,
    retry: false,
  })

  if (!creating && funder.isPending) return <p className="flex items-center gap-2" role="status"><LoaderCircle className="size-5 animate-spin" /> Cargando financiador…</p>
  if (!creating && (funder.isError || !funder.data)) return <Card><CardContent className="space-y-4 p-8" role="alert"><h1 className="text-2xl font-bold">No pudimos abrir el financiador</h1><p className="text-destructive">{adminErrorMessage(funder.error)}</p><Button asChild variant="outline"><Link to="/admin/funders">Volver</Link></Button></CardContent></Card>

  const data = funder.data
  return (
    <div className="space-y-6">
      <Button asChild variant="ghost"><Link to="/admin/funders"><ArrowLeft className="size-4" /> Volver a financiadores</Link></Button>
      <div>
        <p className="text-sm font-bold uppercase tracking-[0.16em] text-primary">Administración</p>
        <div className="mt-1 flex flex-wrap items-center gap-3">
          <h1 className="text-3xl font-bold">{creating ? 'Crear financiador' : data!.name}</h1>
          {data && <PublicationStatusBadge status={data.publicationStatus} />}
        </div>
        {data && <p className="mt-2 text-sm text-muted-foreground">Versión {data.contentVersion} · actualizado {formatAdminDate(data.updatedAtUtc)}</p>}
      </div>
      {data && (
        <EditorialWorkflowPanel
          commands={adminFundersApi}
          disabledReason={dirty ? 'Guarda o descarta los cambios del formulario antes de ejecutar una acción editorial.' : undefined}
          eTag={data.eTag}
          entityId={data.funderId}
          entityName="el financiador"
          onChanged={async () => {
            await queryClient.invalidateQueries({ queryKey: ['admin-funders'] })
            await funder.refetch()
          }}
          publicationStatus={data.publicationStatus}
          rejectionReason={data.rejectionReason}
        />
      )}
      <AdminFunderForm funder={data} onDirtyChange={setDirty} />
    </div>
  )
}
