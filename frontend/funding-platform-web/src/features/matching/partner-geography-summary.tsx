import { useQuery } from '@tanstack/react-query'
import { useTranslation } from 'react-i18next'
import { catalogName } from '@/i18n/catalog-labels'
import { fundingDiscoveryApi } from '@/features/funding-discovery/funding-discovery-api'
import type { GapRecommendations } from './gap-recommendations-api'

// Mounted only with an explicitly requested result; the catalog contains no private profile data.
export function PartnerGeographySummary({ data }: { data: GapRecommendations }) {
  const { t } = useTranslation()
  const state = data.geographyState ?? 'unverified'
  const countries = useQuery({ queryKey: ['funding-discovery-catalogs'], queryFn: ({ signal }) => fundingDiscoveryApi.catalogs(signal),
    enabled: state === 'specific', retry: false, staleTime: 300000, refetchOnWindowFocus: false, refetchOnReconnect: false })
  return <aside className="space-y-2 rounded-lg border p-3 text-sm" aria-label={t('matching.gaps.geography.title')}>
    <p>{t(`matching.gaps.geography.status.${state}`)}</p>
    {state === 'specific' && <ul className="flex flex-wrap gap-x-4 gap-y-1">
      {data.partnerGeography?.regionCodes.map(code => <li key={code}>{t(`matching.gaps.geography.regions.${code}`, { defaultValue: code })}</li>)}
      {data.partnerGeography?.countryIds.map(id => {
        const country = countries.data?.countries.find(item => item.id === id)
        return <li key={id}>{country ? catalogName('countries', country) : t('matching.gaps.geography.unavailableCountry', { id })}</li>
      })}
    </ul>}
    <p className="text-muted-foreground">{t('matching.gaps.geography.summaryHelp')}</p>
  </aside>
}

export function PartnerCountryEvidence({ id }: { id: number | null }) {
  const { t } = useTranslation()
  const catalogs = useQuery({ queryKey: ['funding-discovery-catalogs'], queryFn: ({ signal }) => fundingDiscoveryApi.catalogs(signal),
    enabled: id !== null, retry: false, staleTime: 300000, refetchOnWindowFocus: false, refetchOnReconnect: false })
  const country = catalogs.data?.countries.find(item => item.id === id)
  return <p className="text-sm">{id === null ? t('matching.gaps.geography.unknownHome') : t('matching.gaps.geography.home', {
    country: country ? catalogName('countries', country) : t('matching.gaps.geography.unavailableCountry', { id }),
  })}</p>
}
