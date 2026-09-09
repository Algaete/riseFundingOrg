import { workspaceLocale } from '@/i18n/workspace-messages'
import i18n from '@/i18n'
import { useTranslation } from 'react-i18next'
import { keepPreviousData, useQuery } from '@tanstack/react-query'
import { CircleAlert, LoaderCircle, Search, ShieldCheck, Users } from 'lucide-react'
import { type FormEvent, useEffect, useState } from 'react'
import { useSearchParams } from 'react-router-dom'

import { adminErrorMessage } from '@/i18n/editorial-messages'
import { operationStatus, operationsMessage } from '@/i18n/operations-messages'
import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { adminUsersApi, type AdminUserStatus } from '@/features/admin-users/admin-users-api'

const statusNames: Record<AdminUserStatus, string> = {
  PendingActivation: 'adminUsers.pendingActivation',
  PendingVerification: 'adminUsers.pendingVerification',
  Active: 'operations.active',
  Blocked: 'adminUsers.blocked',
  Disabled: 'adminUsers.disabled',
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
  if (!value) return i18n.t('operations.never')
  return new Intl.DateTimeFormat(workspaceLocale(), {
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(new Date(value))
}

function message(error: unknown) {
  return adminErrorMessage(error)
}

export function AdminUsersWorkspacePage() {
  useTranslation()
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

  return <div className="min-w-0 space-y-6">
    <header className="flex flex-wrap items-end justify-between gap-4">
      <div>
        <p className="text-sm font-bold uppercase tracking-[0.16em] text-primary">{i18n.t('editorial.administration')}</p>
        <h1 className="mt-1 text-3xl font-bold">{i18n.t('operations.users')}</h1>
        <p className="mt-2 text-muted-foreground">{i18n.t('adminUsers.intro')}</p>
      </div>
      {users.data && <p className="rounded-full bg-muted px-3 py-1 text-sm">{i18n.t('adminUsers.count', { count: users.data.totalCount })}</p>}
    </header>

    <Card>
      <CardContent className="grid gap-3 p-4 lg:grid-cols-[minmax(16rem,1fr)_auto_auto]">
        <form className="flex flex-wrap gap-2" onSubmit={submit}>
          <Input aria-label={i18n.t('adminUsers.search')} maxLength={200} onChange={(event) => setDraft(event.target.value)} placeholder={i18n.t('adminUsers.searchPlaceholder')} value={draft} />
          <Button type="submit" variant="outline"><Search className="size-4" />{i18n.t('editorial.search')}</Button>
        </form>
        <label className="grid gap-1 text-xs font-semibold">{i18n.t('operations.status')}
          <select className={selectClass} onChange={(event) => replace('status', event.target.value)} value={status ?? ''}>
            <option value="">{i18n.t('operations.all')}</option>
            {statusOptions.map((option) => <option key={option.value} value={option.value}>{operationsMessage(option.label)}</option>)}
          </select>
        </label>
        <label className="grid gap-1 text-xs font-semibold">{i18n.t('adminUsers.globalRole')}
          <select className={selectClass} onChange={(event) => replace('role', event.target.value)} value={role}>
            <option value="">{i18n.t('operations.all')}</option>
            <option value="Admin">Admin</option>
            <option value="SuperAdmin">SuperAdmin</option>
          </select>
        </label>
      </CardContent>
    </Card>

    {users.isPending && <Card><CardContent className="flex items-center gap-2 p-8" role="status"><LoaderCircle className="size-5 animate-spin" />{i18n.t('adminUsers.loading')}</CardContent></Card>}
    {users.isError && <Card className="border-destructive/40"><CardContent className="space-y-3 p-8" role="alert"><CircleAlert className="size-8 text-foreground" /><h2 className="text-xl font-bold">{i18n.t('adminUsers.failed')}</h2><p className="text-sm text-muted-foreground">{message(users.error)}</p><Button onClick={() => void users.refetch()} variant="outline">{i18n.t('editorial.retry')}</Button></CardContent></Card>}
    {users.data?.items.length === 0 && <Card><CardContent className="space-y-3 p-10 text-center"><Users className="mx-auto size-9 text-muted-foreground" /><h2 className="text-xl font-bold">{i18n.t('adminUsers.empty')}</h2><p className="text-sm text-muted-foreground">{i18n.t('adminUsers.emptyHelp')}</p><Button onClick={() => { setDraft(''); setSearchParams({}, { replace: true }) }} variant="outline">{i18n.t('operations.clear')}</Button></CardContent></Card>}

    {users.data && users.data.items.length > 0 && <Card><CardContent aria-label={i18n.t('adminUsers.table')} role="region" tabIndex={0} className="max-w-full overflow-x-auto p-0">
      <table className="w-full min-w-[900px] text-left text-sm">
        <thead className="border-b bg-muted/60 text-xs uppercase tracking-wide text-muted-foreground"><tr><th className="px-4 py-3">{i18n.t('adminUsers.user')}</th><th className="px-4 py-3">{i18n.t('operations.status')}</th><th className="px-4 py-3">{i18n.t('operations.roles')}</th><th className="px-4 py-3">{i18n.t('adminUsers.security')}</th><th className="px-4 py-3">{i18n.t('operations.activity')}</th></tr></thead>
        <tbody className="divide-y">{users.data.items.map((user) => <tr key={user.publicId}>
          <td className="px-4 py-4"><p className="font-semibold">{user.displayName}</p><p className="text-muted-foreground">{user.email}</p><p className="mt-1 font-mono text-xs text-muted-foreground">{user.publicId}</p></td>
          <td className="px-4 py-4"><span className="rounded-full bg-muted px-2.5 py-1 text-xs font-semibold">{operationStatus(statusNames, user.status)}</span><p className="mt-2 text-xs text-muted-foreground">{user.emailConfirmed ? i18n.t('adminUsers.verified') : i18n.t('adminUsers.unverified')}</p></td>
          <td className="px-4 py-4"><div className="flex flex-wrap gap-1">{user.roles.length ? user.roles.map((item) => <span className="rounded-full bg-accent px-2 py-1 text-xs font-semibold text-accent-foreground" key={item}>{item}</span>) : <span className="text-muted-foreground">{i18n.t('adminUsers.noRole')}</span>}</div></td>
          <td className="px-4 py-4"><span className="inline-flex items-center gap-1"><ShieldCheck className="size-4 text-primary" />{user.mfaEnabled ? i18n.t('adminUsers.mfa') : i18n.t('adminUsers.noMfa')}</span><p className="mt-1 text-xs text-muted-foreground">{i18n.t('adminUsers.locale', { locale: user.preferredLocale })}</p></td>
          <td className="px-4 py-4"><p>{i18n.t('adminUsers.lastLogin', { date: formatDate(user.lastLoginAtUtc) })}</p><p className="mt-1 text-xs text-muted-foreground">{i18n.t('operations.createdAt', { date: formatDate(user.createdAtUtc) })}</p></td>
        </tr>)}</tbody>
      </table>
    </CardContent></Card>}

    {users.data && lastPage > 1 && <nav aria-label={i18n.t('adminUsers.pagination')} className="flex flex-wrap items-center justify-end gap-3 rounded-xl border bg-card p-3"><Button disabled={page <= 1 || users.isFetching} onClick={() => replace('page', String(page - 1), false)} variant="outline">{i18n.t('editorial.previous')}</Button><p className="text-sm text-muted-foreground">{i18n.t('operations.page', { page: users.data.page, total: lastPage })}</p><Button disabled={page >= lastPage || users.isFetching} onClick={() => replace('page', String(page + 1), false)} variant="outline">{i18n.t('editorial.next')}</Button></nav>}
  </div>
}
