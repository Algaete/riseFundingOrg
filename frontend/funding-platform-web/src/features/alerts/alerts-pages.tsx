import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Bell, BellOff, ExternalLink, LoaderCircle, Save, Trash2 } from 'lucide-react'
import { type FormEvent, useMemo, useRef, useState } from 'react'
import { Link, useLocation, useNavigate, useSearchParams } from 'react-router-dom'

import { ApiError } from '@/api/http-client'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { organizationApi } from '@/features/organizations/organization-api'
import { serializeFundingSearch, type FundingSort } from '@/features/funding/organization-funding-api'
import {
  alertsApi,
  toFundingSearch,
  type SavedSearchWrite,
} from '@/features/alerts/alerts-api'

function parseIds(value: string | null) {
  if (!value) return []
  return [...new Set(value.split(',').map(Number).filter((id) => Number.isSafeInteger(id) && id > 0))]
}

function parseGuids(value: string | null) {
  return value?.split(',').map((item) => item.trim()).filter(Boolean) ?? []
}

function parseAmount(value: string | null) {
  if (!value) return null
  const parsed = Number(value)
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : null
}

function draftFromQuery(parameters: URLSearchParams, name: string): SavedSearchWrite {
  const query = parameters.get('q')?.trim() || null
  const sortText = parameters.get('sort')
  const allowed: FundingSort[] = ['relevance', 'closing-soon', 'newest', 'amount-asc', 'amount-desc']
  const sort = allowed.includes(sortText as FundingSort)
    ? sortText as FundingSort
    : query ? 'relevance' : 'closing-soon'
  return {
    name,
    query,
    sponsor: parameters.get('sponsor')?.trim() || null,
    minimumAmount: parseAmount(parameters.get('minAmount')),
    maximumAmount: parseAmount(parameters.get('maxAmount')),
    currency: parameters.get('currency')?.trim().toUpperCase() || null,
    closingFrom: parameters.get('closingFrom'),
    closingTo: parameters.get('closingTo'),
    onlyOpen: parameters.get('onlyOpen') !== 'false',
    sort,
    countryIds: parseIds(parameters.get('countryIds')),
    regionIds: parseIds(parameters.get('regionIds')),
    categoryIds: parseIds(parameters.get('categoryIds')),
    tagIds: parseIds(parameters.get('tagIds')),
    beneficiaryTypeIds: parseIds(parameters.get('beneficiaryTypeIds')),
    projectTypeIds: parseIds(parameters.get('projectTypeIds')),
    fundingTypeIds: parseIds(parameters.get('fundingTypeIds')),
    organizationTypeIds: parseIds(parameters.get('organizationTypeIds')),
    funderIds: parseGuids(parameters.get('funderIds')),
  }
}

function message(error: unknown) {
  if (error instanceof ApiError) {
    return Object.values(error.problem.errors ?? {}).flat()[0]
      ?? error.problem.detail ?? error.problem.title
  }
  return 'No fue posible completar la operación.'
}

function formatDate(value: string | null) {
  if (!value) return '—'
  return new Intl.DateTimeFormat('es-CL', { dateStyle: 'medium', timeStyle: 'short' })
    .format(new Date(value))
}

