import { keepPreviousData, useQuery } from '@tanstack/react-query'
import { CircleAlert, LoaderCircle, Search, ShieldCheck, Users } from 'lucide-react'
import { type FormEvent, useEffect, useState } from 'react'
import { useSearchParams } from 'react-router-dom'

import { ApiError } from '@/api/http-client'
import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { adminUsersApi, type AdminUserStatus } from '@/features/admin-users/admin-users-api'

const statusNames: Record<AdminUserStatus, string> = {
  PendingActivation: 'Pendiente de activación',
  PendingVerification: 'Pendiente de verificación',
  Active: 'Activa',
  Blocked: 'Bloqueada',
  Disabled: 'Deshabilitada',
}

const statusOptions = [
  { value: 0, label: statusNames.PendingActivation },
  { value: 1, label: statusNames.PendingVerification },
  { value: 2, label: statusNames.Active },
  { value: 3, label: statusNames.Blocked },
  { value: 4, label: statusNames.Disabled },
]

const selectClass = 'h-10 rounded-lg border bg-background px-3 text-sm'

function positiveInteger(value: string | null, fallback: number) {
  const parsed = Number(value)
  return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : fallback
}

function formatDate(value: string | null) {
  if (!value) return 'Nunca'
  return new Intl.DateTimeFormat('es-CL', {
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(new Date(value))
}

function message(error: unknown) {
  if (error instanceof ApiError) {
    return error.problem.detail ?? error.problem.title
  }
  return 'No fue posible cargar los usuarios. Comprueba la conexión e intenta nuevamente.'
}

export function AdminUsersWorkspacePage() {
  const [searchParams, setSearchParams] = useSearchParams()
  const query = searchParams.get('q')?.trim() ?? ''
  const statusText = searchParams.get('status')
  const status = statusText !== null && /^[0-4]$/.test(statusText)
    ? Number(statusText)
    : undefined
  const role = searchParams.get('role')?.trim() ?? ''
  const page = positiveInteger(searchParams.get('page'), 1)
  const pageSize = 25
  const [draft, setDraft] = useState(query)

  useEffect(() => setDraft(query), [query])

  const users = useQuery({
    queryKey: ['admin-users', query, status, role, page, pageSize],
    queryFn: ({ signal }) => adminUsersApi.list({
      q: query || undefined,
      status,
      role: role || undefined,
      page,
      pageSize,
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

  const lastPage = users.data
    ? Math.max(1, Math.ceil(users.data.totalCount / users.data.pageSize))
    : 1

  return <div className="space-y-6">
    <header className="flex flex-wrap items-end justify-between gap-4">
      <div>
        <p className="text-sm font-bold uppercase tracking-[0.16em] text-primary">Administración</p>
        <h1 className="mt-1 text-3xl font-bold">Usuarios</h1>
        <p className="mt-2 text-muted-foreground">Consulta cuentas, estado de acceso, roles globales y seguridad.</p>
      </div>
      {users.data && <p className="rounded-full bg-muted px-3 py-1 text-sm"><strong>{users.data.totalCount}</strong> cuentas</p>}
    </header>

    <Card>
      <CardContent className="grid gap-3 p-4 lg:grid-cols-[minmax(16rem,1fr)_auto_auto]">
        <form className="flex gap-2" onSubmit={submit}>
          <Input aria-label="Buscar usuarios" maxLength={200} onChange={(event) => setDraft(event.target.value)} placeholder="Nombre o correo" value={draft} />
          <Button type="submit" variant="outline"><Search className="size-4" />Buscar</Button>
        </form>
        <label className="grid gap-1 text-xs font-semibold">Estado
          <select className={selectClass} onChange={(event) => replace('status', event.target.value)} value={status ?? ''}>
            <option value="">Todos</option>
            {statusOptions.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}
          </select>
        </label>
        <label className="grid gap-1 text-xs font-semibold">Rol global
          <select className={selectClass} onChange={(event) => replace('role', event.target.value)} value={role}>
            <option value="">Todos</option>
            <option value="Admin">Admin</option>
            <option value="SuperAdmin">SuperAdmin</option>
          </select>
        </label>
      </CardContent>
    </Card>

    {users.isPending && <Card><CardContent className="flex items-center gap-2 p-8" role="status"><LoaderCircle className="size-5 animate-spin" />Cargando usuarios…</CardContent></Card>}
    {users.isError && <Card className="border-destructive/40"><CardContent className="space-y-3 p-8" role="alert"><CircleAlert className="size-8 text-destructive" /><h2 className="text-xl font-bold">No pudimos cargar los usuarios</h2><p className="text-sm text-muted-foreground">{message(users.error)}</p><Button onClick={() => void users.refetch()} variant="outline">Reintentar</Button></CardContent></Card>}
    {users.data?.items.length === 0 && <Card><CardContent className="space-y-3 p-10 text-center"><Users className="mx-auto size-9 text-muted-foreground" /><h2 className="text-xl font-bold">No hay usuarios con estos filtros</h2><p className="text-sm text-muted-foreground">Limpia la búsqueda o cambia el estado y rol seleccionados.</p><Button onClick={() => { setDraft(''); setSearchParams({}, { replace: true }) }} variant="outline">Limpiar filtros</Button></CardContent></Card>}

    {users.data && users.data.items.length > 0 && <Card><CardContent className="overflow-x-auto p-0">
      <table className="w-full min-w-[900px] text-left text-sm">
        <thead className="border-b bg-muted/60 text-xs uppercase tracking-wide text-muted-foreground"><tr><th className="px-4 py-3">Usuario</th><th className="px-4 py-3">Estado</th><th className="px-4 py-3">Roles</th><th className="px-4 py-3">Seguridad</th><th className="px-4 py-3">Actividad</th></tr></thead>
        <tbody className="divide-y">{users.data.items.map((user) => <tr key={user.publicId}>
          <td className="px-4 py-4"><p className="font-semibold">{user.displayName}</p><p className="text-muted-foreground">{user.email}</p><p className="mt-1 font-mono text-xs text-muted-foreground">{user.publicId}</p></td>
          <td className="px-4 py-4"><span className="rounded-full bg-muted px-2.5 py-1 text-xs font-semibold">{statusNames[user.status]}</span><p className="mt-2 text-xs text-muted-foreground">{user.emailConfirmed ? 'Correo verificado' : 'Correo no verificado'}</p></td>
          <td className="px-4 py-4"><div className="flex flex-wrap gap-1">{user.roles.length ? user.roles.map((item) => <span className="rounded-full bg-accent px-2 py-1 text-xs font-semibold text-accent-foreground" key={item}>{item}</span>) : <span className="text-muted-foreground">Sin rol global</span>}</div></td>
          <td className="px-4 py-4"><span className="inline-flex items-center gap-1"><ShieldCheck className="size-4 text-primary" />{user.mfaEnabled ? 'MFA activo' : 'MFA no configurado'}</span><p className="mt-1 text-xs text-muted-foreground">Idioma {user.preferredLocale}</p></td>
          <td className="px-4 py-4"><p>Último acceso: {formatDate(user.lastLoginAtUtc)}</p><p className="mt-1 text-xs text-muted-foreground">Creada: {formatDate(user.createdAtUtc)}</p></td>
        </tr>)}</tbody>
      </table>
    </CardContent></Card>}

    {users.data && lastPage > 1 && <nav aria-label="Paginación de usuarios" className="flex items-center justify-end gap-3 rounded-xl border bg-card p-3"><Button disabled={page <= 1 || users.isFetching} onClick={() => replace('page', String(page - 1), false)} variant="outline">Anterior</Button><p className="text-sm text-muted-foreground">Página {users.data.page} de {lastPage}</p><Button disabled={page >= lastPage || users.isFetching} onClick={() => replace('page', String(page + 1), false)} variant="outline">Siguiente</Button></nav>}
  </div>
}
