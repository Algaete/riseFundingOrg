import { useEffect, useState } from 'react'
import { useTranslation } from 'react-i18next'

/** A delayed explanation for a slow first connection, with no polling or reload. */
export function SlowLoadingNotice() {
  const { t } = useTranslation()
  const [visible, setVisible] = useState(false)
  useEffect(() => {
    const timer = window.setTimeout(() => setVisible(true), 5_000)
    return () => window.clearTimeout(timer)
  }, [])
  return visible
    ? <p className="mt-3 text-sm leading-relaxed text-muted-foreground">{t('status.slowConnection')}</p>
    : null
}
