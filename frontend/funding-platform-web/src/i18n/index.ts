import i18n from 'i18next'
import { initReactI18next } from 'react-i18next'

import { es } from '@/i18n/es'
import { en } from '@/i18n/en'
import { isInterfaceLanguage, persistLanguagePreference, readLanguagePreference, supportedLanguages } from '@/i18n/language'

function updateDocumentLanguage(language: string) {
  if (typeof document !== 'undefined') {
    document.documentElement.lang = isInterfaceLanguage(language) ? language : 'es'
  }
}

i18n.on('languageChanged', updateDocumentLanguage)

void i18n.use(initReactI18next).init({
  resources: { es, en },
  supportedLngs: [...supportedLanguages],
  lng: readLanguagePreference(),
  fallbackLng: 'es',
  interpolation: { escapeValue: false },
})

export async function setInterfaceLanguage(language: string): Promise<void> {
  if (!isInterfaceLanguage(language)) return
  await i18n.changeLanguage(language)
  persistLanguagePreference(language)
}

export default i18n
