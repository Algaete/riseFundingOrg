import { afterEach, describe, expect, it, vi } from 'vitest'

import { organizationApi } from '@/features/organizations/organization-api'
import {
  getSafeAuthenticatedPath,
  resolvePostAuthenticationPath,
} from '@/features/auth/post-auth-navigation'

describe('navegación posterior a la autenticación', () => {
  afterEach(() => {
    vi.restoreAllMocks()
  })

  it('envía al onboarding cuando el usuario aún no tiene una organización', async () => {
    vi.spyOn(organizationApi, 'list').mockResolvedValue([])

    await expect(
      resolvePostAuthenticationPath('/dashboard', ['Professional']),
    ).resolves.toBe('/onboarding')
  })

  it('respeta el destino solicitado cuando el usuario ya tiene organización', async () => {
    vi.spyOn(organizationApi, 'list').mockResolvedValue([{
      publicId: '6c73e4f0-d850-4a4a-91f6-2ef995ff8b90',
      name: 'Fundación demo',
      membershipRole: 'admin',
      profileStatus: 1,
      profileCompleteness: 25,
      profileVersion: 1,
      updatedAtUtc: '2026-08-21T12:00:00Z',
    }])

    await expect(
      resolvePostAuthenticationPath('/projects', ['Professional']),
    ).resolves.toBe('/projects')
  })

  it('lleva administradores al panel sin exigir una organización', async () => {
    const list = vi.spyOn(organizationApi, 'list')

    await expect(
      resolvePostAuthenticationPath('/dashboard', ['Admin']),
    ).resolves.toBe('/admin')
    expect(list).not.toHaveBeenCalled()
  })

  it('rechaza destinos externos o relativos', () => {
    expect(getSafeAuthenticatedPath('//evil.example')).toBe('/dashboard')
    expect(getSafeAuthenticatedPath('https://evil.example')).toBe('/dashboard')
    expect(getSafeAuthenticatedPath('/funding')).toBe('/funding')
  })
})
