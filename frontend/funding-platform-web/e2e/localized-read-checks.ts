import { expect } from '@playwright/test'

// Exact resource; only the documented optional locale query is accepted.
export const localizedResource = (path: string) => (url: URL) => url.pathname === path &&
  [...url.searchParams.keys()].every(key => key === 'locale') &&
  (!url.searchParams.has('locale') || ['es', 'en'].includes(url.searchParams.get('locale')!))

// With content translations enabled a language change intentionally fetches once.
// Without them the existing UI-only translation remains read-free. In both modes,
// every business filter and pagination value must be preserved exactly.
export async function expectLocaleSwitch(reads: () => readonly string[]) {
  const before = new URL(reads()[0], 'https://synthetic.example.invalid')
  const count = before.searchParams.has('locale') ? 2 : 1
  await expect.poll(() => reads().length).toBe(count)
  if (count === 2) {
    const after = new URL(reads()[1], 'https://synthetic.example.invalid')
    expect(before.searchParams.get('locale')).toBe('es')
    expect(after.searchParams.get('locale')).toBe('en')
    before.searchParams.delete('locale'); after.searchParams.delete('locale')
    expect(after.pathname + after.search).toBe(before.pathname + before.search)
  }
  return count
}
