import { collaborationApi } from './collaboration-api'
import { blankProfessional, profileIssue, consortiumIssue, invitationIssue, splitSkills } from './collaboration-validation'
import { clearAuthSession, setAuthenticatedSession } from '@/features/auth/auth-session'

describe('collaboration', () => {
  afterEach(() => { vi.unstubAllGlobals(); clearAuthSession() })
  it('mantiene perfil privado y campos opcionales', () => {
    expect(blankProfessional.isDiscoverable).toBe(false)
    expect(blankProfessional.allowsInvitations).toBe(false)
    expect(profileIssue({ ...blankProfessional, displayName: 'Nombre', headline: 'Especialidad' })).toBeNull()
    expect(profileIssue({ ...blankProfessional, displayName: 'Nombre', headline: 'Especialidad', allowsInvitations: true })).toBe('consentRequired')
    expect(profileIssue(blankProfessional)).toBe('profileRequired')
    expect(profileIssue({ ...blankProfessional, displayName: 'Nombre', headline: 'Especialidad', skills: Array(21).fill('SQL') })).toBe('profileLimits')
    expect(splitSkills(' GIS, SQL\n Datos ')).toEqual(['GIS', 'SQL', 'Datos'])
    expect(consortiumIssue('Alianza', '')).toBeNull()
    expect(consortiumIssue('', '')).toBe('consortiumLimits')
  })
  it.each(['Correo: hola@example.invalid', 'Ver HTTPS://example.invalid', 'Visita www.example.invalid', 'Llama al 12345678'])('rechaza mensajes con contacto: %s', message => {
    expect(invitationIssue({ kind: 2, targetId: 'profile', contribution: 'Datos', message })).toBe('messagePrivacy')
  })
  it('usa rutas privadas, sesión, versiones e idempotencia sin campos de roles', async () => {
    setAuthenticatedSession({ status: 'authenticated', accessToken: 'collaboration-token', accessTokenExpiresAtUtc: '2099-01-01T00:00:00Z',
      user: { publicId: 'actor', displayName: 'Nombre', email: 'actor@example.invalid', roles: ['Professional'], preferredLocale: 'es-CL', mfaEnabled: false } })
    const fetchMock = vi.fn((_input: RequestInfo | URL, _init?: RequestInit) => Promise.resolve(new Response(JSON.stringify({ items: [], totalCount: 0, page: 1, pageSize: 20 }), { headers: { 'Content-Type': 'application/json' } })))
    vi.stubGlobal('fetch', fetchMock)
    const data = { ...blankProfessional, displayName: 'Nombre', headline: 'Especialidad' }
    await collaborationApi.profile()
    await collaborationApi.saveProfile(data, 'command-create-0001')
    await collaborationApi.saveProfile(data, 'command-update-0001', '"0102030405060708"')
    await collaborationApi.professionals(' Agua & datos ', '152', '1', 2)
    await collaborationApi.consortia()
    await collaborationApi.create({ projectId: 'project', name: 'Alianza', summary: null }, 'command-create-0002')
    await collaborationApi.update('consortium', { name: 'Alianza', summary: null, status: 1 }, 'command-update-0002', '"0102030405060708"')
    await collaborationApi.invite('consortium', { kind: 2, targetId: 'profile', contribution: 'Datos', message: 'Colaboremos en datos.' }, 'command-invite-0002', '"0102030405060708"')
    await collaborationApi.act('consortium', 'participant', 1, 'command-accept-0002', '"1112131415161718"')
    for (const [, init] of fetchMock.mock.calls) {
      expect(init?.cache).toBe('no-store')
      expect(new Headers(init?.headers).get('Authorization')).toBe('Bearer collaboration-token')
    }
    expect(new Headers(fetchMock.mock.calls[1][1]?.headers).get('If-None-Match')).toBe('*')
    expect(new Headers(fetchMock.mock.calls[1][1]?.headers).has('If-Match')).toBe(false)
    expect(new Headers(fetchMock.mock.calls[2][1]?.headers).get('If-Match')).toBe('"0102030405060708"')
    expect(String(fetchMock.mock.calls[3][0])).toContain('q=Agua+%26+datos')
    expect(new Headers(fetchMock.mock.calls[8][1]?.headers).get('If-Match')).toBe('"1112131415161718"')
    expect(fetchMock.mock.calls[8][1]?.body).toBe('{"action":1}')
  })
})
