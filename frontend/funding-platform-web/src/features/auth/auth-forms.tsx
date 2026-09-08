import { zodResolver } from '@hookform/resolvers/zod'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { QRCodeSVG } from 'qrcode.react'
import { useEffect, useRef, useState } from 'react'
import { useForm } from 'react-hook-form'
import { Link, useLocation, useNavigate, useSearchParams } from 'react-router-dom'
import type { z } from 'zod'
import { Trans, useTranslation } from 'react-i18next'

import { getAuthErrorKey, getExternalNoticeKey, type AuthOperation, type AuthErrorKey } from '@/features/auth/auth-feedback'
import { codeSchema, emailSchema, loginSchema, mfaSetupCodeSchema, registerSchema, resetSchema, type AuthValidationKey } from '@/features/auth/auth-validation'
import { getExternalAuthBaseUrl } from '@/api/api-config'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { authApi } from '@/features/auth/auth-api'
import {
  clearAuthSession,
  getAuthState,
  hasLimitedAccessToken,
  setAuthenticatedSession,
  setLimitedAccessToken,
} from '@/features/auth/auth-session'
import { useAuth } from '@/features/auth/use-auth'
import {
  getSafeAuthenticatedPath,
  resolvePostAuthenticationPath,
} from '@/features/auth/post-auth-navigation'

const registrationAcceptedKey = 'funding-platform-registration-accepted'
const requestErrorClassName = 'rounded-lg border border-destructive/50 bg-destructive/10 p-3 text-sm text-foreground'

function hasAcceptedRegistration() {
  return window.sessionStorage.getItem(registrationAcceptedKey) === 'true'
}

function FieldError({ message, id }: { message?: string; id?: string }) {
  const { t } = useTranslation()
  return message ? (
    <p role="alert" className="text-sm text-destructive" id={id}>{t(message as AuthValidationKey)}</p>
  ) : null
}

function RequestError({ error, operation, messageKey }: { error?: unknown; operation?: AuthOperation; messageKey?: AuthErrorKey }) {
  const { t } = useTranslation()
  if (!error && !messageKey) return null
  return <p role="alert" className={requestErrorClassName}>{t(messageKey ?? getAuthErrorKey(error, operation))}</p>
}

function SuccessMessage({ message }: { message: string }) {
  return <p role="status" className="rounded-lg bg-accent p-3 text-sm">{message}</p>
}

type LoginValues = z.infer<typeof loginSchema>

