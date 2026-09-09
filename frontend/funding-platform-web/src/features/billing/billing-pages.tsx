import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Check, CreditCard, LoaderCircle, ShieldCheck, TriangleAlert } from 'lucide-react'
import { useRef, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Link, useSearchParams } from 'react-router-dom'

import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { organizationApi } from '@/features/organizations/organization-api'
import { billingDate, billingMoney, featureName, planDescription, usageAmount } from '@/i18n/billing-messages'
import { checkoutStatusLabel, subscriptionStatusLabel, trackingErrorMessage, type TrackingFeedback } from '@/i18n/tracking-messages'
import { workspaceLocale } from '@/i18n/workspace-messages'
import { billingApi, billingCommandId, type SubscriptionPlan } from './billing-api'

// Administration remains in Spanish until I18N-05.
function date(value: string | null) {
  return value ? new Intl.DateTimeFormat('es-CL', { dateStyle: 'long' }).format(new Date(value)) : 'Sin fecha'
}

function ReadState({ pending, error, loading, failed, onRetry }: {
  pending: boolean; error: boolean; loading: string; failed: string; onRetry: () => void
}) {
  const { t } = useTranslation()
  if (pending) return <p role="status">{loading}</p>
  if (!error) return null
  return <div className="space-y-3 rounded-lg bg-destructive/10 p-4 text-foreground" role="alert">
    <p>{failed}</p><Button onClick={onRetry} variant="outline">{t('tracking.retry')}</Button>
  </div>
}

function PlanCard({ plan, current, onCheckout, pending, publicView = false, canCheckout = true }: {
  plan: SubscriptionPlan
  current: boolean
  onCheckout?: (priceId: number) => void
  pending: boolean
  publicView?: boolean
  canCheckout?: boolean
}) {
  const { t } = useTranslation()
  const price = plan.prices.find((item) => item.purchasable) ?? plan.prices[0]
  return <Card className={current ? 'min-w-0 border-primary' : 'min-w-0'}>
    <CardHeader><div className="flex flex-wrap items-center justify-between gap-2"><CardTitle className="break-words">{plan.name}</CardTitle>{current && <span className="rounded-full bg-primary px-3 py-1 text-xs font-semibold text-primary-foreground">{t(publicView ? 'billing.free' : 'billing.current')}</span>}</div><p className="break-words text-sm text-muted-foreground">{planDescription(plan.code, plan.description)}</p></CardHeader>
    <CardContent className="space-y-4">
      <p className="break-words text-2xl font-bold">{price ? billingMoney(price.amount, price.currency) : t('billing.noPrice')}{price && price.amount > 0 && <span className="text-sm font-normal text-muted-foreground"> / {t(price.interval === 'annual' ? 'billing.year' : 'billing.month')}</span>}</p>
      <ul className="space-y-2 text-sm">{plan.features.filter((feature) => feature.enabled).map((feature) => <li className="flex gap-2" key={feature.code}><Check className="mt-0.5 size-4 shrink-0 text-primary" /><span className="min-w-0 break-words">{featureName(feature.code, feature.name)}{feature.limitValue !== null ? `: ${usageAmount(feature.limitValue, feature.unit)}` : ''}</span></li>)}</ul>
      {!current && price?.purchasable && (publicView
        ? <Button asChild><Link to="/subscription">{t('billing.manage')}</Link></Button>
        : <Button disabled={pending || !canCheckout} onClick={() => onCheckout?.(price.id)}>{pending ? <LoaderCircle className="size-4 animate-spin" /> : <CreditCard className="size-4" />}{t('billing.checkout')}</Button>)}
      {!current && !price?.purchasable && <p className="rounded-lg bg-muted p-3 text-sm">{t('billing.notEnabled')}</p>}
    </CardContent>
  </Card>
}

export function PublicPricingPage() {
  const { t } = useTranslation()
  const plans = useQuery({ queryKey: ['subscription-plans'], queryFn: ({ signal }) => billingApi.plans(signal) })
  return <div className="mx-auto max-w-7xl space-y-8 px-4 py-16 sm:px-6">
    <header className="text-center"><p className="text-sm font-bold uppercase tracking-[0.16em] text-primary">{t('billing.eyebrow')}</p><h1 className="mt-2 text-4xl font-bold">{t('billing.title')}</h1><p className="mx-auto mt-3 max-w-3xl text-muted-foreground">{t('billing.publicHelp')}</p></header>
    <ReadState pending={plans.isPending} error={plans.isError} loading={t('billing.plansLoading')} failed={t('billing.plansFailed')} onRetry={() => void plans.refetch()} />
    {plans.data?.length === 0 && <p>{t('billing.plansEmpty')}</p>}
    <section className="grid gap-4 lg:grid-cols-3">{plans.data?.map((plan) => <PlanCard current={plan.code === 'FREE'} key={plan.code} pending={false} plan={plan} publicView />)}</section>
  </div>
}

