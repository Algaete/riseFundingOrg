export const languageStorageKey = 'funding-platform-language'
export const supportedLanguages = ['es', 'en'] as const
export type InterfaceLanguage = typeof supportedLanguages[number]

export function isInterfaceLanguage(value: unknown): value is InterfaceLanguage {
  return value === 'es' || value === 'en'
}

export function readLanguagePreference(): InterfaceLanguage {
  try {
    const value = window.localStorage.getItem(languageStorageKey)
    return isInterfaceLanguage(value) ? value : 'es'
  } catch {
    // Storage may be blocked. The interface still works in its default language.
    return 'es'
  }
}

export function persistLanguagePreference(language: InterfaceLanguage): void {
  try {
    window.localStorage.setItem(languageStorageKey, language)
  } catch {
    // A browser preference must never block navigation or authentication.
  }
}