export function LoginForm() {
  const { t } = useTranslation()
  const navigate = useNavigate()
  const location = useLocation()
  const auth = useAuth()
  const [searchParams] = useSearchParams()
  const requestedPath = getSafeAuthenticatedPath(
    (location.state as { from?: string } | null)?.from,
  )
  const externalNoticeKey = getExternalNoticeKey(searchParams.get('sso'))
  const externalAuthenticationMessage = externalNoticeKey ? t(externalNoticeKey) : undefined
  const [logoutIncomplete] = useState(() =>
    searchParams.get('logout') === 'incomplete' ||
    window.sessionStorage.getItem('funding-platform-logout-incomplete') === 'true',
  )
  useEffect(() => {
    if (logoutIncomplete) {
      window.sessionStorage.removeItem('funding-platform-logout-incomplete')
    }
  }, [logoutIncomplete])
  const form = useForm<LoginValues>({
    resolver: zodResolver(loginSchema),
    defaultValues: { email: '', password: '' },
  })
  const providers = useQuery({
    queryKey: ['external-auth-providers'],
    queryFn: authApi.externalProviders,
    staleTime: 5 * 60 * 1000,
    retry: false,
  })
  const entraEnabled = providers.data?.some(provider => provider.code === 'entra' && provider.enabled) ?? false
  const mutation = useMutation({
    mutationFn: authApi.login,
    onSuccess: async (response) => {
      if (response.status === 'authenticated') {
        const session = setAuthenticatedSession(response)
        const destination = await resolvePostAuthenticationPath(
          requestedPath,
          session.user.roles,
        )
        void navigate(destination, { replace: true })
        return
      }
      if (response.status === 'mfa_required' && response.mfaChallengeToken) {
        void navigate('/mfa', {
          replace: true,
          state: { challengeToken: response.mfaChallengeToken, returnUrl: requestedPath },
        })
        return
      }
      if (response.status === 'mfa_setup_required' && response.mfaSetupToken) {
        setLimitedAccessToken(response.mfaSetupToken)
        void navigate('/mfa/setup', { replace: true })
      }
    },
  })

  if (auth.session) {
    return (
      <div className="space-y-4">
        {externalAuthenticationMessage && (
          <p role="alert" className={requestErrorClassName}>
            {externalAuthenticationMessage}
          </p>
        )}
        <p role="status" className="rounded-lg bg-accent p-3 text-sm">
          <Trans i18nKey="auth.notices.existingSession" components={{ email: <strong className="break-all">{auth.session.user.email}</strong> }} />
        </p>
        <Button asChild className="w-full"><Link to="/dashboard">{t('auth.actions.continueSession')}</Link></Button>
      </div>
    )
  }

  return (
    <div className="space-y-4">
      {logoutIncomplete && (
        <p role="alert" className={requestErrorClassName}>
          {t('auth.notices.logoutIncomplete')}
        </p>
      )}
      {externalAuthenticationMessage && (
        <p role="alert" className={requestErrorClassName}>
          {externalAuthenticationMessage}
        </p>
      )}
      {entraEnabled && <>
        <Button className="w-full" variant="outline" asChild>
          <a href={`${getExternalAuthBaseUrl()}/auth/external/entra/start?returnUrl=${encodeURIComponent(requestedPath)}`}>
            {t('auth.actions.microsoft')}
          </a>
        </Button>
        <div className="flex items-center gap-3 text-xs uppercase text-muted-foreground"><span className="h-px flex-1 bg-border" /><span>{t('auth.actions.emailAlternative')}</span><span className="h-px flex-1 bg-border" /></div>
      </>}
      <form className="space-y-4" noValidate onSubmit={form.handleSubmit((values) => mutation.mutate(values))}>
      <div className="space-y-2">
        <label className="text-sm font-medium" htmlFor="login-email">{t('auth.fields.emailAddress')}</label>
        <Input aria-describedby={form.formState.errors.email ? 'login-email-error' : undefined} id="login-email" type="email" autoComplete="email" aria-invalid={Boolean(form.formState.errors.email)} {...form.register('email')} />
        <FieldError id="login-email-error" message={form.formState.errors.email?.message} />
      </div>
      <div className="space-y-2">
        <label className="text-sm font-medium" htmlFor="login-password">{t('auth.fields.password')}</label>
        <Input aria-describedby={form.formState.errors.password ? 'login-password-error' : undefined} id="login-password" type="password" autoComplete="current-password" aria-invalid={Boolean(form.formState.errors.password)} {...form.register('password')} />
        <FieldError id="login-password-error" message={form.formState.errors.password?.message} />
      </div>
      <RequestError operation="login" error={mutation.error} />
      <Button type="submit" className="w-full" disabled={mutation.isPending}>
        {mutation.isPending ? t('auth.actions.signingIn') : t('actions.signIn')}
      </Button>
      </form>
    </div>
  )
}

