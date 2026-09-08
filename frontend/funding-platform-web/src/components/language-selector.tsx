import { useTranslation } from 'react-i18next'

import { setInterfaceLanguage } from '@/i18n'

export function LanguageSelector() {
  const { t, i18n } = useTranslation()

  return (
    <select
      aria-label={t('language.label')}
      className="h-10 max-w-28 cursor-pointer rounded-lg border bg-card px-2.5 text-sm font-semibold text-card-foreground transition-colors hover:bg-accent focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
      value={i18n.resolvedLanguage ?? 'es'}
      onChange={event => void setInterfaceLanguage(event.target.value)}
    >
      <option lang="es" value="es">Español</option>
      <option lang="en" value="en">English</option>
    </select>
  )
}
