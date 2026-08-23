import { PagePlaceholder } from '@/components/page-placeholder'
import { OrganizationWorkspacePage } from '@/features/organizations/organization-pages'
import { useMutation, useQuery } from '@tanstack/react-query'
import { authApi } from '@/features/auth/auth-api'
import { useAuth } from '@/features/auth/use-auth'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { useSearchParams } from 'react-router-dom'
import { Link } from 'react-router-dom'
import { Radar } from 'lucide-react'

export function OnboardingPage() {
  return <OrganizationWorkspacePage onboarding />
}

export function DashboardPage() {
  return (
    <PagePlaceholder
      title="Resumen"
      description="Tus oportunidades recomendadas, cierres próximos y actividad reciente."
    />
  )
}

export function RecommendedPage() {
  return (
    <PagePlaceholder
      title="Recomendados para ti"
      description="El ranking personalizado se activará en la fase de matching. El catálogo general ya está disponible para tu organización."
      eyebrow="Próxima fase · Matching"
    >
      <Card><CardContent className="flex flex-col items-start gap-4 p-6"><Radar className="size-8 text-primary" /><div><h2 className="text-lg font-bold">Revisa los concursos publicados</h2><p className="mt-1 text-sm text-muted-foreground">Mientras preparamos las recomendaciones, puedes explorar y filtrar todas las oportunidades disponibles.</p></div><Button asChild><Link to="/opportunities">Ver concursos disponibles</Link></Button></CardContent></Card>
    </PagePlaceholder>
  )
}

export function ApplicationsPage() {
  return (
    <PagePlaceholder
      title="Postulaciones"
      description="Seguimiento del avance y estado de cada postulación."
    />
  )
}

export function CalendarPage() {
  return (
    <PagePlaceholder
      title="Calendario"
      description="Fechas de cierre e hitos de postulaciones en una vista unificada."
    />
  )
}

export function AlertsPage() {
  return (
    <PagePlaceholder
      title="Alertas"
      description="Preferencias y registro de notificaciones relevantes."
    />
  )
}

export function OrganizationProfilePage() {
  return <OrganizationWorkspacePage />
}

export function AccountPage() {
  const auth = useAuth()
  const [searchParams] = useSearchParams()
  const providers = useQuery({ queryKey: ['external-auth-providers'], queryFn: authApi.externalProviders, retry: false })
  const entraEnabled = providers.data?.some(provider => provider.code === 'entra' && provider.enabled) ?? false
  const link = useMutation({ mutationFn: authApi.createExternalLinkIntent, onSuccess: result => window.location.assign(result.startUrl) })
  const linkStatus = searchParams.get('sso')
  return <div className="space-y-6"><div><h1 className="text-3xl font-bold">Mi cuenta</h1><p className="mt-2 text-muted-foreground">Seguridad y métodos de acceso.</p></div><Card><CardHeader><CardTitle>Inicio de sesión único</CardTitle></CardHeader><CardContent className="space-y-3">{linkStatus === 'linked' && <p role="status" className="rounded-lg bg-accent p-3 text-sm">Tu cuenta Microsoft quedó vinculada correctamente.</p>}{linkStatus === 'already_linked' && <p role="status" className="rounded-lg bg-accent p-3 text-sm">Esa identidad Microsoft ya estaba vinculada a esta cuenta.</p>}{linkStatus === 'link_failed' && <p role="alert" className="rounded-lg bg-destructive/10 p-3 text-sm text-destructive">No fue posible vincular Microsoft. Verifica en el selector si elegiste la cuenta personal o laboral correcta.</p>}{link.isError && <p role="alert" className="rounded-lg bg-destructive/10 p-3 text-sm text-destructive">No fue posible preparar la vinculación. Actualiza tu sesión e intenta nuevamente.</p>}<p className="rounded-lg border p-3 text-sm">Cuenta local activa: <strong>{auth.session?.user.email}</strong></p><p className="text-sm text-muted-foreground">Microsoft mostrará el selector de cuentas. Elige la identidad exacta que deseas asociar a la cuenta local indicada arriba; una cuenta personal y una laboral con el mismo correo son identidades distintas.</p>{entraEnabled ? <Button disabled={link.isPending} onClick={() => link.mutate()} variant="outline">{link.isPending ? 'Preparando…' : `Vincular Microsoft a ${auth.session?.user.email ?? 'esta cuenta'}`}</Button> : <p className="text-sm font-medium">Microsoft SSO está preparado, pendiente de configurar en Entra.</p>}</CardContent></Card></div>
}

export function SubscriptionPage() {
  return (
    <PagePlaceholder
      title="Suscripción"
      description="Estado del plan, límites de uso e historial de facturación."
    />
  )
}
