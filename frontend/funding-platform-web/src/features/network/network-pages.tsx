import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Building2, ExternalLink, Handshake, LoaderCircle, Search, ShieldCheck, Users } from 'lucide-react'
import { type FormEvent, useRef, useState } from 'react'
import { Link } from 'react-router-dom'

import { ApiError } from '@/api/http-client'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { organizationApi } from '@/features/organizations/organization-api'
import { projectApi } from '@/features/projects/project-api'
import {
  createNetworkCommandId,
  networkApi,
  type ConnectionAction,
  type ConnectionDirection,
  type ConnectionPurpose,
  type NetworkDirectoryOrganization,
  type OrganizationConnection,
} from './network-api'

const purposeNames: Record<ConnectionPurpose, string> = {
  partnership: 'Alianza de implementación',
  expertise: 'Intercambio de experiencia',
  'geographic-reach': 'Cobertura territorial',
  'consortium-exploration': 'Explorar un consorcio',
}
const statusNames = {
  pending: 'Pendiente', accepted: 'Aceptada', rejected: 'Rechazada',
  cancelled: 'Cancelada', blocked: 'Bloqueada',
}

function errorMessage(error: unknown) {
  if (error instanceof ApiError) {
    return Object.values(error.problem.errors ?? {}).flat()[0]
      ?? error.problem.detail ?? error.problem.title
  }
  return 'No pudimos confirmar la operación. Puedes reintentar sin duplicarla.'
}

function ConnectionCard({ connection, pending, onAction }: {
  connection: OrganizationConnection
  pending: boolean
  onAction: (connection: OrganizationConnection, action: ConnectionAction) => void
}) {
  return <Card><CardContent className="space-y-4 p-5">
    <div className="flex flex-wrap items-start justify-between gap-3">
      <div><h3 className="font-bold">{connection.counterpartyOrganizationName}</h3>
        <p className="text-sm text-muted-foreground">{purposeNames[connection.purpose]} · {connection.direction === 'incoming' ? 'Recibida' : 'Enviada'}</p></div>
      <span className="rounded-full bg-muted px-3 py-1 text-xs font-semibold">{statusNames[connection.status]}</span>
    </div>
    <p className="rounded-lg bg-muted/60 p-3 text-sm">{connection.message}</p>
    {connection.requesterProjectTitle && <p className="text-sm"><strong>Proyecto:</strong> {connection.requesterProjectTitle}</p>}
    <div className="flex flex-wrap gap-2">
      {connection.counterpartyIsPublic && <Button asChild size="sm" variant="outline"><Link to={`/marketplace/organizations/${connection.counterpartyOrganizationId}`}><ExternalLink className="size-4" />Perfil público</Link></Button>}
      {connection.canRespond && <><Button disabled={pending} onClick={() => onAction(connection, 'accept')} size="sm">Aceptar</Button><Button disabled={pending} onClick={() => onAction(connection, 'reject')} size="sm" variant="outline">Rechazar</Button></>}
      {connection.canCancel && <Button disabled={pending} onClick={() => onAction(connection, 'cancel')} size="sm" variant="outline">Cancelar</Button>}
      {connection.canBlock && <Button disabled={pending} onClick={() => onAction(connection, 'block')} size="sm" variant="ghost">Bloquear</Button>}
    </div>
  </CardContent></Card>
}

