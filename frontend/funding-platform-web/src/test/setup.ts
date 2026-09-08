import '@testing-library/jest-dom/vitest'
import { vi } from 'vitest'

import { resetAuthStateForTests } from '@/features/auth/auth-session'
import i18n from '@/i18n'
import { languageStorageKey } from '@/i18n/language'

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
