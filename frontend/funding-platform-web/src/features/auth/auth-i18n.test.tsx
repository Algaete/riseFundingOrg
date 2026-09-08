import { QueryClientProvider } from '@tanstack/react-query'
import { act, fireEvent, render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import type { ReactNode } from 'react'
import { MemoryRouter } from 'react-router-dom'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { ApiError } from '@/api/http-client'
import { createAppQueryClient } from '@/api/query-client'
import { LanguageSelector } from '@/components/language-selector'
import { authApi } from '@/features/auth/auth-api'
import { ExternalAuthenticationCallback, ForgotPasswordForm, LoginForm, MfaChallengeForm, MfaSetupForm, RegisterForm, ResetPasswordForm, VerifyEmailForm } from '@/features/auth/auth-forms'
import { getAuthState, setAuthenticatedSession, setLimitedAccessToken } from '@/features/auth/auth-session'
import { setInterfaceLanguage } from '@/i18n'

function renderForm(form: ReactNode, entry: string | { pathname: string; state: unknown } = '/') {
  return render(<QueryClientProvider client={createAppQueryClient()}><MemoryRouter initialEntries={[entry]}><LanguageSelector />{form}</MemoryRouter></QueryClientProvider>)
}

async function english() {
  await act(() => setInterfaceLanguage('en'))
}
async function spanish() {
  await act(() => setInterfaceLanguage('es'))
}
function deferred<T>() {
  let resolve!: (value: T) => void
  let reject!: (error: unknown) => void
  const promise = new Promise<T>((res, rej) => { resolve = res; reject = rej })
  return { promise, resolve, reject }
}
function apiError(code: string, status: number) {
  return new ApiError({ status, type: `https://fundingplatform.local/problems/${code}`, title: 'Raw server text' }, new Response(null, { status }))
}

describe('authentication language changes', () => {
  beforeEach(() => {
    sessionStorage.clear()
    vi.spyOn(authApi, 'externalProviders').mockResolvedValue([])
  })
  afterEach(() => vi.restoreAllMocks())

  it.each([
    ['failed', 'We could not complete sign-in with Microsoft. Please try again.'],
    ['invalid_identity', 'Microsoft authenticated your account but did not provide a usable identity and email.'],
    ['account_link_required', 'An account with that email already exists. Sign in with your password and link Microsoft from My account.'],
  ])('translates the existing SSO outcome %s', async (status, message) => {
    renderForm(<LoginForm />, `/login?sso=${status}`)
    await english()
    expect(screen.getByRole('alert')).toHaveTextContent(message)
    expect(screen.queryByRole('link', { name: 'Continue with Microsoft' })).not.toBeInTheDocument()
  })

  it('translates the active-session notice without translating the email or changing the session', async () => {
    const session = setAuthenticatedSession({
      status: 'authenticated', accessToken: 'synthetic-token', accessTokenExpiresAtUtc: '2030-01-01T00:00:00Z',
      user: { publicId: '11111111-1111-1111-1111-111111111111', email: 'synthetic@example.test', displayName: 'Ejemplo', preferredLocale: 'es-CL', roles: ['User'], mfaEnabled: false },
    })
    renderForm(<LoginForm />)
    await english()
    expect(screen.getByRole('status')).toHaveTextContent('You are already signed in as synthetic@example.test. Sign out before signing in with another Microsoft account.')
    expect(screen.getByRole('link', { name: 'Continue with this session' })).toHaveAttribute('href', '/dashboard')
    expect(getAuthState().session).toBe(session)
  })

  it('translates visible validation without clearing input or making a request', async () => {
    const login = vi.spyOn(authApi, 'login')
    renderForm(<LoginForm />)
    fireEvent.change(screen.getByLabelText('Correo electrónico'), { target: { value: 'unfinished@' } })
    await userEvent.click(screen.getByRole('button', { name: 'Ingresar' }))
    expect(await screen.findByText('Ingresa un correo válido')).toBeVisible()
    await english()
    expect(screen.getByLabelText('Email address')).toHaveValue('unfinished@')
    expect(screen.getByLabelText('Email address')).toHaveAccessibleDescription('Enter a valid email')
    expect(screen.getByText('Enter your password')).toBeVisible()
    expect(login).not.toHaveBeenCalled()
  })

  it('keeps a pending login and localizes the eventual protocol error in both languages', async () => {
    const request = deferred<Awaited<ReturnType<typeof authApi.login>>>()
    const login = vi.spyOn(authApi, 'login').mockReturnValue(request.promise)
    renderForm(<LoginForm />)
    fireEvent.change(screen.getByLabelText('Correo electrónico'), { target: { value: 'synthetic@example.test' } })
    fireEvent.change(screen.getByLabelText('Contraseña'), { target: { value: 'Synthetic-test-only' } })
    await userEvent.click(screen.getByRole('button', { name: 'Ingresar' }))
    await english()
    expect(screen.getByRole('button', { name: 'Signing in…' })).toBeDisabled()
    request.reject(apiError('invalid-credentials', 401))
    expect(await screen.findByRole('alert')).toHaveTextContent('The email or password is invalid.')
    await spanish()
    expect(screen.getByRole('alert')).toHaveTextContent('El correo o la contraseña no son válidos.')
    expect(screen.getByLabelText('Contraseña')).toHaveValue('Synthetic-test-only')
    expect(login).toHaveBeenCalledOnce()
    expect(login.mock.calls[0]?.[0]).toEqual({ email: 'synthetic@example.test', password: 'Synthetic-test-only' })
    expect(screen.queryByText('Raw server text')).not.toBeInTheDocument()
  })

  it('preserves registration locking and account locale while translating acceptance', async () => {
    const request = deferred<Awaited<ReturnType<typeof authApi.register>>>()
    const register = vi.spyOn(authApi, 'register').mockReturnValue(request.promise)
    await english()
    renderForm(<RegisterForm />)
    fireEvent.change(screen.getByLabelText(/^Name/), { target: { value: 'Example' } })
    fireEvent.change(screen.getByLabelText(/^Email/), { target: { value: 'synthetic@example.test' } })
    fireEvent.change(screen.getByLabelText(/^Password/), { target: { value: 'Synthetic-test-only' } })
    fireEvent.change(screen.getByLabelText(/^Confirm password/), { target: { value: 'Synthetic-test-only' } })
    fireEvent.click(screen.getByRole('button', { name: 'Create account' }))
    fireEvent.click(screen.getByRole('button', { name: 'Create account' }))
    await waitFor(() => expect(register).toHaveBeenCalledOnce())
    await spanish()
    expect(screen.getByRole('button', { name: 'Creando cuenta…' })).toBeDisabled()
    request.resolve({ message: 'Raw acceptance response' })
    expect(await screen.findByRole('status')).toHaveTextContent('Si la solicitud es válida, recibirás instrucciones por correo.')
    await english()
    expect(screen.getByRole('status')).toHaveTextContent('If the request is valid, you will receive instructions by email.')
    expect(register).toHaveBeenCalledExactlyOnceWith({ displayName: 'Example', email: 'synthetic@example.test', password: 'Synthetic-test-only', preferredLocale: 'es-CL' })
    expect(screen.queryByText('Raw acceptance response')).not.toBeInTheDocument()
  })

  it('keeps recovery acceptance generic without sending another email on language change', async () => {
    const forgot = vi.spyOn(authApi, 'forgotPassword').mockResolvedValue({ message: 'Server acceptance' })
    renderForm(<ForgotPasswordForm />)
    fireEvent.change(screen.getByLabelText('Correo'), { target: { value: 'synthetic@example.test' } })
    await userEvent.click(screen.getByRole('button', { name: 'Enviar enlace' }))
    expect(await screen.findByRole('status')).toHaveTextContent('Si la cuenta existe')
    await english()
    expect(screen.getByRole('status')).toHaveTextContent('If the account exists, you will receive instructions to reset your password.')
    expect(screen.getByRole('button', { name: 'Link sent' })).toBeDisabled()
    expect(forgot).toHaveBeenCalledExactlyOnceWith('synthetic@example.test')
  })

  it.each([
    [<VerifyEmailForm key="verify" />, 'The verification code is missing. Open the complete link you received by email.'],
    [<ResetPasswordForm key="reset" />, 'The recovery code is missing. Open the complete link you received by email.'],
    [<ExternalAuthenticationCallback key="external" />, 'Microsoft sign-in is invalid or has expired. Please start again.'],
  ])('translates missing-link errors without invoking an endpoint (%#)', async (form, message) => {
    const verify = vi.spyOn(authApi, 'verifyEmail')
    const reset = vi.spyOn(authApi, 'resetPassword')
    const exchange = vi.spyOn(authApi, 'exchangeExternalHandoff')
    renderForm(form)
    await english()
    expect(screen.getByRole('alert')).toHaveTextContent(message)
    expect(verify).not.toHaveBeenCalled()
    expect(reset).not.toHaveBeenCalled()
    expect(exchange).not.toHaveBeenCalled()
  })

  it('translates verification success while preserving the one-use token request', async () => {
    const verify = vi.spyOn(authApi, 'verifyEmail').mockResolvedValue({ message: 'Raw server acceptance' })
    renderForm(<VerifyEmailForm />, '/verify-email?token=synthetic-token')
    await userEvent.click(screen.getByRole('button', { name: 'Verificar mi correo' }))
    expect(await screen.findByRole('status')).toHaveTextContent('Tu correo fue confirmado.')
    await english()
    expect(screen.getByRole('status')).toHaveTextContent('Your email has been verified.')
    expect(screen.getByRole('button', { name: 'Email verified' })).toBeDisabled()
    expect(verify).toHaveBeenCalledExactlyOnceWith('synthetic-token')
  })

  it('translates password reset success without changing the payload', async () => {
    const reset = vi.spyOn(authApi, 'resetPassword').mockResolvedValue({ message: 'Raw server acceptance' })
    await english()
    renderForm(<ResetPasswordForm />, '/reset-password?token=synthetic-token')
    fireEvent.change(screen.getByLabelText('New password'), { target: { value: 'Synthetic-test-only' } })
    fireEvent.change(screen.getByLabelText('Confirm password'), { target: { value: 'Synthetic-test-only' } })
    await userEvent.click(screen.getByRole('button', { name: 'Update password' }))
    expect(await screen.findByRole('status')).toHaveTextContent('Your password has been updated.')
    await spanish()
    expect(screen.getByRole('status')).toHaveTextContent('La contraseña fue actualizada.')
    expect(reset).toHaveBeenCalledExactlyOnceWith('synthetic-token', 'Synthetic-test-only')
  })

  it('does not exchange a one-time SSO handoff again after changing language', async () => {
    const request = deferred<Awaited<ReturnType<typeof authApi.exchangeExternalHandoff>>>()
    const exchange = vi.spyOn(authApi, 'exchangeExternalHandoff').mockReturnValue(request.promise)
    renderForm(<ExternalAuthenticationCallback />, '/auth/external/callback?code=synthetic-handoff')
    await english()
    expect(screen.getByRole('status')).toHaveTextContent('Finishing sign-in with Microsoft…')
    request.reject(apiError('invalid-external-handoff', 401))
    expect(await screen.findByRole('alert')).toHaveTextContent('Microsoft sign-in is invalid or has expired.')
    expect(screen.queryByRole('status')).not.toBeInTheDocument()
    await spanish()
    expect(screen.getByRole('link', { name: 'Volver al acceso' })).toHaveAttribute('href', '/login')
    expect(exchange).toHaveBeenCalledExactlyOnceWith('synthetic-handoff')
  })

  it('retains recovery-code MFA support and localizes its error', async () => {
    const challenge = vi.spyOn(authApi, 'completeMfa').mockRejectedValue(apiError('invalid-credentials', 401))
    renderForm(<MfaChallengeForm />, { pathname: '/mfa', state: { challengeToken: 'synthetic-challenge' } })
    fireEvent.change(screen.getByLabelText('Código de autenticación o recuperación'), { target: { value: 'ABCD-EFGH-IJKL' } })
    await english()
    await userEvent.click(screen.getByRole('button', { name: 'Continue' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('The code is invalid or the challenge has expired.')
    expect(challenge).toHaveBeenCalledExactlyOnceWith({ challengeToken: 'synthetic-challenge', code: 'ABCD-EFGH-IJKL' })
  })

  it('keeps the QR and recovery codes unchanged across language switches', async () => {
    setLimitedAccessToken('synthetic-limited-token')
    const setup = vi.spyOn(authApi, 'beginMfaSetup').mockResolvedValue({ sharedKey: 'JBSWY3DPEHPK3PXP', authenticatorUri: 'otpauth://totp/test?secret=JBSWY3DPEHPK3PXP' })
    const confirm = vi.spyOn(authApi, 'confirmMfaSetup').mockResolvedValue({ recoveryCodes: ['ABCD-EFGH-IJKL', 'MNOP-QRST-UVWX'] })
    renderForm(<MfaSetupForm />)
    const qr = await screen.findByRole('img', { name: 'Código QR para configurar MFA' })
    const qrPath = qr.querySelector('path')?.getAttribute('d')
    fireEvent.change(screen.getByLabelText('Código de 6 dígitos'), { target: { value: '123456' } })
    await english()
    expect(screen.getByRole('img', { name: 'QR code to set up MFA' }).querySelector('path')?.getAttribute('d')).toBe(qrPath)
    expect(screen.getByLabelText('6-digit code')).toHaveValue('123456')
    expect(setup).toHaveBeenCalledOnce()
    await userEvent.click(screen.getByRole('button', { name: 'Enable MFA' }))
    expect(await screen.findByRole('status')).toHaveTextContent('MFA is enabled.')
    await spanish()
    expect(screen.getByText('ABCD-EFGH-IJKL')).toBeVisible()
    expect(screen.getByText('MNOP-QRST-UVWX')).toBeVisible()
    expect(screen.queryByRole('img')).not.toBeInTheDocument()
    expect(confirm).toHaveBeenCalledExactlyOnceWith('123456')
    expect(setup).toHaveBeenCalledOnce()
    expect(getAuthState().session).toBeNull()
  })
})
