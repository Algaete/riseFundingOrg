import { workspaceLocale } from '@/i18n/workspace-messages'
import i18n from '@/i18n'
import { catalogName, catalogLanguage } from '@/i18n/catalog-labels'
import { useTranslation } from 'react-i18next'
import { keepPreviousData, useQuery } from '@tanstack/react-query'
import {
  ArrowLeft, Building2, CircleAlert, ExternalLink, FolderKanban, LoaderCircle,
  Search, ShieldCheck, Users, type LucideIcon,
} from 'lucide-react'
import { type FormEvent, useEffect, useState } from 'react'
import { Link, useParams, useSearchParams } from 'react-router-dom'

import { adminErrorMessage } from '@/i18n/editorial-messages'
import { operationsMessage } from '@/i18n/operations-messages'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import {
  adminOrganizationsApi,
  type AdminOrganizationDetail,
} from '@/features/admin-organizations/admin-organizations-api'

const profileNames = ['adminOrganizations.incomplete', 'adminOrganizations.inProgress', 'adminOrganizations.ready']
const selectClass = 'h-10 rounded-lg border bg-background px-3 text-sm'

function positiveInteger(value: string | null, fallback: number) {
  const parsed = Number(value)
  return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : fallback
}

function formatDate(value: string | null) {
  return value ? new Intl.DateTimeFormat(workspaceLocale(), {
    dateStyle: 'medium', timeStyle: 'short',
  }).format(new Date(value)) : i18n.t('editorial.noDate')
}

function errorMessage(error: unknown) {
  return adminErrorMessage(error)
}

function ProfileBadge({ status }: { status: number }) {
  useTranslation()
  return <span className="rounded-full bg-accent px-2.5 py-1 text-xs font-semibold text-accent-foreground">
    {operationsMessage(profileNames[status] ?? 'operations.unknown')}
  </span>
}