export function NetworkWorkspacePage() {
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
  const [feedback, setFeedback] = useState<string | null>(null)
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
      setFeedback('Configuración de networking actualizada.')
    },
    onError: (error) => setFeedback(errorMessage(error)),
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
      setFeedback('Solicitud enviada. La otra organización debe aceptarla explícitamente.')
    },
    onError: (error) => {
      if (error instanceof ApiError) idempotencyKey.current = null
      setFeedback(errorMessage(error))
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
      setFeedback('Solicitud actualizada.')
    },
    onError: (error) => setFeedback(errorMessage(error)),
  })

  function search(event: FormEvent) { event.preventDefault(); setSubmittedQuery(query.trim()) }
  function submitConnection(event: FormEvent) { event.preventDefault(); setFeedback(null); create.mutate() }

  if (organizations.isPending) return <p role="status">Cargando organización…</p>
  if (!organization) return <Card><CardContent className="p-8 text-center"><h1 className="text-2xl font-bold">Primero crea tu organización</h1><Button asChild className="mt-4"><Link to="/onboarding">Comenzar</Link></Button></CardContent></Card>

  return <div className="space-y-8">
    <header><p className="text-sm font-bold uppercase tracking-[0.16em] text-primary">Red de organizaciones</p><h1 className="mt-1 text-3xl font-bold">Conexiones</h1><p className="mt-2 max-w-3xl text-muted-foreground">Descubre organizaciones con proyectos públicos y envía una invitación moderada. La plataforma no publica correos, teléfonos ni datos privados, y no incluye chat.</p></header>
    {feedback && <p className="rounded-lg bg-accent p-3 text-sm" role="status">{feedback}</p>}

    <Card><CardHeader><CardTitle className="flex items-center gap-2"><ShieldCheck className="size-5 text-primary" />Privacidad y visibilidad</CardTitle></CardHeader><CardContent className="space-y-4">
      {settings.isPending && <p role="status">Cargando configuración…</p>}
      {settings.data && <><p className="text-sm text-muted-foreground">Por defecto tu ONG no aparece en este directorio. Solo un administrador puede cambiar esta decisión.</p><div className="flex flex-wrap gap-2">
        {!settings.data.isDiscoverable ? <Button disabled={!isAdmin || saveSettings.isPending} onClick={() => saveSettings.mutate({ isDiscoverable: true, allowRequests: true })}>Activar directorio y recibir solicitudes</Button> : <><Button disabled={!isAdmin || saveSettings.isPending} onClick={() => saveSettings.mutate({ isDiscoverable: true, allowRequests: !settings.data.allowRequests })} variant="outline">{settings.data.allowRequests ? 'Pausar nuevas solicitudes' : 'Volver a recibir solicitudes'}</Button><Button disabled={!isAdmin || saveSettings.isPending} onClick={() => saveSettings.mutate({ isDiscoverable: false, allowRequests: false })} variant="ghost">Salir del directorio</Button></>}
      </div>{!isAdmin && <p className="text-sm">Tu membresía puede explorar la red, pero solo la administración de la ONG puede cambiar visibilidad o responder.</p>}</>}
    </CardContent></Card>

    <section className="space-y-4"><div><h2 className="text-2xl font-bold">Directorio</h2><p className="text-sm text-muted-foreground">Solo aparecen ONG que aceptaron ser visibles y tienen al menos un proyecto público.</p></div>
      <form className="flex max-w-2xl gap-2" onSubmit={search}><Input aria-label="Buscar organizaciones" maxLength={200} onChange={(event) => setQuery(event.target.value)} placeholder="Nombre o descripción" value={query} /><Button type="submit"><Search className="size-4" />Buscar</Button></form>
      {directory.isPending && <p role="status">Buscando organizaciones…</p>}
      {directory.isError && <p className="text-destructive" role="alert">{errorMessage(directory.error)}</p>}
      {directory.data?.items.length === 0 && <p className="rounded-lg border p-6 text-center text-muted-foreground">No encontramos organizaciones con esos criterios.</p>}
      <div className="grid gap-4 lg:grid-cols-2">{directory.data?.items.map((item) => <Card key={item.id}><CardContent className="space-y-4 p-5"><div className="flex items-start justify-between gap-3"><div><h3 className="text-lg font-bold">{item.name}</h3><p className="text-sm text-muted-foreground">{item.organizationType.name} · {item.homeCountry.name}</p></div><Building2 className="size-5 text-primary" /></div><p className="line-clamp-3 text-sm">{item.description ?? 'Sin descripción pública.'}</p><div className="flex flex-wrap gap-1">{item.categories.slice(0, 4).map((category) => <span className="rounded-full bg-muted px-2 py-1 text-xs" key={category.id}>{category.name}</span>)}</div><p className="text-sm">{item.visibleProjectCount} proyecto{item.visibleProjectCount === 1 ? '' : 's'} público{item.visibleProjectCount === 1 ? '' : 's'}</p><div className="flex flex-wrap gap-2"><Button asChild size="sm" variant="outline"><Link to={`/marketplace/organizations/${item.id}`}>Ver perfil</Link></Button>{item.connectionState === 'none' && isAdmin && item.allowsRequests && <Button onClick={() => { setSelected(item); setFeedback(null); idempotencyKey.current = null }} size="sm"><Handshake className="size-4" />Conectar</Button>}{item.connectionState === 'none' && !item.allowsRequests && <span className="rounded-full bg-muted px-3 py-1 text-xs">No recibe solicitudes ahora</span>}{item.connectionState !== 'none' && <span className="rounded-full bg-accent px-3 py-1 text-xs font-semibold">{item.connectionState === 'connected' ? 'Conectadas' : 'Solicitud pendiente'}</span>}</div></CardContent></Card>)}</div>
    </section>

    {selected && <Card><CardHeader><CardTitle>Invitar a {selected.name}</CardTitle></CardHeader><CardContent><form className="grid gap-4" onSubmit={submitConnection}><label className="grid gap-1 text-sm font-semibold">Propósito<select className="h-10 rounded-lg border bg-background px-3" onChange={(event) => setPurpose(event.target.value as ConnectionPurpose)} value={purpose}>{Object.entries(purposeNames).map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select></label><label className="grid gap-1 text-sm font-semibold">Proyecto público opcional<select className="h-10 rounded-lg border bg-background px-3" onChange={(event) => setProjectId(event.target.value)} value={projectId}><option value="">Sin proyecto específico</option>{projects.data?.filter((project) => project.publicationStatus === 2).map((project) => <option key={project.publicId} value={project.publicId}>{project.title}</option>)}</select></label><label className="grid gap-1 text-sm font-semibold">Mensaje privado<textarea className="min-h-28 rounded-lg border bg-background p-3 text-sm" maxLength={500} minLength={10} onChange={(event) => setMessage(event.target.value)} placeholder="Explica el objetivo de la conexión sin incluir correos, teléfonos ni enlaces." required value={message} /></label><p className="text-xs text-muted-foreground">Este primer mensaje queda visible solo para ambas organizaciones. Aceptar no publica automáticamente datos de contacto.</p><div className="flex gap-2"><Button disabled={create.isPending || message.trim().length < 10} type="submit">{create.isPending ? <LoaderCircle className="size-4 animate-spin" /> : <Handshake className="size-4" />}Enviar solicitud</Button><Button onClick={() => setSelected(null)} type="button" variant="outline">Cancelar</Button></div></form></CardContent></Card>}

    <section className="space-y-4"><div className="flex flex-wrap items-center justify-between gap-3"><div><h2 className="text-2xl font-bold">Solicitudes y conexiones</h2><p className="text-sm text-muted-foreground">Las acciones son explícitas y quedan registradas.</p></div><div className="flex gap-1">{(['all', 'incoming', 'outgoing'] as const).map((value) => <Button key={value} onClick={() => setDirection(value)} size="sm" variant={direction === value ? 'default' : 'outline'}>{value === 'all' ? 'Todas' : value === 'incoming' ? 'Recibidas' : 'Enviadas'}</Button>)}</div></div>{connections.isPending && <p role="status">Cargando conexiones…</p>}{connections.isError && <p className="text-destructive" role="alert">{errorMessage(connections.error)}</p>}{connections.data?.items.length === 0 && <Card><CardContent className="p-8 text-center"><Users className="mx-auto size-8 text-muted-foreground" /><p className="mt-3 font-semibold">Aún no hay solicitudes</p></CardContent></Card>}<div className="grid gap-4 lg:grid-cols-2">{connections.data?.items.map((connection) => <ConnectionCard connection={connection} key={connection.id} onAction={(item, requestedAction) => action.mutate({ connection: item, action: requestedAction })} pending={action.isPending} />)}</div></section>
  </div>
}