export function ExternalAuthenticationCallback() {
  const { t } = useTranslation()
  const [searchParams] = useSearchParams()
  const navigate = useNavigate()
  const started = useRef(false)
  const code = searchParams.get('code') ?? ''
  const returnUrl = getSafeAuthenticatedPath(searchParams.get('returnUrl'))
  const exchange = useMutation({
    mutationFn: () => authApi.exchangeExternalHandoff(code),
    onSuccess: async (response) => {
      if (response.status === 'authenticated') {
        const session = setAuthenticatedSession(response)
        const destination = await resolvePostAuthenticationPath(
          returnUrl,
          session.user.roles,
        )
        void navigate(destination, { replace: true })
      } else if (response.status === 'mfa_required' && response.mfaChallengeToken) {
        void navigate('/mfa', { replace: true, state: { challengeToken: response.mfaChallengeToken, returnUrl } })
      } else if (response.status === 'mfa_setup_required' && response.mfaSetupToken) {
        setLimitedAccessToken(response.mfaSetupToken)
        void navigate('/mfa/setup', { replace: true })
      }
    },
  })
  useEffect(() => {
    if (!started.current) {
      started.current = true
      // The callback exchange is the only operation allowed to rotate the
      // refresh cookie on this page. Never race it with session bootstrap.
      if (getAuthState().status === 'initializing') clearAuthSession()
      if (code) exchange.mutate()
    }
  }, [code, exchange])
  if (!code) return <div className="space-y-4"><RequestError messageKey="auth.errors.invalidHandoff" /><Button asChild className="w-full" variant="outline"><Link to="/login">{t('auth.actions.backToSignIn')}</Link></Button></div>
  return <div className="space-y-4">{!exchange.isError && <p role="status" className="text-sm">{t('auth.status.externalPending')}</p>}<RequestError operation="external" error={exchange.error} />{exchange.isError && <Button asChild className="w-full" variant="outline"><Link to="/login">{t('auth.actions.backToSignIn')}</Link></Button>}</div>
}

type RegisterValues = z.infer<typeof registerSchema>

export function RegisterForm() {
  const { t } = useTranslation()
  const [accepted, setAccepted] = useState(hasAcceptedRegistration)
  const submissionLocked = useRef(accepted)
  const form = useForm<RegisterValues>({
    resolver: zodResolver(registerSchema),
    defaultValues: { displayName: '', email: '', password: '', confirmPassword: '' },
  })
  const mutation = useMutation({
    mutationFn: (values: RegisterValues) => authApi.register({
      displayName: values.displayName,
      email: values.email,
      password: values.password,
      preferredLocale: 'es-CL',
    }),
    onSuccess: () => {
      window.sessionStorage.setItem(registrationAcceptedKey, 'true')
      setAccepted(true)
    },
    onError: () => {
      submissionLocked.current = false
    },
  })

  if (accepted) {
    return <div className="space-y-4"><SuccessMessage message={t('auth.notices.registrationAccepted')} /><p className="text-sm text-muted-foreground">{t('auth.notices.registrationHelp')}</p><Button className="w-full" variant="outline" asChild><Link to="/login">{t('auth.actions.goToSignIn')}</Link></Button></div>
  }

  const submit = form.handleSubmit((values) => {
    if (submissionLocked.current) return
    submissionLocked.current = true
    mutation.mutate(values)
  })

  return (
    <form className="space-y-4" noValidate onSubmit={submit}>
      <p className="text-xs text-muted-foreground"><span aria-hidden="true">*</span> {t('auth.fields.required')}</p>
      <div className="space-y-2"><label className="text-sm font-medium" htmlFor="register-name">{t('auth.fields.name')} <span aria-hidden="true" className="text-destructive">*</span></label><Input aria-describedby={form.formState.errors.displayName ? 'register-name-error' : undefined} aria-invalid={Boolean(form.formState.errors.displayName)} id="register-name" autoComplete="name" required {...form.register('displayName')} /><FieldError id="register-name-error" message={form.formState.errors.displayName?.message} /></div>
      <div className="space-y-2"><label className="text-sm font-medium" htmlFor="register-email">{t('auth.fields.email')} <span aria-hidden="true" className="text-destructive">*</span></label><Input aria-describedby={form.formState.errors.email ? 'register-email-error' : undefined} aria-invalid={Boolean(form.formState.errors.email)} id="register-email" type="email" autoComplete="email" required {...form.register('email')} /><FieldError id="register-email-error" message={form.formState.errors.email?.message} /></div>
      <div className="space-y-2"><label className="text-sm font-medium" htmlFor="register-password">{t('auth.fields.password')} <span aria-hidden="true" className="text-destructive">*</span></label><Input aria-describedby={form.formState.errors.password ? 'register-password-error' : undefined} aria-invalid={Boolean(form.formState.errors.password)} id="register-password" type="password" autoComplete="new-password" required {...form.register('password')} /><FieldError id="register-password-error" message={form.formState.errors.password?.message} /></div>
      <div className="space-y-2"><label className="text-sm font-medium" htmlFor="register-confirm">{t('auth.fields.confirmPassword')} <span aria-hidden="true" className="text-destructive">*</span></label><Input aria-describedby={form.formState.errors.confirmPassword ? 'register-confirm-error' : undefined} aria-invalid={Boolean(form.formState.errors.confirmPassword)} id="register-confirm" type="password" autoComplete="new-password" required {...form.register('confirmPassword')} /><FieldError id="register-confirm-error" message={form.formState.errors.confirmPassword?.message} /></div>
      <RequestError operation="register" error={mutation.error} />
      <Button className="w-full" type="submit" disabled={mutation.isPending || submissionLocked.current}>{mutation.isPending ? t('auth.actions.creating') : t('actions.createAccount')}</Button>
    </form>
  )
}

