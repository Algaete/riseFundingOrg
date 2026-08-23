import { zodResolver } from '@hookform/resolvers/zod'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { QRCodeSVG } from 'qrcode.react'
import { useEffect, useRef, useState } from 'react'
import { useForm } from 'react-hook-form'
import { Link, useLocation, useNavigate, useSearchParams } from 'react-router-dom'
import { z } from 'zod'

import { ApiError } from '@/api/http-client'
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

const passwordSchema = z.string()
  .min(12, 'La contraseña debe tener al menos 12 caracteres')
  .max(128, 'La contraseña no puede superar 128 caracteres')

const registrationAcceptedKey = 'funding-platform-registration-accepted'
const genericRegistrationMessage =
  'Si la solicitud es válida, recibirás instrucciones por correo.'

const externalAuthenticationMessages: Record<string, string> = {
  failed: 'No fue posible completar el acceso con Microsoft. Intenta nuevamente.',
  invalid_identity: 'Microsoft autenticó la cuenta, pero no entregó una identidad y un correo utilizables.',
  account_link_required: 'Ya existe una cuenta con ese correo. Ingresa con tu contraseña y vincula Microsoft desde Mi cuenta.',
}

function hasAcceptedRegistration() {
  return window.sessionStorage.getItem(registrationAcceptedKey) === 'true'
}

function FieldError({ message }: { message?: string }) {
  return message ? (
    <p role="alert" className="text-sm text-destructive">{message}</p>
  ) : null
}

function RequestError({ error }: { error: unknown }) {
  if (!error) return null
  const message = error instanceof ApiError
    ? error.problem.detail ?? error.problem.title
    : 'No fue posible completar la solicitud. Intenta nuevamente.'
  return <p role="alert" className="rounded-lg bg-destructive/10 p-3 text-sm text-destructive">{message}</p>
}

function SuccessMessage({ message }: { message: string }) {
  return <p role="status" className="rounded-lg bg-accent p-3 text-sm">{message}</p>
}

const loginSchema = z.object({
  email: z.string().min(1, 'Ingresa tu correo').email('Ingresa un correo válido'),
  password: z.string().min(1, 'Ingresa tu contraseña').max(128),
})

type LoginValues = z.infer<typeof loginSchema>

export function LoginForm() {
  const navigate = useNavigate()
  const location = useLocation()
  const auth = useAuth()
  const [searchParams] = useSearchParams()
  const requestedPath = getSafeAuthenticatedPath(
    (location.state as { from?: string } | null)?.from,
  )
  const externalAuthenticationMessage = externalAuthenticationMessages[
    searchParams.get('sso') ?? ''
  ]
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
          <p role="alert" className="rounded-lg bg-destructive/10 p-3 text-sm text-destructive">
            {externalAuthenticationMessage}
          </p>
        )}
        <p role="status" className="rounded-lg bg-accent p-3 text-sm">
          Ya tienes una sesión abierta como <strong>{auth.session.user.email}</strong>.
          Cierra esa sesión antes de ingresar con otra cuenta Microsoft.
        </p>
        <Button asChild className="w-full"><Link to="/dashboard">Continuar con esta sesión</Link></Button>
      </div>
    )
  }

  return (
    <div className="space-y-4">
      {logoutIncomplete && (
        <p role="alert" className="rounded-lg bg-destructive/10 p-3 text-sm text-destructive">
          La sesión local se cerró, pero no pudimos confirmar su revocación en el servidor.
        </p>
      )}
      {externalAuthenticationMessage && (
        <p role="alert" className="rounded-lg bg-destructive/10 p-3 text-sm text-destructive">
          {externalAuthenticationMessage}
        </p>
      )}
      {entraEnabled && <>
        <Button className="w-full" variant="outline" asChild>
          <a href={`${getExternalAuthBaseUrl()}/auth/external/entra/start?returnUrl=${encodeURIComponent(requestedPath)}`}>
            Continuar con Microsoft
          </a>
        </Button>
        <div className="flex items-center gap-3 text-xs uppercase text-muted-foreground"><span className="h-px flex-1 bg-border" /><span>o con correo</span><span className="h-px flex-1 bg-border" /></div>
      </>}
      <form className="space-y-4" noValidate onSubmit={form.handleSubmit((values) => mutation.mutate(values))}>
      <div className="space-y-2">
        <label className="text-sm font-medium" htmlFor="login-email">Correo electrónico</label>
        <Input id="login-email" type="email" autoComplete="email" aria-invalid={Boolean(form.formState.errors.email)} {...form.register('email')} />
        <FieldError message={form.formState.errors.email?.message} />
      </div>
      <div className="space-y-2">
        <label className="text-sm font-medium" htmlFor="login-password">Contraseña</label>
        <Input id="login-password" type="password" autoComplete="current-password" aria-invalid={Boolean(form.formState.errors.password)} {...form.register('password')} />
        <FieldError message={form.formState.errors.password?.message} />
      </div>
      <RequestError error={mutation.error} />
      <Button type="submit" className="w-full" disabled={mutation.isPending}>
        {mutation.isPending ? 'Ingresando…' : 'Ingresar'}
      </Button>
      </form>
    </div>
  )
}

