import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { createMemoryRouter } from 'react-router-dom'

import { createAppQueryClient } from '@/api/query-client'
import { App } from '@/App'
import { appRoutes } from '@/router'
import { authApi } from '@/features/auth/auth-api'
import { setAuthenticatedSession } from '@/features/auth/auth-session'

function authenticate() {
  setAuthenticatedSession({
    status: 'authenticated',
    accessToken: 'test-access-token',
    accessTokenExpiresAtUtc: '2026-08-21T12:10:00Z',
    user: {
      publicId: '89b8d22a-472c-42e4-b034-c772ce3bb08e',
      email: 'member@example.test',
      displayName: 'Organización demo',
      preferredLocale: 'es-CL',
      roles: ['Professional'],
      mfaEnabled: false,
    },
  })
}

function renderRoute(path: string) {
  const router = createMemoryRouter(appRoutes, { initialEntries: [path] })
  return render(<App router={router} queryClient={createAppQueryClient()} />)
}

describe('aplicación', () => {
  beforeEach(() => {
    localStorage.clear()
    sessionStorage.clear()
    document.documentElement.classList.remove('dark')
  })

  afterEach(() => {
    vi.restoreAllMocks()
    vi.unstubAllGlobals()
    window.history.replaceState({}, '', '/')
  })

  it('renderiza una ruta privada dentro del shell responsive', async () => {
    authenticate()
    renderRoute('/dashboard')

    expect(
      await screen.findByRole('heading', { name: 'Resumen', level: 1 }),
    ).toBeInTheDocument()
    expect(screen.getByText('Espacio de organización')).toBeInTheDocument()
    expect(screen.getAllByRole('link', { name: 'Concursos disponibles' })[0]).toHaveAttribute('href', '/opportunities')
  })

  it('adapta el inicio público cuando ya existe una sesión', async () => {
    authenticate()
    renderRoute('/')

    expect(await screen.findByRole('link', { name: 'Ver concursos disponibles' })).toHaveAttribute('href', '/funding')
    expect(screen.getAllByRole('link', { name: 'Ir a mi espacio' })[0]).toHaveAttribute('href', '/dashboard')
    expect(screen.queryByRole('link', { name: 'Ingresar' })).not.toBeInTheDocument()
    expect(screen.queryByRole('link', { name: 'Crear cuenta' })).not.toBeInTheDocument()
  })

  it('valida el formulario de acceso con React Hook Form y Zod', async () => {
    const user = userEvent.setup()
    renderRoute('/login')

    await user.click(await screen.findByRole('button', { name: 'Ingresar' }))

    expect(await screen.findByText('Ingresa tu correo')).toBeInTheDocument()
    expect(
      screen.getByText('Ingresa tu contraseña'),
    ).toBeInTheDocument()
  })

  it('permite alternar el tema desde el shell', async () => {
    const user = userEvent.setup()
    authenticate()
    renderRoute('/dashboard')

    await screen.findByRole('heading', { name: 'Resumen', level: 1 })
    await user.click(
      screen.getByRole('button', { name: /Cambiar tema: Sistema/i }),
    )
    await user.click(
      screen.getByRole('button', { name: /Cambiar tema: Claro/i }),
    )

    expect(document.documentElement).toHaveClass('dark')
    expect(localStorage.getItem('funding-platform-theme')).toBe('dark')
  })

  it.each([
    ['linked', 'Tu cuenta Microsoft quedó vinculada correctamente.'],
    ['already_linked', 'Esa identidad Microsoft ya estaba vinculada a esta cuenta.'],
    ['link_failed', 'No fue posible vincular Microsoft. Verifica en el selector si elegiste la cuenta personal o laboral correcta.'],
  ])('muestra el resultado de vinculación Microsoft %s', async (status, message) => {
    vi.spyOn(authApi, 'externalProviders').mockResolvedValue([
      { code: 'entra', displayName: 'Microsoft', enabled: true },
    ])
    authenticate()
    renderRoute(`/account?sso=${status}`)

    expect(await screen.findByText(message)).toBeInTheDocument()
  })

  it('no inicia refresh en paralelo con el canje del callback Microsoft', async () => {
    window.history.replaceState({}, '', '/auth/external/callback?code=one-time-code')
    const fetchMock = vi.fn()
    vi.stubGlobal('fetch', fetchMock)
    const exchange = vi.spyOn(authApi, 'exchangeExternalHandoff').mockResolvedValue({
      status: 'authenticated',
      accessToken: 'microsoft-token',
      accessTokenExpiresAtUtc: '2026-08-21T18:00:00Z',
      user: {
        publicId: '11111111-1111-1111-1111-111111111111',
        email: 'admin@example.test',
        displayName: 'Admin',
        preferredLocale: 'es-CL',
        roles: ['Admin'],
        mfaEnabled: true,
      },
    })

    renderRoute('/auth/external/callback?code=one-time-code')

    await vi.waitFor(() => expect(exchange).toHaveBeenCalledOnce())
    expect(fetchMock).not.toHaveBeenCalled()
  })

  it('limpia datos cacheados incluso si falla la revocación de logout', async () => {
    const queryClient = createAppQueryClient()
    queryClient.setQueryData(['organizations'], [{ name: 'Sensitive tenant' }])
    vi.spyOn(authApi, 'logout').mockRejectedValue(new Error('unavailable'))
    authenticate()
    const router = createMemoryRouter(appRoutes, { initialEntries: ['/dashboard'] })
    render(<App router={router} queryClient={queryClient} />)

    const user = userEvent.setup()
    await user.click(await screen.findByRole('button', { name: 'Cerrar sesión' }))

    expect(await screen.findByRole('alert')).toHaveTextContent(
      'La sesión local se cerró',
    )
    expect(queryClient.getQueryData(['organizations'])).toBeUndefined()
  })
})
