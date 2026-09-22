import { useTranslation } from 'react-i18next'
import { Button } from '@/components/ui/button'
import type { FundingLocalization } from './funding-translations-api'
import type { useFundingContentLanguage } from './use-funding-content-language'

export function FundingListLanguageNotice({ selection }: { selection: ReturnType<typeof useFundingContentLanguage> }) {
  const { t } = useTranslation()
  if (!selection.enabled) return null
  return <aside className="flex flex-wrap items-center justify-between gap-3 rounded-xl border bg-muted/40 p-4 text-sm">
    <p>{t(selection.original ? 'fundingCatalog.listOriginal' : 'fundingCatalog.listLanguageHelp')}</p>
    <Button type="button" variant="outline" size="sm" onClick={selection.toggle}>
      {t(selection.original ? 'fundingCatalog.showSelectedLanguage' : 'fundingCatalog.showOriginal')}
    </Button>
  </aside>
}

export function FundingListTranslationLabel({ localization }: { localization?: FundingLocalization | null }) {
  const { t } = useTranslation()
  if (!localization) return null
  return <p className="text-xs text-muted-foreground">{t(localization.status === 'translated'
    ? 'fundingCatalog.listReviewed' : 'fundingCatalog.listUntranslated')}</p>
}
