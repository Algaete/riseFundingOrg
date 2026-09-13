import type { TranslationShape } from '../resource-types'
import type { partnerGeographyEs } from './es'

export const partnerGeographyEn = {
  "title": "Permitted partner countries and regions",
  "help": "Record the headquarters country required by the terms for partner organizations. This does not change applicant eligibility or project location. Do not infer this requirement from the funder's country.",
  "scope": "Partner geographic scope",
  "scopes": {
    "0": "Pending confirmation",
    "1": "No geographic restriction, confirmed in the terms",
    "2": "Specific countries or regions"
  },
  "regionsTitle": "Regions or country groups",
  "countriesTitle": "Specific countries",
  "search": "Search for a country",
  "selected": "Selected countries",
  "union": "Any selected country or country within a selected region is allowed. Select at least one.",
  "distinction": "Europe (UN M49) and the European Union are different groups. If the terms use another definition, select its specific countries. Regions do not automatically include politically associated territories.",
  "regions": {
    "M49-002": "Africa (UN M49)",
    "M49-019": "Americas (UN M49)",
    "M49-142": "Asia (UN M49)",
    "M49-150": "Europe (UN M49)",
    "M49-009": "Oceania (UN M49)",
    "M49-419": "Latin America and the Caribbean (UN M49)",
    "EU": "European Union (27 countries)"
  },
  "catalogUnavailable": "The geographic catalog is unavailable. Your saved selection is preserved; retry loading it to edit.",
  "unavailableCountry": "Unavailable country ({{id}})",
  "remove": "Remove {{country}}",
  "choose": "Select at least one country or region.",
  "reconfirm": "I have reviewed the selection against the current catalog",
  "status": {
    "unverified": "Partner country or region pending confirmation: a different country does not guarantee admissibility.",
    "specific": "Filtered by headquarters country using the opportunity's reviewed selection.",
    "any": "The reviewed terms impose no additional geographic restriction on the partner.",
    "needs-review": "The geographic selection needs review. No organizations are suggested until it is corrected."
  },
  "summaryHelp": "We check declared headquarters, not full eligibility, consortium composition or whether you already have this partner. This filter does not apply to individual professionals.",
  "home": "Declared headquarters: {{country}}.",
  "unknownHome": "Headquarters country not reported.",
  "matched": "The headquarters country matches the reviewed geographic selection."
} satisfies TranslationShape<typeof partnerGeographyEs>
