import { QueryClientProvider } from '@tanstack/react-query'
import { fireEvent, render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter, Route, Routes } from 'react-router-dom'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

import { createAppQueryClient } from '@/api/query-client'
import { authApi, type AcceptedResponse } from '@/features/auth/auth-api'
import {
  ExternalAuthenticationCallback,
  LoginForm,
  MfaSetupForm,
  RegisterForm,
} from '@/features/auth/auth-forms'
import {
  setAuthenticatedSession,
  setLimitedAccessToken,
} from '@/features/auth/auth-session'

function renderRegisterForm() {
  return render(
    <QueryClientProvider client={createAppQueryClient()}>
      <MemoryRouter>
        <RegisterForm />
      </MemoryRouter>
    </QueryClientProvider>,
  )
}

function renderLoginForm(initialEntry: string | { pathname: string; search?: string; state?: unknown }) {
  return render(
    <QueryClientProvider client={createAppQueryClient()}>
      <MemoryRouter initialEntries={[initialEntry]}>
        <LoginForm />
      </MemoryRouter>
    </QueryClientProvider>,
  )
}

function renderExternalCallback(initialEntry: string) {
  return render(
    <QueryClientProvider client={createAppQueryClient()}>
      <MemoryRouter initialEntries={[initialEntry]}>
        <Routes>
          <Route path="/auth/external/callback" element={<ExternalAuthenticationCallback />} />
          <Route path="/admin" element={<p>Destino administrativo</p>} />
        </Routes>
      </MemoryRouter>
    </QueryClientProvider>,
  )
}

function renderMfaSetupForm() {
  return render(
    <QueryClientProvider client={createAppQueryClient()}>
      <MemoryRouter>
        <MfaSetupForm />
      </MemoryRouter>
    </QueryClientProvider>,
  )
}

