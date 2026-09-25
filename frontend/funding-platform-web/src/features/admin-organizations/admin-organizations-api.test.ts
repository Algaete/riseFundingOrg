import { apiClient } from '@/api/http-client'
import { adminOrganizationsApi } from './admin-organizations-api'

describe('API administrativa de verificación de organizaciones', () => {
  afterEach(() => vi.restoreAllMocks())

  it('envía el filtro pendiente cero y conserva los filtros anteriores', async () => {
    const get = vi.spyOn(apiClient, 'get').mockResolvedValue({ items: [] })
    const controller = new AbortController()
    await adminOrganizationsApi.list({ q: '  Agua  ', verificationStatus: 0, profileStatus: 2, isActive: false, page: 2, pageSize: 25 }, controller.signal)
    const url = new URL(String(get.mock.calls[0][0]), 'https://example.test/')
    expect(Object.fromEntries(url.searchParams)).toEqual({ page: '2', pageSize: '25', q: 'Agua', verificationStatus: '0', profileStatus: '2', isActive: 'false' })
    expect(get.mock.calls[0][1]).toEqual({ cache: 'no-store', signal: controller.signal })
  })

  it('omite el filtro no especificado y no decide durante la lectura', async () => {
    const get = vi.spyOn(apiClient, 'get').mockResolvedValue({ items: [] })
    const post = vi.spyOn(apiClient, 'post')
    await adminOrganizationsApi.list({ page: 1, pageSize: 25 })
    expect(get.mock.calls[0][0]).not.toContain('verificationStatus')
    await adminOrganizationsApi.getVerification('org/id')
    expect(get).toHaveBeenLastCalledWith('admin/organizations/org%2Fid/verification', { cache: 'no-store', signal: undefined })
    expect(post).not.toHaveBeenCalled()
  })

  it('envía una decisión con ambas versiones a la ruta privada', async () => {
    const post = vi.spyOn(apiClient, 'post').mockResolvedValue({})
    const decision = { status: 2 as const, reason: 'No se pudo verificar.', expectedRevision: 4, expectedProfileVersion: 7 }
    await adminOrganizationsApi.decideVerification('org/id', decision)
    expect(post).toHaveBeenCalledExactlyOnceWith('admin/organizations/org%2Fid/verification', decision, { cache: 'no-store' })
  })
})
