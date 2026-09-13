import { useCallback, useEffect, useState } from 'react'

export const projectAssetPollingWindowMs = 5 * 60 * 1_000
export const projectAssetPollingIntervalMs = 5_000

/** A user-started window, never extended by responses, focus or language changes. */
export function useProjectAssetPolling(enabled: boolean) {
  const [deadline, setDeadline] = useState(() => enabled ? Date.now() + projectAssetPollingWindowMs : 0)
  const [visible, setVisible] = useState(() => document.visibilityState === 'visible')

  useEffect(() => {
    const update = () => setVisible(document.visibilityState === 'visible')
    document.addEventListener('visibilitychange', update)
    return () => document.removeEventListener('visibilitychange', update)
  }, [])

  useEffect(() => {
    if (!enabled || deadline === 0) return
    const timer = window.setTimeout(() => setDeadline(0), Math.max(0, deadline - Date.now()))
    return () => window.clearTimeout(timer)
  }, [deadline, enabled])

  const canPollNow = useCallback(() => enabled && deadline > Date.now()
    && document.visibilityState === 'visible', [deadline, enabled])

  const restart = useCallback(() => {
    if (enabled) setDeadline(Date.now() + projectAssetPollingWindowMs)
  }, [enabled])

  return { active: enabled && visible && deadline > Date.now(), canPollNow, restart }
}