export function ExternalAuthenticationCallback() {
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
  if (!code) return <RequestError error={new Error('missing external handoff')} />
  return <div className="space-y-4"><p role="status" className="text-sm">Finalizando inicio de sesión con Microsoft…</p><RequestError error={exchange.error} />{exchange.isError && <Button asChild className="w-full" variant="outline"><Link to="/login">Volver al acceso</Link></Button>}</div>
}

const registerSchema = z.object({
  displayName: z.string().trim().min(1, 'Ingresa tu nombre').max(150),
  email: z.string().email('Ingresa un correo válido').max(320),
  password: passwordSchema,
  confirmPassword: z.string(),
}).refine((values) => values.password === values.confirmPassword, {
  message: 'Las contraseñas no coinciden',
  path: ['confirmPassword'],
})

type RegisterValues = z.infer<typeof registerSchema>

export function RegisterForm() {
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
    return <div className="space-y-4"><SuccessMessage message={mutation.data?.message ?? genericRegistrationMessage} /><p className="text-sm text-muted-foreground">Revisa tu bandeja y también la carpeta de correo no deseado. El envío ya fue aceptado; no necesitas crear la cuenta nuevamente.</p><Button className="w-full" variant="outline" asChild><Link to="/login">Ir a iniciar sesión</Link></Button></div>
  }

  const submit = form.handleSubmit((values) => {
    if (submissionLocked.current) return
    submissionLocked.current = true
    mutation.mutate(values)
  })

  return (
    <form className="space-y-4" noValidate onSubmit={submit}>
      <div className="space-y-2"><label className="text-sm font-medium" htmlFor="register-name">Nombre</label><Input id="register-name" autoComplete="name" {...form.register('displayName')} /><FieldError message={form.formState.errors.displayName?.message} /></div>
      <div className="space-y-2"><label className="text-sm font-medium" htmlFor="register-email">Correo</label><Input id="register-email" type="email" autoComplete="email" {...form.register('email')} /><FieldError message={form.formState.errors.email?.message} /></div>
      <div className="space-y-2"><label className="text-sm font-medium" htmlFor="register-password">Contraseña</label><Input id="register-password" type="password" autoComplete="new-password" {...form.register('password')} /><FieldError message={form.formState.errors.password?.message} /></div>
      <div className="space-y-2"><label className="text-sm font-medium" htmlFor="register-confirm">Confirmar contraseña</label><Input id="register-confirm" type="password" autoComplete="new-password" {...form.register('confirmPassword')} /><FieldError message={form.formState.errors.confirmPassword?.message} /></div>
      <RequestError error={mutation.error} />
      <Button className="w-full" type="submit" disabled={mutation.isPending || submissionLocked.current}>{mutation.isPending ? 'Creando cuenta…' : 'Crear cuenta'}</Button>
    </form>
  )
}

