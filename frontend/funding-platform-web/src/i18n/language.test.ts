import i18n, { setInterfaceLanguage } from '@/i18n'
import { en } from '@/i18n/en'
import { es } from '@/i18n/es'
import { languageStorageKey, persistLanguagePreference, readLanguagePreference } from '@/i18n/language'

afterEach(() => vi.restoreAllMocks())

describe('interface language', () => {
  it.each([null, '', 'fr', 'en-US', '<script>', '{"language":"en"}'])('uses Spanish for unsupported preference %s', value => {
    if (value !== null) localStorage.setItem(languageStorageKey, value)
    expect(readLanguagePreference()).toBe('es')
  })

  it.each(['es', 'en'] as const)('restores the explicit %s preference', language => {
    persistLanguagePreference(language)
    expect(readLanguagePreference()).toBe(language)
  })

  it('does not use the browser locale to silently override the Spanish default', () => {
    vi.spyOn(window.navigator, 'language', 'get').mockReturnValue('en-US')
    expect(readLanguagePreference()).toBe('es')
  })

  it('keeps working when storage access or writes are blocked', async () => {
    vi.spyOn(Storage.prototype, 'getItem').mockImplementation(() => { throw new DOMException('blocked', 'SecurityError') })
    vi.spyOn(Storage.prototype, 'setItem').mockImplementation(() => { throw new DOMException('blocked', 'QuotaExceededError') })
    expect(readLanguagePreference()).toBe('es')
    await expect(setInterfaceLanguage('en')).resolves.toBeUndefined()
    expect(i18n.resolvedLanguage).toBe('en')
    expect(document.documentElement).toHaveAttribute('lang', 'en')
  })

  it('updates document language and only writes its own browser preference', async () => {
    const write = vi.spyOn(Storage.prototype, 'setItem')
    await setInterfaceLanguage('en')
    expect(i18n.resolvedLanguage).toBe('en')
    expect(document.documentElement).toHaveAttribute('lang', 'en')
    expect(write.mock.calls).toEqual([[languageStorageKey, 'en']])
    await setInterfaceLanguage('es')
    expect(document.documentElement).toHaveAttribute('lang', 'es')
  })

  it('ignores unsupported language changes without changing the preference', async () => {
    await setInterfaceLanguage('en')
    await setInterfaceLanguage('fr')
    expect(i18n.resolvedLanguage).toBe('en')
    expect(readLanguagePreference()).toBe('en')
  })

  it('has identical, nonempty translation keys in both bundled languages', () => {
    function flatten(value: object, prefix = ''): Record<string, string> {
      return Object.fromEntries(Object.entries(value).flatMap(([key, item]) => {
        const path = prefix ? `${prefix}.${key}` : key
        return typeof item === 'string' ? [[path, item]] : Object.entries(flatten(item, path))
      }))
    }
    const spanish = flatten(es)
    const english = flatten(en)
    expect(Object.keys(english).sort()).toEqual(Object.keys(spanish).sort())
    for (const value of [...Object.values(spanish), ...Object.values(english)]) {
      expect(value.trim().length).toBeGreaterThan(0)
    }
  })
})
