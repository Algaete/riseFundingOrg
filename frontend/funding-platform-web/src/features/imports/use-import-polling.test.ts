import { act, renderHook } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { IMPORT_POLLING_WINDOW_MS, useImportPolling } from './use-import-polling'

describe('bounded import status polling', () => {
  afterEach(() => vi.useRealTimers())
  it('stops after five minutes and only an explicit restart opens another window', () => {
    vi.useFakeTimers()
    const { result, unmount } = renderHook(() => useImportPolling('run'))
    expect(result.current.enabled).toBe(true)
    act(() => vi.advanceTimersByTime(IMPORT_POLLING_WINDOW_MS))
    expect(result.current.enabled).toBe(false)
    act(() => vi.advanceTimersByTime(60 * 60_000))
    expect(result.current.enabled).toBe(false)
    act(() => result.current.restart())
    expect(result.current.enabled).toBe(true)
    act(() => vi.advanceTimersByTime(IMPORT_POLLING_WINDOW_MS))
    expect(result.current.enabled).toBe(false)
    unmount()
    expect(vi.getTimerCount()).toBe(0)
  })
  it('resets for a different run and disposes the previous timer', () => {
    vi.useFakeTimers()
    const { result, rerender, unmount } = renderHook(({ id }) => useImportPolling(id),
      { initialProps: { id: 'one' } })
    act(() => vi.advanceTimersByTime(IMPORT_POLLING_WINDOW_MS))
    rerender({ id: 'two' })
    expect(result.current.enabled).toBe(true)
    expect(vi.getTimerCount()).toBe(1)
    unmount()
    expect(vi.getTimerCount()).toBe(0)
  })
})
