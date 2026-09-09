import type { adminFundersEs } from './es'
import type { TranslationShape } from '@/i18n/resource-types'

export const adminFundersEn = {
  "name": "Name",
  "description": "Description",
  "website": "Official website",
  "country": "Country",
  "aliases": "Known aliases",
  "namePlaceholder": "E.g. Foundation for Development",
  "descriptionPlaceholder": "Mission, scope and funding areas",
  "aliasesPlaceholder": "One alias per line; you can also separate them with commas",
  "loadingCountries": "Loading countries…",
  "countriesFailed": "The available countries could not be loaded.",
  "details": "Funder details",
  "new": "New funder",
  "noCountry": "No country reported",
  "create": "Create funder",
  "title": "Funders",
  "intro": "Standardize organizations, aliases and official websites before linking them to opportunities.",
  "search": "Search funders",
  "searchPlaceholder": "Name or alias",
  "loading": "Loading funders…",
  "empty": "No funders found",
  "emptyHelp": "Create the first one or change the filters.",
  "officialSite": "Official website",
  "pagination": "Funder pagination",
  "loadingDetail": "Loading funder…",
  "openFailed": "We could not open the funder",
  "back": "Back to funders",
  "count": "{{count}} funders"
} satisfies TranslationShape<typeof adminFundersEs>
