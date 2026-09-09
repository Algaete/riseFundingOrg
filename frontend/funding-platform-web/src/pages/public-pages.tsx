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
