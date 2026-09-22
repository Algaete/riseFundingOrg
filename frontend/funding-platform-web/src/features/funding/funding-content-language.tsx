import { useTranslation } from 'react-i18next'
import { Button } from '@/components/ui/button'
import type { FundingLocalization } from './funding-translations-api'
import type { useFundingContentLanguage } from './use-funding-content-language'

export function FundingContentLanguageNotice({ selection, localization }: {
  selection: ReturnType<typeof useFundingContentLanguage>
  localization?: FundingLocalization | null
}) {
  const { t } = useTranslation()
  if (!selection.enabled) return null
  const translated = localization?.status === 'translated' && localization.requestedLanguage === selection.locale
  return <aside className="mb-4 flex flex-wrap items-center justify-between gap-3 rounded-xl border bg-muted/40 p-4 text-sm" aria-label={t('fundingCatalog.contentLanguage')}>
    <p>{t(selection.original ? 'fundingCatalog.showingOriginal' : translated ? 'fundingCatalog.reviewedTranslation' : 'fundingCatalog.translationUnavailable')}</p>
    {(selection.original || translated) && <Button variant="outline" size="sm" onClick={selection.toggle}>
      {t(selection.original ? 'fundingCatalog.showSelectedLanguage' : 'fundingCatalog.showOriginal')}
    </Button>}
  </aside>
}
