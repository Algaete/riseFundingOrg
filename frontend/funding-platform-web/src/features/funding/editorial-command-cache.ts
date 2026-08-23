const storagePrefix = 'funding-platform:editorial-command:'
const commandLifetimeMs = 24 * 60 * 60 * 1000

interface StoredEditorialCommand {
  fingerprint: string
  idempotencyKey: string
  createdAt: number
}

function canonicalize(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(canonicalize)
  if (value === null || typeof value !== 'object') return value

  return Object.fromEntries(
    Object.entries(value)
      .filter(([, entry]) => entry !== undefined)
      .sort(([left], [right]) => left.localeCompare(right))
      .map(([key, entry]) => [key, canonicalize(entry)]),
  )
}

async function fingerprint(payload: unknown) {
  const bytes = new TextEncoder().encode(JSON.stringify(canonicalize(payload)))
  const digest = await crypto.subtle.digest('SHA-256', bytes)
  return Array.from(new Uint8Array(digest), (value) => value.toString(16).padStart(2, '0')).join('')
}

function storageKey(scope: string) {
  return `${storagePrefix}${encodeURIComponent(scope)}`
}

function readStoredCommand(scope: string): StoredEditorialCommand | null {
  try {
    const serialized = sessionStorage.getItem(storageKey(scope))
    if (!serialized) return null

    const candidate = JSON.parse(serialized) as Partial<StoredEditorialCommand>
    if (
      typeof candidate.fingerprint !== 'string'
      || typeof candidate.idempotencyKey !== 'string'
      || typeof candidate.createdAt !== 'number'
      || Date.now() - candidate.createdAt > commandLifetimeMs
    ) {
      sessionStorage.removeItem(storageKey(scope))
      return null
    }

    return candidate as StoredEditorialCommand
  } catch {
    return null
  }
}

function writeStoredCommand(scope: string, command: StoredEditorialCommand) {
  try {
    sessionStorage.setItem(storageKey(scope), JSON.stringify(command))
  } catch {
    // Private browsing and storage policies may disable sessionStorage. The request
    // still remains safe because the server enforces idempotency per supplied key.
  }
}

function clearStoredCommand(scope: string, idempotencyKey: string) {
  const stored = readStoredCommand(scope)
  if (stored?.idempotencyKey !== idempotencyKey) return

  try {
    sessionStorage.removeItem(storageKey(scope))
  } catch {
    // Best effort only; a successful replay remains harmless on the server.
  }
}

async function getEditorialCommandId(scope: string, payload: unknown) {
  const payloadFingerprint = await fingerprint(payload)
  const stored = readStoredCommand(scope)
  if (stored?.fingerprint === payloadFingerprint) return stored.idempotencyKey

  const command: StoredEditorialCommand = {
    fingerprint: payloadFingerprint,
    idempotencyKey: crypto.randomUUID(),
    createdAt: Date.now(),
  }
  writeStoredCommand(scope, command)
  return command.idempotencyKey
}

export async function executeEditorialCommand<T>(
  scope: string,
  payload: unknown,
  execute: (idempotencyKey: string) => Promise<T>,
) {
  const idempotencyKey = await getEditorialCommandId(scope, payload)
  const result = await execute(idempotencyKey)
  clearStoredCommand(scope, idempotencyKey)
  return result
}
