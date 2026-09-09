import { act, render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { createMemoryRouter } from 'react-router-dom'

import { createAppQueryClient } from '@/api/query-client'
import { App } from '@/App'
import { authApi } from '@/features/auth/auth-api'
import { getAuthState, setAuthenticatedSession } from '@/features/auth/auth-session'
import { setInterfaceLanguage } from '@/i18n'
import { appRoutes } from '@/router'

const email = 'synthetic.long.account.name@example.invalid'
function renderAccount(path = '/account') {
  const router = createMemoryRouter(appRoutes, { initialEntries: [path] })
  render(<App router={router} queryClient={createAppQueryClient()} />)
  return router
}

describe('account language changes', () => {
  beforeEach(() => {
    setAuthenticatedSession({
      status: 'authenticated', accessToken: 'synthetic-account-token',
      accessTokenExpiresAtUtc: '2027-09-01T12:00:00Z',
      user: { publicId: '77777777-7777-7777-7777-777777777777', email, displayName: 'Prueba Ñandú', preferredLocale: 'es-CL', roles: ['Professional'], mfaEnabled: false },
    })
    vi.spyOn(authApi, 'externalProviders').mockResolvedValue([{ code: 'entra', displayName: 'Microsoft', enabled: true }])
    vi.spyOn(authApi, 'createExternalLinkIntent').mockRejectedValue(new Error('synthetic error: do not render provider details'))
  })
  afterEach(() => { vi.restoreAllMocks(); vi.unstubAllGlobals() })

  it.each([
    ['linked', 'Tu cuenta Microsoft quedó vinculada correctamente.', 'Your Microsoft account was linked successfully.'],
    ['already_linked', 'Esa identidad Microsoft ya estaba vinculada a esta cuenta.', 'That Microsoft identity was already linked to this account.'],
    ['link_failed', 'No fue posible vincular Microsoft. Verifica en el selector si elegiste la cuenta personal o laboral correcta.', 'We could not link Microsoft. Check whether you selected the correct personal or work account.'],
  ])('localizes the %s result without changing the session, URL or account identity', async (status, spanish, english) => {
    const originalState = getAuthState()
    const router = renderAccount(`/account?sso=${status}&keep=original`)
    await screen.findByText(spanish)
    await act(() => setInterfaceLanguage('en'))
    expect(screen.getByRole('heading', { name: 'My account' })).toBeVisible()
    expect(screen.getByText(english)).toBeVisible()
    expect(screen.getByText(email)).toBeVisible()
    expect(screen.getByRole('button', { name: `Link Microsoft to ${email}` })).toBeEnabled()
    expect(screen.getByRole('main')).not.toHaveAttribute('lang', 'es')
    expect(getAuthState()).toBe(originalState)
    expect(router.state.location.search).toBe(`?sso=${status}&keep=original`)
    expect(authApi.externalProviders).toHaveBeenCalledOnce()
    expect(authApi.createExternalLinkIntent).not.toHaveBeenCalled()
    await act(() => setInterfaceLanguage('es'))
    expect(screen.getByText(spanish)).toBeVisible()
  })

  it.each([
    { providers: [] },
    { providers: [{ code: 'entra', displayName: 'Microsoft', enabled: false }] },
  ])('keeps linking unavailable for disabled or missing providers: $providers', async ({ providers }) => {
    vi.mocked(authApi.externalProviders).mockResolvedValue(providers)
    renderAccount()
    await screen.findByText('Microsoft SSO está preparado, pendiente de configurar en Entra.')
    await act(() => setInterfaceLanguage('en'))
    expect(screen.getByText('Microsoft SSO is prepared and awaiting configuration in Entra.')).toBeVisible()
    expect(screen.queryByRole('button', { name: /Link Microsoft/ })).not.toBeInTheDocument()
    expect(authApi.createExternalLinkIntent).not.toHaveBeenCalled()
  })

  it('does not mistake loading for a disabled provider or repeat the query when changing language', async () => {
    vi.mocked(authApi.externalProviders).mockReturnValue(new Promise(() => undefined))
    renderAccount()
    await screen.findByText('Comprobando métodos de acceso…')
    await act(() => setInterfaceLanguage('en'))
    expect(screen.getByRole('status')).toHaveTextContent('Checking sign-in methods…')
    expect(screen.queryByText(/awaiting configuration/)).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /Link Microsoft/ })).not.toBeInTheDocument()
    expect(authApi.externalProviders).toHaveBeenCalledOnce()
    expect(authApi.createExternalLinkIntent).not.toHaveBeenCalled()
  })

  it('keeps provider errors distinct from configuration and only retries the read on an explicit click', async () => {
    vi.mocked(authApi.externalProviders).mockRejectedValueOnce(new Error('private provider diagnostics'))
    renderAccount()
    await screen.findByText('No pudimos comprobar si Microsoft está habilitado. Intenta nuevamente.')
    await act(() => setInterfaceLanguage('en'))
    expect(screen.getByRole('alert')).toHaveTextContent('We could not check whether Microsoft is enabled. Try again.')
    expect(screen.queryByText(/awaiting configuration/)).not.toBeInTheDocument()
    expect(screen.queryByText(/private provider diagnostics/)).not.toBeInTheDocument()
    expect(authApi.externalProviders).toHaveBeenCalledOnce()
    await userEvent.click(screen.getByRole('button', { name: 'Retry' }))
    expect(await screen.findByRole('button', { name: `Link Microsoft to ${email}` })).toBeEnabled()
    expect(authApi.externalProviders).toHaveBeenCalledTimes(2)
    expect(authApi.createExternalLinkIntent).not.toHaveBeenCalled()
  })

  it('localizes link preparation errors without exposing server details or retrying automatically', async () => {
    renderAccount()
    await userEvent.click(await screen.findByRole('button', { name: `Vincular Microsoft a ${email}` }))
    await screen.findByText('No fue posible preparar la vinculación. Actualiza tu sesión e intenta nuevamente.')
    await act(() => setInterfaceLanguage('en'))
    expect(screen.getByRole('alert')).toHaveTextContent('We could not prepare account linking. Refresh your session and try again.')
    expect(screen.queryByText(/do not render provider details/)).not.toBeInTheDocument()
    expect(authApi.createExternalLinkIntent).toHaveBeenCalledOnce()
    expect(authApi.externalProviders).toHaveBeenCalledOnce()
  })

  it('preserves a pending link and navigates once to the original start URL only after it resolves', async () => {
    let finish!: (result: { startUrl: string }) => void
    vi.mocked(authApi.createExternalLinkIntent).mockReturnValue(new Promise(resolve => { finish = resolve }))
    const assign = vi.fn()
    vi.stubGlobal('location', { ...window.location, assign })
    renderAccount()
    await userEvent.click(await screen.findByRole('button', { name: `Vincular Microsoft a ${email}` }))
    expect(await screen.findByRole('button', { name: 'Preparando…' })).toBeDisabled()
    await act(() => setInterfaceLanguage('en'))
    expect(screen.getByRole('button', { name: 'Preparing…' })).toBeDisabled()
    expect(authApi.createExternalLinkIntent).toHaveBeenCalledOnce()
    expect(assign).not.toHaveBeenCalled()
    const startUrl = 'https://example.invalid/synthetic-start?intent=opaque-once'
    await act(async () => { finish({ startUrl }) })
    await waitFor(() => expect(assign).toHaveBeenCalledExactlyOnceWith(startUrl))
    expect(screen.queryByText(/opaque-once/)).not.toBeInTheDocument()
    await act(() => setInterfaceLanguage('es'))
    expect(assign).toHaveBeenCalledOnce()
  })

  it('ignores unknown URL status text rather than rendering it as an account message', async () => {
    renderAccount('/account?sso=untrusted-message')
    await screen.findByRole('button', { name: `Vincular Microsoft a ${email}` })
    await act(() => setInterfaceLanguage('en'))
    expect(screen.queryByText(/untrusted-message/)).not.toBeInTheDocument()
    expect(authApi.createExternalLinkIntent).not.toHaveBeenCalled()
  })
})
