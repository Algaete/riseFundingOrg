import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { expect, it } from 'vitest'
import { validationEs } from '../src/i18n/validation/es'
import { validationEn } from '../src/i18n/validation/en'

it('covers every code emitted by organization and project write validators in both languages', () => {
  const services = ['Organizations/OrganizationProfileService.cs', 'Projects/ProjectService.cs']
  const codes = new Set()
  for (const service of services) {
    const source = readFileSync(resolve(process.cwd(), '../../src/FundingPlatform.Application', service), 'utf8')
    for (const match of source.matchAll(/(?:errors\.Set|FieldValidationErrors\.Single)\([^,\n]+,\s*"([a-z-]+)"/g)) {
      codes.add(match[1])
    }
    expect(source).not.toMatch(/errors\[[^\n]+\]\s*=/)
    expect(source).not.toContain('new Dictionary<string, string[]>')
  }
  expect([...codes].sort()).toEqual(Object.keys(validationEs).sort())
  expect(Object.keys(validationEn).sort()).toEqual([...codes].sort())
})
