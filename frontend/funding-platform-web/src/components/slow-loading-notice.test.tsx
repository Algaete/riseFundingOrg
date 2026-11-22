import { act, render, screen } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import i18n from '@/i18n'
import { SlowLoadingNotice } from './slow-loading-notice'

afterEach(() => vi.useRealTimers())

describe('slow first connection', () => {
  it('explains a prolonged wait and removes its timer when loading ends', async () => {
    await i18n.changeLanguage('es')
    vi.useFakeTimers()
    const view = render(<SlowLoadingNotice />)
    expect(screen.queryByText(/no necesitas recargar/)).not.toBeInTheDocument()
    act(() => vi.advanceTimersByTime(5_000))
    expect(screen.getByText(/no necesitas recargar/)).toBeInTheDocument()
    view.unmount()
    expect(vi.getTimerCount()).toBe(0)
  })
})
