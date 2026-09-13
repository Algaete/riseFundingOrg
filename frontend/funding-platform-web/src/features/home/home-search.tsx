import { useQuery } from '@tanstack/react-query'
import { Grid2X2, MapPin, Search } from 'lucide-react'
import { useEffect, useState, type FormEvent } from 'react'
import { useTranslation } from 'react-i18next'
import { useLocation, useNavigate } from 'react-router-dom'
import { marketplaceApi } from '@/features/marketplace/marketplace-api'
import { catalogLanguage, catalogName } from '@/i18n/catalog-display'
import { homeSearchUrl, type HomeSearchScope } from './home-model'

export function HomeSearch() {
  const { t } = useTranslation()
  const navigate = useNavigate()
  const { hash } = useLocation()
  useEffect(() => { if (hash === '#home-search') document.getElementById('home-search-query')?.focus() }, [hash])
  const [scope, setScope] = useState<HomeSearchScope>('all')
  const [query, setQuery] = useState('')
  const [country, setCountry] = useState('')
  const [category, setCategory] = useState('')
  const catalogs = useQuery({ queryKey: ['marketplace', 'catalogs'], queryFn: ({ signal }) => marketplaceApi.catalogs(signal), staleTime: 60 * 60 * 1000, retry: false })
  function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    navigate(homeSearchUrl(scope, query, country, category))
  }
  return <form id="home-search" className="home-search" role="search" aria-label={t('home.search.title')} onSubmit={submit}>
    <fieldset className="home-search-scopes">
      <legend className="sr-only">{t('home.search.scope')}</legend>
      <span aria-hidden="true">{t('home.search.scope')}</span>
      {(['all', 'projects', 'funding', 'organizations', 'professionals'] as const).map(value => <label key={value} className={scope === value ? 'is-selected' : ''}>
        <input className="home-scope-radio" type="radio" name="home-search-scope" value={value} checked={scope === value} onChange={() => setScope(value)} />
        {t(`home.search.${value}`)}
      </label>)}
    </fieldset>
    <div className="home-search-row">
      <div className="home-search-fields">
        <label className="home-search-query"><Search size={19} aria-hidden="true" />
          <span className="sr-only">{t('home.search.query')}</span>
          <input id="home-search-query" type="search" placeholder={t('home.search.placeholder')} maxLength={200} value={query} onChange={event => setQuery(event.target.value)} />
        </label>
        <label className="home-search-select"><MapPin size={18} aria-hidden="true" />
          <span className="sr-only">{t('home.search.country')}</span>
          <select disabled={!catalogs.data} value={country} onChange={event => setCountry(event.target.value)}>
            <option value="">{t('home.search.allCountries')}</option>
            {catalogs.data?.countries.map(item => <option key={item.id} value={item.id} lang={catalogLanguage('countries', item)}>{catalogName('countries', item)}</option>)}
          </select>
        </label>
        <label className="home-search-select"><Grid2X2 size={18} aria-hidden="true" />
          <span className="sr-only">{t('home.search.sector')}</span>
          <select disabled={!catalogs.data} value={category} onChange={event => setCategory(event.target.value)}>
            <option value="">{t('home.search.allSectors')}</option>
            {catalogs.data?.fundingCategories.map(item => <option key={item.id} value={item.id} lang={catalogLanguage('fundingCategories', item)}>{catalogName('fundingCategories', item)}</option>)}
          </select>
        </label>
      </div>
      <button className="home-primary home-search-submit" type="submit">{t('home.search.submit')}</button>
    </div>
    {catalogs.isError && <p className="home-inline-feedback" role="status">{t('home.search.catalogsError')} <button type="button" onClick={() => void catalogs.refetch()}>{t('home.search.retry')}</button></p>}
  </form>
}