export function AdminOrganizationsWorkspacePage() {
  useTranslation()
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

  return <div className="min-w-0 space-y-6">
    <header className="flex flex-wrap items-end justify-between gap-4">
      <div><p className="text-sm font-bold uppercase tracking-[0.16em] text-primary">{i18n.t('editorial.administration')}</p><h1 className="mt-1 text-3xl font-bold">{i18n.t('operations.organizations')}</h1><p className="mt-2 text-muted-foreground">{i18n.t('adminOrganizations.intro')}</p></div>
      {organizations.data && <p className="rounded-full bg-muted px-3 py-1 text-sm">{i18n.t('adminOrganizations.count', { count: organizations.data.totalCount })}</p>}
    </header>

    <Card><CardContent className="grid gap-3 p-4 lg:grid-cols-[minmax(16rem,1fr)_auto_auto]">
      <form className="flex flex-wrap gap-2" onSubmit={submit}><Input aria-label={i18n.t('adminOrganizations.search')} maxLength={200} onChange={event => setDraft(event.target.value)} placeholder={i18n.t('adminOrganizations.searchPlaceholder')} value={draft} /><Button type="submit" variant="outline"><Search className="size-4" />{i18n.t('editorial.search')}</Button></form>
      <label className="grid gap-1 text-xs font-semibold">{i18n.t('adminOrganizations.profileStatus')}<select className={selectClass} onChange={event => replace('profileStatus', event.target.value)} value={profileStatus ?? ''}><option value="">{i18n.t('operations.all')}</option>{profileNames.map((label, value) => <option key={label} value={value}>{operationsMessage(label)}</option>)}</select></label>
      <label className="grid gap-1 text-xs font-semibold">{i18n.t('adminOrganizations.access')}<select className={selectClass} onChange={event => replace('isActive', event.target.value)} value={activeText ?? ''}><option value="">{i18n.t('operations.allFeminine')}</option><option value="true">{i18n.t('adminOrganizations.activePlural')}</option><option value="false">{i18n.t('adminOrganizations.inactivePlural')}</option></select></label>
    </CardContent></Card>

    {organizations.isPending && <Card><CardContent className="flex items-center gap-2 p-8" role="status"><LoaderCircle className="size-5 animate-spin" />{i18n.t('adminOrganizations.loading')}</CardContent></Card>}
    {organizations.isError && <Card className="border-destructive/40"><CardContent className="space-y-3 p-8" role="alert"><CircleAlert className="size-8 text-foreground" /><h2 className="text-xl font-bold">{i18n.t('adminOrganizations.failed')}</h2><p className="text-sm text-muted-foreground">{errorMessage(organizations.error)}</p><Button onClick={() => void organizations.refetch()} variant="outline">{i18n.t('editorial.retry')}</Button></CardContent></Card>}
    {organizations.data?.items.length === 0 && <Card><CardContent className="space-y-3 p-10 text-center"><Building2 className="mx-auto size-9 text-muted-foreground" /><h2 className="text-xl font-bold">{i18n.t('adminOrganizations.empty')}</h2><Button onClick={() => { setDraft(''); setSearchParams({}, { replace: true }) }} variant="outline">{i18n.t('operations.clear')}</Button></CardContent></Card>}

    {organizations.data && organizations.data.items.length > 0 && <Card><CardContent aria-label={i18n.t('operations.organizations')} role="region" tabIndex={0} className="max-w-full overflow-x-auto p-0"><table className="w-full min-w-[920px] text-left text-sm"><thead className="border-b bg-muted/60 text-xs uppercase tracking-wide text-muted-foreground"><tr><th className="px-4 py-3">{i18n.t('operations.organization')}</th><th className="px-4 py-3">{i18n.t('adminOrganizations.profile')}</th><th className="px-4 py-3">{i18n.t('operations.activity')}</th><th className="px-4 py-3">{i18n.t('adminOrganizations.plan')}</th><th className="px-4 py-3">{i18n.t('adminOrganizations.update')}</th><th className="relative px-4 py-3"><span className="sr-only">{i18n.t('adminOrganizations.action')}</span></th></tr></thead><tbody className="divide-y">{organizations.data.items.map(item => <tr key={item.publicId}><td className="px-4 py-4"><p className="font-semibold">{item.name}</p><p className="text-muted-foreground"><span lang="es">{item.organizationTypeName}</span> · <span lang={catalogLanguage('countries', { code: item.countryCode, name: item.countryName })}>{catalogName('countries', { code: item.countryCode, name: item.countryName })}</span></p><p className="mt-1 font-mono text-xs text-muted-foreground">{item.publicId}</p></td><td className="px-4 py-4"><ProfileBadge status={item.profileStatus} /><p className="mt-2 text-xs text-muted-foreground">{i18n.t('operations.complete', { value: item.profileCompleteness })} · {item.isActive ? i18n.t('operations.active') : i18n.t('operations.inactive')}</p></td><td className="px-4 py-4"><p>{i18n.t('adminOrganizations.membersCount', { count: item.memberCount })}</p><p className="text-xs text-muted-foreground">{i18n.t('adminOrganizations.projectsCount', { count: item.projectCount })}</p></td><td className="px-4 py-4"><p className="font-semibold">{item.planName}</p><p className="text-xs text-muted-foreground">{item.planCode}</p></td><td className="px-4 py-4 text-muted-foreground">{formatDate(item.updatedAtUtc)}</td><td className="px-4 py-4"><Button asChild size="sm" variant="outline"><Link to={`/admin/organizations/${item.publicId}`}>{i18n.t('operations.detail')}</Link></Button></td></tr>)}</tbody></table></CardContent></Card>}

    {organizations.data && lastPage > 1 && <nav aria-label={i18n.t('adminOrganizations.pagination')} className="flex flex-wrap items-center justify-end gap-3 rounded-xl border bg-card p-3"><Button disabled={page <= 1 || organizations.isFetching} onClick={() => replace('page', String(page - 1), false)} variant="outline">{i18n.t('editorial.previous')}</Button><p className="text-sm text-muted-foreground">{i18n.t('operations.page', { page, total: lastPage })}</p><Button disabled={page >= lastPage || organizations.isFetching} onClick={() => replace('page', String(page + 1), false)} variant="outline">{i18n.t('editorial.next')}</Button></nav>}
  </div>
}

function SummaryCard({ item }: { item: AdminOrganizationDetail }) {
  useTranslation()
  const metrics: { label: string; value: number; icon: LucideIcon }[] = [
    { label: i18n.t('adminOrganizations.members'), value: item.memberCount, icon: Users },
    { label: i18n.t('adminOrganizations.admins'), value: item.adminMemberCount, icon: ShieldCheck },
    { label: i18n.t('adminOrganizations.projects'), value: item.projectCount, icon: FolderKanban },
    { label: i18n.t('adminOrganizations.published'), value: item.publishedProjectCount, icon: ExternalLink },
  ]
  return <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
    {metrics.map(({ label, value, icon: Icon }) => <Card key={label}><CardContent className="flex items-center justify-between p-5"><div><p className="text-sm text-muted-foreground">{label}</p><p className="mt-1 text-2xl font-bold">{value}</p></div><Icon className="size-5 text-primary" /></CardContent></Card>)}
  </div>
}

