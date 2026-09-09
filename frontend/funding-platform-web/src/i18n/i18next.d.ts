import 'i18next'
import type { es } from '@/i18n/es'

declare module 'i18next' {
  interface CustomTypeOptions {
    defaultNS: 'translation'
    resources: typeof es
  }
}
