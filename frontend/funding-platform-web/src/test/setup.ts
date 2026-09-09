import '@testing-library/jest-dom/vitest'
import { vi } from 'vitest'

import { resetAuthStateForTests } from '@/features/auth/auth-session'
import i18n, { ensureInterfaceResources } from '@/i18n'
import { allResourceModules } from '@/i18n/resource-loader'
import { languageStorageKey } from '@/i18n/language'

beforeAll(async () => { await ensureInterfaceResources(allResourceModules) })

beforeEach(async () => {
  resetAuthStateForTests()
  localStorage.removeItem(languageStorageKey)
  await i18n.changeLanguage('es')
})

Object.defineProperty(window, 'matchMedia', {
  writable: true,
  value: vi.fn().mockImplementation((query: string) => ({
    matches: false,
    media: query,
    onchange: null,
    addEventListener: vi.fn(),
    removeEventListener: vi.fn(),
    addListener: vi.fn(),
    removeListener: vi.fn(),
    dispatchEvent: vi.fn(),
  })),
})