export function ForgotPasswordForm() {
  const { t } = useTranslation()
  const form = useForm<z.infer<typeof emailSchema>>({ resolver: zodResolver(emailSchema), defaultValues: { email: '' } })
  const mutation = useMutation({ mutationFn: ({ email }: { email: string }) => authApi.forgotPassword(email) })
  return <form className="space-y-4" noValidate onSubmit={form.handleSubmit((values) => mutation.mutate(values))}>
    <div className="space-y-2"><label className="text-sm font-medium" htmlFor="forgot-email">{t('auth.fields.email')}</label><Input aria-describedby={form.formState.errors.email ? 'forgot-email-error' : undefined} aria-invalid={Boolean(form.formState.errors.email)} id="forgot-email" type="email" autoComplete="email" {...form.register('email')} /><FieldError id="forgot-email-error" message={form.formState.errors.email?.message} /></div>
    {mutation.data && <SuccessMessage message={t('auth.notices.recoveryAccepted')} />}<RequestError operation="forgot" error={mutation.error} />
    <Button className="w-full" type="submit" disabled={mutation.isPending || Boolean(mutation.data)}>{mutation.isPending ? t('auth.actions.sending') : mutation.data ? t('auth.actions.linkSent') : t('auth.actions.sendLink')}</Button>
  </form>
}

export function VerifyEmailForm() {
  const { t } = useTranslation()
  const [searchParams] = useSearchParams()
  const token = searchParams.get('token') ?? ''
  const mutation = useMutation({ mutationFn: () => authApi.verifyEmail(token) })
  if (!token) return <RequestError messageKey="auth.errors.missingVerifyToken" />
  return <div className="space-y-4">{mutation.data && <SuccessMessage message={t('auth.notices.emailVerified')} />}<RequestError operation="verify" error={mutation.error} /><Button className="w-full" onClick={() => mutation.mutate()} disabled={mutation.isPending || Boolean(mutation.data)}>{mutation.isPending ? t('auth.actions.verifying') : mutation.data ? t('auth.actions.emailVerified') : t('auth.actions.verifyEmail')}</Button>{mutation.data && <Button className="w-full" variant="outline" asChild><Link to="/login">{t('auth.actions.signIn')}</Link></Button>}</div>
}

