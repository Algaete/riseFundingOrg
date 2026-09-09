import type { ParseKeys } from 'i18next'
import i18n from '@/i18n'
import { catalogsEs } from '@/i18n/catalogs/es'
import { catalogsEn } from '@/i18n/catalogs/en'

export type CatalogKind = keyof typeof catalogsEs
type CatalogItem = { code: string; name: string }
type CatalogKey = Extract<ParseKeys, `catalogs.${string}`>
type CatalogEntry = { key: CatalogKey; names: readonly string[] }

// Index by kind + stable code + exact source label. IDs, order and query cache stay untouched.
// A renamed row or a new/custom code remains original until its translation is reviewed.
const entries = new Map<CatalogKind, Map<string, Map<string, CatalogEntry>>>()
for (const kind of Object.keys(catalogsEs) as CatalogKind[]) {
  const codes = new Map<string, Map<string, CatalogEntry>>()
  const english = catalogsEn[kind] as Record<string, Record<string, string>>
  for (const [code, variants] of Object.entries(catalogsEs[kind] as Record<string, Record<string, string>>)) {
    const labels = new Map<string, CatalogEntry>()
    for (const [variant, name] of Object.entries(variants)) {
      labels.set(name, {
        key: `catalogs.${kind}.${code}.${variant}` as CatalogKey,
        names: [name, english[code][variant]],
      })
    }
    codes.set(code, labels)
  }
  entries.set(kind, codes)
}

function entry(kind: CatalogKind, item: CatalogItem) {
  return entries.get(kind)?.get(item.code)?.get(item.name)
}

export function catalogName(kind: CatalogKind, item: CatalogItem): string {
  const known = entry(kind, item)
  // Preserve the server's exact Spanish spelling, including legacy versions.
  return i18n.resolvedLanguage === 'en' && known ? i18n.t(known.key) : item.name
}

export function catalogLanguage(kind: CatalogKind, item: CatalogItem): 'es' | 'en' {
  // The current API catalog contract supplies Spanish labels, unlike user-authored content.
  return i18n.resolvedLanguage === 'en' && entry(kind, item) ? 'en' : 'es'
}

export function catalogAliases(kind: CatalogKind, item: CatalogItem): readonly string[] {
  // Validate against the same official option in both interface languages. Do not translate
  // custom values, accept fuzzy code/name matches or broaden legacy labels into newer ones.
  return entry(kind, item)?.names ?? [item.name]
}
