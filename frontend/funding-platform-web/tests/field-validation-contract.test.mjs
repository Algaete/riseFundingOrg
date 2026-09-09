import { readFileSync, readdirSync } from 'node:fs'
import { resolve } from 'node:path'
import { expect, it } from 'vitest'
import { validationEs } from '../src/i18n/validation/es'
import { validationEn } from '../src/i18n/validation/en'

function sources(directory) {
  return readdirSync(directory, { withFileTypes: true }).flatMap(entry => {
    if (['bin', 'obj'].includes(entry.name)) return []
    const path = resolve(directory, entry.name)
    return entry.isDirectory() ? sources(path) : entry.name.endsWith('.cs') ? [readFileSync(path, 'utf8')] : []
  })
}

it('covers static field codes across every application and API module in both languages', () => {
  const files = ['Application', 'Api'].flatMap(layer =>
    sources(resolve(process.cwd(), '../../src/FundingPlatform.' + layer)))
  const codes = new Set()
  for (const source of files) {
    for (const match of source.matchAll(/(?:errors\.(?:Set|Add)|FieldValidationErrors\.Single)\([^,\n]+,\s*"([a-z0-9-]+)"/g)) codes.add(match[1])
    for (const match of source.matchAll(/\{\s*"[^"]+",\s*"([a-z0-9-]+)",\s*\$?"/g)) codes.add(match[1])
    for (const match of source.matchAll(/"(api-validation-\d+)"/g)) codes.add(match[1])
    expect(source).not.toMatch(/errors\[[^\n]+\]\s*=/)
    expect(source.replace('errors ?? new Dictionary<string, string[]>()', '')).not.toContain('new Dictionary<string, string[]>')
  }
  expect(codes.size).toBeGreaterThan(200)
  for (const code of codes) {
    expect(validationEs, code).toHaveProperty(code)
    expect(validationEn, code).toHaveProperty(code)
  }
  expect(Object.keys(validationEs).sort()).toEqual(Object.keys(validationEn).sort())
})

it('has no duplicate IDs in the extended validation catalogs', () => {
  for (const language of ['es', 'en']) {
    const source = readFileSync(resolve('src/i18n/api-validation', language + '.ts'), 'utf8')
    const codes = [...source.matchAll(/['"]([^'"]+)['"]:/g)].map(match => match[1])
    expect(codes.length).toBeGreaterThan(200)
    expect(new Set(codes).size).toBe(codes.length)
  }
})
