import { executeEditorialCommand } from '@/features/funding/editorial-command-cache'

describe('editorial command idempotency cache', () => {
  beforeEach(() => sessionStorage.clear())

  it('reuses the same key after an ambiguous failure without storing the payload', async () => {
    const keys: string[] = []
    const payload = { title: 'Contenido editorial sensible', aliases: ['Uno', 'Dos'] }

    for (let attempt = 0; attempt < 2; attempt += 1) {
      await expect(executeEditorialCommand('funder:create', payload, (key) => {
        keys.push(key)
        return Promise.reject(new TypeError('network unavailable'))
      })).rejects.toThrow('network unavailable')
    }

    expect(keys).toHaveLength(2)
    expect(keys[0]).toBe(keys[1])
    const storedValues = Array.from(
      { length: sessionStorage.length },
      (_, index) => sessionStorage.getItem(sessionStorage.key(index) ?? ''),
    ).join('')
    expect(storedValues).not.toContain(payload.title)
    expect(storedValues).not.toContain(payload.aliases[0])
  })

  it('rotates the key when the payload changes and clears it after success', async () => {
    const keys: string[] = []
    const fail = (key: string) => {
      keys.push(key)
      return Promise.reject(new Error('ambiguous'))
    }

    await expect(executeEditorialCommand('opportunity:create', { title: 'A' }, fail)).rejects.toThrow()
    await expect(executeEditorialCommand('opportunity:create', { title: 'B' }, fail)).rejects.toThrow()
    expect(keys[0]).not.toBe(keys[1])

    await executeEditorialCommand('opportunity:create', { title: 'B' }, async (key) => {
      keys.push(key)
      return { ok: true }
    })
    expect(keys[2]).toBe(keys[1])

    await expect(executeEditorialCommand('opportunity:create', { title: 'B' }, fail)).rejects.toThrow()
    expect(keys[3]).not.toBe(keys[2])
  })
})
