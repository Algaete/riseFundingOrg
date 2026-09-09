import type { ParseKeys } from 'i18next'
import i18n from '@/i18n'
import { catalogsEs } from './catalogs/es'

export type CatalogKind = keyof typeof catalogsEs
export type CatalogItem = { code: string; name: string }
type CatalogKey = Extract<ParseKeys, `catalogs.${string}`>
type CatalogEntry = { key: CatalogKey; variant: string }

// Display-only consumers must not eagerly download the English validation aliases.
// Match kind + stable code + exact reviewed Spanish label; preserve unknown/custom values.
const entries = new Map<CatalogKind, Map<string, Map<string, CatalogEntry>>>()
for (const kind of Object.keys(catalogsEs) as CatalogKind[]) {
  const codes = new Map<string, Map<string, CatalogEntry>>()
  for (const [code, variants] of Object.entries(catalogsEs[kind] as Record<string, Record<string, string>>)) {
    const labels = new Map<string, CatalogEntry>()
    for (const [variant, name] of Object.entries(variants)) labels.set(name, { key: `catalogs.${kind}.${code}.${variant}` as CatalogKey, variant })
    codes.set(code, labels)
  }
  entries.set(kind, codes)
}
export function catalogEntry(kind: CatalogKind, item: CatalogItem) {
  return entries.get(kind)?.get(item.code)?.get(item.name)
}
export function catalogName(kind: CatalogKind, item: CatalogItem): string {
  const known = catalogEntry(kind, item)
  return i18n.resolvedLanguage === 'en' && known ? i18n.t(known.key) : item.name
}
export function catalogLanguage(kind: CatalogKind, item: CatalogItem): 'es' | 'en' {
  return i18n.resolvedLanguage === 'en' && catalogEntry(kind, item) ? 'en' : 'es'
}
