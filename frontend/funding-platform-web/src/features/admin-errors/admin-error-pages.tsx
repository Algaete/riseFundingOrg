import { keepPreviousData, useQuery } from '@tanstack/react-query'
import { CircleAlert, FileWarning, LoaderCircle, RefreshCw, Search } from 'lucide-react'
import { type FormEvent, useEffect, useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'

import { ApiError } from '@/api/http-client'
import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import {
  adminErrorsApi,
  type AdminOperationalError,
  type OperationalErrorCategory,
} from '@/features/admin-errors/admin-errors-api'

const categoryLabels: Record<OperationalErrorCategory, string> = {
  import: 'Importación', extraction: 'Extracción', semantic: 'Semántica',
  explanation: 'Explicación asistida', payment: 'Pago',
}
const categories = Object.keys(categoryLabels) as OperationalErrorCategory[]
const selectClass = 'h-10 rounded-lg border bg-background px-3 text-sm'

function positiveInteger(value: string | null, fallback: number) {
  const parsed = Number(value)
  return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : fallback
}
function formatDate(value: string) {
  return new Intl.DateTimeFormat('es-CL', { dateStyle: 'medium', timeStyle: 'short' })
    .format(new Date(value))
}
function message(error: unknown) {
  return error instanceof ApiError
    ? error.problem.detail ?? error.problem.title
    : 'No fue posible consultar los incidentes operacionales.'
}
function relatedPath(item: AdminOperationalError) {
  if (!item.relatedResourcePublicId) return null
  if (item.category === 'import') return `/admin/imports/${item.relatedResourcePublicId}`
  if (item.category === 'extraction') return `/admin/source-documents/${item.relatedResourcePublicId}`
  return null
}

export function AdminErrorsWorkspacePage() {
  const [searchParams, setSearchParams] = useSearchParams()
  const query = searchParams.get('q')?.trim() ?? ''
  const categoryText = searchParams.get('category')
  const category = categories.includes(categoryText as OperationalErrorCategory)
    ? categoryText as OperationalErrorCategory : undefined
  const retryableText = searchParams.get('retryable')
  const retryable = retryableText === 'true' ? true : retryableText === 'false' ? false : undefined
  const page = positiveInteger(searchParams.get('page'), 1)
  const pageSize = 25
  const [draft, setDraft] = useState(query)
  useEffect(() => setDraft(query), [query])

  const errors = useQuery({
    queryKey: ['admin-operational-errors', query, category, retryable, page, pageSize],
    queryFn: ({ signal }) => adminErrorsApi.list({
      q: query || undefined, category, retryable, page, pageSize,
    }, signal),
    placeholderData: keepPreviousData,
  })
  function replace(name: string, value?: string, resetPage = true) {
    const next = new URLSearchParams(searchParams)
    if (!value) next.delete(name)
    else next.set(name, value)
    if (resetPage) next.delete('page')
    setSearchParams(next, { replace: true })
  }
  function submit(event: FormEvent) {
    event.preventDefault()
    replace('q', draft.trim())
  }
  const lastPage = errors.data ? Math.max(1, Math.ceil(errors.data.totalCount / errors.data.pageSize)) : 1

  return <div className="space-y-6">
    <header className="flex flex-wrap items-end justify-between gap-4"><div><p className="text-sm font-bold uppercase tracking-[0.16em] text-primary">Administración</p><h1 className="mt-1 text-3xl font-bold">Errores operacionales</h1><p className="mt-2 max-w-3xl text-muted-foreground">Vista sanitizada de fallos de ingesta, extracción, procesos asistidos y pagos.</p></div>{errors.data && <p className="rounded-full bg-muted px-3 py-1 text-sm"><strong>{errors.data.totalCount}</strong> incidentes</p>}</header>

    <Card><CardContent className="grid gap-3 p-4 lg:grid-cols-[minmax(16rem,1fr)_auto_auto]">
      <form className="flex gap-2" onSubmit={submit}><Input aria-label="Buscar errores" maxLength={200} onChange={event => setDraft(event.target.value)} placeholder="Código, mensaje o fuente" value={draft} /><Button type="submit" variant="outline"><Search className="size-4" />Buscar</Button></form>
      <label className="grid gap-1 text-xs font-semibold">Origen<select className={selectClass} onChange={event => replace('category', event.target.value)} value={category ?? ''}><option value="">Todos</option>{categories.map(value => <option key={value} value={value}>{categoryLabels[value]}</option>)}</select></label>
      <label className="grid gap-1 text-xs font-semibold">Reintento<select className={selectClass} onChange={event => replace('retryable', event.target.value)} value={retryableText ?? ''}><option value="">Todos</option><option value="true">Reintentables</option><option value="false">Permanentes</option></select></label>
    </CardContent></Card>

    {errors.isPending && <Card><CardContent className="flex items-center gap-2 p-8" role="status"><LoaderCircle className="size-5 animate-spin" />Cargando incidentes…</CardContent></Card>}
    {errors.isError && <Card className="border-destructive/40"><CardContent className="space-y-3 p-8" role="alert"><CircleAlert className="size-8 text-destructive" /><h2 className="text-xl font-bold">No pudimos cargar los incidentes</h2><p className="text-sm text-muted-foreground">{message(errors.error)}</p><Button onClick={() => void errors.refetch()} variant="outline">Reintentar</Button></CardContent></Card>}
    {errors.data?.items.length === 0 && <Card><CardContent className="space-y-3 p-10 text-center"><FileWarning className="mx-auto size-9 text-muted-foreground" /><h2 className="text-xl font-bold">No hay incidentes con estos filtros</h2><p className="text-sm text-muted-foreground">Esta vista sólo muestra información sanitizada; nunca payloads ni credenciales.</p><Button onClick={() => { setDraft(''); setSearchParams({}, { replace: true }) }} variant="outline">Limpiar filtros</Button></CardContent></Card>}

    {errors.data && errors.data.items.length > 0 && <div className="space-y-3">{errors.data.items.map(item => {
      const path = relatedPath(item)
      return <Card className={item.severity >= 2 ? 'border-destructive/35' : ''} key={item.id}><CardContent className="flex flex-col gap-4 p-5 lg:flex-row lg:items-start lg:justify-between"><div className="min-w-0 space-y-2"><div className="flex flex-wrap items-center gap-2"><span className="rounded-full bg-muted px-2.5 py-1 text-xs font-semibold">{categoryLabels[item.category]}</span><span className={item.severity >= 2 ? 'text-sm font-semibold text-destructive' : 'text-sm font-semibold text-amber-700 dark:text-amber-300'}>{item.severity >= 2 ? 'Fallo permanente' : 'Advertencia'}</span>{item.isRetryable && <span className="inline-flex items-center gap-1 text-xs text-muted-foreground"><RefreshCw className="size-3" />Reintentable</span>}</div><p className="font-mono text-sm font-semibold">{item.code}</p><p className="text-sm text-muted-foreground">{item.message}</p><p className="text-xs text-muted-foreground">{item.sourceName ?? 'Origen no informado'} · {formatDate(item.occurredAtUtc)}</p></div>{path && <Button asChild className="shrink-0" size="sm" variant="outline"><Link to={path}>Abrir contexto</Link></Button>}</CardContent></Card>
    })}</div>}

    {errors.data && lastPage > 1 && <nav aria-label="Paginación de errores" className="flex items-center justify-end gap-3 rounded-xl border bg-card p-3"><Button disabled={page <= 1 || errors.isFetching} onClick={() => replace('page', String(page - 1), false)} variant="outline">Anterior</Button><p className="text-sm text-muted-foreground">Página {page} de {lastPage}</p><Button disabled={page >= lastPage || errors.isFetching} onClick={() => replace('page', String(page + 1), false)} variant="outline">Siguiente</Button></nav>}
  </div>
}
