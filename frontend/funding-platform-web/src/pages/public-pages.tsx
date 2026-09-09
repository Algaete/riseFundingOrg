import { ArrowRight, Handshake, SearchCheck, Target } from 'lucide-react'
import type { ReactNode } from 'react'
import { Link } from 'react-router-dom'
import { useTranslation } from 'react-i18next'

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
    key: 'projects',
    icon: Target,
  },
  {
    key: 'funding',
    icon: SearchCheck,
  },
  {
    key: 'partners',
    icon: Handshake,
  },
] as const

export function HomePage() {
  const { t } = useTranslation()
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
            {t('home.eyebrow')}
          </p>
          <h1 className="text-4xl font-bold tracking-tight sm:text-6xl">
            {t('home.title')}
          </h1>
          <p className="mx-auto mt-6 max-w-2xl text-lg leading-8 text-muted-foreground">
            {t('home.description')}
          </p>
          <div className="mt-8 flex flex-col justify-center gap-3 sm:flex-row">
            <Button size="default" asChild>
              <Link to="/funding">
                {t('actions.findFunding')} <ArrowRight className="size-4" />
              </Link>
            </Button>
            <Button variant="outline" asChild>
              <Link to={isAuthenticated ? '/projects' : '/register'}>{t('actions.publishProject')}</Link>
            </Button>
          </div>
          {isAuthenticated && (
            <Link className="mt-5 inline-flex text-sm font-semibold text-primary hover:underline" to={workspaceUrl}>
              {t('actions.workspace')}
            </Link>
          )}
        </div>
      </section>
      <section className="mx-auto grid max-w-7xl gap-4 px-4 pb-20 sm:px-6 md:grid-cols-3">
        {benefits.map(({ key, icon: Icon }) => (
          <Card key={key}>
            <CardHeader>
              <span className="mb-2 grid size-10 place-items-center rounded-xl bg-accent text-accent-foreground">
                <Icon className="size-5" aria-hidden="true" />
              </span>
              <CardTitle>{t(`home.benefits.${key}.title`)}</CardTitle>
            </CardHeader>
            <CardContent className="text-sm leading-6 text-muted-foreground">
              {t(`home.benefits.${key}.description`)}
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
  const { t } = useTranslation()
  return (
    <AuthPanel
      title={t('auth.pages.login.title')}
      description={t('auth.pages.login.description')}
    >
      <LoginForm />
      <div className="mt-4 flex flex-wrap justify-between gap-3 text-sm">
        <Link className="text-primary hover:underline" to="/forgot-password">
          {t('auth.actions.forgotPassword')}
        </Link>
        <Link className="text-primary hover:underline" to="/register">
          {t('actions.createAccount')}
        </Link>
      </div>
    </AuthPanel>
  )
}

export function ExternalAuthenticationCallbackPage() {
  const { t } = useTranslation()
  return <AuthPanel title={t('auth.pages.external.title')} description={t('auth.pages.external.description')}><ExternalAuthenticationCallback /></AuthPanel>
}

export function PricingPage() {
  return <PublicPricingPage />
}

export function RegisterPage() {
  const { t } = useTranslation()
  return (
    <AuthPanel
      title={t('auth.pages.register.title')}
      description={t('auth.pages.register.description')}
    ><RegisterForm /></AuthPanel>
  )
}

export function VerifyEmailPage() {
  const { t } = useTranslation()
  return (
    <AuthPanel
      title={t('auth.pages.verify.title')}
      description={t('auth.pages.verify.description')}
    ><VerifyEmailForm /></AuthPanel>
  )
}

export function ForgotPasswordPage() {
  const { t } = useTranslation()
  return (
    <AuthPanel
      title={t('auth.pages.forgot.title')}
      description={t('auth.pages.forgot.description')}
    ><ForgotPasswordForm /></AuthPanel>
  )
}

export function ResetPasswordPage() {
  const { t } = useTranslation()
  return (
    <AuthPanel
      title={t('auth.pages.reset.title')}
      description={t('auth.pages.reset.description')}
    ><ResetPasswordForm /></AuthPanel>
  )
}

export function MfaChallengePage() {
  const { t } = useTranslation()
  return (
    <AuthPanel
      title={t('auth.pages.challenge.title')}
      description={t('auth.pages.challenge.description')}
    ><MfaChallengeForm /></AuthPanel>
  )
}

export function MfaSetupPage() {
  const { t } = useTranslation()
  return (
    <AuthPanel
      title={t('auth.pages.setup.title')}
      description={t('auth.pages.setup.description')}
    ><MfaSetupForm /></AuthPanel>
  )
}

export function NotFoundPage() {
  const { t } = useTranslation()
  return (
    <div className="grid min-h-screen place-items-center px-4 text-center">
      <div>
        <p className="text-sm font-bold text-primary">404</p>
        <h1 className="mt-2 text-3xl font-bold">{t('status.notFound')}</h1>
        <Button className="mt-6" asChild>
          <Link to="/">{t('actions.backToHome')}</Link>
        </Button>
      </div>
    </div>
  )
}
