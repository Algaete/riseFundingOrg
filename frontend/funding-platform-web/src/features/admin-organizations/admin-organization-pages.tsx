import { keepPreviousData, useQuery } from '@tanstack/react-query'
import {
  ArrowLeft, Building2, CircleAlert, ExternalLink, FolderKanban, LoaderCircle,
  Search, ShieldCheck, Users, type LucideIcon,
} from 'lucide-react'
import { type FormEvent, useEffect, useState } from 'react'
import { Link, useParams, useSearchParams } from 'react-router-dom'

import { ApiError } from '@/api/http-client'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import {
  adminOrganizationsApi,
  type AdminOrganizationDetail,
} from '@/features/admin-organizations/admin-organizations-api'

const profileNames = ['Sin completar', 'En progreso', 'Listo para publicar']
const selectClass = 'h-10 rounded-lg border bg-background px-3 text-sm'

function positiveInteger(value: string | null, fallback: number) {
  const parsed = Number(value)
  return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : fallback
}

function formatDate(value: string | null) {
  return value ? new Intl.DateTimeFormat('es-CL', {
    dateStyle: 'medium', timeStyle: 'short',
  }).format(new Date(value)) : 'Sin fecha'
}

function errorMessage(error: unknown) {
  return error instanceof ApiError
    ? error.problem.detail ?? error.problem.title
    : 'No fue posible consultar las organizaciones.'
}

function ProfileBadge({ status }: { status: number }) {
  return <span className="rounded-full bg-accent px-2.5 py-1 text-xs font-semibold text-accent-foreground">
    {profileNames[status] ?? 'Estado desconocido'}
  </span>
}

