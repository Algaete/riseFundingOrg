import { catalogsEs } from './catalogs/es'
import { catalogsEn } from './catalogs/en'
import { catalogAliases, catalogLanguage, catalogName, type CatalogKind } from './catalog-labels'
import { setInterfaceLanguage } from '@/i18n'

const kinds = Object.keys(catalogsEs) as CatalogKind[]

describe('catalog labels are presentation only', () => {
  it.each(kinds)('translates reviewed %s labels without changing source objects', async kind => {
    const entries = catalogsEs[kind] as Record<string, Record<string, string>>
    const english = catalogsEn[kind] as Record<string, Record<string, string>>
    for (const [code, variants] of Object.entries(entries)) {
      for (const [variant, name] of Object.entries(variants)) {
        const item = Object.freeze({ id: 987654, code, name })
        await setInterfaceLanguage('es')
        expect(catalogName(kind, item)).toBe(name)
        expect(catalogLanguage(kind, item)).toBe('es')
        await setInterfaceLanguage('en')
        expect(catalogName(kind, item)).toBe(english[code][variant])
        expect(catalogLanguage(kind, item)).toBe('en')
        expect(catalogAliases(kind, item)).toEqual([name, english[code][variant]])
        expect(item).toEqual({ id: 987654, code, name })
      }
    }
  })

  it('keeps unknown, renamed, wrong-kind and prototype-like records unchanged', async () => {
    await setInterfaceLanguage('en')
    for (const item of [
      { code: 'FOUNDATION', name: 'Fundación Ñandú personalizada' },
      { code: 'NEW', name: 'Fundación' },
      { code: 'foundation', name: 'Fundación' },
      { code: 'FOUNDATION', name: ' Fundación ' },
      { code: '__proto__', name: 'Fundación' },
      { code: 'toString', name: 'Fundación' },
    ]) {
      expect(catalogName('organizationTypes', item)).toBe(item.name)
      expect(catalogLanguage('organizationTypes', item)).toBe('es')
      expect(catalogAliases('organizationTypes', item)).toEqual([item.name])
    }
    expect(catalogName('projectTypes', { code: 'FOUNDATION', name: 'Fundación' })).toBe('Fundación')
    expect(catalogName('regions', { code: 'CL-NB', name: 'Ñuble' })).toBe('Ñuble')
    expect(catalogName('tags', { code: 'ENVIRONMENT', name: 'Medio ambiente' })).toBe('Medio ambiente')
  })

  it('does not silently widen old catalog wording or replace historical size bands', async () => {
    await setInterfaceLanguage('en')
    expect(catalogName('fundingCategories', { code: 'ENVIRONMENT', name: 'Medio ambiente' })).toBe('Environment')
    expect(catalogName('fundingCategories', { code: 'ENVIRONMENT', name: 'Medio ambiente y biodiversidad' })).toBe('Environment and biodiversity')
    expect(catalogAliases('fundingCategories', { code: 'ENVIRONMENT', name: 'Medio ambiente' })).not.toContain('Environment and biodiversity')
    expect(catalogName('projectTypes', { code: 'ADVOCACY', name: 'Incidencia' })).toBe('Advocacy')
    expect(catalogName('projectTypes', { code: 'ADVOCACY', name: 'Incidencia y políticas públicas' })).toBe('Advocacy and public policy')
    expect(catalogName('organizationSizes', { code: 'SMALL', name: 'Pequeña' })).toBe('Small')
    expect(catalogName('organizationSizes', { code: 'EMPLOYEES_11_50', name: '11–50 personas' })).toBe('11–50 people')
  })

  it('covers all 17 SDG codes independently from their database identifiers', async () => {
    expect(Object.keys(catalogsEs.sustainableDevelopmentGoals)).toEqual(
      Array.from({ length: 17 }, (_, index) => 'SDG_' + String(index + 1).padStart(2, '0')),
    )
    await setInterfaceLanguage('en')
    const item = { id: 999, code: 'SDG_06', name: 'Agua limpia y saneamiento' }
    expect(catalogName('sustainableDevelopmentGoals', item)).toBe('Clean Water and Sanitation')
  })
})
