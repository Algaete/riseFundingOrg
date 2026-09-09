import i18n from 'i18next'
import { initReactI18next } from 'react-i18next'
import { coreEs } from './core/es'
import { createResourceCoordinator } from './resource-coordinator'
import { resourceLoaders, type ResourceModule } from './resource-loader'
import { isInterfaceLanguage, persistLanguagePreference, readLanguagePreference, supportedLanguages } from './language'

function updateDocumentLanguage(language: string) {
  if (typeof document !== 'undefined') document.documentElement.lang = isInterfaceLanguage(language) ? language : 'es'
}

i18n.on('languageChanged', updateDocumentLanguage)
void i18n.use(initReactI18next).init({
  resources: { es: { translation: coreEs } },
  supportedLngs: [...supportedLanguages],
  lng: 'es',
  fallbackLng: 'es',
  interpolation: { escapeValue: false },
})

const resources = createResourceCoordinator<ResourceModule>({
  core: 'core',
  current: () => isInterfaceLanguage(i18n.resolvedLanguage) ? i18n.resolvedLanguage : 'es',
  load: async (language, module) => {
    const resource = await resourceLoaders[language][module]()
    i18n.addResourceBundle(language, 'translation', resource, true, true)
  },
  change: language => i18n.changeLanguage(language),
  persist: persistLanguagePreference,
})

export const ensureInterfaceResources = resources.ensure

export async function setInterfaceLanguage(language: string): Promise<void> {
  if (isInterfaceLanguage(language)) await resources.select(language)
}

export async function initializeInterfaceLanguage() {
  const preferred = readLanguagePreference()
  if (preferred === 'es') return
  try { await setInterfaceLanguage(preferred) } catch {
    // Keep the working Spanish shell and the saved preference; selector can retry.
  }
}

export default i18n