describe('RegisterForm', () => {
  beforeEach(() => {
    sessionStorage.clear()
  })

  afterEach(() => {
    vi.restoreAllMocks()
  })

  it('envía una sola solicitud aunque se pulse dos veces y conserva el bloqueo', async () => {
    var resolveRegistration: (value: AcceptedResponse) => void = () => undefined
    const request = new Promise<AcceptedResponse>((resolve) => {
      resolveRegistration = resolve
    })
    const register = vi.spyOn(authApi, 'register').mockReturnValue(request)
    const user = userEvent.setup()
    const firstRender = renderRegisterForm()

    await user.type(screen.getByLabelText('Nombre'), 'Fundación de prueba')
    await user.type(screen.getByLabelText('Correo'), 'fundacion@example.test')
    await user.type(screen.getByLabelText('Contraseña'), 'UnaClaveLocal-2026')
    await user.type(screen.getByLabelText('Confirmar contraseña'), 'UnaClaveLocal-2026')

    const createAccount = screen.getByRole('button', { name: 'Crear cuenta' })
    fireEvent.click(createAccount)
    fireEvent.click(createAccount)

    await waitFor(() => expect(register).toHaveBeenCalledTimes(1))
    resolveRegistration({ message: 'Solicitud aceptada.' })
    expect(await screen.findByText('Solicitud aceptada.')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Crear cuenta' })).not.toBeInTheDocument()

    firstRender.unmount()
    renderRegisterForm()

    expect(screen.getByText(/El envío ya fue aceptado/)).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Crear cuenta' })).not.toBeInTheDocument()
    expect(register).toHaveBeenCalledTimes(1)
  })
})

describe('LoginForm Microsoft SSO', () => {
  afterEach(() => {
    vi.restoreAllMocks()
  })

  it.each([
    ['invalid_identity', 'Microsoft autenticó la cuenta, pero no entregó una identidad y un correo utilizables.'],
    ['account_link_required', 'Ya existe una cuenta con ese correo. Ingresa con tu contraseña y vincula Microsoft desde Mi cuenta.'],
    ['failed', 'No fue posible completar el acceso con Microsoft. Intenta nuevamente.'],
  ])('explica el resultado %s en vez de volver silenciosamente al login', async (status, message) => {
    vi.spyOn(authApi, 'externalProviders').mockResolvedValue([
      { code: 'entra', displayName: 'Microsoft', enabled: true },
    ])

    renderLoginForm(`/login?sso=${status}`)

    expect(await screen.findByRole('alert')).toHaveTextContent(message)
  })

  it('conserva la ruta protegida al comenzar el acceso Microsoft', async () => {
    vi.spyOn(authApi, 'externalProviders').mockResolvedValue([
      { code: 'entra', displayName: 'Microsoft', enabled: true },
    ])
    renderLoginForm({
      pathname: '/login',
      state: { from: '/funding/grants-gov-123' },
    })

    const link = await screen.findByRole('link', { name: 'Continuar con Microsoft' })
    const target = new URL(link.getAttribute('href')!, 'http://localhost:5173')

    expect(target.searchParams.get('returnUrl')).toBe('/funding/grants-gov-123')
  })

  it('no permite iniciar otro SSO mientras existe una sesión local', async () => {
    vi.spyOn(authApi, 'externalProviders').mockResolvedValue([
      { code: 'entra', displayName: 'Microsoft', enabled: true },
    ])
    setAuthenticatedSession({
      status: 'authenticated',
      accessToken: 'current-token',
      accessTokenExpiresAtUtc: '2026-08-21T18:00:00Z',
      user: {
        publicId: '11111111-1111-1111-1111-111111111111',
        email: 'current@example.test',
        displayName: 'Current User',
        preferredLocale: 'es-CL',
        roles: ['User'],
        mfaEnabled: false,
      },
    })

    renderLoginForm('/login')

    expect(screen.getByRole('status')).toHaveTextContent('current@example.test')
    expect(screen.queryByRole('link', { name: 'Continuar con Microsoft' }))
      .not.toBeInTheDocument()
  })
})

describe('ExternalAuthenticationCallback', () => {
  afterEach(() => {
    vi.restoreAllMocks()
  })

  it('canjea una vez el handoff y conserva la sesión antes de navegar', async () => {
    const exchange = vi.spyOn(authApi, 'exchangeExternalHandoff').mockResolvedValue({
      status: 'authenticated',
      accessToken: 'access-token',
      accessTokenExpiresAtUtc: '2026-08-21T13:10:00Z',
      user: {
        publicId: '11111111-1111-1111-1111-111111111111',
        email: 'admin@example.test',
        displayName: 'Admin',
        preferredLocale: 'es-CL',
        roles: ['Admin'],
        mfaEnabled: true,
      },
    })

    renderExternalCallback('/auth/external/callback?code=one-time-code&returnUrl=%2Fdashboard')

    expect(await screen.findByText('Destino administrativo')).toBeInTheDocument()
    expect(exchange).toHaveBeenCalledOnce()
    expect(exchange).toHaveBeenCalledWith('one-time-code')
  })

  it('explica un fallo de canje y permite volver al acceso', async () => {
    vi.spyOn(authApi, 'exchangeExternalHandoff').mockRejectedValue(new Error('expired'))

    renderExternalCallback('/auth/external/callback?code=expired-code')

    expect(await screen.findByRole('alert')).toHaveTextContent(
      'No fue posible completar la solicitud. Intenta nuevamente.',
    )
    expect(screen.getByRole('link', { name: 'Volver al acceso' })).toHaveAttribute('href', '/login')
  })
})

describe('MfaSetupForm', () => {
  afterEach(() => {
    vi.restoreAllMocks()
  })

  it('muestra un QR local y conserva la clave manual como alternativa', async () => {
    setLimitedAccessToken('limited-mfa-setup-token')
    const beginSetup = vi.spyOn(authApi, 'beginMfaSetup').mockResolvedValue({
      sharedKey: 'JBSWY3DPEHPK3PXP',
      authenticatorUri: 'otpauth://totp/FundingPlatform:test@example.test?secret=JBSWY3DPEHPK3PXP&issuer=FundingPlatform&digits=6',
    })

    renderMfaSetupForm()

    const qr = await screen.findByRole('img', { name: 'Código QR para configurar MFA' })
    expect(qr.tagName.toLowerCase()).toBe('svg')
    expect(screen.queryByRole('img', { hidden: true })).toBe(qr)
    expect(screen.getByText('¿No puedes escanearlo? Usa la clave manual')).toBeInTheDocument()
    expect(screen.getByText('JBSWY3DPEHPK3PXP')).toBeInTheDocument()
    expect(screen.getByLabelText('Código de 6 dígitos')).toHaveAttribute('inputmode', 'numeric')

    await userEvent.click(screen.getByRole('button', { name: 'Generar un QR nuevo' }))
    await waitFor(() => expect(beginSetup).toHaveBeenCalledTimes(2))
  })
})
