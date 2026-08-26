import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Check, CreditCard, LoaderCircle, ShieldCheck, TriangleAlert } from 'lucide-react'
import { useRef, useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'

import { ApiError } from '@/api/http-client'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { organizationApi } from '@/features/organizations/organization-api'
import { billingApi, billingCommandId, type SubscriptionPlan } from './billing-api'

function money(amount: number, currency: string) {
  return new Intl.NumberFormat('es-CL', {
    style: 'currency', currency, maximumFractionDigits: currency === 'CLP' ? 0 : 2,
  }).format(amount)
}

function date(value: string | null) {
  return value ? new Intl.DateTimeFormat('es-CL', { dateStyle: 'long' }).format(new Date(value)) : 'Sin fecha'
}

function message(error: unknown) {
  if (error instanceof ApiError) return error.problem.detail ?? error.problem.title
  return 'No pudimos confirmar la operación. Reintenta sin cambiar la solicitud.'
}

function PlanCard({ plan, current, onCheckout, pending }: {
  plan: SubscriptionPlan
  current: boolean
  onCheckout: (priceId: number) => void
  pending: boolean
}) {
  const price = plan.prices.find((item) => item.purchasable) ?? plan.prices[0]
  return <Card className={current ? 'border-primary' : ''}>
    <CardHeader><div className="flex items-center justify-between gap-2"><CardTitle>{plan.name}</CardTitle>{current && <span className="rounded-full bg-primary px-3 py-1 text-xs font-semibold text-primary-foreground">Plan actual</span>}</div><p className="text-sm text-muted-foreground">{plan.description}</p></CardHeader>
    <CardContent className="space-y-4">
      <p className="text-2xl font-bold">{price ? money(price.amount, price.currency) : 'Precio por definir'}{price && price.amount > 0 && <span className="text-sm font-normal text-muted-foreground"> / {price.interval === 'annual' ? 'año' : 'mes'}</span>}</p>
      <ul className="space-y-2 text-sm">{plan.features.filter((feature) => feature.enabled).map((feature) => <li className="flex gap-2" key={feature.code}><Check className="mt-0.5 size-4 text-primary" /><span>{feature.name}{feature.limitValue !== null ? `: ${feature.limitValue} ${feature.unit ?? ''}` : ''}</span></li>)}</ul>
      {!current && price?.purchasable && <Button disabled={pending} onClick={() => onCheckout(price.id)}>{pending ? <LoaderCircle className="size-4 animate-spin" /> : <CreditCard className="size-4" />}Probar checkout sandbox</Button>}
      {!current && !price?.purchasable && <p className="rounded-lg bg-muted p-3 text-sm">Aún no habilitado. Falta aprobar precio e identificador sandbox; no se cobrará nada desde esta pantalla.</p>}
    </CardContent>
  </Card>
}

export function PublicPricingPage() {
  const plans = useQuery({ queryKey: ['subscription-plans'], queryFn: ({ signal }) => billingApi.plans(signal) })
  return <div className="mx-auto max-w-7xl space-y-8 px-4 py-16 sm:px-6">
    <header className="text-center"><p className="text-sm font-bold uppercase tracking-[0.16em] text-primary">Planes</p><h1 className="mt-2 text-4xl font-bold">Parte gratis y crece con tu organización</h1><p className="mx-auto mt-3 max-w-3xl text-muted-foreground">Los planes pagados aún no están a la venta. Publicaremos el precio aprobado antes de habilitar cualquier checkout sandbox o real.</p></header>
    {plans.isError && <p className="rounded-lg bg-destructive/10 p-4 text-center text-destructive" role="alert">No pudimos cargar los planes.</p>}
    <section className="grid gap-4 lg:grid-cols-3">{plans.data?.map((plan) => <PlanCard current={plan.code === 'FREE'} key={plan.code} onCheckout={() => undefined} pending={false} plan={plan} />)}</section>
  </div>
}

export function SubscriptionWorkspacePage() {
  const [searchParams] = useSearchParams()
  const queryClient = useQueryClient()
  const organizations = useQuery({ queryKey: ['organizations'], queryFn: ({ signal }) => organizationApi.list(signal) })
  const organization = organizations.data?.[0]
  const plans = useQuery({ queryKey: ['subscription-plans'], queryFn: ({ signal }) => billingApi.plans(signal) })
  const current = useQuery({ queryKey: ['subscription', organization?.publicId], queryFn: ({ signal }) => billingApi.current(organization!.publicId, signal), enabled: Boolean(organization) })
  const usage = useQuery({ queryKey: ['subscription-usage', organization?.publicId], queryFn: ({ signal }) => billingApi.usage(organization!.publicId, signal), enabled: Boolean(organization) })
  const checkoutId = searchParams.get('checkout')
  const checkout = useQuery({ queryKey: ['subscription-checkout', organization?.publicId, checkoutId], queryFn: ({ signal }) => billingApi.checkout(organization!.publicId, checkoutId!, signal), enabled: Boolean(organization && checkoutId), refetchInterval: (query) => query.state.data?.status === 'pending' ? 5000 : false })
  const command = useRef<{ priceId: number; key: string } | null>(null)
  const [feedback, setFeedback] = useState<string | null>(null)
  const create = useMutation({
    mutationFn: (priceId: number) => {
      if (command.current?.priceId !== priceId) command.current = { priceId, key: billingCommandId() }
      return billingApi.createCheckout(organization!.publicId, priceId, command.current.key)
    },
    onSuccess: (result) => {
      command.current = null
      if (result.checkoutUrl) window.location.assign(result.checkoutUrl)
      else setFeedback('Checkout creado; espera la reconciliación del proveedor sandbox.')
    },
    onError: (error) => setFeedback(message(error)),
  })
  const lifecycle = useMutation({
    mutationFn: (resume: boolean) => resume
      ? billingApi.resume(organization!.publicId, current.data!.eTag!)
      : billingApi.cancel(organization!.publicId, current.data!.eTag!),
    onSuccess: async () => { await queryClient.invalidateQueries({ queryKey: ['subscription', organization?.publicId] }); setFeedback('Preferencia de renovación actualizada.') },
    onError: (error) => setFeedback(message(error)),
  })

  if (organizations.isPending) return <p role="status">Cargando organización…</p>
  if (!organization) return <Card><CardContent className="p-8 text-center"><h1 className="text-2xl font-bold">Primero crea tu organización</h1><Button asChild className="mt-4"><Link to="/onboarding">Comenzar</Link></Button></CardContent></Card>
  return <div className="space-y-8">
    <header><p className="text-sm font-bold uppercase tracking-[0.16em] text-primary">Planes y uso</p><h1 className="mt-1 text-3xl font-bold">Suscripción</h1><p className="mt-2 max-w-3xl text-muted-foreground">El acceso pertenece a la organización. En esta fase todos los cobros están deshabilitados o restringidos a sandbox.</p></header>
    {feedback && <p className="rounded-lg bg-accent p-3 text-sm" role="status">{feedback}</p>}
    {checkout.data && <Card><CardContent className="flex items-start gap-3 p-5"><ShieldCheck className="size-5 text-primary" /><div><p className="font-semibold">Checkout {checkout.data.status === 'completed' ? 'confirmado' : 'en verificación'}</p><p className="text-sm text-muted-foreground">El retorno del navegador nunca activa el plan por sí solo. Estado autoritativo: {checkout.data.status}.</p></div></CardContent></Card>}
    {current.data && <Card><CardHeader><CardTitle>{current.data.planName}</CardTitle></CardHeader><CardContent className="space-y-4"><div className="grid gap-3 text-sm sm:grid-cols-3"><div><p className="text-muted-foreground">Estado</p><p className="font-semibold">{current.data.status}</p></div><div><p className="text-muted-foreground">Período</p><p className="font-semibold">{date(current.data.currentPeriodEndUtc)}</p></div><div><p className="text-muted-foreground">Renovación</p><p className="font-semibold">{current.data.cancelAtPeriodEnd ? 'Se cancelará al cierre' : 'Sin cancelación programada'}</p></div></div>{organization.membershipRole === 'admin' && current.data.eTag && !current.data.freeFallback && <Button disabled={lifecycle.isPending} onClick={() => lifecycle.mutate(current.data!.cancelAtPeriodEnd)} variant="outline">{current.data.cancelAtPeriodEnd ? 'Reanudar renovación' : 'Cancelar al fin del período'}</Button>}</CardContent></Card>}
    <section className="grid gap-4 lg:grid-cols-3">{plans.data?.map((plan) => <PlanCard current={current.data?.planCode === plan.code} key={plan.code} onCheckout={(id) => create.mutate(id)} pending={create.isPending} plan={plan} />)}</section>
    <section className="space-y-3"><h2 className="text-2xl font-bold">Uso y límites</h2>{usage.data?.map((item) => <Card key={item.featureCode}><CardContent className="flex items-center justify-between gap-4 p-4"><div><p className="font-semibold">{item.featureName}</p><p className="text-sm text-muted-foreground">{item.enabled ? 'Habilitado' : 'No incluido en el plan actual'}</p></div><p className="text-sm font-semibold">{item.usageValue}{item.limitValue !== null ? ` / ${item.limitValue}` : ''} {item.unit ?? ''}</p></CardContent></Card>)}</section>
  </div>
}

export function AdminBillingPage() {
  const [query, setQuery] = useState('')
  const [submitted, setSubmitted] = useState('')
  const dashboard = useQuery({ queryKey: ['admin-billing-dashboard'], queryFn: ({ signal }) => billingApi.adminDashboard(signal) })
  const subscriptions = useQuery({ queryKey: ['admin-subscriptions', submitted], queryFn: ({ signal }) => billingApi.adminList(1, submitted, '', signal) })
  return <div className="space-y-8"><header><p className="text-sm font-bold uppercase tracking-[0.16em] text-primary">Administración</p><h1 className="mt-1 text-3xl font-bold">Suscripciones</h1><p className="mt-2 text-muted-foreground">Vista operativa sin datos de tarjeta, secretos ni payloads del proveedor.</p></header>
    <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-5">{dashboard.data && [[dashboard.data.activeOrganizations, 'ONG activas'], [dashboard.data.activePaidSubscriptions, 'Pagadas activas'], [dashboard.data.pastDueSubscriptions, 'En mora'], [dashboard.data.pendingCheckouts, 'Checkouts pendientes'], [dashboard.data.failedWebhookEvents, 'Webhooks fallidos']].map(([value, label]) => <Card key={label}><CardContent className="p-4"><p className="text-2xl font-bold">{value}</p><p className="text-sm text-muted-foreground">{label}</p></CardContent></Card>)}</div>
    {dashboard.data && dashboard.data.failedWebhookEvents > 0 && <p className="flex gap-2 rounded-lg bg-destructive/10 p-3 text-sm text-destructive"><TriangleAlert className="size-4" />Hay eventos que requieren reconciliación o soporte.</p>}
    <form className="flex max-w-xl gap-2" onSubmit={(event) => { event.preventDefault(); setSubmitted(query.trim()) }}><Input aria-label="Buscar organización" maxLength={200} onChange={(event) => setQuery(event.target.value)} placeholder="Buscar organización" value={query} /><Button type="submit">Buscar</Button></form>
    <div className="space-y-3">{subscriptions.data?.items.map((item) => <Card key={item.organizationId}><CardContent className="flex flex-wrap items-center justify-between gap-3 p-4"><div><p className="font-semibold">{item.organizationName}</p><p className="text-sm text-muted-foreground">{item.planName} · {item.status}</p></div><p className="text-sm">{item.currentPeriodEndUtc ? `Hasta ${date(item.currentPeriodEndUtc)}` : 'Plan Free'}</p></CardContent></Card>)}</div>
  </div>
}
