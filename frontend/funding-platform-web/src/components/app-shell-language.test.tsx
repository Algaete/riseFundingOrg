import { render, screen } from '@testing-library/react'
import { createMemoryRouter, RouterProvider } from 'react-router-dom'
import { AppShell } from '@/components/app-shell'
import { ThemeProvider } from '@/components/theme/theme-provider'
import { ProtectedRoute } from '@/features/auth/auth-provider'
import { setAuthenticatedSession } from '@/features/auth/auth-session'
import { language, trackingPage } from '@/test/tracking-test-harness'

describe('editorial route language boundaries', () => {
  it.each([
    ['/admin/funding', false], ['/admin/funding/new', false],
    ['/admin/funders/synthetic', false], ['/admin/projects/synthetic', false],
    ['/admin/users', false], ['/admin/imports/synthetic', false],
    ['/admin', false], ['/admin/organizations/synthetic', false],
    ['/admin/imports/upload-document', false], ['/admin/sources', false],
    ['/admin/subscriptions', false], ['/admin/errors', false],
    ['/admin/source-documents/synthetic', false], ['/admin/unknown', true],
    ['/admin/funding/synthetic/history', true],
  ] as const)('sets the correct content language for %s', async (path, legacy) => {
    trackingPage(<ThemeProvider><AppShell mode="admin" /></ThemeProvider>, path)
    await language('en')
    if (legacy) expect(screen.getByRole('main')).toHaveAttribute('lang', 'es')
    else expect(screen.getByRole('main')).not.toHaveAttribute('lang', 'es')
  })

  it('changing language does not grant editorial access to a regular member', async () => {
    setAuthenticatedSession({
      status: 'authenticated', accessToken: 'synthetic-ui-only', accessTokenExpiresAtUtc: '2099-01-01T00:00:00Z',
      user: { publicId: '33333333-3333-3333-3333-333333333333', email: 'member@example.invalid', displayName: 'Member', roles: ['Professional'], preferredLocale: 'es-CL', mfaEnabled: false },
    })
    await language('en')
    const router = createMemoryRouter([
      { path: '/admin/funding', element: <ProtectedRoute requireAdmin><p>Private editorial content</p></ProtectedRoute> },
      { path: '/dashboard', element: <p>Member workspace</p> },
    ], { initialEntries: ['/admin/funding'] })
    render(<RouterProvider router={router} />)
    expect(await screen.findByText('Member workspace')).toBeInTheDocument()
    expect(screen.queryByText('Private editorial content')).not.toBeInTheDocument()
    expect(router.state.location.pathname).toBe('/dashboard')
  })
})
