import { useTranslation } from 'react-i18next'
import { useState } from 'react'

import { setInterfaceLanguage } from '@/i18n'

export function LanguageSelector() {
  const { t, i18n } = useTranslation()
  const [failed, setFailed] = useState(false)
  const [pending, setPending] = useState(false)

  return (
    <span className="inline-flex w-24 min-w-0 shrink-0 flex-col gap-1">
    <select
      aria-label={t('language.label')}
      className="h-10 w-full min-w-0 cursor-pointer rounded-lg border bg-card px-2.5 text-sm font-semibold text-card-foreground transition-colors hover:bg-accent focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
      value={i18n.resolvedLanguage ?? 'es'}
      aria-busy={pending}
      disabled={pending}
      onChange={event => {
        setFailed(false)
        setPending(true)
        void setInterfaceLanguage(event.target.value).catch(() => setFailed(true)).finally(() => setPending(false))
      }}
    >
      <option lang="es" value="es">Español</option>
      <option lang="en" value="en">English</option>
    </select>
    {failed && <span className="text-xs text-destructive" role="alert">{t('language.loadError')}</span>}
    </span>
  )
}
