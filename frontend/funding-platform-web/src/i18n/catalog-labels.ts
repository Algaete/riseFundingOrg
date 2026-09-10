import { catalogsEn } from '@/i18n/catalogs/en'
import { catalogEntry, type CatalogKind, type CatalogItem } from './catalog-display'
export { catalogName, catalogLanguage, type CatalogKind } from './catalog-display'

export function catalogAliases(kind: CatalogKind, item: CatalogItem): readonly string[] {
  // Validate against the same official option in both interface languages. Do not translate
  // custom values, accept fuzzy code/name matches or broaden legacy labels into newer ones.
  const known = catalogEntry(kind, item)
  const english = catalogsEn[kind] as Record<string, Record<string, string>>
  return known ? [item.name, english[item.code][known.variant]] : [item.name]
}