export function ResetPasswordForm() {
  const { t } = useTranslation()
  const [searchParams] = useSearchParams()
  const token = searchParams.get('token') ?? ''
  const form = useForm<z.infer<typeof resetSchema>>({ resolver: zodResolver(resetSchema), defaultValues: { password: '', confirmPassword: '' } })
  const mutation = useMutation({ mutationFn: ({ password }: z.infer<typeof resetSchema>) => authApi.resetPassword(token, password) })
  if (!token) return <RequestError messageKey="auth.errors.missingResetToken" />
  return <form className="space-y-4" noValidate onSubmit={form.handleSubmit((values) => mutation.mutate(values))}>
    <div className="space-y-2"><label className="text-sm font-medium" htmlFor="reset-password">{t('auth.fields.newPassword')}</label><Input aria-describedby={form.formState.errors.password ? 'reset-password-error' : undefined} aria-invalid={Boolean(form.formState.errors.password)} id="reset-password" type="password" autoComplete="new-password" {...form.register('password')} /><FieldError id="reset-password-error" message={form.formState.errors.password?.message} /></div>
    <div className="space-y-2"><label className="text-sm font-medium" htmlFor="reset-confirm">{t('auth.fields.confirmPassword')}</label><Input aria-describedby={form.formState.errors.confirmPassword ? 'reset-confirm-error' : undefined} aria-invalid={Boolean(form.formState.errors.confirmPassword)} id="reset-confirm" type="password" autoComplete="new-password" {...form.register('confirmPassword')} /><FieldError id="reset-confirm-error" message={form.formState.errors.confirmPassword?.message} /></div>
    {mutation.data && <SuccessMessage message={t('auth.notices.passwordUpdated')} />}<RequestError operation="reset" error={mutation.error} />
    <Button className="w-full" type="submit" disabled={mutation.isPending || Boolean(mutation.data)}>{mutation.isPending ? t('auth.actions.updating') : t('auth.actions.updatePassword')}</Button>
  </form>
}

export function MfaChallengeForm() {
  const { t } = useTranslation()
  const location = useLocation()
  const navigate = useNavigate()
  const challengeState = location.state as { challengeToken?: string; returnUrl?: string } | null
  const challengeToken = challengeState?.challengeToken
  const form = useForm<z.infer<typeof codeSchema>>({ resolver: zodResolver(codeSchema), defaultValues: { code: '' } })
  const mutation = useMutation({
    mutationFn: ({ code }: { code: string }) => authApi.completeMfa({ challengeToken: challengeToken ?? '', code }),
    onSuccess: async (response) => {
      const session = setAuthenticatedSession(response)
      const destination = await resolvePostAuthenticationPath(
        challengeState?.returnUrl,
        session.user.roles,
      )
      void navigate(destination, { replace: true })
    },
  })
  if (!challengeToken) return <p className="text-sm">{t('auth.notices.challengeExpired')} <Link className="text-primary underline underline-offset-2" to="/login">{t('auth.actions.signInAgain')}</Link></p>
  return <form className="space-y-4" onSubmit={form.handleSubmit((values) => mutation.mutate(values))}><div className="space-y-2"><label className="text-sm font-medium" htmlFor="mfa-code">{t('auth.fields.challengeCode')}</label><Input aria-describedby={form.formState.errors.code ? 'mfa-code-error' : undefined} aria-invalid={Boolean(form.formState.errors.code)} id="mfa-code" autoComplete="one-time-code" inputMode="numeric" {...form.register('code')} /><FieldError id="mfa-code-error" message={form.formState.errors.code?.message} /></div><RequestError operation="challenge" error={mutation.error} /><Button className="w-full" disabled={mutation.isPending}>{mutation.isPending ? t('auth.actions.verifying') : t('auth.actions.continue')}</Button></form>
}

