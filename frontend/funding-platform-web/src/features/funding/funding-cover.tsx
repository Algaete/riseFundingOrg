import { ImageIcon } from 'lucide-react'
import { useState } from 'react'
import { useTranslation } from 'react-i18next'
import { resolveFundingCover } from './funding-covers'

export function FundingCover({ coverKey, detail = false, compact = false }: {
  coverKey?: string | null; detail?: boolean; compact?: boolean
}) {
  const { t } = useTranslation()
  const cover = resolveFundingCover(coverKey)
  const [failedSource, setFailedSource] = useState<string | null>(null)
  const failed = failedSource === cover.src
  const label = t(`fundingCatalog.${cover.label}`)
  return <div role="img" aria-label={t('fundingCatalog.coverImageLabel', { theme: label })}
    className={`relative overflow-hidden bg-gradient-to-br from-emerald-950 to-teal-700 ${compact ? 'h-24' : detail ? 'h-64 sm:h-72' : 'h-40'}`}>
    {!failed && <img src={cover.src} alt="" width={1200} height={800} loading={detail ? 'eager' : 'lazy'}
      decoding="async" className="absolute inset-0 h-full w-full object-cover" onError={() => setFailedSource(cover.src)} />}
    {failed && <ImageIcon aria-hidden="true" className="absolute inset-0 m-auto size-12 text-white/80" />}
    {!compact && <div className="absolute inset-x-0 bottom-0 bg-gradient-to-t from-black/65 to-transparent px-4 pb-3 pt-9">
      <span className="rounded-full bg-black/60 px-2.5 py-1 text-xs font-medium text-white">{t('fundingCatalog.coverIllustration')}</span>
    </div>}
  </div>
}
