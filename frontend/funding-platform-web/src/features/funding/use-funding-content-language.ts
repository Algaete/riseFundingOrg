import { useState } from 'react'
import { useTranslation } from 'react-i18next'
import { fundingTranslationsEnabled, type FundingLanguage } from './funding-translations-api'

export function useFundingContentLanguage() {
  const { i18n } = useTranslation()
  const language: FundingLanguage = i18n.resolvedLanguage?.startsWith('en') ? 'en' : 'es'
  const [originalFor, setOriginalFor] = useState<FundingLanguage | null>(null)
  const enabled = fundingTranslationsEnabled()
  const original = originalFor === language
  return {
    enabled, original,
    locale: enabled && !original ? language : undefined,
    toggle: () => setOriginalFor(original ? null : language),
  }
}