const emailSchema = z.object({ email: z.string().email('Ingresa un correo válido').max(320) })

export function ForgotPasswordForm() {
  const form = useForm<z.infer<typeof emailSchema>>({ resolver: zodResolver(emailSchema), defaultValues: { email: '' } })
  const mutation = useMutation({ mutationFn: ({ email }: { email: string }) => authApi.forgotPassword(email) })
  return <form className="space-y-4" noValidate onSubmit={form.handleSubmit((values) => mutation.mutate(values))}>
    <div className="space-y-2"><label className="text-sm font-medium" htmlFor="forgot-email">Correo</label><Input id="forgot-email" type="email" autoComplete="email" {...form.register('email')} /><FieldError message={form.formState.errors.email?.message} /></div>
    {mutation.data && <SuccessMessage message={mutation.data.message} />}<RequestError error={mutation.error} />
    <Button className="w-full" type="submit" disabled={mutation.isPending || Boolean(mutation.data)}>{mutation.isPending ? 'Enviando…' : mutation.data ? 'Enlace enviado' : 'Enviar enlace'}</Button>
  </form>
}

export function VerifyEmailForm() {
  const [searchParams] = useSearchParams()
  const token = searchParams.get('token') ?? ''
  const mutation = useMutation({ mutationFn: () => authApi.verifyEmail(token) })
  if (!token) return <RequestError error={new Error('missing token')} />
  return <div className="space-y-4">{mutation.data && <SuccessMessage message={mutation.data.message} />}<RequestError error={mutation.error} /><Button className="w-full" onClick={() => mutation.mutate()} disabled={mutation.isPending || Boolean(mutation.data)}>{mutation.isPending ? 'Verificando…' : mutation.data ? 'Correo verificado' : 'Verificar mi correo'}</Button>{mutation.data && <Button className="w-full" variant="outline" asChild><Link to="/login">Iniciar sesión</Link></Button>}</div>
}

const resetSchema = z.object({ password: passwordSchema, confirmPassword: z.string() }).refine((value) => value.password === value.confirmPassword, { message: 'Las contraseñas no coinciden', path: ['confirmPassword'] })

export function ResetPasswordForm() {
  const [searchParams] = useSearchParams()
  const token = searchParams.get('token') ?? ''
  const form = useForm<z.infer<typeof resetSchema>>({ resolver: zodResolver(resetSchema), defaultValues: { password: '', confirmPassword: '' } })
  const mutation = useMutation({ mutationFn: ({ password }: z.infer<typeof resetSchema>) => authApi.resetPassword(token, password) })
  if (!token) return <RequestError error={new Error('missing token')} />
  return <form className="space-y-4" noValidate onSubmit={form.handleSubmit((values) => mutation.mutate(values))}>
    <div className="space-y-2"><label className="text-sm font-medium" htmlFor="reset-password">Nueva contraseña</label><Input id="reset-password" type="password" autoComplete="new-password" {...form.register('password')} /><FieldError message={form.formState.errors.password?.message} /></div>
    <div className="space-y-2"><label className="text-sm font-medium" htmlFor="reset-confirm">Confirmar contraseña</label><Input id="reset-confirm" type="password" autoComplete="new-password" {...form.register('confirmPassword')} /><FieldError message={form.formState.errors.confirmPassword?.message} /></div>
    {mutation.data && <SuccessMessage message={mutation.data.message} />}<RequestError error={mutation.error} />
    <Button className="w-full" type="submit" disabled={mutation.isPending || Boolean(mutation.data)}>{mutation.isPending ? 'Actualizando…' : 'Actualizar contraseña'}</Button>
  </form>
}

const codeSchema = z.object({ code: z.string().trim().min(6, 'Ingresa el código').max(64) })
const mfaSetupCodeSchema = z.object({
  code: z.string().trim().regex(/^\d{6}$/, 'Ingresa el código de 6 dígitos'),
})

