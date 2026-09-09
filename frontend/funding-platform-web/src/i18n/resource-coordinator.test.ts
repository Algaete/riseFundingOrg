import { createResourceCoordinator } from './resource-coordinator'
import type { InterfaceLanguage } from './language'

function deferred() {
  let resolve!: () => void
  let reject!: (reason: Error) => void
  const promise = new Promise<void>((yes, no) => { resolve = yes; reject = no })
  return { promise, resolve, reject }
}

function harness(load = vi.fn(async (_language: InterfaceLanguage, _module: string) => {})) {
  let current: InterfaceLanguage = 'es'
  const persist = vi.fn()
  const change = vi.fn(async (language: InterfaceLanguage) => { current = language })
  const coordinator = createResourceCoordinator<string>({
    core: 'core', load, current: () => current, change, persist,
  })
  return { ...coordinator, load, persist, change, current: () => current }
}

it('loads only requested modules in the current language, deduplicating concurrent calls', async () => {
  const h = harness()
  await Promise.all([h.ensure(['projects']), h.ensure(['projects'])])
  expect(h.load.mock.calls).toEqual([['es', 'projects']])
  await h.select('en')
  expect(h.load.mock.calls).toEqual([['es', 'projects'], ['en', 'core'], ['en', 'projects']])
  await h.select('es')
  await h.select('en')
  expect(h.load).toHaveBeenCalledTimes(3)
})

it('keeps the previous language and preference on failure and retries failed resources', async () => {
  const h = harness(vi.fn(async (language, module) => {
    if (language === 'en' && module === 'projects') throw new Error('synthetic chunk failure')
  }))
  await h.ensure(['projects'])
  await expect(h.select('en')).rejects.toThrow('synthetic chunk failure')
  expect(h.current()).toBe('es')
  expect(h.persist).not.toHaveBeenCalled()
  h.load.mockImplementation(async () => {})
  await h.select('en')
  expect(h.current()).toBe('en')
  expect(h.persist).toHaveBeenCalledExactlyOnceWith('en')
  expect(h.load.mock.calls.filter(([lang, mod]) => lang === 'en' && mod === 'core')).toHaveLength(1)
  expect(h.load.mock.calls.filter(([lang, mod]) => lang === 'en' && mod === 'projects')).toHaveLength(2)
})

it.each([false, true])('last selection wins over a pending older request (failure=%s)', async failure => {
  const gate = deferred()
  const h = harness(vi.fn(async language => { if (language === 'en') await gate.promise }))
  const old = h.select('en')
  await h.select('es')
  if (failure) gate.reject(new Error('stale failure'))
  else gate.resolve()
  await old
  expect(h.current()).toBe('es')
  expect(h.persist).toHaveBeenCalledExactlyOnceWith('es')
})

it('includes a newly opened route before committing a pending language change', async () => {
  const gate = deferred()
  const h = harness(vi.fn(async (language, module) => {
    if (language === 'en' && module === 'core') await gate.promise
  }))
  const selection = h.select('en')
  await h.ensure(['funding'])
  expect(h.current()).toBe('es')
  gate.resolve()
  await selection
  expect(h.current()).toBe('en')
  expect(h.load.mock.calls).toContainEqual(['es', 'funding'])
  expect(h.load.mock.calls).toContainEqual(['en', 'funding'])
})

it('keeps a new route usable in the current language if the requested language fails', async () => {
  const gate = deferred()
  const h = harness(vi.fn(async (language, module) => {
    if (language === 'en' && module === 'core') await gate.promise
    if (language === 'en' && module === 'funding') throw new Error('synthetic funding chunk failure')
  }))
  const selection = h.select('en')
  await expect(h.ensure(['funding'])).resolves.toBeUndefined()
  expect(h.current()).toBe('es')
  gate.resolve()
  await expect(selection).rejects.toThrow('synthetic funding chunk failure')
  expect(h.persist).not.toHaveBeenCalled()
})
