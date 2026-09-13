import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { expect, it } from 'vitest'
import { catalogsEs } from '../src/i18n/catalogs/es'

// Read repository seeds in the test runner, without bundling SQL or widening
// the development server's filesystem access or the app's browser-only types.
it('keeps reviewed catalog source labels grounded in versioned database seeds', () => {
  const directory = resolve(process.cwd(), '../../database/Migrations')
  const migrations = [
    '001_initial_schema.sql',
    '031_organization_profile_catalog_expansion.sql',
    '033_project_impact_profile.sql',
    '034_organization_funding_experience_types.sql',
    '048_world_country_catalog.sql',
  ].map(name => readFileSync(resolve(directory, name), 'utf8')).join('\n')

  for (const entries of Object.values(catalogsEs)) {
    for (const [code, variants] of Object.entries(entries)) {
      expect(migrations).toContain("'" + code + "'")
      for (const name of Object.values(variants)) {
        expect(migrations).toContain("N'" + name.replaceAll("'", "''") + "'")
      }
    }
  }
})