export function MfaChallengeForm() {
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
  if (!challengeToken) return <p className="text-sm">El desafío ya no está disponible. <Link className="text-primary hover:underline" to="/login">Inicia sesión nuevamente.</Link></p>
  return <form className="space-y-4" onSubmit={form.handleSubmit((values) => mutation.mutate(values))}><div className="space-y-2"><label className="text-sm font-medium" htmlFor="mfa-code">Código de autenticación o recuperación</label><Input id="mfa-code" autoComplete="one-time-code" inputMode="numeric" {...form.register('code')} /><FieldError message={form.formState.errors.code?.message} /></div><RequestError error={mutation.error} /><Button className="w-full" disabled={mutation.isPending}>{mutation.isPending ? 'Verificando…' : 'Continuar'}</Button></form>
}

export function MfaSetupForm() {
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
  if (!hasLimitedAccessToken() && recoveryCodes.length === 0) return <p className="text-sm">Esta configuración expiró. <Link className="text-primary hover:underline" to="/login">Inicia sesión nuevamente.</Link></p>
  if (recoveryCodes.length > 0) return <div className="space-y-4"><SuccessMessage message="MFA fue activado. Guarda estos códigos una sola vez." /><ul className="grid grid-cols-2 gap-2 font-mono text-sm">{recoveryCodes.map((code) => <li className="rounded border p-2" key={code}>{code}</li>)}</ul><Button className="w-full" asChild><Link to="/login">Volver a iniciar sesión</Link></Button></div>
  if (setup.isPending) return <p role="status" className="text-sm">Preparando autenticador…</p>
  if (setup.error || !setup.data) return <RequestError error={setup.error ?? new Error('setup unavailable')} />
  return <div className="space-y-5">
    <div className="space-y-3 text-center">
      <p className="text-sm font-medium">Escanea este QR con tu aplicación autenticadora</p>
      <div className="mx-auto w-fit rounded-xl border bg-white p-3 shadow-sm">
        <QRCodeSVG
          aria-label="Código QR para configurar MFA"
          bgColor="#ffffff"
          fgColor="#111827"
          level="M"
          marginSize={4}
          role="img"
          size={196}
          title="Código QR para configurar MFA"
          value={setup.data.authenticatorUri}
        />
      </div>
      <p className="text-sm text-muted-foreground">
        En Microsoft Authenticator, Google Authenticator o 1Password elige agregar una cuenta y escanear un código QR.
      </p>
    </div>
    <details className="rounded-lg bg-muted p-4 text-sm">
      <summary className="cursor-pointer font-medium">¿No puedes escanearlo? Usa la clave manual</summary>
      <p className="mt-3 break-all font-mono">{setup.data.sharedKey}</p>
    </details>
    <div className="space-y-2 text-center">
      <Button
        disabled={setup.isFetching || confirmation.isPending}
        onClick={() => void setup.refetch()}
        type="button"
        variant="outline"
      >
        {setup.isFetching ? 'Generando QR…' : 'Generar un QR nuevo'}
      </Button>
      <p className="text-xs text-muted-foreground">
        Úsalo solo si el QR anterior fue compartido o dejó de funcionar; al regenerarlo, el anterior queda inválido.
      </p>
    </div>
    <form className="space-y-4" onSubmit={form.handleSubmit((values) => confirmation.mutate(values))}>
      <div className="space-y-2">
        <label className="text-sm font-medium" htmlFor="mfa-setup-code">Código de 6 dígitos</label>
        <Input
          id="mfa-setup-code"
          autoComplete="one-time-code"
          inputMode="numeric"
          maxLength={6}
          placeholder="123456"
          {...form.register('code')}
        />
        <FieldError message={form.formState.errors.code?.message} />
      </div>
      <RequestError error={confirmation.error} />
      <Button className="w-full" disabled={confirmation.isPending}>{confirmation.isPending ? 'Confirmando…' : 'Activar MFA'}</Button>
    </form>
  </div>
}
