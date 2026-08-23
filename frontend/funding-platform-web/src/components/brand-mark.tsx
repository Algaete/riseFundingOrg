import { Sparkles } from 'lucide-react'
import { Link } from 'react-router-dom'
import { useTranslation } from 'react-i18next'

export function BrandMark({ compact = false }: { compact?: boolean }) {
  const { t } = useTranslation()

  return (
    <Link
      to="/"
      className="inline-flex items-center gap-2 rounded-lg font-bold tracking-tight"
      aria-label={t('appName')}
    >
      <span className="grid size-9 place-items-center rounded-xl bg-primary text-primary-foreground">
        <Sparkles className="size-5" aria-hidden="true" />
      </span>
      {!compact && <span>{t('appName')}</span>}
    </Link>
  )
}