export function MfaSetupForm() {
  const { t } = useTranslation()
  const queryClient = useQueryClient()
  const [recoveryCodes, setRecoveryCodes] = useState<string[]>([])
  const setup = useQuery({
    queryKey: ['mfa-setup'],
    queryFn: authApi.beginMfaSetup,
    enabled: hasLimitedAccessToken(),
    retry: false,
    gcTime: 0,
    staleTime: Number.POSITIVE_INFINITY,
    refetchOnReconnect: false,
    refetchOnWindowFocus: false,
  })
  const form = useForm<z.infer<typeof mfaSetupCodeSchema>>({
    resolver: zodResolver(mfaSetupCodeSchema),
    defaultValues: { code: '' },
  })
  const confirmation = useMutation({
    mutationFn: ({ code }: { code: string }) => authApi.confirmMfaSetup(code),
    onSuccess: (response) => {
      setRecoveryCodes(response.recoveryCodes)
      queryClient.removeQueries({ queryKey: ['mfa-setup'] })
      clearAuthSession()
    },
  })
  if (!hasLimitedAccessToken() && recoveryCodes.length === 0) return <p className="text-sm">{t('auth.notices.setupExpired')} <Link className="text-primary underline underline-offset-2" to="/login">{t('auth.actions.signInAgain')}</Link></p>
  if (recoveryCodes.length > 0) return <div className="space-y-4"><SuccessMessage message={t('auth.notices.mfaActivated')} /><ul className="grid grid-cols-2 gap-2 font-mono text-sm">{recoveryCodes.map((code) => <li className="min-w-0 break-all rounded border p-2" key={code}>{code}</li>)}</ul><Button className="w-full" asChild><Link to="/login">{t('auth.actions.returnToSignIn')}</Link></Button></div>
  if (setup.isPending) return <p role="status" className="text-sm">{t('auth.status.preparingAuthenticator')}</p>
  if (setup.error || !setup.data) return <RequestError operation="setup" error={setup.error ?? new Error('setup unavailable')} />
  return <div className="space-y-5">
    <div className="space-y-3 text-center">
      <p className="text-sm font-medium">{t('auth.mfa.scan')}</p>
      <div className="mx-auto w-fit rounded-xl border bg-white p-3 shadow-sm">
        <QRCodeSVG
          aria-label={t('auth.mfa.qrLabel')}
          bgColor="#ffffff"
          fgColor="#111827"
          level="M"
          marginSize={4}
          role="img"
          size={196}
          title={t('auth.mfa.qrLabel')}
          value={setup.data.authenticatorUri}
        />
      </div>
      <p className="text-sm text-muted-foreground">
        {t('auth.mfa.scanHelp')}
      </p>
    </div>
    <details className="rounded-lg bg-muted p-4 text-sm">
      <summary className="cursor-pointer font-medium">{t('auth.mfa.manualKey')}</summary>
      <p className="mt-3 break-all font-mono">{setup.data.sharedKey}</p>
    </details>
    <div className="space-y-2 text-center">
      <Button
        disabled={setup.isFetching || confirmation.isPending}
        onClick={() => void setup.refetch()}
        type="button"
        variant="outline"
      >
        {setup.isFetching ? t('auth.actions.generatingQr') : t('auth.actions.generateQr')}
      </Button>
      <p className="text-xs text-muted-foreground">
        {t('auth.mfa.regenerateWarning')}
      </p>
    </div>
    <form className="space-y-4" onSubmit={form.handleSubmit((values) => confirmation.mutate(values))}>
      <div className="space-y-2">
        <label className="text-sm font-medium" htmlFor="mfa-setup-code">{t('auth.fields.setupCode')}</label>
        <Input aria-describedby={form.formState.errors.code ? 'mfa-setup-code-error' : undefined} aria-invalid={Boolean(form.formState.errors.code)}
          id="mfa-setup-code"
          autoComplete="one-time-code"
          inputMode="numeric"
          maxLength={6}
          placeholder="123456"
          {...form.register('code')}
        />
        <FieldError id="mfa-setup-code-error" message={form.formState.errors.code?.message} />
      </div>
      <RequestError operation="setup" error={confirmation.error} />
      <Button className="w-full" disabled={confirmation.isPending}>{confirmation.isPending ? t('auth.actions.confirming') : t('auth.actions.activateMfa')}</Button>
    </form>
  </div>
}
