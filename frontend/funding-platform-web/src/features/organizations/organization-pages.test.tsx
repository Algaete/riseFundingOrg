import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { createMemoryRouter } from 'react-router-dom'

import { createAppQueryClient } from '@/api/query-client'
import { App } from '@/App'
import { setAuthenticatedSession } from '@/features/auth/auth-session'
import type { OrganizationProfile, OrganizationSummary } from '@/features/organizations/organization-api'
import { appRoutes } from '@/router'

const catalogs = {
  countries: [{ id: 152, code: 'CL', name: 'Chile' }],
  regions: [{ id: 7, countryId: 152, code: 'CL-RM', name: 'Metropolitana' }],
  currencies: [
    { code: 'CLP', name: 'Peso chileno', minorUnits: 0 },
    { code: 'USD', name: 'Dólar estadounidense', minorUnits: 2 },
  ],
  fundingCategories: [
    { id: 1, code: 'ENVIRONMENT', name: 'Medio ambiente' },
    { id: 16, code: 'OTHER', name: 'Otros' },
  ],
  fundingTypes: [{ id: 1, code: 'GRANT', name: 'Subvención' }],
  organizationTypes: [{ id: 2, code: 'FOUNDATION', name: 'Fundación' }],
  legalEntityTypes: [{ id: 1, countryId: 152, code: 'CL_FOUNDATION', name: 'Fundación' }],
  organizationSizes: [
    { id: 1, code: 'MICRO', name: 'Micro' },
    { id: 10, code: 'EMPLOYEES_1_10', name: '1–10 personas' },
    { id: 11, code: 'EMPLOYEES_11_50', name: '11–50 personas' },
    { id: 12, code: 'EMPLOYEES_51_100', name: '51–100 personas' },
    { id: 13, code: 'EMPLOYEES_101_PLUS', name: '101+ personas' },
  ],
  beneficiaryTypes: [
    { id: 1, code: 'CHILDREN', name: 'Niños, niñas y adolescentes' },
    { id: 12, code: 'OTHER', name: 'Otros' },
  ],
  projectTypes: [
    { id: 1, code: 'PROGRAM', name: 'Programa' },
    { id: 13, code: 'OTHER', name: 'Otros' },
    { id: 2, code: 'RESEARCH', name: 'Investigación' },
    { id: 7, code: 'COMMUNITY_DEVELOPMENT', name: 'Desarrollo comunitario' },
    { id: 4, code: 'CAPACITY_BUILDING', name: 'Fortalecimiento institucional' },
    { id: 6, code: 'EMERGENCY_RESPONSE', name: 'Ayuda humanitaria y respuesta a emergencias' },
    { id: 3, code: 'INFRASTRUCTURE', name: 'Infraestructura' },
    { id: 9, code: 'INNOVATION_TECHNOLOGY', name: 'Innovación y tecnología' },
    { id: 5, code: 'ADVOCACY', name: 'Incidencia y políticas públicas' },
    { id: 12, code: 'DISASTER_RISK_PREVENTION_REDUCTION', name: 'Prevención y reducción de riesgos de desastres' },
    { id: 8, code: 'TRAINING_CAPACITY_DEVELOPMENT', name: 'Capacitación y desarrollo de capacidades' },
    { id: 11, code: 'ENVIRONMENTAL_CONSERVATION_RESTORATION', name: 'Conservación y restauración ambiental' },
    { id: 10, code: 'ENTREPRENEURSHIP_PRODUCTIVE_DEVELOPMENT', name: 'Emprendimiento y desarrollo productivo' },
  ],
  tags: [],
  languages: [
    { id: 1, code: 'es', name: 'Español' },
    { id: 5, code: 'und', name: 'Otro' },
  ],
  fundingExperienceTypes: [
    { id: 1, code: 'GOVERNMENTS_PUBLIC_FUNDS', name: 'Gobiernos / fondos públicos' },
    { id: 2, code: 'FOUNDATIONS_GRANTMAKERS', name: 'Fundaciones / grantmakers' },
    { id: 3, code: 'MULTILATERAL_ORGANIZATIONS', name: 'Organismos multilaterales' },
    { id: 4, code: 'INTERNATIONAL_COOPERATION', name: 'Cooperación internacional' },
    { id: 5, code: 'COMPANIES', name: 'Empresas' },
    { id: 6, code: 'PHILANTHROPISTS', name: 'Filántropos' },
  ],
}

