import { act, renderHook } from '@testing-library/react'
import { projectAssetPollingWindowMs, useProjectAssetPolling } from './use-project-asset-polling'

describe('project asset polling budget', () => {
  beforeEach(() => {
    vi.useFakeTimers()
    vi.setSystemTime(new Date('2026-09-11T12:00:00Z'))
  })

  afterEach(() => { vi.useRealTimers(); vi.restoreAllMocks() })

  it('expires after five minutes and only an explicit restart opens another window', () => {
    const { result, rerender } = renderHook(() => useProjectAssetPolling(true))
    expect(result.current.active).toBe(true)
    act(() => vi.advanceTimersByTime(projectAssetPollingWindowMs))
    expect(result.current.active).toBe(false)
    expect(result.current.canPollNow()).toBe(false)
    rerender()
    expect(result.current.active).toBe(false)
    act(() => result.current.restart())
    expect(result.current.active).toBe(true)
    act(() => vi.advanceTimersByTime(projectAssetPollingWindowMs))
    expect(result.current.active).toBe(false)
  })

  it('pauses hidden tabs without extending the deadline on return', () => {
    const visibility = vi.spyOn(document, 'visibilityState', 'get')
    const { result } = renderHook(() => useProjectAssetPolling(true))
    visibility.mockReturnValue('hidden')
    act(() => document.dispatchEvent(new Event('visibilitychange')))
    expect(result.current.active).toBe(false)
    expect(result.current.canPollNow()).toBe(false)
    act(() => vi.advanceTimersByTime(projectAssetPollingWindowMs))
    visibility.mockReturnValue('visible')
    act(() => document.dispatchEvent(new Event('visibilitychange')))
    expect(result.current.active).toBe(false)
  })

  it('checks wall-clock expiry even before a throttled browser timer fires', () => {
    const { result } = renderHook(() => useProjectAssetPolling(true))
    vi.setSystemTime(Date.now() + projectAssetPollingWindowMs + 1)
    expect(result.current.canPollNow()).toBe(false)
  })

  it('cannot be restarted when the feature is disabled and cleans up on unmount', () => {
    const { result, unmount } = renderHook(() => useProjectAssetPolling(false))
    act(() => result.current.restart())
    expect(result.current.active).toBe(false)
    expect(result.current.canPollNow()).toBe(false)
    unmount()
    expect(vi.getTimerCount()).toBe(0)
  })
})
