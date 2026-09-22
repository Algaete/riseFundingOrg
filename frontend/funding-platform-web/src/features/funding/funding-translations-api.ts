import { apiClient } from '@/api/http-client'

export type FundingLanguage = 'es' | 'en'
export const translationFields = [
  ['title', 350], ['summary', 2000], ['description', 50000],
  ['eligibilityDescription', 30000], ['requirements', 30000], ['objectives', 30000],
  ['allowedActivities', 30000], ['excludedActivities', 30000], ['restrictions', 30000],
  ['targetOrganizationsDescription', 2000], ['targetPopulationsDescription', 2000],
] as const
export type TranslationField = typeof translationFields[number][0]
export type FundingTranslationText = Record<TranslationField, string | null>
export interface FundingLocalization {
  requestedLanguage: FundingLanguage
  status: 'original' | 'translated'
  revision: number | null
}
export interface FundingTranslation {
  language: FundingLanguage
  sourceContentVersion: number
  revision: number
  reviewed: boolean
  text: FundingTranslationText
  updatedAtUtc: string
}
export interface FundingTranslationWrite {
  sourceContentVersion: number
  expectedRevision: number
  reviewed: boolean
  text: FundingTranslationText
}
export function fundingTranslationsEnabled() {
  return import.meta.env.VITE_FUNDING_TRANSLATIONS_ENABLED === 'true'
}
function path(id: string, language: FundingLanguage) {
  return `admin/funding-opportunities/${encodeURIComponent(id)}/translations/${language}`
}
export const fundingTranslationsApi = {
  get(id: string, language: FundingLanguage, signal?: AbortSignal) {
    return apiClient.get<{ translation: FundingTranslation | null }>(path(id, language), { signal, cache: 'no-store' })
  },
  save(id: string, language: FundingLanguage, eTag: string, input: FundingTranslationWrite) {
    return apiClient.put<FundingTranslation>(path(id, language), input, { headers: { 'If-Match': eTag } })
  },
}