const organizationId = '51ea2f6f-b1af-4e09-856c-6dcbdcfc812f'
const summary: OrganizationSummary = {
  publicId: organizationId,
  name: 'Fundación Demo',
  membershipRole: 'admin',
  profileStatus: 1,
  profileCompleteness: 40,
  profileVersion: 1,
  updatedAtUtc: '2026-08-21T04:00:00Z',
}
const profile: OrganizationProfile = {
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
  fundingExperienceTypeIds: [],
  customImpactAreas: [],
  customBeneficiaryTypes: [],
  customProjectTypes: [],
  customLanguages: [],
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

function json(value: unknown, status = 200) {
  return Promise.resolve(new Response(JSON.stringify(value), {
    status,
    headers: { 'Content-Type': status >= 400 ? 'application/problem+json' : 'application/json' },
  }))
}

function renderExistingProfile({
  catalogData = catalogs,
  profileData = profile,
  onUpdate,
}: {
  catalogData?: typeof catalogs
  profileData?: typeof profile
  onUpdate?: (init: RequestInit) => Promise<Response>
} = {}) {
  vi.stubGlobal('fetch', vi.fn((input: string | URL | Request, init?: RequestInit) => {
    const url = String(input)
    if (url.endsWith('/catalogs')) return json(catalogData)
    if (url.endsWith('/organizations') && init?.method !== 'PUT') return json([summary])
    if (url.endsWith(`/organizations/${organizationId}/profile`) && init?.method === 'PUT') {
      return onUpdate?.(init) ?? json({ ...profileData, profileVersion: 2, eTag: '"0000000000000002"' })
    }
    if (url.endsWith(`/organizations/${organizationId}/profile`)) return json(profileData)
    throw new Error(`Unexpected request: ${url}`)
  }))

  const router = createMemoryRouter(appRoutes, { initialEntries: ['/organization/profile'] })
  render(<App router={router} queryClient={createAppQueryClient()} />)
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
    expect(screen.getByLabelText(/Nombre público.*obligatorio/i)).toBeRequired()
    expect(screen.getByText(/indica un campo obligatorio/i)).toBeInTheDocument()
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

    const name = await screen.findByLabelText(/Nombre público.*obligatorio/i)
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

  it('muestra los tamaños nuevos en el orden definido y oculta rangos anteriores no seleccionados', async () => {
    authenticate()
    renderExistingProfile()

    const size = await screen.findByLabelText(/Tamaño del equipo.*Recomendado/i)
    expect(screen.getByText('Cantidad de personas activas que forman parte del equipo.')).toBeInTheDocument()
    expect(Array.from((size as HTMLSelectElement).options).map(option => option.text)).toEqual([
      'Sin informar',
      '1–10 personas',
      '11–50 personas',
      '51–100 personas',
      '101+ personas',
    ])
    expect(screen.getByLabelText(/Sitio web.*Opcional/i)).toBeInTheDocument()
  })

  it('conserva solo el tamaño anterior seleccionado hasta que se confirme uno nuevo', async () => {
    authenticate()
    const user = userEvent.setup()
    renderExistingProfile({ profileData: { ...profile, organizationSizeId: 1 } })

    const size = await screen.findByLabelText(/Tamaño del equipo.*Recomendado/i) as HTMLSelectElement
    expect(size).toHaveValue('1')
    expect(Array.from(size.options).map(option => option.text)).toContain('Micro (rango anterior; confirma uno nuevo)')

    await user.selectOptions(size, '10')

    expect(size).toHaveValue('10')
    expect(Array.from(size.options).map(option => option.text)).not.toContain('Micro (rango anterior; confirma uno nuevo)')
  })

  it('mantiene disponibles los tamaños anteriores si el API aún no entrega los rangos nuevos', async () => {
    authenticate()
    const legacyCatalogs = {
      ...catalogs,
      organizationSizes: [
        { id: 1, code: 'MICRO', name: 'Micro' },
        { id: 2, code: 'SMALL', name: 'Pequeña' },
        { id: 3, code: 'MEDIUM', name: 'Mediana' },
        { id: 4, code: 'LARGE', name: 'Grande' },
      ],
    }
    renderExistingProfile({ catalogData: legacyCatalogs })

    const size = await screen.findByLabelText(/Tamaño del equipo.*Recomendado/i) as HTMLSelectElement
    expect(Array.from(size.options).map(option => option.text)).toEqual([
      'Sin informar',
      'Micro',
      'Pequeña',
      'Mediana',
      'Grande',
    ])
  })

  it('muestra solo los 12 tipos de proyecto solicitados y en el orden de producto', async () => {
    authenticate()
    const user = userEvent.setup()
    renderExistingProfile()

    await screen.findByLabelText(/Nombre público.*obligatorio/i)
    await user.click(screen.getByRole('button', { name: /2\.\s*Impacto/i }))
    const group = screen.getByRole('group', { name: /Tipos de proyecto.*Recomendado/i })

    expect(within(group).getAllByRole('checkbox').map(item => item.parentElement?.textContent?.trim())).toEqual([
      'Fortalecimiento institucional',
      'Desarrollo comunitario',
      'Capacitación y desarrollo de capacidades',
      'Incidencia y políticas públicas',
      'Infraestructura',
      'Investigación',
      'Innovación y tecnología',
      'Emprendimiento y desarrollo productivo',
      'Conservación y restauración ambiental',
      'Ayuda humanitaria y respuesta a emergencias',
      'Prevención y reducción de riesgos de desastres',
    ])
    expect(within(group).getByRole('button', { name: 'Agregar otra opción' })).toBeInTheDocument()
    expect(within(group).queryByRole('checkbox', { name: 'Programa' })).not.toBeInTheDocument()
  })

  it('conserva Programa con aviso solo mientras siga seleccionado en un perfil anterior', async () => {
    authenticate()
    const user = userEvent.setup()
    renderExistingProfile({ profileData: { ...profile, projectTypeIds: [1] } })

    await screen.findByLabelText(/Nombre público.*obligatorio/i)
    await user.click(screen.getByRole('button', { name: /2\.\s*Impacto/i }))
    const group = screen.getByRole('group', { name: /Tipos de proyecto.*Recomendado/i })
    const legacyProgram = within(group).getByRole('checkbox', {
      name: 'Programa (valor anterior; confirma un tipo nuevo)',
    })
    expect(legacyProgram).toBeChecked()

    await user.click(legacyProgram)

    expect(within(group).queryByRole('checkbox', { name: /Programa/ })).not.toBeInTheDocument()
  })

  it('mantiene el catálogo de tipos anterior mientras el API aún no entregue la ampliación', async () => {
    authenticate()
    const user = userEvent.setup()
    const legacyCatalogs = {
      ...catalogs,
      projectTypes: [
        { id: 1, code: 'PROGRAM', name: 'Programa' },
        { id: 2, code: 'RESEARCH', name: 'Investigación' },
        { id: 3, code: 'INFRASTRUCTURE', name: 'Infraestructura' },
        { id: 4, code: 'CAPACITY_BUILDING', name: 'Fortalecimiento institucional' },
        { id: 5, code: 'ADVOCACY', name: 'Incidencia' },
        { id: 6, code: 'EMERGENCY_RESPONSE', name: 'Respuesta a emergencias' },
      ],
    }
    renderExistingProfile({ catalogData: legacyCatalogs })

    await screen.findByLabelText(/Nombre público.*obligatorio/i)
    await user.click(screen.getByRole('button', { name: /2\.\s*Impacto/i }))
    const group = screen.getByRole('group', { name: /Tipos de proyecto.*Recomendado/i })
    expect(within(group).getAllByRole('checkbox').map(item => item.parentElement?.textContent?.trim())).toEqual([
      'Programa',
      'Investigación',
      'Infraestructura',
      'Fortalecimiento institucional',
      'Incidencia',
      'Respuesta a emergencias',
    ])
  })

  it('agrega una opción privada con Enter sin persistir el identificador OTHER', async () => {
    authenticate()
    let submittedBody: Record<string, unknown> | undefined
    renderExistingProfile({
      onUpdate: async (init) => {
        submittedBody = JSON.parse(String(init.body)) as Record<string, unknown>
        return (await json({ ...profile, ...submittedBody, profileVersion: 2 }))
      },
    })
    const user = userEvent.setup()

    await screen.findByLabelText(/Nombre público.*obligatorio/i)
    await user.click(screen.getByRole('button', { name: /2\.\s*Impacto/i }))
    const impact = screen.getByRole('group', { name: /Áreas de impacto.*Recomendado/i })
    await user.click(within(impact).getByRole('button', { name: 'Agregar otra opción' }))
    const input = screen.getByLabelText('Agregar otra opción en áreas de impacto')
    await waitFor(() => expect(document.activeElement).toBe(input))
    await user.type(input, 'Economía circular{Enter}')

    expect(submittedBody).toBeUndefined()
    expect(screen.getByRole('button', { name: 'Quitar Economía circular' })).toBeInTheDocument()
    expect(within(impact).queryByRole('checkbox', { name: 'Otros' })).not.toBeInTheDocument()
    expect(screen.getByText(/privadas para tu organización.*no influyen en las recomendaciones/i)).toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: /Guardar/i }))

    await waitFor(() => expect(submittedBody).toMatchObject({
      categoryIds: [],
      customImpactAreas: ['Economía circular'],
    }))
    expect(submittedBody?.categoryIds).not.toContain(16)
  })

  it('muestra y permite limpiar opciones existentes aunque OTHER no esté seleccionado', async () => {
    authenticate()
    let submittedBody: Record<string, unknown> | undefined
    renderExistingProfile({
      profileData: { ...profile, customImpactAreas: ['Economía circular'] },
      onUpdate: async (init) => {
        submittedBody = JSON.parse(String(init.body)) as Record<string, unknown>
        return (await json({ ...profile, ...submittedBody }))
      },
    })
    const user = userEvent.setup()

    await screen.findByLabelText(/Nombre público.*obligatorio/i)
    await user.click(screen.getByRole('button', { name: /2\.\s*Impacto/i }))
    await user.click(screen.getByRole('button', { name: 'Quitar Economía circular' }))
    await user.click(screen.getByRole('button', { name: /Guardar/i }))

    await waitFor(() => expect(submittedBody?.customImpactAreas).toEqual([]))
  })

  it('conserva visible un OTHER histórico sin detalle hasta que el usuario lo edite', async () => {
    authenticate()
    const user = userEvent.setup()
    renderExistingProfile({ profileData: { ...profile, categoryIds: [16] } })

    await screen.findByLabelText(/Nombre público.*obligatorio/i)
    await user.click(screen.getByRole('button', { name: /2\.\s*Impacto/i }))

    expect(screen.getByRole('checkbox', { name: 'Otros (valor anterior)' })).toBeChecked()
    expect(screen.getByText('Otro sin especificar')).toBeInTheDocument()
  })

  it('usa und como acción para agregar un idioma privado sin persistir el id Otro', async () => {
    authenticate()
    let submittedBody: Record<string, unknown> | undefined
    renderExistingProfile({
      onUpdate: async (init) => {
        submittedBody = JSON.parse(String(init.body)) as Record<string, unknown>
        return (await json({ ...profile, ...submittedBody }))
      },
    })
    const user = userEvent.setup()

    await screen.findByLabelText(/Nombre público.*obligatorio/i)
    await user.click(screen.getByRole('button', { name: /3\.\s*Financiamiento/i }))
    const languages = screen.getByRole('group', { name: /Idiomas de trabajo.*Recomendado/i })
    await user.click(within(languages).getByRole('button', { name: 'Agregar otra opción' }))
    await user.type(screen.getByLabelText('Agregar otra opción en idiomas de trabajo'), 'Mapudungun{Enter}')
    await user.click(screen.getByRole('button', { name: /Guardar/i }))

    await waitFor(() => expect(submittedBody).toMatchObject({
      languages: [],
      customImpactAreas: [],
      customBeneficiaryTypes: [],
      customProjectTypes: [],
      customLanguages: ['Mapudungun'],
    }))
    expect(submittedBody?.languages).not.toContainEqual({ languageId: 5, proficiency: null })
  })

  it('navega y enfoca el editor cuando el API rechaza una opción personalizada', async () => {
    authenticate()
    renderExistingProfile({
      onUpdate: async () => (await json({
        title: 'La solicitud contiene errores.',
        status: 400,
        errors: { customImpactAreas: ['La opción personalizada ya existe.'] },
      }, 400)),
    })
    const user = userEvent.setup()

    const name = await screen.findByLabelText(/Nombre público.*obligatorio/i)
    await user.type(name, ' actualizada')
    await user.click(screen.getByRole('button', { name: /Guardar/i }))

    await screen.findByText('No pudimos guardar. Revisa lo siguiente:')
    await waitFor(() => expect(document.activeElement).toHaveAttribute('id', 'organization-custom-impact-areas'))
  })

  it('aplica presets financieros y vuelve a rango personalizado ante cambios manuales', async () => {
    authenticate()
    let submittedBody: Record<string, unknown> | undefined
    renderExistingProfile({
      onUpdate: async (init) => {
        submittedBody = JSON.parse(String(init.body)) as Record<string, unknown>
        return (await json({
          ...profile,
          ...submittedBody,
          profileVersion: 2,
          eTag: '"0000000000000002"',
        }))
      },
    })
    const user = userEvent.setup()

    await screen.findByLabelText(/Nombre público.*obligatorio/i)
    await user.click(screen.getByRole('button', { name: /3\.\s*Financiamiento/i }))

    const desiredPreset = screen.getByLabelText(/Rango habitual.*Recomendado/i) as HTMLSelectElement
    expect(Array.from(desiredPreset.options).map(option => option.text)).toContain('Sin informar')
    expect(Array.from(desiredPreset.options).map(option => option.text)).toContain('Rango personalizado')
    await user.selectOptions(desiredPreset, '25k-100k')
    expect(screen.getByLabelText(/Financiamiento mínimo.*Opcional/i)).toHaveValue(25_000)
    expect(screen.getByLabelText(/Financiamiento máximo.*Opcional/i)).toHaveValue(100_000)
    expect(screen.getByLabelText(/Moneda objetivo.*obligatorio/i)).toHaveValue('USD')

    const desiredMaximum = screen.getByLabelText(/Financiamiento máximo.*Opcional/i)
    await user.clear(desiredMaximum)
    await user.type(desiredMaximum, '120000')
    expect(desiredPreset).toHaveValue('custom')

    const annualPreset = screen.getByLabelText(/Rango de presupuesto anual.*Opcional/i) as HTMLSelectElement
    expect(Array.from(annualPreset.options).map(option => option.text)).toContain('Sin informar')
    expect(Array.from(annualPreset.options).map(option => option.text)).toContain('Rango personalizado')
    await user.selectOptions(annualPreset, '250k-1m')
    expect(screen.getByLabelText(/Presupuesto anual mínimo.*Opcional/i)).toHaveValue(250_000)
    expect(screen.getByLabelText(/Presupuesto anual máximo.*Opcional/i)).toHaveValue(1_000_000)
    expect(screen.getByLabelText(/Moneda del presupuesto anual.*obligatorio/i)).toHaveValue('USD')

    await user.selectOptions(screen.getByLabelText(/Moneda del presupuesto anual.*obligatorio/i), 'CLP')
    expect(annualPreset).toHaveValue('custom')
    await user.click(screen.getByRole('button', { name: /Guardar/i }))

    expect(await screen.findByText('Perfil guardado correctamente.')).toBeInTheDocument()
    expect(submittedBody).toMatchObject({
      desiredFundingMin: 25_000,
      desiredFundingMax: 120_000,
      desiredFundingCurrency: 'USD',
      annualBudgetMin: 250_000,
      annualBudgetMax: 1_000_000,
      annualBudgetCurrency: 'CLP',
    })
  })

  it('permite seleccionar varios tipos de financiadores solo cuando declara experiencia', async () => {
    authenticate()
    let submittedBody: Record<string, unknown> | undefined
    renderExistingProfile({
      onUpdate: async (init) => {
        submittedBody = JSON.parse(String(init.body)) as Record<string, unknown>
        return (await json({
          ...profile,
          ...submittedBody,
          profileVersion: 2,
          eTag: '"0000000000000002"',
        }))
      },
    })
    const user = userEvent.setup()

    await screen.findByLabelText(/Nombre público.*obligatorio/i)
    await user.click(screen.getByRole('button', { name: /3\.\s*Financiamiento/i }))
    const experience = screen.getByLabelText(/¿La organización tiene experiencia previa con financiadores?.*Opcional/i)
    expect(screen.queryByRole('group', { name: /Experiencia previa con financiadores/ })).not.toBeInTheDocument()

    await user.selectOptions(experience, '2')
    const group = screen.getByRole('group', { name: /Experiencia previa con financiadores.*Opcional/i })
    expect(within(group).getAllByRole('checkbox').map(item => item.parentElement?.textContent?.trim())).toEqual([
      'Gobiernos / fondos públicos',
      'Fundaciones / grantmakers',
      'Organismos multilaterales',
      'Cooperación internacional',
      'Empresas',
      'Filántropos',
    ])
    await user.click(within(group).getByRole('checkbox', { name: 'Gobiernos / fondos públicos' }))
    await user.click(within(group).getByRole('checkbox', { name: 'Cooperación internacional' }))
    await user.click(screen.getByRole('button', { name: /Guardar/i }))

    expect(await screen.findByText('Perfil guardado correctamente.')).toBeInTheDocument()
    expect(submittedBody).toMatchObject({
      previousFundingExperience: 2,
      fundingExperienceTypeIds: [1, 4],
    })
  })

  it('limpia los tipos de financiadores al cambiar a sin experiencia', async () => {
    authenticate()
    let submittedBody: Record<string, unknown> | undefined
    renderExistingProfile({
      profileData: { ...profile, previousFundingExperience: 2, fundingExperienceTypeIds: [1, 4] },
      onUpdate: async (init) => {
        submittedBody = JSON.parse(String(init.body)) as Record<string, unknown>
        return (await json({ ...profile, ...submittedBody }))
      },
    })
    const user = userEvent.setup()

    await screen.findByLabelText(/Nombre público.*obligatorio/i)
    await user.click(screen.getByRole('button', { name: /3\.\s*Financiamiento/i }))
    const group = screen.getByRole('group', { name: /Experiencia previa con financiadores.*Opcional/i })
    expect(within(group).getByRole('checkbox', { name: 'Gobiernos / fondos públicos' })).toBeChecked()

    await user.selectOptions(
      screen.getByLabelText(/¿La organización tiene experiencia previa con financiadores?.*Opcional/i),
      '1',
    )
    expect(screen.queryByRole('group', { name: /Experiencia previa con financiadores/ })).not.toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: /Guardar/i }))

    await waitFor(() => expect(submittedBody).toMatchObject({
      previousFundingExperience: 1,
      fundingExperienceTypeIds: [],
    }))
  })

  it('valida montos, orden y moneda antes de enviar y enfoca el primer campo inválido', async () => {
    authenticate()
    const update = vi.fn()
    renderExistingProfile({ onUpdate: update })
    const user = userEvent.setup()

    await screen.findByLabelText(/Nombre público.*obligatorio/i)
    await user.click(screen.getByRole('button', { name: /3\.\s*Financiamiento/i }))
    await user.type(screen.getByLabelText(/Financiamiento mínimo.*Opcional/i), '100000')
    await user.type(screen.getByLabelText(/Financiamiento máximo.*Opcional/i), '50000')
    await user.click(screen.getByRole('button', { name: /Guardar/i }))

    expect(await screen.findByText('El monto máximo debe ser igual o mayor al mínimo.')).toBeInTheDocument()
    expect(screen.getByText('Selecciona una moneda para el rango informado.')).toBeInTheDocument()
    await waitFor(() => expect(document.activeElement).toBe(screen.getByLabelText(/Financiamiento máximo.*Opcional/i)))
    expect(update).not.toHaveBeenCalled()
  })

  it('omite el error global al elegir el primer paso y enfoca el primer error con campo', async () => {
    authenticate()
    renderExistingProfile({
      onUpdate: async () => (await json({
        title: 'La solicitud contiene errores.',
        status: 400,
        errors: {
          profile: ['Revisa los datos generales del perfil.'],
          desiredFundingCurrency: ['Debes seleccionar la moneda del financiamiento.'],
          annualBudgetMax: ['El presupuesto anual máximo no es válido.'],
          languages: ['Selecciona al menos un idioma válido.'],
        },
      }, 400)),
    })
    const user = userEvent.setup()

    const name = await screen.findByLabelText(/Nombre público.*obligatorio/i)
    await user.type(name, ' actualizada')
    await user.click(screen.getByRole('button', { name: /Guardar/i }))

    expect(await screen.findByText('No pudimos guardar. Revisa lo siguiente:')).toBeInTheDocument()
    expect(screen.getAllByText('Debes seleccionar la moneda del financiamiento.')).toHaveLength(2)
    expect(screen.getAllByText('El presupuesto anual máximo no es válido.')).toHaveLength(2)
    expect(screen.getAllByText('Selecciona al menos un idioma válido.')).toHaveLength(2)
    expect(screen.getByText('Revisa los datos generales del perfil.')).toBeInTheDocument()
    await waitFor(() => {
      expect(document.activeElement).toHaveAttribute('id', 'organization-desired-funding-currency')
    })
  })

  it('navega desde el resumen a un error de otro paso y enfoca su campo', async () => {
    authenticate()
    renderExistingProfile({
      onUpdate: async () => (await json({
        title: 'La solicitud contiene errores.',
        status: 400,
        errors: {
          desiredFundingCurrency: ['Debes seleccionar la moneda del financiamiento.'],
          name: ['Corrige el nombre público.'],
        },
      }, 400)),
    })
    const user = userEvent.setup()

    const name = await screen.findByLabelText(/Nombre público.*obligatorio/i)
    await user.type(name, ' actualizada')
    await user.click(screen.getByRole('button', { name: /Guardar/i }))

    const identityErrorLink = await screen.findByRole('link', { name: 'Corrige el nombre público.' })
    await waitFor(() => {
      expect(document.activeElement).toHaveAttribute('id', 'organization-desired-funding-currency')
    })
    await user.click(identityErrorLink)

    await waitFor(() => {
      expect(document.activeElement).toHaveAttribute('id', 'organization-name')
    })
    expect(screen.getByLabelText(/Nombre público.*obligatorio/i)).toHaveAttribute('aria-invalid', 'true')
  })
})