export function SubscriptionWorkspacePage() {
  const { t } = useTranslation()
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
  const [feedback, setFeedback] = useState<TrackingFeedback | null>(null)
  const create = useMutation({
    mutationFn: (priceId: number) => {
      if (command.current?.priceId !== priceId) command.current = { priceId, key: billingCommandId() }
      return billingApi.createCheckout(organization!.publicId, priceId, command.current.key)
    },
    onSuccess: (result) => {
      command.current = null
      if (result.checkoutUrl) window.location.assign(result.checkoutUrl)
      else setFeedback({ key: 'billing.checkoutCreated' })
    },
    onError: (error) => setFeedback({ error }),
  })
  const lifecycle = useMutation({
    mutationFn: (resume: boolean) => resume
      ? billingApi.resume(organization!.publicId, current.data!.eTag!)
      : billingApi.cancel(organization!.publicId, current.data!.eTag!),
    onSuccess: async () => { await queryClient.invalidateQueries({ queryKey: ['subscription', organization?.publicId] }); setFeedback({ key: 'billing.renewalUpdated' }) },
    onError: (error) => setFeedback({ error }),
  })

  if (organizations.isPending) return <p role="status">{t('tracking.organizationLoading')}</p>
  if (organizations.isError) return <ReadState pending={false} error loading="" failed={t('tracking.organizationFailed')} onRetry={() => void organizations.refetch()} />
  if (!organization) return <Card><CardContent className="p-8 text-center"><h1 className="text-2xl font-bold">{t('tracking.organizationRequired')}</h1><Button asChild className="mt-4"><Link to="/onboarding">{t('tracking.start')}</Link></Button></CardContent></Card>
  return <div className="space-y-8">
    <header><p className="text-sm font-bold uppercase tracking-[0.16em] text-primary">{t('billing.subscriptionEyebrow')}</p><h1 className="mt-1 text-3xl font-bold">{t('billing.subscriptionTitle')}</h1><p className="mt-2 max-w-3xl text-muted-foreground">{t('billing.help')}</p></header>
    {feedback && <p className="rounded-lg bg-accent p-3 text-sm text-accent-foreground" role={'error' in feedback ? 'alert' : 'status'}>{'key' in feedback ? t(feedback.key) : trackingErrorMessage(feedback.error, 'billing', 'write')}</p>}
    {checkoutId && <ReadState pending={checkout.isPending} error={checkout.isError} loading={t('billing.checkoutLoading')} failed={t('billing.checkoutFailed')} onRetry={() => void checkout.refetch()} />}
    {checkout.data && <Card><CardContent className="flex items-start gap-3 p-5"><ShieldCheck className="size-5 shrink-0 text-primary" /><div><p className="font-semibold">{t('billing.checkoutStatus', { status: checkoutStatusLabel(checkout.data.status) })}</p><p className="text-sm text-muted-foreground">{t('billing.checkoutHelp', { status: checkoutStatusLabel(checkout.data.status) })}</p></div></CardContent></Card>}
    <ReadState pending={current.isPending} error={current.isError} loading={t('billing.currentLoading')} failed={t('billing.currentFailed')} onRetry={() => void current.refetch()} />
    {current.data && <Card><CardHeader><CardTitle>{current.data.planName}</CardTitle></CardHeader><CardContent className="space-y-4"><div className="grid gap-3 text-sm sm:grid-cols-3"><div><p className="text-muted-foreground">{t('tracking.status')}</p><p className="font-semibold">{subscriptionStatusLabel(current.data.status)}</p></div><div><p className="text-muted-foreground">{t('billing.period')}</p><p className="font-semibold">{billingDate(current.data.currentPeriodEndUtc)}</p></div><div><p className="text-muted-foreground">{t('billing.renewal')}</p><p className="font-semibold">{t(current.data.cancelAtPeriodEnd ? 'billing.cancelScheduled' : 'billing.noCancellation')}</p></div></div>{organization.membershipRole === 'admin' && current.data.eTag && !current.data.freeFallback && <Button disabled={lifecycle.isPending || current.isError} onClick={() => lifecycle.mutate(current.data!.cancelAtPeriodEnd)} variant="outline">{t(current.data.cancelAtPeriodEnd ? 'billing.resume' : 'billing.cancel')}</Button>}</CardContent></Card>}
    <ReadState pending={plans.isPending} error={plans.isError} loading={t('billing.plansLoading')} failed={t('billing.plansFailed')} onRetry={() => void plans.refetch()} />
    {plans.data?.length === 0 && <p>{t('billing.plansEmpty')}</p>}
    {organization.membershipRole !== 'admin' && <p className="text-sm text-muted-foreground">{t('billing.adminOnly')}</p>}
    <section className="grid gap-4 lg:grid-cols-3">{plans.data?.map((plan) => <PlanCard current={current.data?.planCode === plan.code} key={plan.code} onCheckout={(id) => create.mutate(id)} pending={create.isPending} canCheckout={organization.membershipRole === 'admin' && current.isSuccess} plan={plan} />)}</section>
    <section className="space-y-3"><h2 className="text-2xl font-bold">{t('billing.usage')}</h2>
      <ReadState pending={usage.isPending} error={usage.isError} loading={t('billing.usageLoading')} failed={t('billing.usageFailed')} onRetry={() => void usage.refetch()} />
      {usage.data?.length === 0 && <p>{t('billing.usageEmpty')}</p>}
      {usage.data?.map((item) => <Card key={item.featureCode}><CardContent className="flex flex-wrap items-center justify-between gap-4 p-4"><div><p className="font-semibold">{featureName(item.featureCode, item.featureName)}</p><p className="text-sm text-muted-foreground">{t(item.enabled ? 'billing.enabled' : 'billing.notIncluded')}</p></div><p className="text-sm font-semibold">{item.limitValue !== null ? `${item.usageValue.toLocaleString(workspaceLocale())} / ${usageAmount(item.limitValue, item.unit)}` : usageAmount(item.usageValue, item.unit)}</p></CardContent></Card>)}
    </section>
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