export function AlertsWorkspacePage() {
  const [searchParams, setSearchParams] = useSearchParams()
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const organizations = useQuery({
    queryKey: ['organizations'],
    queryFn: ({ signal }) => organizationApi.list(signal),
  })
  const organization = organizations.data?.[0]
  const searches = useQuery({
    queryKey: ['saved-searches', organization?.publicId],
    queryFn: ({ signal }) => alertsApi.list(organization!.publicId, 1, 50, signal),
    enabled: Boolean(organization),
  })
  const notifications = useQuery({
    queryKey: ['notification-logs', organization?.publicId],
    queryFn: ({ signal }) => alertsApi.notifications(organization!.publicId, 1, 20, signal),
    enabled: Boolean(organization),
  })
  const [name, setName] = useState('')
  const [enableAlert, setEnableAlert] = useState(true)
  const [hour, setHour] = useState(8)
  const [feedback, setFeedback] = useState<string | null>(null)
  const idempotencyKey = useRef<string | null>(null)
  const creating = searchParams.get('new') === 'true'
  const draft = useMemo(() => draftFromQuery(searchParams, name), [searchParams, name])

  const create = useMutation({
    mutationFn: async () => {
      const key = idempotencyKey.current ??= `saved-search-${crypto.randomUUID()}`
      const saved = await alertsApi.create(organization!.publicId, draft, key)
      if (enableAlert) {
        const timeZone = Intl.DateTimeFormat().resolvedOptions().timeZone
        try {
          await alertsApi.putAlert(organization!.publicId, saved.id, hour, timeZone)
        } catch (error) {
          return {
            saved,
            alertWarning: error instanceof ApiError && error.response.status === 503
              ? 'La búsqueda quedó guardada; el envío de correo aún no está habilitado en este ambiente.'
              : 'La búsqueda quedó guardada, pero no pudimos confirmar la activación del correo. Revisa su estado antes de reintentar.',
          }
        }
      }
      return { saved, alertWarning: null }
    },
    onSuccess: async ({ alertWarning }) => {
      idempotencyKey.current = null
      await queryClient.invalidateQueries({ queryKey: ['saved-searches', organization?.publicId] })
      setFeedback(alertWarning ?? 'Búsqueda y alerta guardadas correctamente.')
      setSearchParams({}, { replace: true })
      setName('')
    },
    onError: (error) => {
      if (error instanceof ApiError) idempotencyKey.current = null
      setFeedback(message(error))
    },
  })
  const remove = useMutation({
    mutationFn: ({ id, eTag }: { id: string; eTag: string }) =>
      alertsApi.remove(organization!.publicId, id, eTag),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ['saved-searches', organization?.publicId] })
      setFeedback('Búsqueda eliminada y alerta desactivada.')
    },
    onError: (error) => setFeedback(message(error)),
  })
  const toggle = useMutation({
    mutationFn: async ({ id, active }: { id: string; active: boolean }) => {
      if (active) return alertsApi.deleteAlert(organization!.publicId, id)
      return alertsApi.putAlert(
        organization!.publicId,
        id,
        8,
        Intl.DateTimeFormat().resolvedOptions().timeZone,
      )
    },
    onSuccess: async (_, variables) => {
      await queryClient.invalidateQueries({ queryKey: ['saved-searches', organization?.publicId] })
      setFeedback(variables.active ? 'Alerta desactivada.' : 'Alerta diaria activada a las 08:00.')
    },
    onError: (error) => setFeedback(message(error)),
  })
  const open = useMutation({
    mutationFn: (id: string) => alertsApi.get(organization!.publicId, id),
    onSuccess: (saved) => navigate(`/opportunities?${serializeFundingSearch(toFundingSearch(saved.filters))}`),
    onError: (error) => setFeedback(message(error)),
  })

  function submit(event: FormEvent) {
    event.preventDefault()
    setFeedback(null)
    create.mutate()
  }

  if (organizations.isPending) return <p role="status">Cargando organización…</p>
  if (!organization) return <Card><CardContent className="p-8 text-center"><h1 className="text-2xl font-bold">Primero crea tu organización</h1><Button asChild className="mt-4"><Link to="/onboarding">Comenzar</Link></Button></CardContent></Card>

  return (
    <div className="space-y-6">
      <header><p className="text-sm font-bold uppercase tracking-[0.16em] text-primary">Seguimiento</p><h1 className="mt-1 text-3xl font-bold">Búsquedas y alertas</h1><p className="mt-2 text-muted-foreground">Guarda filtros privados y recibe un solo resumen diario con oportunidades nuevas. Una alerta no confirma elegibilidad.</p></header>
      {feedback && <p className="rounded-lg bg-accent p-3 text-sm" role="status">{feedback}</p>}
      {creating && <Card><CardHeader><CardTitle>Guardar la búsqueda actual</CardTitle></CardHeader><CardContent><form className="grid gap-4" onSubmit={submit}><label className="grid gap-1 text-sm font-semibold">Nombre<input autoFocus className="h-10 rounded-lg border bg-background px-3" maxLength={150} onChange={(event) => setName(event.target.value)} required value={name} /></label><label className="flex items-center gap-2 text-sm"><input checked={enableAlert} onChange={(event) => setEnableAlert(event.target.checked)} type="checkbox" />Activar resumen diario por correo</label>{enableAlert && <label className="grid max-w-xs gap-1 text-sm font-semibold">Hora local<select className="h-10 rounded-lg border bg-background px-3" onChange={(event) => setHour(Number(event.target.value))} value={hour}>{Array.from({ length: 24 }, (_, value) => <option key={value} value={value}>{String(value).padStart(2, '0')}:00</option>)}</select></label>}<div className="flex gap-2"><Button disabled={create.isPending || !name.trim()} type="submit">{create.isPending ? <LoaderCircle className="size-4 animate-spin" /> : <Save className="size-4" />}Guardar</Button><Button onClick={() => setSearchParams({}, { replace: true })} type="button" variant="outline">Cancelar</Button></div></form></CardContent></Card>}
      <section className="space-y-3"><div className="flex items-center justify-between gap-3"><h2 className="text-xl font-bold">Búsquedas guardadas</h2><Button asChild variant="outline"><Link to="/opportunities">Crear desde el catálogo</Link></Button></div>{searches.isPending && <p role="status">Cargando búsquedas…</p>}{searches.isError && <p className="text-destructive" role="alert">{message(searches.error)}</p>}{searches.data?.items.length === 0 && <Card><CardContent className="p-8 text-center"><Bell className="mx-auto size-8 text-muted-foreground" /><p className="mt-3 font-semibold">Todavía no guardas búsquedas</p><p className="mt-1 text-sm text-muted-foreground">Aplica filtros en Concursos disponibles y selecciona Guardar búsqueda.</p></CardContent></Card>}<div className="grid gap-3 lg:grid-cols-2">{searches.data?.items.map((item) => <Card key={item.id}><CardContent className="space-y-3 p-5"><div className="flex items-start justify-between gap-3"><div><h3 className="font-bold">{item.name}</h3><p className="text-sm text-muted-foreground">{item.query ? `Texto: ${item.query}` : 'Todos los fondos según filtros'}</p></div><span className="rounded-full bg-muted px-2 py-1 text-xs">{item.hasActiveAlert ? 'Alerta activa' : 'Sin alerta'}</span></div><div className="flex flex-wrap gap-2"><Button disabled={open.isPending} onClick={() => open.mutate(item.id)} size="sm"><ExternalLink className="size-4" />Abrir</Button><Button disabled={toggle.isPending} onClick={() => toggle.mutate({ id: item.id, active: item.hasActiveAlert })} size="sm" variant="outline">{item.hasActiveAlert ? <BellOff className="size-4" /> : <Bell className="size-4" />}{item.hasActiveAlert ? 'Desactivar' : 'Activar alerta'}</Button><Button aria-label={`Eliminar ${item.name}`} disabled={remove.isPending} onClick={() => remove.mutate({ id: item.id, eTag: item.eTag })} size="sm" variant="ghost"><Trash2 className="size-4" />Eliminar</Button></div></CardContent></Card>)}</div></section>
      <section className="space-y-3"><h2 className="text-xl font-bold">Historial de notificaciones</h2>{notifications.isPending && <p role="status">Cargando historial…</p>}{notifications.isError && <p className="text-destructive" role="alert">{message(notifications.error)}</p>}{notifications.data?.items.length === 0 && <p className="text-sm text-muted-foreground">Aún no se han generado resúmenes.</p>}<div className="space-y-2">{notifications.data?.items.map((item) => <Card key={item.id}><CardContent className="flex flex-wrap items-center justify-between gap-3 p-4"><div><p className="font-semibold">{item.savedSearchName ?? 'Búsqueda eliminada'}</p><p className="text-sm text-muted-foreground">{item.itemCount} oportunidades · programada {formatDate(item.scheduledForUtc)}{item.wasTruncated ? ' · resumen limitado a 50' : ''}</p></div><span className="rounded-full bg-muted px-2 py-1 text-xs">{item.status}</span></CardContent></Card>)}</div></section>
    </div>
  )
}