export function AdminOrganizationsWorkspacePage() {
  const [searchParams, setSearchParams] = useSearchParams()
  const query = searchParams.get('q')?.trim() ?? ''
  const statusText = searchParams.get('profileStatus')
  const profileStatus = statusText !== null && /^[0-2]$/.test(statusText)
    ? Number(statusText) : undefined
  const activeText = searchParams.get('isActive')
  const isActive = activeText === 'true' ? true : activeText === 'false' ? false : undefined
  const page = positiveInteger(searchParams.get('page'), 1)
  const pageSize = 25
  const [draft, setDraft] = useState(query)
  useEffect(() => setDraft(query), [query])

  const organizations = useQuery({
    queryKey: ['admin-organizations', query, profileStatus, isActive, page, pageSize],
    queryFn: ({ signal }) => adminOrganizationsApi.list({
      q: query || undefined, profileStatus, isActive, page, pageSize,
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
  const lastPage = organizations.data
    ? Math.max(1, Math.ceil(organizations.data.totalCount / organizations.data.pageSize)) : 1

  return <div className="space-y-6">
    <header className="flex flex-wrap items-end justify-between gap-4">
      <div><p className="text-sm font-bold uppercase tracking-[0.16em] text-primary">Administración</p><h1 className="mt-1 text-3xl font-bold">Organizaciones</h1><p className="mt-2 text-muted-foreground">Consulta perfiles institucionales, actividad y plan vigente.</p></div>
      {organizations.data && <p className="rounded-full bg-muted px-3 py-1 text-sm"><strong>{organizations.data.totalCount}</strong> organizaciones</p>}
    </header>

    <Card><CardContent className="grid gap-3 p-4 lg:grid-cols-[minmax(16rem,1fr)_auto_auto]">
      <form className="flex gap-2" onSubmit={submit}><Input aria-label="Buscar organizaciones" maxLength={200} onChange={event => setDraft(event.target.value)} placeholder="Nombre o identificador" value={draft} /><Button type="submit" variant="outline"><Search className="size-4" />Buscar</Button></form>
      <label className="grid gap-1 text-xs font-semibold">Estado del perfil<select className={selectClass} onChange={event => replace('profileStatus', event.target.value)} value={profileStatus ?? ''}><option value="">Todos</option>{profileNames.map((label, value) => <option key={label} value={value}>{label}</option>)}</select></label>
      <label className="grid gap-1 text-xs font-semibold">Acceso<select className={selectClass} onChange={event => replace('isActive', event.target.value)} value={activeText ?? ''}><option value="">Todas</option><option value="true">Activas</option><option value="false">Inactivas</option></select></label>
    </CardContent></Card>

    {organizations.isPending && <Card><CardContent className="flex items-center gap-2 p-8" role="status"><LoaderCircle className="size-5 animate-spin" />Cargando organizaciones…</CardContent></Card>}
    {organizations.isError && <Card className="border-destructive/40"><CardContent className="space-y-3 p-8" role="alert"><CircleAlert className="size-8 text-destructive" /><h2 className="text-xl font-bold">No pudimos cargar las organizaciones</h2><p className="text-sm text-muted-foreground">{errorMessage(organizations.error)}</p><Button onClick={() => void organizations.refetch()} variant="outline">Reintentar</Button></CardContent></Card>}
    {organizations.data?.items.length === 0 && <Card><CardContent className="space-y-3 p-10 text-center"><Building2 className="mx-auto size-9 text-muted-foreground" /><h2 className="text-xl font-bold">No hay organizaciones con estos filtros</h2><Button onClick={() => { setDraft(''); setSearchParams({}, { replace: true }) }} variant="outline">Limpiar filtros</Button></CardContent></Card>}

    {organizations.data && organizations.data.items.length > 0 && <Card><CardContent className="overflow-x-auto p-0"><table className="w-full min-w-[920px] text-left text-sm"><thead className="border-b bg-muted/60 text-xs uppercase tracking-wide text-muted-foreground"><tr><th className="px-4 py-3">Organización</th><th className="px-4 py-3">Perfil</th><th className="px-4 py-3">Actividad</th><th className="px-4 py-3">Plan</th><th className="px-4 py-3">Actualización</th><th className="px-4 py-3"><span className="sr-only">Acción</span></th></tr></thead><tbody className="divide-y">{organizations.data.items.map(item => <tr key={item.publicId}><td className="px-4 py-4"><p className="font-semibold">{item.name}</p><p className="text-muted-foreground">{item.organizationTypeName} · {item.countryName}</p><p className="mt-1 font-mono text-xs text-muted-foreground">{item.publicId}</p></td><td className="px-4 py-4"><ProfileBadge status={item.profileStatus} /><p className="mt-2 text-xs text-muted-foreground">{item.profileCompleteness}% completo · {item.isActive ? 'Activa' : 'Inactiva'}</p></td><td className="px-4 py-4"><p>{item.memberCount} miembros</p><p className="text-xs text-muted-foreground">{item.projectCount} proyectos</p></td><td className="px-4 py-4"><p className="font-semibold">{item.planName}</p><p className="text-xs text-muted-foreground">{item.planCode}</p></td><td className="px-4 py-4 text-muted-foreground">{formatDate(item.updatedAtUtc)}</td><td className="px-4 py-4"><Button asChild size="sm" variant="outline"><Link to={`/admin/organizations/${item.publicId}`}>Ver detalle</Link></Button></td></tr>)}</tbody></table></CardContent></Card>}

    {organizations.data && lastPage > 1 && <nav aria-label="Paginación de organizaciones" className="flex items-center justify-end gap-3 rounded-xl border bg-card p-3"><Button disabled={page <= 1 || organizations.isFetching} onClick={() => replace('page', String(page - 1), false)} variant="outline">Anterior</Button><p className="text-sm text-muted-foreground">Página {page} de {lastPage}</p><Button disabled={page >= lastPage || organizations.isFetching} onClick={() => replace('page', String(page + 1), false)} variant="outline">Siguiente</Button></nav>}
  </div>
}

function SummaryCard({ item }: { item: AdminOrganizationDetail }) {
  const metrics: { label: string; value: number; icon: LucideIcon }[] = [
    { label: 'Miembros', value: item.memberCount, icon: Users },
    { label: 'Administradores', value: item.adminMemberCount, icon: ShieldCheck },
    { label: 'Proyectos', value: item.projectCount, icon: FolderKanban },
    { label: 'Publicados', value: item.publishedProjectCount, icon: ExternalLink },
  ]
  return <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
    {metrics.map(({ label, value, icon: Icon }) => <Card key={label}><CardContent className="flex items-center justify-between p-5"><div><p className="text-sm text-muted-foreground">{label}</p><p className="mt-1 text-2xl font-bold">{value}</p></div><Icon className="size-5 text-primary" /></CardContent></Card>)}
  </div>
}

export function AdminOrganizationDetailPage() {
  const { organizationId } = useParams()
  const organization = useQuery({
    queryKey: ['admin-organization', organizationId],
    queryFn: ({ signal }) => adminOrganizationsApi.get(organizationId!, signal),
    enabled: Boolean(organizationId),
  })
  if (organization.isPending) return <Card><CardContent className="flex items-center gap-2 p-8" role="status"><LoaderCircle className="size-5 animate-spin" />Cargando organización…</CardContent></Card>
  if (organization.isError) return <div className="space-y-4"><Button asChild variant="ghost"><Link to="/admin/organizations"><ArrowLeft className="size-4" />Volver</Link></Button><Card className="border-destructive/40"><CardContent className="space-y-3 p-8" role="alert"><CircleAlert className="size-8 text-destructive" /><h1 className="text-xl font-bold">No pudimos cargar la organización</h1><p>{errorMessage(organization.error)}</p><Button onClick={() => void organization.refetch()} variant="outline">Reintentar</Button></CardContent></Card></div>
  const item = organization.data!
  return <div className="space-y-6"><Button asChild variant="ghost"><Link to="/admin/organizations"><ArrowLeft className="size-4" />Volver a organizaciones</Link></Button><header><p className="text-sm font-bold uppercase tracking-[0.16em] text-primary">Administración</p><div className="mt-1 flex flex-wrap items-center gap-3"><h1 className="text-3xl font-bold">{item.name}</h1><ProfileBadge status={item.profileStatus} /></div><p className="mt-2 text-muted-foreground">{item.organizationTypeName} · {item.countryName} · perfil {item.profileCompleteness}% completo</p></header><SummaryCard item={item} /><div className="grid gap-6 lg:grid-cols-2"><Card><CardHeader><CardTitle>Perfil institucional</CardTitle></CardHeader><CardContent><dl className="grid gap-4 text-sm sm:grid-cols-2"><div><dt className="text-muted-foreground">Razón legal</dt><dd className="font-semibold">{item.legalName ?? 'Sin informar'}</dd></div><div><dt className="text-muted-foreground">Entidad jurídica</dt><dd className="font-semibold">{item.legalEntityTypeName ?? 'Sin informar'}</dd></div><div><dt className="text-muted-foreground">Tamaño</dt><dd className="font-semibold">{item.organizationSizeName ?? 'Sin informar'}</dd></div><div><dt className="text-muted-foreground">Año de fundación</dt><dd className="font-semibold">{item.establishedYear ?? 'Sin informar'}</dd></div><div className="sm:col-span-2"><dt className="text-muted-foreground">Descripción</dt><dd className="mt-1 whitespace-pre-line">{item.description ?? 'Sin descripción.'}</dd></div>{item.websiteUrl && <div className="sm:col-span-2"><dt className="text-muted-foreground">Sitio web</dt><dd><a className="font-semibold text-primary underline" href={item.websiteUrl} rel="noreferrer" target="_blank">Abrir sitio <ExternalLink className="inline size-3.5" /></a></dd></div>}</dl></CardContent></Card><Card><CardHeader><CardTitle>Acceso y suscripción</CardTitle></CardHeader><CardContent><dl className="grid gap-4 text-sm"><div><dt className="text-muted-foreground">Estado</dt><dd className="font-semibold">{item.isActive ? 'Organización activa' : 'Organización inactiva'}</dd></div><div><dt className="text-muted-foreground">Plan observado</dt><dd className="font-semibold">{item.planName} ({item.planCode})</dd></div><div><dt className="text-muted-foreground">Fin del período</dt><dd className="font-semibold">{formatDate(item.currentPeriodEndUtc)}</dd></div><div><dt className="text-muted-foreground">Versión del perfil</dt><dd className="font-semibold">{item.profileVersion}</dd></div><div><dt className="text-muted-foreground">Creada</dt><dd className="font-semibold">{formatDate(item.createdAtUtc)}</dd></div><div><dt className="text-muted-foreground">Última actualización</dt><dd className="font-semibold">{formatDate(item.updatedAtUtc)}</dd></div></dl></CardContent></Card></div></div>
}
