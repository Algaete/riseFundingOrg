import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Building2, ExternalLink, Handshake, LoaderCircle, Search, ShieldCheck, Users } from 'lucide-react'
import { type FormEvent, useRef, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { catalogName, catalogLanguage } from '@/i18n/catalog-labels'
import { Link } from 'react-router-dom'

import { ApiError } from '@/api/http-client'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { organizationApi } from '@/features/organizations/organization-api'
import { projectApi } from '@/features/projects/project-api'
import { collaborationErrorMessage } from '@/i18n/collaboration-messages'
import {
  createNetworkCommandId,
  networkApi,
  type ConnectionAction,
  type ConnectionDirection,
  type ConnectionPurpose,
  type NetworkDirectoryOrganization,
  type OrganizationConnection,
} from './network-api'

const connectionPurposes = ['partnership', 'expertise', 'geographic-reach', 'consortium-exploration'] as const satisfies readonly ConnectionPurpose[]

type NetworkFeedback =
  | { kind: 'success'; key: 'network.settingsSaved' | 'network.requestSent' | 'network.requestUpdated' }
  | { kind: 'error'; error: unknown }

function NetworkReadError({ error, retry }: { error: unknown; retry: () => void }) {
  const { t } = useTranslation()
  return <div className="space-y-3 rounded-lg border border-destructive/40 p-3 text-foreground" role="alert">
    <p>{collaborationErrorMessage(error, 'network')}</p>
    <Button onClick={retry} size="sm" variant="outline">{t('network.retry')}</Button>
  </div>
}

function ConnectionCard({ connection, pending, onAction }: {
  connection: OrganizationConnection
  pending: boolean
  onAction: (connection: OrganizationConnection, action: ConnectionAction) => void
}) {
  const { t } = useTranslation()
  return <Card><CardContent className="space-y-4 p-5">
    <div className="flex flex-wrap items-start justify-between gap-3">
      <div><h3 className="font-bold">{connection.counterpartyOrganizationName}</h3>
        <p className="text-sm text-muted-foreground">{t(`network.purposes.${connection.purpose}`)} · {connection.direction === 'incoming' ? t('network.incoming') : t('network.outgoing')}</p></div>
      <span className="rounded-full bg-muted px-3 py-1 text-xs font-semibold">{t(`network.statuses.${connection.status}`)}</span>
    </div>
    <p className="rounded-lg bg-muted/60 p-3 text-sm" lang="es">{connection.message}</p>
    {connection.requesterProjectTitle && <p className="text-sm"><strong>{t('network.project')}</strong> {connection.requesterProjectTitle}</p>}
    <div className="flex flex-wrap gap-2">
      {connection.counterpartyIsPublic && <Button asChild size="sm" variant="outline"><Link to={`/marketplace/organizations/${connection.counterpartyOrganizationId}`}><ExternalLink className="size-4" />{t('network.publicProfile')}</Link></Button>}
      {connection.canRespond && <><Button disabled={pending} onClick={() => onAction(connection, 'accept')} size="sm">{t('network.accept')}</Button><Button disabled={pending} onClick={() => onAction(connection, 'reject')} size="sm" variant="outline">{t('network.reject')}</Button></>}
      {connection.canCancel && <Button disabled={pending} onClick={() => onAction(connection, 'cancel')} size="sm" variant="outline">{t('network.cancel')}</Button>}
      {connection.canBlock && <Button disabled={pending} onClick={() => onAction(connection, 'block')} size="sm" variant="ghost">{t('network.block')}</Button>}
    </div>
  </CardContent></Card>
}

export function NetworkWorkspacePage() {
  const { t } = useTranslation()
  const queryClient = useQueryClient()
  const organizations = useQuery({ queryKey: ['organizations'], queryFn: ({ signal }) => organizationApi.list(signal) })
  const organization = organizations.data?.[0]
  const isAdmin = organization?.membershipRole === 'admin'
  const [query, setQuery] = useState('')
  const [submittedQuery, setSubmittedQuery] = useState('')
  const [direction, setDirection] = useState<ConnectionDirection>('all')
  const [selected, setSelected] = useState<NetworkDirectoryOrganization | null>(null)
  const [purpose, setPurpose] = useState<ConnectionPurpose>('partnership')
  const [message, setMessage] = useState('')
  const [projectId, setProjectId] = useState('')
  const [feedback, setFeedback] = useState<NetworkFeedback | null>(null)
  const idempotencyKey = useRef<string | null>(null)

  const settings = useQuery({
    queryKey: ['network-settings', organization?.publicId],
    queryFn: ({ signal }) => networkApi.settings(organization!.publicId, signal),
    enabled: Boolean(organization),
  })
  const directory = useQuery({
    queryKey: ['network-directory', organization?.publicId, submittedQuery],
    queryFn: ({ signal }) => networkApi.directory(organization!.publicId, submittedQuery, 1, signal),
    enabled: Boolean(organization),
  })
  const connections = useQuery({
    queryKey: ['network-connections', organization?.publicId, direction],
    queryFn: ({ signal }) => networkApi.connections(organization!.publicId, direction, signal),
    enabled: Boolean(organization),
  })
  const projects = useQuery({
    queryKey: ['projects', organization?.publicId],
    queryFn: ({ signal }) => projectApi.list(organization!.publicId, signal),
    enabled: Boolean(organization && isAdmin),
  })

  const saveSettings = useMutation({
    mutationFn: (input: { isDiscoverable: boolean; allowRequests: boolean }) =>
      networkApi.putSettings(organization!.publicId, input, settings.data?.eTag),
    onSuccess: async () => {
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: ['network-settings', organization?.publicId] }),
        queryClient.invalidateQueries({ queryKey: ['network-directory'] }),
      ])
      setFeedback({ kind: 'success', key: 'network.settingsSaved' })
    },
    onError: (error) => setFeedback({ kind: 'error', error }),
  })
  const create = useMutation({
    mutationFn: () => networkApi.create(organization!.publicId, {
      recipientOrganizationId: selected!.id,
      requesterProjectId: projectId || null,
      purpose,
      message,
    }, idempotencyKey.current ??= createNetworkCommandId()),
    onSuccess: async () => {
      idempotencyKey.current = null
      setSelected(null); setMessage(''); setProjectId('')
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: ['network-directory'] }),
        queryClient.invalidateQueries({ queryKey: ['network-connections'] }),
      ])
      setFeedback({ kind: 'success', key: 'network.requestSent' })
    },
    onError: (error) => {
      if (error instanceof ApiError) idempotencyKey.current = null
      setFeedback({ kind: 'error', error })
    },
  })
  const action = useMutation({
    mutationFn: ({ connection, action }: { connection: OrganizationConnection; action: ConnectionAction }) =>
      networkApi.action(organization!.publicId, connection, action),
    onSuccess: async () => {
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: ['network-connections'] }),
        queryClient.invalidateQueries({ queryKey: ['network-directory'] }),
      ])
      setFeedback({ kind: 'success', key: 'network.requestUpdated' })
    },
    onError: (error) => setFeedback({ kind: 'error', error }),
  })

  function search(event: FormEvent) { event.preventDefault(); setSubmittedQuery(query.trim()) }
  function submitConnection(event: FormEvent) { event.preventDefault(); setFeedback(null); create.mutate() }

  if (organizations.isPending) return <p role="status">{t('network.loadingOrganization')}</p>
  if (organizations.isError) return <Card><CardContent className="space-y-3 p-8">
    <h1 className="text-xl font-bold">{t('network.organizationFailed')}</h1>
    <NetworkReadError error={organizations.error} retry={() => void organizations.refetch()} />
  </CardContent></Card>
  if (!organization) return <Card><CardContent className="p-8 text-center"><h1 className="text-2xl font-bold">{t('network.organizationRequired')}</h1><Button asChild className="mt-4"><Link to="/onboarding">{t('network.start')}</Link></Button></CardContent></Card>

  return <div className="space-y-8">
    <header><p className="text-sm font-bold uppercase tracking-[0.16em] text-primary">{t('network.eyebrow')}</p><h1 className="mt-1 text-3xl font-bold">{t('network.title')}</h1><p className="mt-2 max-w-3xl text-muted-foreground">{t('network.description')}</p></header>
    {feedback && <p className="rounded-lg bg-accent p-3 text-sm" role={feedback.kind === 'error' ? 'alert' : 'status'}>{feedback.kind === 'success' ? t(feedback.key) : collaborationErrorMessage(feedback.error, 'network', 'write')}</p>}

    <Card><CardHeader><CardTitle className="flex items-center gap-2"><ShieldCheck className="size-5 text-primary" />{t('network.privacy')}</CardTitle></CardHeader><CardContent className="space-y-4">
      {settings.isPending && <p role="status">{t('network.loadingSettings')}</p>}
      {settings.isError && <NetworkReadError error={settings.error} retry={() => void settings.refetch()} />}
      {settings.data && <><p className="text-sm text-muted-foreground">{t('network.privacyHelp')}</p><div className="flex flex-wrap gap-2">
        {!settings.data.isDiscoverable ? <Button className="h-auto min-h-10 whitespace-normal" disabled={!isAdmin || saveSettings.isPending} onClick={() => saveSettings.mutate({ isDiscoverable: true, allowRequests: true })}>{t('network.enable')}</Button> : <><Button disabled={!isAdmin || saveSettings.isPending} onClick={() => saveSettings.mutate({ isDiscoverable: true, allowRequests: !settings.data.allowRequests })} variant="outline">{settings.data.allowRequests ? t('network.pauseRequests') : t('network.resumeRequests')}</Button><Button disabled={!isAdmin || saveSettings.isPending} onClick={() => saveSettings.mutate({ isDiscoverable: false, allowRequests: false })} variant="ghost">{t('network.leave')}</Button></>}
      </div>{!isAdmin && <p className="text-sm">{t('network.memberHelp')}</p>}</>}
    </CardContent></Card>

    <section className="space-y-4"><div><h2 className="text-2xl font-bold">{t('network.directory')}</h2><p className="text-sm text-muted-foreground">{t('network.directoryHelp')}</p></div>
      <form className="flex max-w-2xl flex-col gap-2 sm:flex-row" onSubmit={search}><Input aria-label={t('network.searchLabel')} maxLength={200} onChange={(event) => setQuery(event.target.value)} placeholder={t('network.searchPlaceholder')} value={query} /><Button type="submit"><Search className="size-4" />{t('network.search')}</Button></form>
      {directory.isPending && <p role="status">{t('network.searching')}</p>}
      {directory.isError && <NetworkReadError error={directory.error} retry={() => void directory.refetch()} />}
      {directory.data?.items.length === 0 && <p className="rounded-lg border p-6 text-center text-muted-foreground">{t('network.emptyDirectory')}</p>}
      <div className="grid gap-4 lg:grid-cols-2">{directory.data?.items.map((item) => <Card key={item.id}><CardContent className="space-y-4 p-5"><div className="flex items-start justify-between gap-3"><div><h3 className="text-lg font-bold">{item.name}</h3><p className="text-sm text-muted-foreground"><span lang={catalogLanguage('organizationTypes', item.organizationType)}>{catalogName('organizationTypes', item.organizationType)}</span> · <span lang={catalogLanguage('countries', item.homeCountry)}>{catalogName('countries', item.homeCountry)}</span></p></div><Building2 className="size-5 text-primary" /></div><p className="line-clamp-3 text-sm" lang={item.description ? 'es' : undefined}>{item.description ?? t('network.noDescription')}</p><div className="flex flex-wrap gap-1">{item.categories.slice(0, 4).map((category) => <span className="rounded-full bg-muted px-2 py-1 text-xs" key={category.id} lang={catalogLanguage('fundingCategories', category)}>{catalogName('fundingCategories', category)}</span>)}</div><p className="text-sm">{t('network.projectCount', { count: item.visibleProjectCount })}</p><div className="flex flex-wrap gap-2"><Button asChild size="sm" variant="outline"><Link to={`/marketplace/organizations/${item.id}`}>{t('network.viewProfile')}</Link></Button>{item.connectionState === 'none' && isAdmin && item.allowsRequests && <Button onClick={() => { setSelected(item); setFeedback(null); idempotencyKey.current = null }} size="sm"><Handshake className="size-4" />{t('network.connect')}</Button>}{item.connectionState === 'none' && !item.allowsRequests && <span className="rounded-full bg-muted px-3 py-1 text-xs">{t('network.notReceiving')}</span>}{item.connectionState !== 'none' && <span className="rounded-full bg-accent px-3 py-1 text-xs font-semibold">{item.connectionState === 'connected' ? t('network.connected') : t('network.requestPending')}</span>}</div></CardContent></Card>)}</div>
    </section>

    {selected && <Card><CardHeader><CardTitle>{t('network.invite', { name: selected.name })}</CardTitle></CardHeader><CardContent><form className="grid gap-4" onSubmit={submitConnection}>{projects.isError && <p className="rounded-lg border p-3 text-sm" role="alert">{t('network.projectsFailed')}</p>}<label className="grid gap-1 text-sm font-semibold">{t('network.purpose')}<select className="h-10 rounded-lg border bg-background px-3" onChange={(event) => setPurpose(event.target.value as ConnectionPurpose)} value={purpose}>{connectionPurposes.map(value => <option key={value} value={value}>{t(`network.purposes.${value}`)}</option>)}</select></label><label className="grid gap-1 text-sm font-semibold">{t('network.optionalProject')}<select className="h-10 rounded-lg border bg-background px-3" onChange={(event) => setProjectId(event.target.value)} value={projectId}><option value="">{t('network.noProject')}</option>{projects.data?.filter((project) => project.publicationStatus === 2).map((project) => <option key={project.publicId} lang="es" value={project.publicId}>{project.title}</option>)}</select></label><label className="grid gap-1 text-sm font-semibold">{t('network.privateMessage')}<textarea className="min-h-28 rounded-lg border bg-background p-3 text-sm" maxLength={500} minLength={10} onChange={(event) => setMessage(event.target.value)} placeholder={t('network.messagePlaceholder')} required value={message} /></label><p className="text-xs text-muted-foreground">{t('network.messageHelp')}</p><div className="flex flex-wrap gap-2"><Button disabled={create.isPending || message.trim().length < 10} type="submit">{create.isPending ? <LoaderCircle className="size-4 animate-spin" /> : <Handshake className="size-4" />}{t('network.send')}</Button><Button onClick={() => setSelected(null)} type="button" variant="outline">{t('network.cancel')}</Button></div></form></CardContent></Card>}

    <section className="space-y-4"><div className="flex flex-wrap items-center justify-between gap-3"><div><h2 className="text-2xl font-bold">{t('network.connections')}</h2><p className="text-sm text-muted-foreground">{t('network.connectionsHelp')}</p></div><div className="flex flex-wrap gap-1">{(['all', 'incoming', 'outgoing'] as const).map((value) => <Button key={value} aria-pressed={direction === value} onClick={() => setDirection(value)} size="sm" variant={direction === value ? 'default' : 'outline'}>{t(`network.directions.${value}`)}</Button>)}</div></div>{connections.isPending && <p role="status">{t('network.loadingConnections')}</p>}{connections.isError && <NetworkReadError error={connections.error} retry={() => void connections.refetch()} />}{connections.data?.items.length === 0 && <Card><CardContent className="p-8 text-center"><Users className="mx-auto size-8 text-muted-foreground" /><p className="mt-3 font-semibold">{t('network.noConnections')}</p></CardContent></Card>}<div className="grid gap-4 lg:grid-cols-2">{connections.data?.items.map((connection) => <ConnectionCard connection={connection} key={connection.id} onAction={(item, requestedAction) => action.mutate({ connection: item, action: requestedAction })} pending={action.isPending} />)}</div></section>
  </div>
}