export function AdminOrganizationDetailPage() {
  useTranslation()
  const { organizationId } = useParams()
  const organization = useQuery({
    queryKey: ['admin-organization', organizationId],
    queryFn: ({ signal }) => adminOrganizationsApi.get(organizationId!, signal),
    enabled: Boolean(organizationId),
  })
  if (organization.isPending) return <Card><CardContent className="flex items-center gap-2 p-8" role="status"><LoaderCircle className="size-5 animate-spin" />{i18n.t('adminOrganizations.loadingDetail')}</CardContent></Card>
  if (organization.isError) return <div className="space-y-4"><Button asChild variant="ghost"><Link to="/admin/organizations"><ArrowLeft className="size-4" />{i18n.t('editorial.back')}</Link></Button><Card className="border-destructive/40"><CardContent className="space-y-3 p-8" role="alert"><CircleAlert className="size-8 text-foreground" /><h1 className="text-xl font-bold">{i18n.t('adminOrganizations.detailFailed')}</h1><p>{errorMessage(organization.error)}</p><Button onClick={() => void organization.refetch()} variant="outline">{i18n.t('editorial.retry')}</Button></CardContent></Card></div>
  const item = organization.data!
  return <div className="min-w-0 space-y-6"><Button asChild variant="ghost"><Link to="/admin/organizations"><ArrowLeft className="size-4" />{i18n.t('adminOrganizations.back')}</Link></Button><header><p className="text-sm font-bold uppercase tracking-[0.16em] text-primary">{i18n.t('editorial.administration')}</p><div className="mt-1 flex flex-wrap items-center gap-3"><h1 className="text-3xl font-bold">{item.name}</h1><ProfileBadge status={item.profileStatus} /></div><p className="mt-2 text-muted-foreground"><span lang="es">{item.organizationTypeName}</span> · <span lang={catalogLanguage('countries', { code: item.countryCode, name: item.countryName })}>{catalogName('countries', { code: item.countryCode, name: item.countryName })}</span> · {i18n.t('adminOrganizations.profileComplete', { value: item.profileCompleteness })}</p></header><SummaryCard item={item} /><div className="grid gap-6 lg:grid-cols-2"><Card><CardHeader><CardTitle>{i18n.t('adminOrganizations.institutional')}</CardTitle></CardHeader><CardContent><dl className="grid gap-4 text-sm sm:grid-cols-2"><div><dt className="text-muted-foreground">{i18n.t('adminOrganizations.legalName')}</dt><dd className="font-semibold">{item.legalName ?? i18n.t('operations.notReported')}</dd></div><div><dt className="text-muted-foreground">{i18n.t('adminOrganizations.legalType')}</dt><dd className="font-semibold">{item.legalEntityTypeName ? <span lang="es">{item.legalEntityTypeName}</span> : i18n.t('operations.notReported')}</dd></div><div><dt className="text-muted-foreground">{i18n.t('adminOrganizations.size')}</dt><dd className="font-semibold">{item.organizationSizeName ? <span lang="es">{item.organizationSizeName}</span> : i18n.t('operations.notReported')}</dd></div><div><dt className="text-muted-foreground">{i18n.t('adminOrganizations.established')}</dt><dd className="font-semibold">{item.establishedYear ?? i18n.t('operations.notReported')}</dd></div><div className="sm:col-span-2"><dt className="text-muted-foreground">{i18n.t('adminFunders.description')}</dt><dd className="mt-1 whitespace-pre-line">{item.description ?? i18n.t('editorial.noDescription')}</dd></div>{item.websiteUrl && <div className="sm:col-span-2"><dt className="text-muted-foreground">{i18n.t('adminOrganizations.website')}</dt><dd><a className="font-semibold text-primary underline" href={item.websiteUrl} rel="noreferrer" target="_blank">{i18n.t('adminOrganizations.openWebsite')} <ExternalLink className="inline size-3.5" /></a></dd></div>}</dl></CardContent></Card><Card><CardHeader><CardTitle>{i18n.t('adminOrganizations.accessSubscription')}</CardTitle></CardHeader><CardContent><dl className="grid gap-4 text-sm"><div><dt className="text-muted-foreground">{i18n.t('operations.status')}</dt><dd className="font-semibold">{item.isActive ? i18n.t('adminOrganizations.activeOrganization') : i18n.t('adminOrganizations.inactiveOrganization')}</dd></div><div><dt className="text-muted-foreground">{i18n.t('adminOrganizations.observedPlan')}</dt><dd className="font-semibold">{item.planName} ({item.planCode})</dd></div><div><dt className="text-muted-foreground">{i18n.t('adminOrganizations.periodEnd')}</dt><dd className="font-semibold">{formatDate(item.currentPeriodEndUtc)}</dd></div><div><dt className="text-muted-foreground">{i18n.t('adminOrganizations.version')}</dt><dd className="font-semibold">{item.profileVersion}</dd></div><div><dt className="text-muted-foreground">{i18n.t('operations.created')}</dt><dd className="font-semibold">{formatDate(item.createdAtUtc)}</dd></div><div><dt className="text-muted-foreground">{i18n.t('adminOrganizations.lastUpdate')}</dt><dd className="font-semibold">{formatDate(item.updatedAtUtc)}</dd></div></dl></CardContent></Card></div></div>
}
