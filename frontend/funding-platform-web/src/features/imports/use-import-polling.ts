import { useCallback, useEffect, useState } from 'react'

export const IMPORT_POLLING_WINDOW_MS = 5 * 60_000

// A forgotten tab must not keep a serverless database awake indefinitely when
// a run is queued/stranded. Explicit refresh opens another bounded window.
export function useImportPolling(scope: string) {
  const [windowId, setWindowId] = useState(0)
  const [enabled, setEnabled] = useState(true)
  useEffect(() => {
    setEnabled(true)
    const timer = window.setTimeout(() => setEnabled(false), IMPORT_POLLING_WINDOW_MS)
    return () => window.clearTimeout(timer)
  }, [scope, windowId])
  const restart = useCallback(() => setWindowId((value) => value + 1), [])
  return { enabled, restart }
}
