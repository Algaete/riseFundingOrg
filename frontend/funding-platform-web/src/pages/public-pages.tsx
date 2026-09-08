import { ArrowRight, Handshake, SearchCheck, Target } from 'lucide-react'
import type { ReactNode } from 'react'
import { Link } from 'react-router-dom'

import { PublicPricingPage } from '@/features/billing/billing-pages'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import {
  ForgotPasswordForm,
  ExternalAuthenticationCallback,
  LoginForm,
  MfaChallengeForm,
  MfaSetupForm,
  RegisterForm,
  ResetPasswordForm,
  VerifyEmailForm,
} from '@/features/auth/auth-forms'
import { useAuth } from '@/features/auth/use-auth'

const benefits = [
  {
    title: 'Publica tu proyecto',
    description: 'Ordena su propósito, impacto y necesidades para presentarlo con claridad.',
    icon: Target,
  },
  {
    title: 'Encuentra financiamiento',
    description: 'Explora oportunidades y entiende por qué coinciden con tu proyecto.',
    icon: SearchCheck,
  },
  {
    title: 'Conecta con aliados',
    description: 'Descubre organizaciones y crea vínculos para colaborar o formar alianzas.',
    icon: Handshake,
  },
]

export function HomePage() {
  const auth = useAuth()
  const isAuthenticated = auth.status === 'authenticated' && auth.session !== null
  const workspaceUrl = auth.session?.user.roles.some(role => role === 'Admin' || role === 'SuperAdmin')
    ? '/admin'
    : '/dashboard'

  return (
    <>
      <section className="relative overflow-hidden px-4 py-20 sm:px-6 sm:py-28">
        <div className="absolute inset-x-0 top-0 -z-10 mx-auto h-72 max-w-3xl rounded-full bg-accent/70 blur-3xl" />
        <div className="mx-auto max-w-4xl text-center">
          <p className="mb-4 text-sm font-bold uppercase tracking-[0.2em] text-primary">
            Proyectos que encuentran oportunidades
          </p>
          <h1 className="text-4xl font-bold tracking-tight sm:text-6xl">
            Conecta tu proyecto con el financiamiento y los aliados que necesita
          </h1>
          <p className="mx-auto mt-6 max-w-2xl text-lg leading-8 text-muted-foreground">
            Publica tus iniciativas, descubre fondos compatibles y organiza
            alianzas para avanzar desde la idea hasta la ejecución.
          </p>
          <div className="mt-8 flex flex-col justify-center gap-3 sm:flex-row">
            <Button size="default" asChild>
              <Link to="/funding">
                Encontrar financiamiento <ArrowRight className="size-4" />
              </Link>
            </Button>
            <Button variant="outline" asChild>
              <Link to={isAuthenticated ? '/projects' : '/register'}>Publicar mi proyecto</Link>
            </Button>
          </div>
          {isAuthenticated && (
            <Link className="mt-5 inline-flex text-sm font-semibold text-primary hover:underline" to={workspaceUrl}>
              Ir a mi espacio
            </Link>
          )}
        </div>
      </section>
      <section className="mx-auto grid max-w-7xl gap-4 px-4 pb-20 sm:px-6 md:grid-cols-3">
        {benefits.map(({ title, description, icon: Icon }) => (
          <Card key={title}>
            <CardHeader>
              <span className="mb-2 grid size-10 place-items-center rounded-xl bg-accent text-accent-foreground">
                <Icon className="size-5" aria-hidden="true" />
              </span>
              <CardTitle>{title}</CardTitle>
            </CardHeader>
            <CardContent className="text-sm leading-6 text-muted-foreground">
              {description}
            </CardContent>
          </Card>
        ))}
      </section>
    </>
  )
}

function AuthPanel({
  title,
  description,
  children,
}: {
  title: string
  description: string
  children?: ReactNode
}) {
  return (
    <section className="mx-auto flex min-h-[calc(100vh-9rem)] max-w-md items-center px-4 py-12">
      <Card className="w-full">
        <CardHeader>
          <CardTitle className="text-2xl">{title}</CardTitle>
          <p className="text-sm leading-6 text-muted-foreground">{description}</p>
        </CardHeader>
        <CardContent>{children}</CardContent>
      </Card>
    </section>
  )
}

export function LoginPage() {
  return (
    <AuthPanel
      title="Bienvenido de vuelta"
      description="Accede al espacio de tu organización."
    >
      <LoginForm />
      <div className="mt-4 flex justify-between text-sm">
        <Link className="text-primary hover:underline" to="/forgot-password">
          Recuperar contraseña
        </Link>
        <Link className="text-primary hover:underline" to="/register">
          Crear cuenta
        </Link>
      </div>
    </AuthPanel>
  )
}

export function ExternalAuthenticationCallbackPage() {
  return <AuthPanel title="Acceso con Microsoft" description="Validamos una autorización de un solo uso."><ExternalAuthenticationCallback /></AuthPanel>
}

export function PricingPage() {
  return <PublicPricingPage />
}

export function RegisterPage() {
  return (
    <AuthPanel
      title="Crea tu cuenta"
      description="Usaremos tu correo para verificar la cuenta antes de permitir el acceso."
    ><RegisterForm /></AuthPanel>
  )
}

export function VerifyEmailPage() {
  return (
    <AuthPanel
      title="Verifica tu correo"
      description="Confirma el enlace temporal que recibiste por correo."
    ><VerifyEmailForm /></AuthPanel>
  )
}

export function ForgotPasswordPage() {
  return (
    <AuthPanel
      title="Recupera tu contraseña"
      description="Si la cuenta existe, enviaremos un enlace temporal sin revelar su estado."
    ><ForgotPasswordForm /></AuthPanel>
  )
}

export function ResetPasswordPage() {
  return (
    <AuthPanel
      title="Define una nueva contraseña"
      description="El enlace es de un solo uso y todas tus sesiones anteriores se cerrarán."
    ><ResetPasswordForm /></AuthPanel>
  )
}

export function MfaChallengePage() {
  return (
    <AuthPanel
      title="Verificación en dos pasos"
      description="Ingresa el código de tu autenticador o uno de recuperación."
    ><MfaChallengeForm /></AuthPanel>
  )
}

export function MfaSetupPage() {
  return (
    <AuthPanel
      title="Protege tu cuenta administrativa"
      description="MFA es obligatorio para administradores antes de acceder a la consola."
    ><MfaSetupForm /></AuthPanel>
  )
}

export function NotFoundPage() {
  return (
    <div className="grid min-h-screen place-items-center px-4 text-center">
      <div>
        <p className="text-sm font-bold text-primary">404</p>
        <h1 className="mt-2 text-3xl font-bold">Página no encontrada</h1>
        <Button className="mt-6" asChild>
          <Link to="/">Volver al inicio</Link>
        </Button>
      </div>
    </div>
  )
}
