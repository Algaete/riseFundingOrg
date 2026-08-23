import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { createMemoryRouter } from 'react-router-dom'

import { createAppQueryClient } from '@/api/query-client'
import { App } from '@/App'
import { setAuthenticatedSession } from '@/features/auth/auth-session'
import { appRoutes } from '@/router'

const catalogs = {
  countries: [{ id: 152, code: 'CL', name: 'Chile' }],
  regions: [{ id: 7, countryId: 152, code: 'CL-RM', name: 'Metropolitana' }],
  currencies: [{ code: 'CLP', name: 'Peso chileno', minorUnits: 0 }],
  fundingCategories: [{ id: 1, code: 'ENVIRONMENT', name: 'Medio ambiente' }],
  fundingTypes: [{ id: 1, code: 'GRANT', name: 'Subvención' }],
  organizationTypes: [{ id: 2, code: 'FOUNDATION', name: 'Fundación' }],
  legalEntityTypes: [{ id: 1, countryId: 152, code: 'CL_FOUNDATION', name: 'Fundación' }],
  organizationSizes: [{ id: 1, code: 'MICRO', name: 'Micro' }],
  beneficiaryTypes: [{ id: 1, code: 'CHILDREN', name: 'Niños, niñas y adolescentes' }],
  projectTypes: [{ id: 1, code: 'PROGRAM', name: 'Programa' }],
  tags: [],
  languages: [{ id: 1, code: 'es', name: 'Español' }],
}

const organizationId = '51ea2f6f-b1af-4e09-856c-6dcbdcfc812f'
const summary = {
  publicId: organizationId,
  name: 'Fundación Demo',
  membershipRole: 'admin',
  profileStatus: 1,
  profileCompleteness: 40,
  profileVersion: 1,
  updatedAtUtc: '2026-08-21T04:00:00Z',
}
const profile = {
  ...summary,
  legalName: null,
  taxIdentifier: null,
  homeCountryId: 152,
  organizationTypeId: 2,
  legalEntityTypeId: null,
  organizationSizeId: null,
  establishedYear: null,
  websiteUrl: null,
  description: null,
  previousFundingExperience: 0,
  experienceSummary: null,
  annualBudgetMin: null,
  annualBudgetMax: null,
  annualBudgetCurrency: null,
  desiredFundingMin: null,
  desiredFundingMax: null,
  desiredFundingCurrency: null,
  canEdit: true,
  eTag: '"0000000000000001"',
  countryIds: [],
  regionIds: [],
  categoryIds: [],
  beneficiaryTypeIds: [],
  projectTypeIds: [],
  tagIds: [],
  languages: [],
}

function authenticate() {
  setAuthenticatedSession({
    status: 'authenticated',
    accessToken: 'organization-test-token',
    accessTokenExpiresAtUtc: '2026-08-21T12:00:00Z',
    user: {
      publicId: '89b8d22a-472c-42e4-b034-c772ce3bb08e',
      email: 'member@example.test',
      displayName: 'Miembro demo',
      preferredLocale: 'es-CL',
      roles: ['Professional'],
      mfaEnabled: false,
    },
  })
}

function json(value: unknown) {
  return Promise.resolve(new Response(JSON.stringify(value), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  }))
}

describe('perfil de organización', () => {
  afterEach(() => vi.unstubAllGlobals())

  it('muestra el alta inicial cuando el usuario todavía no tiene organización', async () => {
    authenticate()
    vi.stubGlobal('fetch', vi.fn((input: string | URL | Request) => {
      const url = String(input)
      if (url.endsWith('/catalogs')) return json(catalogs)
      if (url.endsWith('/organizations')) return json([])
      throw new Error(`Unexpected request: ${url}`)
    }))

    const router = createMemoryRouter(appRoutes, { initialEntries: ['/onboarding'] })
    render(<App router={router} queryClient={createAppQueryClient()} />)

    expect(await screen.findByRole('heading', { name: 'Crea el espacio de tu organización' })).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /Crear organización/ })).toBeEnabled()
  })

  it('envía If-Match al guardar un perfil existente', async () => {
    authenticate()
    const requests: Array<{ url: string; init?: RequestInit }> = []
    vi.stubGlobal('fetch', vi.fn((input: string | URL | Request, init?: RequestInit) => {
      const url = String(input)
      requests.push({ url, init })
      if (url.endsWith('/catalogs')) return json(catalogs)
      if (url.endsWith('/organizations') && init?.method !== 'PUT') return json([summary])
      if (url.endsWith(`/organizations/${organizationId}/profile`) && init?.method === 'PUT') {
        return json({ ...profile, name: 'Fundación Actualizada', profileVersion: 2, eTag: '"0000000000000002"' })
      }
      if (url.endsWith(`/organizations/${organizationId}/profile`)) return json(profile)
      throw new Error(`Unexpected request: ${url}`)
    }))

    const user = userEvent.setup()
    const router = createMemoryRouter(appRoutes, { initialEntries: ['/organization/profile'] })
    render(<App router={router} queryClient={createAppQueryClient()} />)

    const name = await screen.findByLabelText('Nombre público')
    await user.clear(name)
    await user.type(name, 'Fundación Actualizada')
    await user.click(screen.getByRole('button', { name: /Guardar/ }))

    expect(await screen.findByText('Perfil guardado correctamente.')).toBeInTheDocument()
    await waitFor(() => {
      const request = requests.find(item => item.init?.method === 'PUT')
      expect(new Headers(request?.init?.headers).get('If-Match')).toBe('"0000000000000001"')
    })
  })

  it('acepta un dominio sin protocolo y lo envía normalizado con HTTPS', async () => {
    authenticate()
    let submittedBody: Record<string, unknown> | undefined
    vi.stubGlobal('fetch', vi.fn((input: string | URL | Request, init?: RequestInit) => {
      const url = String(input)
      if (url.endsWith('/catalogs')) return json(catalogs)
      if (url.endsWith('/organizations') && init?.method !== 'PUT') return json([summary])
      if (url.endsWith(`/organizations/${organizationId}/profile`) && init?.method === 'PUT') {
        submittedBody = JSON.parse(String(init.body)) as Record<string, unknown>
        return json({ ...profile, websiteUrl: 'https://onara.org', profileVersion: 2, eTag: '"0000000000000002"' })
      }
      if (url.endsWith(`/organizations/${organizationId}/profile`)) return json(profile)
      throw new Error(`Unexpected request: ${url}`)
    }))

    const user = userEvent.setup()
    const router = createMemoryRouter(appRoutes, { initialEntries: ['/organization/profile'] })
    render(<App router={router} queryClient={createAppQueryClient()} />)

    const website = await screen.findByLabelText(/Sitio web/)
    expect(website).toHaveAttribute('type', 'text')
    await user.type(website, 'onara.org')
    await user.click(screen.getByRole('button', { name: /Guardar/ }))

    expect(await screen.findByText('Perfil guardado correctamente.')).toBeInTheDocument()
    expect(submittedBody?.websiteUrl).toBe('https://onara.org')
  })
})
