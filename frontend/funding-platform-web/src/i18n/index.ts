import i18n from 'i18next'
import { initReactI18next } from 'react-i18next'

import { es } from '@/i18n/es'

void i18n.use(initReactI18next).init({
  resources: { es },
  lng: 'es',
  fallbackLng: 'es',
  interpolation: { escapeValue: false },
})

export default i18n