export function AlertUnsubscribePage() {
  const location = useLocation()
  const token = new URLSearchParams(location.hash.slice(1)).get('token') ?? ''
  const unsubscribe = useMutation({
    mutationFn: () => alertsApi.unsubscribe(token),
  })
  return <div className="mx-auto max-w-lg py-16"><Card><CardContent className="space-y-4 p-8 text-center"><BellOff className="mx-auto size-10 text-primary" /><h1 className="text-2xl font-bold">Desactivar alerta</h1>{!token && <p role="alert">El enlace está incompleto.</p>}{token && !unsubscribe.isSuccess && <p>Confirma que quieres dejar de recibir este resumen diario.</p>}{token && unsubscribe.isSuccess && <p>La alerta quedó desactivada. Puedes volver a activarla desde tu cuenta.</p>}{token && unsubscribe.isError && <p role="alert">No pudimos procesar el enlace.</p>}{token && !unsubscribe.isSuccess && <Button disabled={unsubscribe.isPending} onClick={() => unsubscribe.mutate()}>{unsubscribe.isPending ? <LoaderCircle className="size-4 animate-spin" /> : <BellOff className="size-4" />}{unsubscribe.isError ? 'Reintentar' : 'Confirmar baja'}</Button>}<Button asChild variant="outline"><Link to="/">Volver al inicio</Link></Button></CardContent></Card></div>
}
