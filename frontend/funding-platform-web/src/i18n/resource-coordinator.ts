import type { InterfaceLanguage } from './language'

type ResourceCoordinatorOptions<M extends string> = {
  core: M
  load: (language: InterfaceLanguage, module: M) => Promise<void>
  current: () => InterfaceLanguage
  change: (language: InterfaceLanguage) => Promise<unknown>
  persist: (language: InterfaceLanguage) => void
}

// Coordinates resources independently of React, storage and the bundler.
export function createResourceCoordinator<M extends string>(options: ResourceCoordinatorOptions<M>) {
  const active = new Set<M>([options.core])
  const pending = new Map<string, Promise<void>>([['es:' + options.core, Promise.resolve()]])
  let wanted: InterfaceLanguage = options.current()
  let selection = 0
  let commit = Promise.resolve()

  async function load(language: InterfaceLanguage, modules: readonly M[]) {
    await Promise.all(modules.map(module => {
      const key = language + ':' + module
      if (!pending.has(key)) {
        const promise = Promise.resolve().then(() => options.load(language, module)).catch(error => {
          pending.delete(key)
          throw error
        })
        pending.set(key, promise)
      }
      return pending.get(key)
    }))
  }

  async function ensure(modules: readonly M[]) {
    modules.forEach(module => active.add(module))
    for (;;) {
      const requested = wanted
      const current = options.current()
      await load(current, modules)
      if (requested !== current) {
        try { await load(requested, modules) } catch (error) {
          // A failed optional language change must not break navigation in the
          // already working language. select() owns the visible failure notice.
          if (current === options.current()) return
          throw error
        }
      }
      if (requested === wanted && current === options.current()) return
    }
  }

  async function select(language: InterfaceLanguage) {
    const request = ++selection
    wanted = language
    try {
      let size: number
      do {
        size = active.size
        await load(language, [...active])
      } while (size !== active.size)
      // Serial commits also protect callers whose language adapter is asynchronous.
      commit = commit.catch(() => undefined).then(async () => {
        if (request !== selection) return
        await options.change(language)
        if (request === selection) options.persist(language)
      })
      await commit
    } catch (error) {
      if (request === selection) {
        wanted = options.current()
        throw error
      }
    }
  }

  return { ensure, select }
}
